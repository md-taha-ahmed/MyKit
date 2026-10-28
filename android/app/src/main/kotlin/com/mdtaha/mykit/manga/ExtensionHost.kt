package com.mdtaha.mykit.manga

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import dalvik.system.PathClassLoader
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.JavaScriptEngine
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.awaitSuccess
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingleton
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Installs and loads Mihon/Tachiyomi extension APKs inside MyKit.
 *
 * Mirrors Mihon's ExtensionLoader (Apache-2.0): extensions are stored as
 * read-only files in app-private storage, must declare the
 * `tachiyomi.extension` feature, use a supported lib version, and be signed
 * with the key their repository publishes. Untrusted APKs are never loaded.
 */
class ExtensionHost private constructor(private val context: Context) {

    data class LoadedExtension(
        val pkgName: String,
        val name: String,
        val versionName: String,
        val versionCode: Long,
        val libVersion: Double,
        val nsfw: Boolean,
        val signature: String,
        val sources: List<Source>,
    )

    class ExtensionException(message: String) : Exception(message)

    private val dir = File(context.filesDir, "manga_extensions").apply { mkdirs() }
    private val trust = context.getSharedPreferences("manga_extension_trust", Context.MODE_PRIVATE)
    private val extensions = ConcurrentHashMap<String, LoadedExtension>()
    private val sources = ConcurrentHashMap<Long, Source>()
    @Volatile private var loadedAll = false

    val network: NetworkHelper get() = Injekt.get()

    fun installed(): List<LoadedExtension> {
        ensureLoaded()
        return extensions.values.sortedBy { it.name.lowercase() }
    }

    fun source(id: Long): Source {
        ensureLoaded()
        return sources[id] ?: throw ExtensionException("Source $id is not installed")
    }

    /** Loads every installed extension once per process. */
    @Synchronized
    fun ensureLoaded() {
        if (loadedAll) return
        dir.listFiles { f -> f.extension == EXT }?.forEach { file ->
            val pkg = file.nameWithoutExtension
            val key = trust.getString(pkg, null)
            try {
                if (key == null) throw ExtensionException("No trusted key recorded")
                register(load(file, key))
            } catch (e: Throwable) {
                android.util.Log.e(TAG, "Failed to load $pkg", e)
            }
        }
        loadedAll = true
    }

    /**
     * Downloads [apkUrl], verifies it against [signingKey] (SHA-256 of the
     * signing certificate, as published in the repo) and loads it.
     */
    suspend fun install(apkUrl: String, pkgName: String, signingKey: String): LoadedExtension {
        ensureLoaded()
        val tmp = File(context.cacheDir, "$pkgName.download.apk")
        try {
            network.client.newCall(GET(apkUrl)).awaitSuccess().use { response ->
                tmp.outputStream().use { out -> response.body.byteStream().copyTo(out) }
            }
            val info = archiveInfo(tmp) ?: throw ExtensionException("Not a valid APK")
            if (info.packageName != pkgName) {
                throw ExtensionException("Package mismatch: ${info.packageName}")
            }

            val target = File(dir, "$pkgName.$EXT")
            val staged = File(dir, "$pkgName.$EXT.part")
            staged.delete()
            tmp.copyTo(staged, overwrite = true)
            staged.setReadOnly() // Android 14+ refuses writable dex files.

            // Validate fully before replacing a working install.
            load(staged, signingKey)
            unregister(pkgName)
            target.setWritable(true)
            target.delete()
            if (!staged.renameTo(target)) throw ExtensionException("Could not save extension")
            trust.edit().putString(pkgName, signingKey.lowercase()).apply()
            val final = load(target, signingKey)
            register(final)
            return final
        } finally {
            tmp.delete()
            File(dir, "$pkgName.$EXT.part").let { it.setWritable(true); it.delete() }
        }
    }

    fun uninstall(pkgName: String) {
        unregister(pkgName)
        File(dir, "$pkgName.$EXT").let { it.setWritable(true); it.delete() }
        trust.edit().remove(pkgName).apply()
    }

    private fun register(ext: LoadedExtension) {
        unregister(ext.pkgName)
        extensions[ext.pkgName] = ext
        ext.sources.forEach { sources[it.id] = it }
    }

    private fun unregister(pkgName: String) {
        extensions.remove(pkgName)?.sources?.forEach { sources.remove(it.id) }
    }

    private fun archiveInfo(file: File): PackageInfo? =
        context.packageManager.getPackageArchiveInfo(file.absolutePath, PACKAGE_FLAGS)
            ?.also {
                it.applicationInfo?.sourceDir = file.absolutePath
                it.applicationInfo?.publicSourceDir = file.absolutePath
            }

    private fun load(file: File, signingKey: String): LoadedExtension {
        val info = archiveInfo(file) ?: throw ExtensionException("Not a valid APK")
        if (info.reqFeatures.orEmpty().none { it.name == FEATURE }) {
            throw ExtensionException("${info.packageName} isn't a Mihon extension")
        }
        val meta = info.applicationInfo?.metaData
            ?: throw ExtensionException("Extension has no metadata")

        val libVersion = if (meta.containsKey(META_LIB)) {
            meta.getFloat(META_LIB).toString().toDouble()
        } else {
            info.versionName?.substringBeforeLast('.')?.toDoubleOrNull() ?: 0.0
        }
        if (libVersion !in SUPPORTED_LIBS) {
            throw ExtensionException(
                "Lib version $libVersion isn't supported (needs ${SUPPORTED_LIBS.joinToString()})",
            )
        }

        val signatures = signatures(info)
        if (signatures.none { it.equals(signingKey, ignoreCase = true) }) {
            throw ExtensionException("Untrusted: not signed by this repository's key")
        }

        val loader = DelegateLastPathClassLoader(file.absolutePath, context.classLoader)
        val classNames = meta.getString(META_CLASS)?.split(";")
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?.map { if (it.startsWith(".")) info.packageName + it else it }
            .orEmpty()
        if (classNames.isEmpty()) throw ExtensionException("Extension declares no sources")

        val loadedSources = classNames.flatMap { className ->
            when (val obj = Class.forName(className, false, loader).getDeclaredConstructor().newInstance()) {
                is Source -> listOf(obj)
                is SourceFactory -> obj.createSources()
                else -> throw ExtensionException("Unknown source type ${obj.javaClass.name}")
            }
        }

        val contentWarning = if (meta.containsKey(META_CONTENT_WARNING)) {
            meta.getInt(META_CONTENT_WARNING) == 3
        } else {
            meta.getInt(META_NSFW, 0) == 1
        }

        @Suppress("DEPRECATION")
        val versionCode = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return LoadedExtension(
            pkgName = info.packageName,
            name = (meta.getString(META_NAME) ?: info.applicationInfo?.nonLocalizedLabel?.toString()
                ?: info.packageName).removePrefix("Tachiyomi: "),
            versionName = info.versionName ?: "",
            versionCode = versionCode,
            libVersion = libVersion,
            nsfw = contentWarning,
            signature = signatures.last(),
            sources = loadedSources,
        )
    }

    @SuppressLint("PackageManagerGetSignatures")
    private fun signatures(info: PackageInfo): List<String> {
        @Suppress("DEPRECATION")
        val raw = if (Build.VERSION.SDK_INT >= 28) {
            val signing = info.signingInfo ?: return emptyList()
            if (signing.hasMultipleSigners()) signing.apkContentsSigners else signing.signingCertificateHistory
        } else {
            info.signatures
        }
        return raw.orEmpty().map { sha256(it.toByteArray()) }
    }

    /** Boot classes first, then the extension's own dex, then MyKit (like Mihon). */
    private class DelegateLastPathClassLoader(dexPath: String, parent: ClassLoader) :
        PathClassLoader(dexPath, null, parent) {
        private val boot: ClassLoader? = Any::class.java.classLoader

        override fun loadClass(name: String, resolve: Boolean): Class<*> {
            findLoadedClass(name)?.let { return it }
            try {
                return boot?.loadClass(name) ?: throw ClassNotFoundException(name)
            } catch (_: ClassNotFoundException) {
            }
            return try {
                findClass(name)
            } catch (_: ClassNotFoundException) {
                parent.loadClass(name)
            }
        }
    }

    companion object {
        private const val TAG = "MangaExtensionHost"
        private const val EXT = "ext"
        private const val FEATURE = "tachiyomi.extension"
        private const val META_CLASS = "tachiyomi.extension.class"
        private const val META_NSFW = "tachiyomi.extension.nsfw"
        private const val META_NAME = "tachiyomix.name"
        private const val META_LIB = "tachiyomix.extensionLib"
        private const val META_CONTENT_WARNING = "tachiyomix.contentWarning"
        private val SUPPORTED_LIBS = listOf(1.4, 1.6)

        @Suppress("DEPRECATION")
        private val PACKAGE_FLAGS = PackageManager.GET_CONFIGURATIONS or
            PackageManager.GET_META_DATA or
            PackageManager.GET_SIGNATURES or
            (if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else 0)

        @Volatile private var instance: ExtensionHost? = null

        /** Also registers what extensions pull from Injekt (Context, NetworkHelper, Json). */
        fun get(context: Context): ExtensionHost = instance ?: synchronized(this) {
            instance ?: run {
                val app = context.applicationContext
                // Extensions ask for both Context and Application.
                Injekt.addSingleton<Context>(app)
                Injekt.addSingleton<Application>(app as Application)
                Injekt.addSingletonFactory { NetworkHelper(app) }
                Injekt.addSingletonFactory {
                    Json {
                        ignoreUnknownKeys = true
                        explicitNulls = false
                    }
                }
                Injekt.addSingletonFactory { JavaScriptEngine(app) }
                ExtensionHost(app).also { instance = it }
            }
        }

        private fun sha256(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }
}

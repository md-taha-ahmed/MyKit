package com.mdtaha.mykit.backup

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Native half of MyKit's backup (`lib/features/backup/data/datasources/
 * backup_native_data_source.dart`): what Flutter's SharedPreferences can't
 * see — installed extension APKs, their trust keys and each source's own
 * settings (`source_<id>` preferences) — plus restarting the app after a
 * restore so every layer reloads from disk.
 *
 * A plugin rather than a channel in MainActivity, so it's also there on the
 * engine WorkManager starts for scheduled backups.
 *
 * Preference values cross the channel tagged with their type
 * (`[tag, value]`) so ints, longs and floats come back as what they were.
 */
class BackupPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var context: Context
    private var channel: MethodChannel? = null
    private var io: ExecutorService? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        io = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "com.mdtaha.mykit/backup").apply {
            setMethodCallHandler(this@BackupPlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        io?.shutdown()
        io = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "restart" -> {
                result.success(null)
                restart()
            }
            "export" -> runIo(result) { export() }
            "import" -> runIo(result) {
                @Suppress("UNCHECKED_CAST")
                import(call.arguments as Map<String, Any?>)
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun runIo(result: MethodChannel.Result, work: () -> Any?) {
        val executor = io ?: return result.error("Detached", "Backup plugin is detached", null)
        executor.execute {
            val reply = runCatching(work)
            main.post {
                reply.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error(it.javaClass.simpleName, it.message, null) },
                )
            }
        }
    }

    private fun export(): Map<String, Any> {
        val prefs = mutableMapOf<String, Any>()
        prefsDir().listFiles { f -> f.extension == "xml" }?.forEach { file ->
            val name = file.nameWithoutExtension
            if (!backsUp(name)) return@forEach
            val entries = mutableMapOf<String, Any>()
            context.getSharedPreferences(name, Context.MODE_PRIVATE).all.forEach { (key, value) ->
                tag(value)?.let { entries[key] = it }
            }
            prefs[name] = entries
        }

        val files = mutableMapOf<String, ByteArray>()
        for (dir in FILE_DIRS) {
            File(context.filesDir, dir).listFiles { f -> f.isFile && f.extension == EXT }
                ?.forEach { files["$dir/${it.name}"] = it.readBytes() }
        }
        return mapOf("prefs" to prefs, "files" to files)
    }

    private fun import(data: Map<String, Any?>) {
        @Suppress("UNCHECKED_CAST")
        val prefs = data["prefs"] as? Map<String, Map<String, List<Any?>>> ?: emptyMap()
        for ((name, entries) in prefs) {
            if (!backsUp(name) || name.contains('/')) continue
            val editor = context.getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear()
            for ((key, tagged) in entries) {
                val value = tagged.getOrNull(1) ?: continue
                when (tagged[0]) {
                    "s" -> editor.putString(key, value as String)
                    "b" -> editor.putBoolean(key, value as Boolean)
                    "i" -> editor.putInt(key, (value as Number).toInt())
                    "l" -> editor.putLong(key, (value as Number).toLong())
                    "f" -> editor.putFloat(key, (value as Number).toFloat())
                    "ss" -> editor.putStringSet(key, (value as List<*>).map { it.toString() }.toSet())
                }
            }
            editor.commit()
        }

        @Suppress("UNCHECKED_CAST")
        val files = data["files"] as? Map<String, ByteArray> ?: emptyMap()
        for (dir in FILE_DIRS) {
            val target = File(context.filesDir, dir).apply { mkdirs() }
            // Replace, not merge: the backup's set of extensions is the truth.
            target.listFiles()?.forEach { it.setWritable(true); it.delete() }
            files.filterKeys { it.substringBefore('/') == dir }.forEach { (path, bytes) ->
                val name = path.substringAfter('/')
                if (name.contains('/') || name.startsWith('.') || !name.endsWith(".$EXT")) return@forEach
                File(target, name).apply {
                    writeBytes(bytes)
                    setReadOnly() // Android 14+ refuses writable dex files.
                }
            }
        }
    }

    /** Relaunches MyKit in a fresh process (extensions, players and caches reload). */
    private fun restart() {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        // NEW_TASK | CLEAR_TASK, so it can start from the application context.
        val intent = Intent.makeRestartActivityTask(launch.component)
        main.postDelayed({
            context.startActivity(intent)
            Runtime.getRuntime().exit(0)
        }, 300)
    }

    private fun prefsDir() = File(context.applicationInfo.dataDir, "shared_prefs")

    private fun backsUp(name: String) =
        name != FLUTTER_PREFS && SKIP_PREFIXES.none { name.startsWith(it) }

    private fun tag(value: Any?): List<Any>? = when (value) {
        is String -> listOf("s", value)
        is Boolean -> listOf("b", value)
        is Int -> listOf("i", value)
        is Long -> listOf("l", value)
        is Float -> listOf("f", value.toDouble())
        is Set<*> -> listOf("ss", value.map { it.toString() }.sorted())
        else -> null
    }

    companion object {
        /** Flutter's own preferences are backed up from Dart. */
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"

        /**
         * Library/system state that belongs to this install only, and the
         * fingerprint-unlock key (only this phone's Keystore can open it).
         */
        private val SKIP_PREFIXES = listOf("androidx.", "com.google.", "WebView", "_", "vault_biometric")

        /** `ExtensionHost` directories (manga and anime). */
        private val FILE_DIRS = listOf("manga_extensions", "anime_extensions")
        private const val EXT = "ext"
    }
}

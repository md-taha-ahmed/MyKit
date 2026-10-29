package com.mdtaha.mykit.manga

import android.content.Context
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.awaitSuccess
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.online.HttpSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.io.File
import java.security.MessageDigest

/**
 * Bridge between Flutter (`lib/features/manga/data/datasources/
 * manga_native_data_source.dart`) and loaded extension sources.
 *
 * Mangas/chapters cross the channel as maps; `memo` (lib 1.6 per-entry state)
 * is passed through as a JSON string so sources get it back unchanged.
 */
class MangaChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/manga").apply {
        setMethodCallHandler(this@MangaChannel)
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val host by lazy { ExtensionHost.manga(context) }
    private val imageDir by lazy { File(context.cacheDir, "manga_images").apply { mkdirs() } }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            val reply = try {
                Result.success(handle(call))
            } catch (e: Throwable) {
                Result.failure(e)
            }
            withContext(Dispatchers.Main) {
                reply.fold(
                    onSuccess = { if (it === NotImplemented) result.notImplemented() else result.success(it) },
                    onFailure = {
                        result.error(
                            it.javaClass.simpleName,
                            it.message ?: it.javaClass.simpleName,
                            it.stackTraceToString().take(4000),
                        )
                    },
                )
            }
        }
    }

    private suspend fun handle(call: MethodCall): Any? = when (call.method) {
        "installed" -> host.installed().map { it.toMap() }
        "install" -> host.install(
            apkUrl = call.argument<String>("apkUrl")!!,
            pkgName = call.argument<String>("pkgName")!!,
            signingKey = call.argument<String>("signingKey")!!,
        ).toMap()
        "uninstall" -> host.uninstall(call.argument<String>("pkgName")!!)
        "popular" -> catalogue(call).getPopularManga(page(call)).toMap()
        "latest" -> catalogue(call).getLatestUpdates(page(call)).toMap()
        "search" -> catalogue(call).getSearchManga(
            page(call),
            call.argument<String>("query") ?: "",
            catalogue(call).getFilterList(),
        ).toMap()
        "details" -> {
            val manga = manga(call.argument<Map<String, Any?>>("manga")!!)
            source(call).getMangaUpdate(manga, emptyList(), fetchDetails = true, fetchChapters = false)
                .manga.toMap()
        }
        "chapters" -> {
            val manga = manga(call.argument<Map<String, Any?>>("manga")!!)
            source(call).getMangaUpdate(manga, emptyList(), fetchDetails = false, fetchChapters = true)
                .chapters.map { it.toMap() }
        }
        "pages" -> {
            val chapter = chapter(call.argument<Map<String, Any?>>("chapter")!!)
            source(call).getPageList(chapter).mapIndexed { i, p ->
                mapOf("index" to i, "url" to p.url, "imageUrl" to p.imageUrl)
            }
        }
        "image" -> downloadPage(call)
        "cover" -> downloadCover(call)
        "webUrl" -> (source(call) as? HttpSource)?.let { src ->
            call.argument<Map<String, Any?>>("chapter")?.let { src.getChapterUrl(chapter(it)) }
                ?: src.getMangaUrl(manga(call.argument<Map<String, Any?>>("manga")!!))
        }
        else -> NotImplemented
    }

    // -- Images --------------------------------------------------------------

    /** Downloads a reader page through the source (its headers/cookies). Returns a file path. */
    private suspend fun downloadPage(call: MethodCall): String {
        val src = source(call) as? HttpSource ?: error("Source can't load images")
        val map = call.argument<Map<String, Any?>>("page")!!
        val page = Page(
            index = (map["index"] as Number).toInt(),
            url = map["url"] as String? ?: "",
            imageUrl = map["imageUrl"] as String?,
        )
        if (page.imageUrl.isNullOrEmpty()) page.imageUrl = src.getImageUrl(page)
        val file = File(imageDir, "p_${hash("${src.id}|${page.url}|${page.imageUrl}")}")
        if (file.length() > 0) return file.absolutePath
        src.getImage(page).use { response ->
            writeAtomically(file) { out -> response.body.byteStream().copyTo(out) }
        }
        return file.absolutePath
    }

    /** Downloads a cover with the source's headers (many sites block hotlinking). */
    private suspend fun downloadCover(call: MethodCall): String {
        val url = call.argument<String>("url")!!
        val src = source(call)
        val file = File(imageDir, "c_${hash("${src.id}|$url")}")
        if (file.length() > 0) return file.absolutePath
        val http = src as? HttpSource
        val request = GET(url, http?.headers ?: okhttp3.Headers.Builder().build())
        val client = http?.client ?: host.network.client
        client.newCall(request).awaitSuccess().use { response ->
            writeAtomically(file) { out -> response.body.byteStream().copyTo(out) }
        }
        return file.absolutePath
    }

    private inline fun writeAtomically(file: File, write: (java.io.OutputStream) -> Unit) {
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.outputStream().use(write)
        tmp.renameTo(file)
    }

    // -- Mapping -------------------------------------------------------------

    private fun source(call: MethodCall): Source =
        host.source(call.argument<String>("sourceId")!!.toLong())

    private fun catalogue(call: MethodCall): CatalogueSource =
        source(call) as? CatalogueSource ?: error("Source can't be browsed")

    private fun page(call: MethodCall): Int = call.argument<Int>("page") ?: 1

    private fun ExtensionHost.LoadedExtension<Source>.toMap() = mapOf(
        "pkgName" to pkgName,
        "name" to name,
        "versionName" to versionName,
        "versionCode" to versionCode,
        "libVersion" to libVersion,
        "nsfw" to nsfw,
        "sources" to sources.map { s ->
            mapOf(
                "id" to s.id.toString(),
                "name" to s.name,
                "lang" to s.lang,
                "supportsLatest" to (s as? CatalogueSource)?.supportsLatest,
                "baseUrl" to (s as? HttpSource)?.baseUrl,
            )
        },
    )

    private fun MangasPage.toMap() = mapOf(
        "mangas" to mangas.map { it.toMap() },
        "hasNextPage" to hasNextPage,
    )

    private fun SManga.toMap() = mapOf(
        "url" to url,
        "title" to title,
        "artist" to artist,
        "author" to author,
        "description" to description,
        "genre" to genre,
        "status" to status,
        "thumbnailUrl" to thumbnail_url,
        "initialized" to initialized,
        "memo" to memo.toString(),
    )

    private fun SChapter.toMap() = mapOf(
        "url" to url,
        "name" to name,
        "dateUpload" to date_upload,
        "chapterNumber" to chapter_number.toDouble(),
        "scanlator" to scanlator,
        "memo" to memo.toString(),
    )

    private fun manga(map: Map<String, Any?>): SManga = SManga.create().apply {
        url = map["url"] as String
        title = map["title"] as String? ?: ""
        artist = map["artist"] as String?
        author = map["author"] as String?
        description = map["description"] as String?
        genre = map["genre"] as String?
        status = (map["status"] as Number?)?.toInt() ?: SManga.UNKNOWN
        thumbnail_url = map["thumbnailUrl"] as String?
        initialized = map["initialized"] as Boolean? ?: false
        memo = parseMemo(map["memo"])
    }

    private fun chapter(map: Map<String, Any?>): SChapter = SChapter.create().apply {
        url = map["url"] as String
        name = map["name"] as String? ?: ""
        date_upload = (map["dateUpload"] as Number?)?.toLong() ?: 0L
        chapter_number = (map["chapterNumber"] as Number?)?.toFloat() ?: -1f
        scanlator = map["scanlator"] as String?
        memo = parseMemo(map["memo"])
    }

    private fun parseMemo(raw: Any?): JsonObject =
        (raw as? String)?.takeIf { it.isNotBlank() }
            ?.let { runCatching { Json.parseToJsonElement(it) as JsonObject }.getOrNull() }
            ?: JsonObject(emptyMap())

    fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    private object NotImplemented

    companion object {
        private fun hash(s: String) = MessageDigest.getInstance("SHA-1").digest(s.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }
}

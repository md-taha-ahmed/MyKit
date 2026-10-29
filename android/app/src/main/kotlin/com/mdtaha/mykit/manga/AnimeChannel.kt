package com.mdtaha.mykit.manga

import android.content.Context
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.FetchType
import eu.kanade.tachiyomi.animesource.model.Hoster
import eu.kanade.tachiyomi.animesource.model.Hoster.Companion.toHosterList
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.animesource.online.ParsedAnimeHttpSource
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.awaitSuccess
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * Bridge between Flutter (`lib/features/manga/data/datasources/anime_native_data_source.dart`)
 * and loaded Aniyomi anime sources.
 *
 * Playback follows Aniyomi's EpisodeLoader: sources that override the hoster
 * API (ext lib 16) give hosters → videos; older ones give videos directly.
 * Hosters and videos stay here and cross the channel as tokens.
 */
class AnimeChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/anime").apply {
        setMethodCallHandler(this@AnimeChannel)
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val host by lazy { ExtensionHost.anime(context) }
    private val imageDir by lazy { File(context.cacheDir, "anime_images").apply { mkdirs() } }

    private val counter = AtomicLong()
    private val hosters = ConcurrentHashMap<String, Hoster>()
    private val videos = ConcurrentHashMap<String, Video>()

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
        "uninstall" -> host.uninstall(call.argument<String>("pkgName")!!).let { null }
        "popular" -> catalogue(call).getPopularAnime(page(call)).toMap()
        "latest" -> catalogue(call).getLatestUpdates(page(call)).toMap()
        "search" -> catalogue(call).let { src ->
            src.getSearchAnime(page(call), call.argument<String>("query") ?: "", src.getFilterList()).toMap()
        }
        "details" -> source(call).getAnimeDetails(anime(call)).toMap()
        "episodes" -> source(call).getEpisodeList(anime(call)).map { it.toMap() }
        "seasons" -> source(call).getSeasonList(anime(call)).map { it.toMap() }
        "hosters" -> hostersFor(source(call), episode(call.argument<Map<String, Any?>>("episode")!!))
        "hosterVideos" -> {
            val src = source(call)
            val hoster = hosters[call.argument<String>("hoster")!!] ?: error("Hoster expired, reload the episode")
            videosOf(src, hoster).map { it.toMap() }
        }
        "resolve" -> resolve(source(call), call.argument<String>("video")!!)
        "cover" -> downloadCover(call)
        "webUrl" -> (source(call) as? AnimeHttpSource)?.let { src ->
            call.argument<Map<String, Any?>>("episode")?.let { src.getEpisodeUrl(episode(it)) }
                ?: src.getAnimeUrl(anime(call))
        }
        else -> NotImplemented
    }

    // -- Playback -------------------------------------------------------------

    /** Hosters for an episode; non-lazy ones come with their videos already loaded. */
    private suspend fun hostersFor(src: AnimeSource, episode: SEpisode): List<Map<String, Any?>> {
        // Tokens from earlier episodes are no longer needed.
        hosters.clear()
        videos.clear()
        val list = when (src) {
            is AnimeHttpSource -> if (hasHosters(src)) {
                src.getHosterList(episode).let { src.run { it.sortHosters() } }
            } else {
                src.getVideoList(episode).let { src.run { it.sortVideos() } }.toHosterList()
            }
            else -> src.getVideoList(episode).toHosterList()
        }
        return coroutineScope {
            list.map { hoster ->
                async {
                    val token = "h${counter.incrementAndGet()}"
                    hosters[token] = hoster
                    val loaded = if (hoster.lazy) {
                        null
                    } else {
                        runCatching { videosOf(src, hoster) }.getOrNull()
                    }
                    mapOf(
                        "token" to token,
                        "name" to hoster.hosterName.takeUnless { it == Hoster.NO_HOSTER_LIST },
                        "lazy" to hoster.lazy,
                        "videos" to loaded?.map { it.toMap() },
                    )
                }
            }.awaitAll()
        }
    }

    private suspend fun videosOf(src: AnimeSource, hoster: Hoster): List<Video> {
        val list = hoster.videoList ?: (src as? AnimeHttpSource)?.getVideoList(hoster)
            ?: src.getVideoList(hoster)
        val withUrls = if (src is AnimeHttpSource) {
            list.map { v -> if (v.videoUrl != "null") v else v.copy(videoUrl = src.getVideoUrl(v)) }
        } else {
            list
        }
        return if (src is AnimeHttpSource) src.run { withUrls.sortVideos() } else withUrls
    }

    /** Final URL, headers and tracks for a video the user picked. */
    private suspend fun resolve(src: AnimeSource, token: String): Map<String, Any?> {
        var video = videos[token] ?: error("Video expired, reload the episode")
        if (!video.initialized && src is AnimeHttpSource) {
            video = src.resolveVideo(video) ?: error("This video is no longer available")
        }
        if (video.videoUrl.isBlank() || video.videoUrl == "null") error("This video has no URL")
        return mapOf(
            "url" to video.videoUrl,
            "title" to video.videoTitle,
            "headers" to video.headers?.let { h -> h.names().associateWith { h[it] ?: "" } },
            "subtitles" to video.subtitleTracks.map { mapOf("url" to it.url, "lang" to it.lang) },
            "audios" to video.audioTracks.map { mapOf("url" to it.url, "lang" to it.lang) },
            "usesHttpServer" to video.usesHttpServer(),
        )
    }

    /** Same check as Aniyomi: does the source (or a parent) override the hoster API? */
    private fun hasHosters(source: AnimeHttpSource): Boolean {
        var current: Class<*> = source.javaClass
        while (true) {
            if (current == ParsedAnimeHttpSource::class.java ||
                current == AnimeHttpSource::class.java ||
                current == AnimeSource::class.java
            ) {
                return false
            }
            if (current.declaredMethods.any {
                    it.name in listOf("getHosterList", "hosterListRequest", "hosterListParse")
                }
            ) {
                return true
            }
            current = current.superclass ?: return false
        }
    }

    // -- Images --------------------------------------------------------------

    /** Downloads a cover with the source's headers (many sites block hotlinking). */
    private suspend fun downloadCover(call: MethodCall): String {
        val url = call.argument<String>("url")!!
        val src = source(call)
        val file = File(imageDir, "c_${hash("${src.id}|$url")}")
        if (file.length() > 0) return file.absolutePath
        val http = src as? AnimeHttpSource
        val request = GET(url, http?.headers ?: okhttp3.Headers.Builder().build())
        val client = http?.client ?: host.network.client
        client.newCall(request).awaitSuccess().use { response ->
            val tmp = File(file.parentFile, "${file.name}.tmp")
            tmp.outputStream().use { out -> response.body.byteStream().copyTo(out) }
            tmp.renameTo(file)
        }
        return file.absolutePath
    }

    // -- Mapping -------------------------------------------------------------

    private fun source(call: MethodCall): AnimeSource =
        host.source(call.argument<String>("sourceId")!!.toLong())

    private fun catalogue(call: MethodCall): AnimeCatalogueSource =
        source(call) as? AnimeCatalogueSource ?: error("Source can't be browsed")

    private fun page(call: MethodCall): Int = call.argument<Int>("page") ?: 1

    private fun ExtensionHost.LoadedExtension<AnimeSource>.toMap() = mapOf(
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
                "supportsLatest" to s.supportsLatest,
                "baseUrl" to (s as? AnimeHttpSource)?.baseUrl,
            )
        },
    )

    private fun AnimesPage.toMap() = mapOf(
        "animes" to animes.map { it.toMap() },
        "hasNextPage" to hasNextPage,
    )

    private fun SAnime.toMap() = mapOf(
        "url" to url,
        "title" to title,
        "artist" to artist,
        "author" to author,
        "description" to description,
        "genre" to genre,
        "status" to status,
        "thumbnailUrl" to thumbnail_url,
        "backgroundUrl" to background_url,
        "fetchType" to fetch_type.name,
        "seasonNumber" to season_number,
        "initialized" to initialized,
        "memo" to memo.toString(),
    )

    private fun SEpisode.toMap() = mapOf(
        "url" to url,
        "name" to name,
        "dateUpload" to date_upload,
        "episodeNumber" to episode_number.toDouble(),
        "scanlator" to scanlator,
        "summary" to summary,
        "previewUrl" to preview_url,
        "filler" to fillermark,
        "memo" to memo.toString(),
    )

    private fun Video.toMap(): Map<String, Any?> {
        val token = "v${counter.incrementAndGet()}"
        videos[token] = this
        return mapOf(
            "token" to token,
            "title" to videoTitle,
            "resolution" to resolution,
            "preferred" to preferred,
        )
    }

    private fun anime(call: MethodCall): SAnime {
        val map = call.argument<Map<String, Any?>>("anime")!!
        return SAnime.create().apply {
            url = map["url"] as String
            title = map["title"] as String? ?: ""
            artist = map["artist"] as String?
            author = map["author"] as String?
            description = map["description"] as String?
            genre = map["genre"] as String?
            status = (map["status"] as Number?)?.toInt() ?: SAnime.UNKNOWN
            thumbnail_url = map["thumbnailUrl"] as String?
            background_url = map["backgroundUrl"] as String?
            fetch_type = (map["fetchType"] as String?)
                ?.let { runCatching { FetchType.valueOf(it) }.getOrNull() } ?: FetchType.Episodes
            season_number = (map["seasonNumber"] as Number?)?.toDouble() ?: -1.0
            initialized = map["initialized"] as Boolean? ?: false
            memo = parseMemo(map["memo"])
        }
    }

    private fun episode(map: Map<String, Any?>): SEpisode = SEpisode.create().apply {
        url = map["url"] as String
        name = map["name"] as String? ?: ""
        date_upload = (map["dateUpload"] as Number?)?.toLong() ?: 0L
        episode_number = (map["episodeNumber"] as Number?)?.toFloat() ?: -1f
        scanlator = map["scanlator"] as String?
        summary = map["summary"] as String?
        preview_url = map["previewUrl"] as String?
        fillermark = map["filler"] as Boolean? ?: false
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

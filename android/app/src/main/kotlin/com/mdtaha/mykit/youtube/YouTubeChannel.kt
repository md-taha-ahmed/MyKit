package com.mdtaha.mykit.youtube

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import java.util.concurrent.TimeUnit

/**
 * Plays YouTube Shorts inside MyKit (`lib/features/rss/data/datasources/
 * shorts_native_data_source.dart`): resolves a video id to direct stream
 * URLs with NewPipeExtractor (the library behind NewPipe), so MyKit's own
 * player can play them — no ads, smooth swiping. If YouTube changes and this
 * fails, the app opens the Short in the YouTube app instead.
 */
class YouTubeChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/youtube").apply {
        setMethodCallHandler(this@YouTubeChannel)
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Recently resolved streams (prefetched while the previous Short plays). */
    private val cache = object : LinkedHashMap<String, Map<String, Any?>>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Map<String, Any?>>) =
            size > 30
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resolve" -> {
                val id = call.argument<String>("id")!!
                scope.launch {
                    val reply = runCatching { resolve(id) }
                    withContext(Dispatchers.Main) {
                        reply.fold(
                            onSuccess = { result.success(it) },
                            onFailure = {
                                result.error(
                                    it.javaClass.simpleName,
                                    it.message ?: it.javaClass.simpleName,
                                    null,
                                )
                            },
                        )
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun resolve(id: String): Map<String, Any?> {
        synchronized(cache) { cache[id] }?.let { return it }
        ensureInit()
        val info = StreamInfo.getInfo(ServiceList.YouTube, "https://www.youtube.com/shorts/$id")

        fun shortSide(w: Int, h: Int) = if (w > 0 && h > 0) minOf(w, h) else maxOf(w, h)

        // Best video-only stream up to 720p (looks the same on a phone, half
        // the data of 1080p; MP4/H.264 first: hardware decoding everywhere),
        // plus the best M4A audio.
        val video = info.videoOnlyStreams
            .filter { it.isUrl && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
            .filter { shortSide(it.width, it.height) in 1..720 }
            .sortedWith(
                compareByDescending<org.schabi.newpipe.extractor.stream.VideoStream> {
                    it.format == MediaFormat.MPEG_4
                }.thenByDescending { shortSide(it.width, it.height) },
            )
            .firstOrNull()
        val audio = info.audioStreams
            .filter { it.isUrl && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
            .sortedWith(
                compareByDescending<org.schabi.newpipe.extractor.stream.AudioStream> {
                    it.format == MediaFormat.M4A
                }.thenByDescending { it.averageBitrate },
            )
            .firstOrNull()
        // Fallback: a stream with both (usually 360p).
        val muxed = info.videoStreams
            .filter { it.isUrl && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
            .maxByOrNull { shortSide(it.width, it.height) }

        val out: Map<String, Any?> = when {
            video != null && audio != null -> mapOf(
                "video" to video.content,
                "audio" to audio.content,
                "width" to video.width,
                "height" to video.height,
            )
            muxed != null -> mapOf(
                "video" to muxed.content,
                "width" to muxed.width,
                "height" to muxed.height,
            )
            !info.hlsUrl.isNullOrEmpty() -> mapOf("video" to info.hlsUrl)
            else -> throw IllegalStateException("No playable stream")
        } + mapOf(
            // Single-file stream (usually 360p): the fallback when the HD
            // video + audio pair won't play.
            "fallback" to muxed?.content,
            "title" to info.name,
            "channel" to info.uploaderName,
            "duration" to info.duration,
        )
        synchronized(cache) { cache[id] = out }
        return out
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    companion object {
        @Volatile private var initialized = false

        @Synchronized
        private fun ensureInit() {
            if (initialized) return
            NewPipe.init(OkHttpDownloader(), Localization.DEFAULT)
            initialized = true
        }
    }
}

/** NewPipeExtractor's network access, through OkHttp. */
private class OkHttpDownloader : Downloader() {
    private val client = OkHttpClient.Builder()
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    override fun execute(request: Request): Response {
        val data = request.dataToSend()
        val body = data?.toRequestBody() ?: if (request.httpMethod() == "POST") {
            ByteArray(0).toRequestBody()
        } else {
            null
        }
        val builder = okhttp3.Request.Builder()
            .method(request.httpMethod(), body)
            .url(request.url())
            .header("User-Agent", USER_AGENT)
        request.headers().forEach { (name, values) ->
            builder.removeHeader(name)
            values.forEach { builder.addHeader(name, it) }
        }
        client.newCall(builder.build()).execute().use { res ->
            if (res.code == 429) {
                throw ReCaptchaException("YouTube asked for a captcha", request.url())
            }
            return Response(
                res.code,
                res.message,
                res.headers.toMultimap(),
                res.body.string(),
                res.request.url.toString(),
            )
        }
    }

    companion object {
        const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0"
    }
}

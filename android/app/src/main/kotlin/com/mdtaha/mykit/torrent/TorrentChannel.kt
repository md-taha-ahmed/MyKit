package com.mdtaha.mykit.torrent

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Bridge for `lib/features/movies/data/datasources/torrent_stream_data_source.dart`.
 */
class TorrentChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/torrent").apply {
        setMethodCallHandler(this@TorrentChannel)
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val engine by lazy { TorrentStreamEngine.get(context) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            val reply = try {
                Result.success(handle(call))
            } catch (e: UnsatisfiedLinkError) {
                Result.failure(IllegalStateException("Torrent streaming isn't supported on this device's CPU."))
            } catch (e: Throwable) {
                Result.failure(e)
            }
            withContext(Dispatchers.Main) {
                reply.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("TORRENT", it.message ?: it.javaClass.simpleName, null) },
                )
            }
        }
    }

    private fun handle(call: MethodCall): Any? = when (call.method) {
        "start" -> engine.start(
            infoHash = call.argument<String>("infoHash")!!,
            fileIdx = call.argument<Int>("fileIdx"),
            trackers = call.argument<List<String>>("trackers") ?: emptyList(),
            filename = call.argument<String>("filename"),
        ).toMap()
        "status" -> engine.status(call.argument<String>("id")!!)
        "stop" -> engine.stop(call.argument<String>("id")!!).let { null }
        "warmUp" -> engine.warmUp().let { null }
        else -> throw IllegalArgumentException("Unknown method ${call.method}")
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }
}

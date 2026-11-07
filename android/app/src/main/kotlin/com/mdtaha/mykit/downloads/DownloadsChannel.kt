package com.mdtaha.mykit.downloads

import android.content.Context
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Bridge for `lib/features/downloads/data/downloads_native.dart`. */
class DownloadsChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/downloads").apply {
        setMethodCallHandler(this@DownloadsChannel)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "keepAlive" -> {
                    DownloadService.update(
                        context,
                        call.argument<String>("title") ?: "MyKit",
                        call.argument<String>("text") ?: "",
                        call.argument<Int>("progress") ?: -1,
                    )
                    result.success(null)
                }
                "release" -> {
                    DownloadService.stop(context)
                    result.success(null)
                }
                "freeSpace" -> result.success(StatFs(call.argument<String>("path")!!).availableBytes)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("DOWNLOADS", e.message ?: e.javaClass.simpleName, null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}

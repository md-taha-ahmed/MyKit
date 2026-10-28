package com.mdtaha.mykit.apps

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Opens links in a specific app. YouTube links only auto-open in apps Google
 * has verified for youtube.com, so patched clients like ReVanced never get
 * them; here we target them explicitly.
 */
class ExternalAppsChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mdtaha.mykit/external_apps"

        /** Preferred YouTube clients, best first (must also be in <queries>). */
        private val YOUTUBE_APPS = listOf(
            "app.revanced.android.youtube", // YouTube ReVanced
            "app.rvx.android.youtube", // ReVanced Extended
            "com.google.android.youtube", // official
        )
    }

    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(this@ExternalAppsChannel)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openYoutube" -> result.success(openYoutube(call.argument<String>("url")!!))
            "openVideo" -> result.success(
                openVideo(call.argument<String>("url")!!, call.argument<String>("title")),
            )
            else -> result.notImplemented()
        }
    }

    /** Returns the package that opened the link, or null if none could. */
    private fun openYoutube(url: String): String? {
        val uri = Uri.parse(url)
        for (pkg in YOUTUBE_APPS) {
            if (!isEnabled(pkg)) continue
            val intent = Intent(Intent.ACTION_VIEW, uri)
                .setPackage(pkg)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                activity.startActivity(intent)
                return pkg
            } catch (_: Exception) {
                // This client can't handle the link; try the next one.
            }
        }
        return null
    }

    /** Lets the user pick a video player (VLC, MX Player, …). False if none. */
    private fun openVideo(url: String, title: String?): Boolean {
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse(url), "video/*")
            .apply { if (title != null) putExtra("title", title) }
        return try {
            activity.startActivity(Intent.createChooser(intent, title ?: "Open with"))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun isEnabled(pkg: String): Boolean = try {
        activity.packageManager.getApplicationInfo(pkg, 0).enabled
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    fun dispose() = channel.setMethodCallHandler(null)
}

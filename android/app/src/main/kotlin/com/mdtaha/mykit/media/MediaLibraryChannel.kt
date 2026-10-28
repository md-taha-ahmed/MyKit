package com.mdtaha.mykit.media

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Reads on-device audio from MediaStore for Dart
 * (`lib/features/music/data/datasources/media_store_data_source.dart`).
 */
class MediaLibraryChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mdtaha.mykit/media_library"
        const val PERMISSION_REQUEST_CODE = 4822
    }

    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(this@MediaLibraryChannel)
    }
    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val audioPermission =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "openSettings" -> {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null),
                    ),
                )
                result.success(null)
            }
            "getTracks" -> background(result) { queryTracks() }
            "getArtwork" -> {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                val size = call.argument<Int>("size") ?: 256
                background(result) { loadArtwork(uri, size) }
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission() =
        activity.checkSelfPermission(audioPermission) == PackageManager.PERMISSION_GRANTED

    /** Asks for audio access, plus notifications (Android 13+) for player controls. */
    private fun requestPermission(result: MethodChannel.Result) {
        val wanted = mutableListOf(audioPermission)
        if (Build.VERSION.SDK_INT >= 33) wanted += Manifest.permission.POST_NOTIFICATIONS
        val missing = wanted.filter {
            activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        pendingPermissionResult?.success(hasPermission())
        pendingPermissionResult = result
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    /** Called from [com.mdtaha.mykit.MainActivity.onRequestPermissionsResult]. */
    fun onPermissionResult() {
        // Only audio access is required; notifications are optional.
        pendingPermissionResult?.success(hasPermission())
        pendingPermissionResult = null
    }

    private fun <T> background(result: MethodChannel.Result, work: () -> T) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("PERMISSION_DENIED", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("FAILED", e.message, null) }
            }
        }
    }

    private fun queryTracks(): List<Map<String, Any?>> {
        if (!hasPermission()) throw SecurityException("Audio permission not granted")

        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val columns = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DATE_ADDED,
        )
        if (Build.VERSION.SDK_INT >= 29) columns += MediaStore.Audio.Media.RELATIVE_PATH

        // Everything except system sounds.
        val selection = "${MediaStore.Audio.Media.IS_NOTIFICATION} = 0 AND " +
            "${MediaStore.Audio.Media.IS_RINGTONE} = 0 AND " +
            "${MediaStore.Audio.Media.IS_ALARM} = 0"

        val tracks = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(collection, columns.toTypedArray(), selection, null, null)
            ?.use { c ->
                val id = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val title = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val album = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val duration = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val name = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val data = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val added = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                val relative = c.getColumnIndex("relative_path")

                while (c.moveToNext()) {
                    val mediaId = c.getLong(id)
                    val path = c.getString(data)
                    val folder = path?.let { File(it).parent }
                        ?: (if (relative >= 0) c.getString(relative)?.trimEnd('/') else null)
                        ?: "Unknown"
                    tracks += mapOf(
                        "id" to mediaId.toString(),
                        "uri" to ContentUris.withAppendedId(collection, mediaId).toString(),
                        "title" to c.getString(title),
                        "artist" to c.getString(artist),
                        "album" to c.getString(album),
                        "durationMs" to c.getLong(duration),
                        "fileName" to (c.getString(name) ?: path?.substringAfterLast('/') ?: ""),
                        "folder" to folder,
                        "dateAdded" to c.getLong(added) * 1000,
                    )
                }
            }
        return tracks
    }

    /** Embedded cover art as JPEG bytes, or null when the file has none. */
    private fun loadArtwork(uri: Uri, size: Int): ByteArray? {
        if (Build.VERSION.SDK_INT < 29) return null
        val bitmap = try {
            activity.contentResolver.loadThumbnail(uri, Size(size, size), null)
        } catch (e: Exception) {
            return null
        }
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            out.toByteArray()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }
}

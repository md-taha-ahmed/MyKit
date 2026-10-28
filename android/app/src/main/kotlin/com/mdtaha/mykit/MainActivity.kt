package com.mdtaha.mykit

import android.content.pm.PackageManager
import com.mdtaha.mykit.apps.ExternalAppsChannel
import com.mdtaha.mykit.calendar.CalendarChannel
import com.mdtaha.mykit.manga.MangaChannel
import com.mdtaha.mykit.media.MediaLibraryChannel
import com.mdtaha.mykit.torrent.TorrentChannel
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/** AudioServiceActivity (a FlutterActivity) lets music keep playing in the background. */
class MainActivity : AudioServiceActivity() {
    private var calendarChannel: CalendarChannel? = null
    private var mediaLibraryChannel: MediaLibraryChannel? = null
    private var mangaChannel: MangaChannel? = null
    private var externalAppsChannel: ExternalAppsChannel? = null
    private var torrentChannel: TorrentChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        calendarChannel = CalendarChannel(this, messenger)
        mediaLibraryChannel = MediaLibraryChannel(this, messenger)
        mangaChannel = MangaChannel(applicationContext, messenger)
        externalAppsChannel = ExternalAppsChannel(this, messenger)
        torrentChannel = TorrentChannel(applicationContext, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        calendarChannel?.dispose()
        calendarChannel = null
        mediaLibraryChannel?.dispose()
        mediaLibraryChannel = null
        mangaChannel?.dispose()
        mangaChannel = null
        externalAppsChannel?.dispose()
        externalAppsChannel = null
        torrentChannel?.dispose()
        torrentChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            CalendarChannel.PERMISSION_REQUEST_CODE -> calendarChannel?.onPermissionResult(
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED,
            )
            MediaLibraryChannel.PERMISSION_REQUEST_CODE ->
                mediaLibraryChannel?.onPermissionResult()
        }
    }
}

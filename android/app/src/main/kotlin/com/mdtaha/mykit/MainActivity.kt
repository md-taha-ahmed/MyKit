package com.mdtaha.mykit

import android.content.pm.PackageManager
import com.mdtaha.mykit.apps.ExternalAppsChannel
import com.mdtaha.mykit.calendar.CalendarChannel
import com.mdtaha.mykit.manga.AnimeChannel
import com.mdtaha.mykit.manga.MangaChannel
import com.mdtaha.mykit.media.MediaLibraryChannel
import com.mdtaha.mykit.torrent.TorrentChannel
import com.mdtaha.mykit.vault.VaultChannel
import com.mdtaha.mykit.youtube.YouTubeChannel
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * AudioServiceFragmentActivity lets music keep playing in the background; the
 * Fragment variant is what BiometricPrompt (fingerprint unlock) needs.
 */
class MainActivity : AudioServiceFragmentActivity() {
    private var calendarChannel: CalendarChannel? = null
    private var mediaLibraryChannel: MediaLibraryChannel? = null
    private var mangaChannel: MangaChannel? = null
    private var animeChannel: AnimeChannel? = null
    private var externalAppsChannel: ExternalAppsChannel? = null
    private var torrentChannel: TorrentChannel? = null
    private var vaultChannel: VaultChannel? = null
    private var youTubeChannel: YouTubeChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        calendarChannel = CalendarChannel(this, messenger)
        mediaLibraryChannel = MediaLibraryChannel(this, messenger)
        mangaChannel = MangaChannel(applicationContext, messenger)
        animeChannel = AnimeChannel(applicationContext, messenger)
        externalAppsChannel = ExternalAppsChannel(this, messenger)
        torrentChannel = TorrentChannel(applicationContext, messenger)
        vaultChannel = VaultChannel(this, messenger)
        youTubeChannel = YouTubeChannel(messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        calendarChannel?.dispose()
        calendarChannel = null
        mediaLibraryChannel?.dispose()
        mediaLibraryChannel = null
        mangaChannel?.dispose()
        mangaChannel = null
        animeChannel?.dispose()
        animeChannel = null
        externalAppsChannel?.dispose()
        externalAppsChannel = null
        torrentChannel?.dispose()
        torrentChannel = null
        vaultChannel?.dispose()
        vaultChannel = null
        youTubeChannel?.dispose()
        youTubeChannel = null
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

package com.mdtaha.mykit.downloads

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Keeps the app alive while offline downloads run (the downloads themselves
 * run in Dart, see `lib/features/downloads/`). It only shows the
 * "Downloading…" notification; Android would otherwise stop the app soon
 * after it's left.
 */
class DownloadService : Service() {

    companion object {
        private const val TAG = "DownloadService"
        private const val CHANNEL = "mykit_downloads"
        private const val NOTIFICATION_ID = 4127

        @Volatile
        private var running = false

        /** Starts the service, or updates its notification if it runs already. */
        fun update(context: Context, title: String, text: String, progress: Int) {
            val notification = build(context, title, text, progress)
            if (running) {
                manager(context).notify(NOTIFICATION_ID, notification)
                return
            }
            val intent = Intent(context, DownloadService::class.java)
                .putExtra("title", title)
                .putExtra("text", text)
                .putExtra("progress", progress)
            try {
                context.startForegroundService(intent)
            } catch (e: Exception) {
                // Not allowed from the background (Android 12+): downloads
                // still run while Android keeps the app.
                Log.w(TAG, "Couldn't start: ${e.message}")
            }
        }

        fun stop(context: Context) {
            if (!running) return
            context.stopService(Intent(context, DownloadService::class.java))
        }

        private fun manager(context: Context) =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        private fun build(context: Context, title: String, text: String, progress: Int): Notification {
            val nm = manager(context)
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW),
                )
            }
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val tap = launch?.let {
                PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE)
            }
            return Notification.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(tap)
                .apply { if (progress in 0..100) setProgress(100, progress, false) else setProgress(0, 0, true) }
                .build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = build(
            this,
            intent?.getStringExtra("title") ?: "MyKit",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("progress", -1) ?: -1,
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            running = true
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't go foreground: ${e.message}")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /** Android 15 limits data-sync services to 6 hours a day. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}

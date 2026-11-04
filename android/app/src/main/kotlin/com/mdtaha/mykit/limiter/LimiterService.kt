package com.mdtaha.mykit.limiter

import android.accessibilityservice.AccessibilityService
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.mdtaha.mykit.AppLanguage
import com.mdtaha.mykit.R
import java.time.LocalDateTime

/**
 * MyKit's screen-time limiter (Settings → Accessibility → MyKit Screen time).
 *
 * Watches which app is in front and, in browsers, which site the address
 * bar shows; counts seconds per platform while the screen is on; warns
 * before the daily limit and opens [BlockActivity] when it's reached or
 * during focus hours. Nothing leaves the phone, and nothing but the app
 * name and the browser's address is read.
 */
class LimiterService : AccessibilityService() {

    private val main = Handler(Looper.getMainLooper())
    private lateinit var store: LimiterStore

    /** What's in front: an app, or a site in a browser. */
    private var foregroundPackage: String? = null
    private var browserHost: String? = null
    private var currentGroup: LimitGroup? = null
    private var screenOn = true
    private var lastUrlCheck = 0L
    private var ticks = 0

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            screenOn = intent.action != Intent.ACTION_SCREEN_OFF
            if (!screenOn) store.flush()
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            onTick()
            main.postDelayed(this, 1000)
        }
    }

    override fun onServiceConnected() {
        store = LimiterStore.get(this)
        running = this
        screenOn = getSystemService(PowerManager::class.java)?.isInteractive != false
        registerReceiver(
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            },
        )
        createChannel()
        main.post(tick)
    }

    override fun onDestroy() {
        running = null
        main.removeCallbacks(tick)
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Exception) {
        }
        if (::store.isInitialized) store.flush()
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                // The app in front (the keyboard or a dialog of another app
                // don't count: use the active window's app).
                val front = rootInActiveWindow?.packageName?.toString() ?: pkg
                if (front in IGNORED || front in keyboards() ||
                    front == packageName && BlockActivity.showing
                ) {
                    return
                }
                if (front != foregroundPackage) {
                    foregroundPackage = front
                    browserHost = null
                    store.flush()
                }
                if (front in BROWSERS) readUrl(force = true)
                update()
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                if (pkg == foregroundPackage && pkg in BROWSERS) {
                    readUrl(force = false)
                    update()
                }
            }
        }
    }

    /** The site in the browser's address bar (kept while the bar is hidden). */
    private fun readUrl(force: Boolean) {
        val now = System.currentTimeMillis()
        if (!force && now - lastUrlCheck < 700) return
        lastUrlCheck = now
        val root = rootInActiveWindow ?: return
        val ids = BROWSERS[foregroundPackage] ?: return
        val text = ids.firstNotNullOfOrNull { id ->
            root.findAccessibilityNodeInfosByViewId(id)?.firstOrNull()?.text?.toString()
        } ?: return
        hostOf(text)?.let { browserHost = it }
    }

    private var keyboardPackages: Set<String>? = null

    /** Installed keyboards: typing doesn't mean the app in front changed. */
    private fun keyboards(): Set<String> = keyboardPackages ?: try {
        getSystemService(android.view.inputmethod.InputMethodManager::class.java)
            ?.inputMethodList?.map { it.packageName }?.toSet().orEmpty()
    } catch (_: Exception) {
        emptySet()
    }.also { keyboardPackages = it }

    /** Re-evaluates now (settings changed, Shorts opened/closed…). */
    fun refresh() {
        store.reloadConfig()
        update()
    }

    /** Which platform (if any) is in front now; blocks if it must. */
    private fun update() {
        val config = store.config
        val pkg = foregroundPackage
        val host = browserHost
        currentGroup = config.groups.firstOrNull { g ->
            g.enabled && (
                (pkg != null && pkg in g.packages) ||
                    (host != null && pkg in BROWSERS && g.matchesHost(host)) ||
                    (g.id == "youtube" && pkg == packageName && shortsActive)
                )
        }
        currentGroup?.let { if (shouldBlock(it)) block(it) }
    }

    private fun onTick() {
        val group = currentGroup ?: return
        if (!screenOn || BlockActivity.showing) return
        store.addSecond(group.id)
        if (++ticks % 10 == 0) store.flush()
        val remaining = group.limitMinutes * 60 - store.secondsToday(group.id)
        val warnAt = store.config.warnMinutes * 60
        if (remaining in 1..warnAt && !store.warnedToday(group.id) &&
            !store.extensionActive(group.id)
        ) {
            store.markWarned(group.id)
            warn(group, remaining)
        }
        if (shouldBlock(group)) block(group)
    }

    private fun shouldBlock(group: LimitGroup): Boolean {
        if (inFocus(group)) return true
        if (store.extensionActive(group.id)) return false
        return store.secondsToday(group.id) >= group.limitMinutes * 60
    }

    private fun inFocus(group: LimitGroup): Boolean {
        val now = LocalDateTime.now()
        return store.config.focus.any { it.isActive(now, group.id) }
    }

    private fun block(group: LimitGroup) {
        if (BlockActivity.showing) return
        store.flush()
        // Leave the app / page, then explain why.
        performGlobalAction(GLOBAL_ACTION_HOME)
        startActivity(
            Intent(this, BlockActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(BlockActivity.EXTRA_GROUP, group.id)
                .putExtra(BlockActivity.EXTRA_FOCUS, inFocus(group)),
        )
        currentGroup = null
        foregroundPackage = null
    }

    private fun createChannel() {
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(
            NotificationChannel(CHANNEL, "Screen time", NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = "Warnings before a daily limit is reached" },
        )
    }

    private fun warn(group: LimitGroup, remainingSeconds: Int) {
        val minutes = (remainingSeconds + 59) / 60
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(
                AppLanguage.t(
                    this,
                    "${group.name}: $minutes min left today",
                    "${group.name}: بقي $minutes د اليوم",
                ),
            )
            .setContentText(
                AppLanguage.t(
                    this,
                    "Your daily limit is almost used up.",
                    "أوشك حدّك اليومي على الانتهاء.",
                ),
            )
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(this).notify(NOTIFICATION_BASE + group.id.hashCode() % 1000, notification)
        } catch (_: SecurityException) {
            // Notifications not allowed; the block screen still works.
        }
    }

    companion object {
        private const val CHANNEL = "screen_time"
        private const val NOTIFICATION_BASE = 7300

        /** The running service, if switched on (for the app's status). */
        @Volatile var running: LimiterService? = null

        /** MyKit's own Shorts player is open (counts as YouTube). */
        @Volatile var shortsActive = false

        /** Address bar view ids per browser. */
        val BROWSERS = mapOf(
            "com.android.chrome" to listOf("com.android.chrome:id/url_bar"),
            "com.chrome.beta" to listOf("com.chrome.beta:id/url_bar"),
            "com.vivaldi.browser" to listOf(
                "com.vivaldi.browser:id/url_bar",
                "com.vivaldi.browser:id/address_bar",
            ),
            "com.brave.browser" to listOf("com.brave.browser:id/url_bar"),
            "com.microsoft.emmx" to listOf("com.microsoft.emmx:id/url_bar"),
            "com.kiwibrowser.browser" to listOf("com.kiwibrowser.browser:id/url_bar"),
            "com.opera.browser" to listOf(
                "com.opera.browser:id/url_field",
                "com.opera.browser:id/url_bar",
            ),
            "com.sec.android.app.sbrowser" to listOf(
                "com.sec.android.app.sbrowser:id/location_bar_edit_text",
            ),
            "org.mozilla.firefox" to listOf(
                "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
            ),
            "com.duckduckgo.mobile.android" to listOf(
                "com.duckduckgo.mobile.android:id/omnibarTextInput",
            ),
            "com.heytap.browser" to listOf("com.heytap.browser:id/url_bar"),
        )

        /** System surfaces that aren't "the app in front". */
        private val IGNORED = setOf("com.android.systemui", "android")

        fun hostOf(text: String): String? {
            var t = text.trim().lowercase()
            if (t.isEmpty() || ' ' in t) return null
            t = t.substringAfter("://")
            val host = t.substringBefore('/').substringBefore('?').substringBefore(':')
            return host.takeIf { it.contains('.') }?.removePrefix("www.")
        }
    }
}

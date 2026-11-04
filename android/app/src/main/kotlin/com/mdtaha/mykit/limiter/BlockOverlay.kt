package com.mdtaha.mykit.limiter

import android.accessibilityservice.AccessibilityService
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.CountDownTimer
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.mdtaha.mykit.AppLanguage
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/**
 * "Time's up" screen drawn by [LimiterService] over the blocked app or site.
 *
 * It's an accessibility overlay rather than an Activity: Android (and OEM
 * skins like OnePlus/ColorOS) can refuse to open an Activity from the
 * background, but an accessibility service may always draw its overlay. The
 * app stays underneath, so after "5 more minutes" you carry on where you were.
 * Close (or Back) goes to the home screen.
 */
class BlockOverlay(private val service: AccessibilityService) {
    private var root: View? = null
    private var timer: CountDownTimer? = null

    /** The platform being blocked, while the overlay is up. */
    var groupId: String? = null
        private set

    val showing get() = root != null

    fun show(group: LimitGroup, focus: Boolean) {
        if (showing) return
        val store = LimiterStore.get(service)
        val view = build(store, group, focus)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.OPAQUE,
        )
        try {
            service.getSystemService(WindowManager::class.java).addView(view, params)
            root = view
            groupId = group.id
        } catch (_: Exception) {
            // Couldn't draw (service unbinding): at least leave the app.
            service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
        }
    }

    fun dismiss() {
        timer?.cancel()
        timer = null
        root?.let {
            try {
                service.getSystemService(WindowManager::class.java).removeView(it)
            } catch (_: Exception) {
            }
        }
        root = null
        groupId = null
    }

    private fun goHome() {
        service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
        dismiss()
    }

    private fun build(store: LimiterStore, group: LimitGroup, focus: Boolean): View {
        val ctx = service
        val dp = ctx.resources.displayMetrics.density
        val ar = AppLanguage.isArabic(ctx)
        fun t(en: String, arabic: String) = if (ar) arabic else en

        val used = store.secondsToday(group.id) / 60
        val title = if (focus) {
            t("${group.name} is paused", "${group.name} متوقف الآن")
        } else {
            t("Time's up for ${group.name}", "انتهى وقت ${group.name}")
        }
        val message = if (focus) {
            val end = store.config.focus
                .firstOrNull { it.isActive(LocalDateTime.now(), group.id) }
                ?.end?.format(DateTimeFormatter.ofPattern("HH:mm"))
            t(
                "Focus hours are on" + (end?.let { " until $it" } ?: "") + ".",
                "ساعات التركيز مفعّلة" + (end?.let { " حتى $it" } ?: "") + ".",
            )
        } else {
            t(
                "You've used $used min of your ${group.limitMinutes} min today.\n" +
                    "It resets at midnight.",
                "استخدمت $used د من ${group.limitMinutes} د اليوم.\n" +
                    "يُعاد ضبطه عند منتصف الليل.",
            )
        }

        fun text(value: String, size: Float, bold: Boolean = false, alpha: Float = 1f) =
            TextView(ctx).apply {
                text = value
                textSize = size
                setTextColor(Color.WHITE)
                this.alpha = alpha
                gravity = Gravity.CENTER
                if (bold) setTypeface(typeface, Typeface.BOLD)
                setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
            }

        fun button(label: String, filled: Boolean) = Button(ctx).apply {
            text = label
            isAllCaps = false
            textSize = 16f
            setTextColor(if (filled) Color.BLACK else Color.WHITE)
            background = GradientDrawable().apply {
                cornerRadius = 28 * dp
                if (filled) setColor(Color.WHITE) else setStroke((1 * dp).toInt(), 0x99FFFFFF.toInt())
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                (52 * dp).toInt(),
            ).apply { topMargin = (12 * dp).toInt() }
        }

        val column = LinearLayout(ctx).apply {
            layoutDirection = if (ar) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            val pad = (32 * dp).toInt()
            setPadding(pad, pad, pad, pad)
        }
        column.addView(text("⏳", 56f))
        column.addView(text(title, 24f, bold = true))
        column.addView(text(message, 16f, alpha = 0.75f))
        column.addView(
            button(t("Close", "إغلاق"), filled = true).apply { setOnClickListener { goHome() } },
        )

        val left = store.extensionsLeft(group.id)
        if (!focus && left > 0) {
            val extra = store.config.extensionMinutes
            val wait = store.config.extensionWaitSeconds
            val more = button(
                t("$extra more minutes · wait $wait s", "$extra دقائق إضافية · انتظر $wait ث"),
                filled = false,
            ).apply {
                isEnabled = false
                alpha = 0.6f
            }
            column.addView(more)
            timer = object : CountDownTimer(wait * 1000L, 1000) {
                override fun onTick(ms: Long) {
                    val s = (ms + 999) / 1000
                    more.text = t("$extra more minutes · wait $s s", "$extra دقائق إضافية · انتظر $s ث")
                }

                override fun onFinish() {
                    more.text = t(
                        "$extra more minutes ($left left today)",
                        "$extra دقائق إضافية (متبقٍّ اليوم: $left)",
                    )
                    more.isEnabled = true
                    more.alpha = 1f
                }
            }.start()
            more.setOnClickListener {
                store.grantExtension(group.id)
                dismiss() // back to the app, for the extra minutes
            }
        } else if (!focus) {
            column.addView(
                text(t("No more extensions today.", "لا مزيد من التمديد اليوم."), 14f, alpha = 0.5f),
            )
        }

        // Full screen, swallowing touches; Back closes like the Close button.
        return object : FrameLayout(ctx) {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK) {
                    if (event.action == KeyEvent.ACTION_UP) goHome()
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }.apply {
            setBackgroundColor(0xFF121317.toInt())
            isClickable = true
            isFocusable = true
            isFocusableInTouchMode = true
            addView(
                column,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }
    }
}

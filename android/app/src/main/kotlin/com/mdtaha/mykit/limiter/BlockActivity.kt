package com.mdtaha.mykit.limiter

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.CountDownTimer
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/**
 * "Time's up" screen shown by [LimiterService] over a blocked app or site.
 * Close goes home; when allowed, "5 more minutes" unlocks after a short
 * wait (friction, not a wall), a limited number of times per day.
 */
class BlockActivity : Activity() {

    private var timer: CountDownTimer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val store = LimiterStore.get(this)
        val groupId = intent.getStringExtra(EXTRA_GROUP) ?: return finish()
        val group = store.config.groups.firstOrNull { it.id == groupId } ?: return finish()
        val focus = intent.getBooleanExtra(EXTRA_FOCUS, false)
        val dp = resources.displayMetrics.density

        val used = store.secondsToday(groupId) / 60
        val title = if (focus) "${group.name} is paused" else "Time's up for ${group.name}"
        val message = if (focus) {
            val end = store.config.focus
                .firstOrNull { it.isActive(LocalDateTime.now(), groupId) }
                ?.end?.format(DateTimeFormatter.ofPattern("HH:mm"))
            "Focus hours are on" + (end?.let { " until $it" } ?: "") + "."
        } else {
            "You've used $used min of your ${group.limitMinutes} min today.\n" +
                "It resets at midnight."
        }

        fun text(value: String, size: Float, bold: Boolean = false, alpha: Float = 1f) =
            TextView(this).apply {
                text = value
                textSize = size
                setTextColor(Color.WHITE)
                this.alpha = alpha
                gravity = Gravity.CENTER
                if (bold) setTypeface(typeface, Typeface.BOLD)
                setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
            }

        fun button(label: String, filled: Boolean) = Button(this).apply {
            text = label
            isAllCaps = false
            textSize = 16f
            setTextColor(if (filled) Color.BLACK else Color.WHITE)
            background = GradientDrawable().apply {
                cornerRadius = 28 * dp
                if (filled) setColor(Color.WHITE) else setStroke((1 * dp).toInt(), 0x66FFFFFF)
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                (52 * dp).toInt(),
            ).apply { topMargin = (12 * dp).toInt() }
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF121317.toInt())
            val pad = (32 * dp).toInt()
            setPadding(pad, pad, pad, pad)
        }
        root.addView(text("⏳", 56f))
        root.addView(text(title, 24f, bold = true))
        root.addView(text(message, 16f, alpha = 0.75f))

        root.addView(
            button("Close", filled = true).apply { setOnClickListener { goHome() } },
        )

        val left = store.extensionsLeft(groupId)
        if (!focus && left > 0) {
            val extra = store.config.extensionMinutes
            val more = button("", filled = false).apply { isEnabled = false }
            root.addView(more)
            timer = object : CountDownTimer(store.config.extensionWaitSeconds * 1000L, 1000) {
                override fun onTick(ms: Long) {
                    more.text = "$extra more minutes · wait ${(ms + 999) / 1000} s"
                }

                override fun onFinish() {
                    more.text = "$extra more minutes ($left left today)"
                    more.isEnabled = true
                }
            }.start()
            more.setOnClickListener {
                store.grantExtension(groupId)
                finish()
            }
        } else if (!focus) {
            root.addView(text("No more extensions today.", 14f, alpha = 0.5f))
        }
        setContentView(root)
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        finish()
    }

    @Deprecated("Back closes, like the Close button.")
    override fun onBackPressed() = goHome()

    override fun onResume() {
        super.onResume()
        showing = true
    }

    override fun onPause() {
        super.onPause()
        showing = false
    }

    override fun onDestroy() {
        timer?.cancel()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_GROUP = "group"
        const val EXTRA_FOCUS = "focus"

        @Volatile var showing = false
    }
}

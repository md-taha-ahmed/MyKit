package com.mdtaha.mykit.widgets

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.mdtaha.mykit.MainActivity
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Lets the user choose which countdown a widget shows. Opened by the launcher
 * when the widget is added (or reconfigured), and when an unlinked widget is tapped.
 */
class CountdownWidgetConfigureActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Backing out of the picker cancels adding the widget.
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val countdowns = CountdownData.listFromJson(
            HomeWidgetPlugin.getData(this).getString(CountdownWidgetProvider.KEY_COUNTDOWNS, null),
        )
        setContentView(buildContent(countdowns))
    }

    private fun buildContent(countdowns: List<CountdownData>): LinearLayout {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#2B2B2E"))
            setPadding(dp(20), dp(20), dp(20), dp(12))
            minimumWidth = dp(300)
        }

        root.addView(TextView(this).apply {
            text = "Choose countdown"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            setPadding(0, 0, 0, dp(12))
        })

        if (countdowns.isEmpty()) {
            root.addView(TextView(this).apply {
                text = "You don't have any countdowns yet. Create one in MyKit, " +
                    "then tap this widget to link it."
                setTextColor(Color.parseColor("#B3FFFFFF"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            })
        } else {
            val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            countdowns.forEach { list.addView(buildRow(it)) }
            root.addView(
                ScrollView(this).apply { addView(list) },
                // Weighted so a long list scrolls instead of pushing the button off-screen.
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, 1f),
            )
        }

        root.addView(Button(this).apply {
            text = "Create new countdown"
            setOnClickListener { createNew() }
        }, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            topMargin = dp(12)
        })
        return root
    }

    private fun buildRow(countdown: CountdownData): LinearLayout {
        val snap = CountdownMath.snapshot(countdown)
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), 0, dp(8))
            isClickable = true
            val ripple = TypedValue()
            context.theme.resolveAttribute(android.R.attr.selectableItemBackground, ripple, true)
            setBackgroundResource(ripple.resourceId)
            setOnClickListener { select(countdown) }

            addView(ImageView(context).apply {
                setImageBitmap(CountdownRenderer.render(countdown, dp(52)))
            }, LinearLayout.LayoutParams(dp(52), dp(52)))

            addView(TextView(context).apply {
                text = countdown.title.ifBlank { "Untitled" } +
                    "\n${snap.valueText} ${snap.label.lowercase()}"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setPadding(dp(16), 0, 0, 0)
            })
        }
    }

    private fun select(countdown: CountdownData) {
        CountdownWidgetProvider.bind(this, appWidgetId, countdown.id)
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )
        finish()
    }

    private fun createNew() {
        // Keep the widget (unlinked); tapping it later opens this picker again.
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )
        CountdownWidgetProvider.updateAll(this)
        startActivity(Intent(this, MainActivity::class.java).apply {
            action = "es.antonborri.home_widget.action.LAUNCH"
            data = Uri.parse("mykit://countdown/new")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
        finish()
    }

    private fun dp(value: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP,
        value.toFloat(),
        resources.displayMetrics,
    ).toInt()
}

package com.mdtaha.mykit.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.mdtaha.mykit.MainActivity
import com.mdtaha.mykit.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen countdown widget. Each widget instance is linked to one countdown
 * through the `widget_<appWidgetId>` key in the home_widget shared preferences.
 */
class CountdownWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) updateWidget(context, appWidgetManager, id, widgetData)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val editor = HomeWidgetPlugin.getData(context).edit()
        for (id in appWidgetIds) editor.remove(mappingKey(id))
        editor.apply()
    }

    companion object {
        const val KEY_COUNTDOWNS = "countdowns"
        private const val KEY_PENDING_PIN = "pending_pin_countdown_id"
        private const val BITMAP_SIZE = 400

        fun mappingKey(appWidgetId: Int) = "widget_$appWidgetId"

        fun bind(context: Context, appWidgetId: Int, countdownId: String) {
            HomeWidgetPlugin.getData(context).edit()
                .putString(mappingKey(appWidgetId), countdownId)
                .remove(KEY_PENDING_PIN)
                .apply()
            updateWidget(
                context,
                AppWidgetManager.getInstance(context),
                appWidgetId,
                HomeWidgetPlugin.getData(context),
            )
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, CountdownWidgetProvider::class.java),
            )
            val prefs = HomeWidgetPlugin.getData(context)
            for (id in ids) updateWidget(context, manager, id, prefs)
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            prefs: SharedPreferences,
        ) {
            var countdownId = prefs.getString(mappingKey(appWidgetId), null)

            // A widget pinned from inside the app gets the countdown that requested it.
            if (countdownId == null) {
                val pending = prefs.getString(KEY_PENDING_PIN, null)
                if (pending != null) {
                    prefs.edit()
                        .putString(mappingKey(appWidgetId), pending)
                        .remove(KEY_PENDING_PIN)
                        .apply()
                    countdownId = pending
                }
            }

            val countdown = CountdownData.listFromJson(prefs.getString(KEY_COUNTDOWNS, null))
                .firstOrNull { it.id == countdownId }

            val views = RemoteViews(context.packageName, R.layout.countdown_widget)

            if (countdown == null) {
                views.setImageViewBitmap(
                    R.id.widget_ring,
                    CountdownRenderer.renderPlaceholder(BITMAP_SIZE),
                )
                views.setViewVisibility(R.id.widget_title, View.GONE)
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    configureIntent(context, appWidgetId),
                )
            } else {
                views.setImageViewBitmap(
                    R.id.widget_ring,
                    CountdownRenderer.render(countdown, BITMAP_SIZE),
                )
                val showTitle = countdown.showTitleInWidget && countdown.title.isNotBlank()
                views.setTextViewText(R.id.widget_title, countdown.title)
                views.setViewVisibility(
                    R.id.widget_title,
                    if (showTitle) View.VISIBLE else View.GONE,
                )
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("mykit://countdown/${countdown.id}"),
                    ),
                )
            }

            manager.updateAppWidget(appWidgetId, views)
        }

        private fun configureIntent(context: Context, appWidgetId: Int): PendingIntent {
            val intent = Intent(context, CountdownWidgetConfigureActivity::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                // Unique data so each widget gets its own PendingIntent.
                data = Uri.parse("mykit://widget-config/$appWidgetId")
            }
            return PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}

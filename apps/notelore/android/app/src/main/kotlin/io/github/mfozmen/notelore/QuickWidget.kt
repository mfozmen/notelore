package io.github.mfozmen.notelore

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * The home-screen widget (#799). It shows what the app last handed it
 * (quick_widget.dart's widgetData, kept in [PREFS]); a tap opens MainActivity
 * with one of the widget's links, which the app checks again before acting.
 */
class QuickWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = views(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    companion object {
        const val ACTION = "io.github.mfozmen.notelore.QUICK"
        private const val PREFS = "quick_widget"
        private const val DATA = "data"

        /** Keeps [data] (JSON from the app) and draws every placed widget with it. */
        fun refresh(context: Context, data: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(DATA, data).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, QuickWidget::class.java))
            if (ids.isNotEmpty()) manager.updateAppWidget(ids, views(context))
        }

        private fun views(context: Context): RemoteViews {
            val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(DATA, null)
            val data = runCatching { JSONObject(saved ?: "{}") }.getOrDefault(JSONObject())
            val views = RemoteViews(context.packageName, R.layout.quick_widget)
            if (data.has("hint")) views.setTextViewText(R.id.qw_hint, data.getString("hint"))
            val sync = data.optString("sync")
            val shown = if (sync.isEmpty()) View.GONE else View.VISIBLE
            views.setTextViewText(R.id.qw_sync, sync)
            views.setViewVisibility(R.id.qw_sync, shown)
            views.setViewVisibility(R.id.qw_dot, shown)
            views.setContentDescription(R.id.qw_talk, data.optString("talk"))
            views.setOnClickPendingIntent(R.id.qw_hint, open(context, "notelore-widget://write", 0))
            views.setOnClickPendingIntent(R.id.qw_talk, open(context, "notelore-widget://talk", 1))
            val notes = data.optJSONArray("notes")
            val rows = listOf(
                Triple(R.id.qw_note1, R.id.qw_title1, R.id.qw_date1),
                Triple(R.id.qw_note2, R.id.qw_title2, R.id.qw_date2),
            )
            rows.forEachIndexed { i, (row, title, date) ->
                val note = notes?.optJSONObject(i)
                views.setViewVisibility(row, if (note == null) View.GONE else View.VISIBLE)
                if (note != null) {
                    views.setTextViewText(title, note.optString("title"))
                    views.setTextViewText(date, note.optString("date"))
                    views.setOnClickPendingIntent(row, open(context, note.optString("open"), 2 + i))
                }
            }
            views.setViewVisibility(R.id.qw_line2, if ((notes?.length() ?: 0) > 1) View.VISIBLE else View.GONE)
            return views
        }

        private fun open(context: Context, link: String, code: Int): PendingIntent = PendingIntent.getActivity(
            context,
            code,
            Intent()
                .setClassName(context, "${context.packageName}.QuickOpen")
                .setAction(ACTION)
                .setData(Uri.parse(link))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

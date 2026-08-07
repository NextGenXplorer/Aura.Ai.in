package com.aura.mobile.aura_mobile.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import com.aura.mobile.aura_mobile.R

/**
 * AURA Daily Briefing widget: a scrollable news list plus weather and a quote.
 *
 * The clock is a `TextClock`, so the time ticks on its own every minute without
 * the provider being woken — an `AppWidgetProvider` cannot redraw itself more
 * often than roughly every 30 minutes, so a rendered timestamp went stale
 * almost immediately in the old version.
 *
 * Data refreshes come from three places:
 *  - the OS update period (30 min),
 *  - the in-widget refresh button, and
 *  - WorkManager / app-open pushes from Dart (`HomeWidgetService`).
 */
class AuraBriefingWidget : AppWidgetProvider() {

    companion object {
        private const val TAG = "AuraBriefingWidget"

        /** Retained for compatibility; the shared constant is authoritative. */
        const val ACTION_REFRESH = WidgetPrefs.ACTION_REFRESH

        /** Sent when a headline row is tapped. */
        const val ACTION_OPEN_ARTICLE = "com.aura.mobile.widget.ACTION_OPEN_ARTICLE"

        /** Article URL carried by [ACTION_OPEN_ARTICLE]. */
        const val EXTRA_ARTICLE_LINK = "article_link"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                render(context, appWidgetManager, appWidgetId, showSpinner = false)
            } catch (e: Exception) {
                Log.e(TAG, "onUpdate failed for $appWidgetId: ${e.message}")
            }
        }
        if (WidgetPrefs.isStale(WidgetPrefs.prefs(context), WidgetNewsStore.MAX_AGE_MILLIS)) {
            refresh(context, showSpinner = false)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetPrefs.ACTION_REFRESH -> refresh(context, showSpinner = true)
            ACTION_OPEN_ARTICLE -> openArticle(context, intent.getStringExtra(EXTRA_ARTICLE_LINK))
        }
    }

    /** Re-renders every placed instance, then refetches and re-renders again. */
    private fun refresh(context: Context, showSpinner: Boolean) {
        try {
            val manager = AppWidgetManager.getInstance(context)
            val ids = WidgetPrefs.widgetIds(context, AuraBriefingWidget::class.java)
            if (ids.isEmpty()) return

            if (showSpinner) {
                for (id in ids) render(context, manager, id, showSpinner = true)
            }

            WidgetNewsStore.refreshAsync(context) {
                Handler(Looper.getMainLooper()).post {
                    try {
                        for (id in ids) {
                            render(context, manager, id, showSpinner = false)
                            // Tell the launcher's adapter to re-read the cache.
                            manager.notifyAppWidgetViewDataChanged(id, R.id.news_list)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Post-fetch render failed: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Refresh failed: ${e.message}")
        }
    }

    /**
     * Opens a tapped headline in the browser, falling back to opening AURA when
     * the feed gave us no link or no browser can handle it.
     */
    private fun openArticle(context: Context, link: String?) {
        if (link.isNullOrBlank()) {
            launchApp(context)
            return
        }
        try {
            val browser = Intent(Intent.ACTION_VIEW, Uri.parse(link)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(browser)
        } catch (e: Exception) {
            Log.e(TAG, "Could not open article: ${e.message}")
            launchApp(context)
        }
    }

    private fun launchApp(context: Context) {
        try {
            WidgetPrefs.openAppIntent(context, null, REQ_OPEN_APP).send()
        } catch (e: PendingIntent.CanceledException) {
            Log.e(TAG, "Launch cancelled: ${e.message}")
        }
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        showSpinner: Boolean
    ) {
        val views = RemoteViews(context.packageName, R.layout.aura_briefing_widget)
        val prefs = WidgetPrefs.prefs(context)

        // Header: tapping the title opens the in-app briefing screen.
        views.setOnClickPendingIntent(
            R.id.header_row,
            WidgetPrefs.openAppIntent(context, ROUTE_BRIEFING, REQ_HEADER)
        )
        views.setOnClickPendingIntent(
            R.id.widget_refresh,
            WidgetPrefs.refreshIntent(context, AuraBriefingWidget::class.java, REQ_REFRESH)
        )
        views.setViewVisibility(
            R.id.widget_refreshing,
            if (showSpinner) View.VISIBLE else View.GONE
        )
        views.setViewVisibility(
            R.id.widget_refresh,
            if (showSpinner) View.GONE else View.VISIBLE
        )

        // Scrollable headline list.
        val serviceIntent = Intent(context, NewsWidgetService::class.java).apply {
            // The adapter is cached per intent; the widget id keeps instances
            // from sharing one adapter across differently sized placements.
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }
        views.setRemoteAdapter(R.id.news_list, serviceIntent)
        views.setEmptyView(R.id.news_list, R.id.news_empty)

        val rowTemplate = PendingIntent.getBroadcast(
            context,
            REQ_ARTICLE_TEMPLATE,
            Intent(context, AuraBriefingWidget::class.java).apply {
                action = ACTION_OPEN_ARTICLE
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        views.setPendingIntentTemplate(R.id.news_list, rowTemplate)

        // Footer.
        views.setTextViewText(
            R.id.widget_weather,
            WidgetPrefs.readText(prefs, WidgetPrefs.KEY_WEATHER) ?: "Weather unavailable"
        )
        views.setTextViewText(
            R.id.widget_quote,
            WidgetPrefs.readText(prefs, WidgetPrefs.KEY_QUOTE) ?: "✦ AURA AI"
        )
        views.setOnClickPendingIntent(
            R.id.footer_row,
            WidgetPrefs.openAppIntent(context, null, REQ_OPEN_APP)
        )

        appWidgetManager.updateAppWidget(appWidgetId, views)
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.news_list)
    }
}

// Distinct request codes: Android matches cached PendingIntents by request code
// and ignores extras, so shared codes would make every tap do the same thing.
private const val REQ_HEADER = 100
private const val REQ_REFRESH = 101
private const val REQ_OPEN_APP = 102
private const val REQ_ARTICLE_TEMPLATE = 103

private const val ROUTE_BRIEFING = "daily_briefing"

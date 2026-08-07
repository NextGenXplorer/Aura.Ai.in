package com.aura.mobile.aura_mobile.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.util.Log
import android.widget.RemoteViews
import com.aura.mobile.aura_mobile.R

/**
 * A row of shortcuts straight into AURA: ask, voice, scan, image.
 *
 * This widget holds no cached data, so it is never stale and never waits on the
 * network — every tap routes into the app immediately.
 */
class AuraQuickActionsWidget : AppWidgetProvider() {

    companion object {
        private const val TAG = "AuraQuickActions"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                render(context, appWidgetManager, appWidgetId)
            } catch (e: Exception) {
                Log.e(TAG, "onUpdate failed for $appWidgetId: ${e.message}")
            }
        }
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val views = RemoteViews(context.packageName, R.layout.aura_quick_actions_widget)

        views.setOnClickPendingIntent(
            R.id.action_ask,
            WidgetPrefs.openAppIntent(context, "chat", REQ_ASK)
        )
        views.setOnClickPendingIntent(
            R.id.action_voice,
            WidgetPrefs.openAppIntent(context, "voice", REQ_VOICE)
        )
        views.setOnClickPendingIntent(
            R.id.action_scan,
            WidgetPrefs.openAppIntent(context, "camera_scan", REQ_SCAN)
        )
        views.setOnClickPendingIntent(
            R.id.action_image,
            WidgetPrefs.openAppIntent(context, "image_studio", REQ_IMAGE)
        )

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}

private const val REQ_ASK = 200
private const val REQ_VOICE = 201
private const val REQ_SCAN = 202
private const val REQ_IMAGE = 203

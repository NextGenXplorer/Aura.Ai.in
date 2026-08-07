package com.aura.mobile.aura_mobile.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import com.aura.mobile.aura_mobile.R

/**
 * Study progress at a glance: cards due for review, current streak and a
 * countdown to the next exam.
 *
 * Values are written by Dart (`HomeWidgetService.updateStudyData`) whenever the
 * study data changes — reviewing a card or adding an exam pushes an update, so
 * the widget tracks the app rather than waiting for a timer.
 */
class AuraStudyWidget : AppWidgetProvider() {

    companion object {
        private const val TAG = "AuraStudyWidget"
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

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != WidgetPrefs.ACTION_REFRESH) return
        try {
            val manager = AppWidgetManager.getInstance(context)
            for (id in WidgetPrefs.widgetIds(context, AuraStudyWidget::class.java)) {
                render(context, manager, id)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Refresh failed: ${e.message}")
        }
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val views = RemoteViews(context.packageName, R.layout.aura_study_widget)
        val prefs = WidgetPrefs.prefs(context)

        val due = WidgetPrefs.readInt(prefs, WidgetPrefs.KEY_STUDY_DUE)
        val streak = WidgetPrefs.readInt(prefs, WidgetPrefs.KEY_STUDY_STREAK)
        val decks = WidgetPrefs.readInt(prefs, WidgetPrefs.KEY_STUDY_DECKS)
        val examName = WidgetPrefs.readText(prefs, WidgetPrefs.KEY_STUDY_EXAM_NAME)
        val examDays = WidgetPrefs.readInt(prefs, WidgetPrefs.KEY_STUDY_EXAM_DAYS, -1)

        views.setTextViewText(R.id.study_due_count, due.toString())
        views.setTextViewText(
            R.id.study_due_label,
            if (due == 1) "card due" else "cards due"
        )
        views.setTextViewText(R.id.study_streak, "🔥 $streak day streak")

        if (examName != null && examDays >= 0) {
            views.setViewVisibility(R.id.study_exam, View.VISIBLE)
            val countdown = when {
                examDays == 0 -> "today"
                examDays == 1 -> "tomorrow"
                else -> "in $examDays days"
            }
            views.setTextViewText(R.id.study_exam, "📅 $examName $countdown")
        } else {
            views.setViewVisibility(R.id.study_exam, View.GONE)
        }

        // Nudge the user toward the action that matters right now.
        val cta = when {
            decks == 0 -> "Create your first deck"
            due > 0 -> "Review now →"
            else -> "All caught up ✓"
        }
        views.setTextViewText(R.id.study_cta, cta)

        val target = if (due > 0) "flashcard_review" else "study_dashboard"
        views.setOnClickPendingIntent(
            R.id.study_container,
            WidgetPrefs.openAppIntent(context, target, REQ_STUDY_OPEN)
        )
        views.setOnClickPendingIntent(
            R.id.study_quiz,
            WidgetPrefs.openAppIntent(context, "quiz", REQ_STUDY_QUIZ)
        )

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}

private const val REQ_STUDY_OPEN = 300
private const val REQ_STUDY_QUIZ = 301

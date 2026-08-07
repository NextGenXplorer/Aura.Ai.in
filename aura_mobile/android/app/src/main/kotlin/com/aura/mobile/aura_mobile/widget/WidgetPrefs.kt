package com.aura.mobile.aura_mobile.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import com.aura.mobile.aura_mobile.MainActivity

/**
 * Shared helpers for every AURA home screen widget.
 *
 * All widgets read the same `HomeWidgetPreferences` store that the `home_widget`
 * plugin writes from Dart, so there is exactly one contract between the Flutter
 * side and the native providers.
 */
object WidgetPrefs {

    /** Preference file used by the home_widget plugin. */
    const val FILE = "HomeWidgetPreferences"

    /** Broadcast any widget can send to force a re-render plus a data refresh. */
    const val ACTION_REFRESH = "com.aura.mobile.widget.ACTION_REFRESH"

    /** Extra carrying an in-app destination for [openAppIntent]. */
    const val EXTRA_ROUTE = "aura_widget_route"

    // ── Data keys (mirrored in lib/features/daily_briefing/home_widget_service.dart) ──

    /** JSON array of `{"title":…,"source":…,"link":…}` objects. */
    const val KEY_HEADLINES_JSON = "widget_headlines_json"
    const val KEY_WEATHER = "widget_weather"
    const val KEY_QUOTE = "widget_quote"
    const val KEY_LAST_FETCH = "widget_last_fetch"

    // Legacy flat headline keys, still written so an older placed widget that
    // has not been recreated keeps working.
    const val KEY_HEADLINE_1 = "widget_headline_1"
    const val KEY_HEADLINE_1_SOURCE = "widget_headline_1_source"

    // Study widget keys
    const val KEY_STUDY_DUE = "widget_study_due"
    const val KEY_STUDY_STREAK = "widget_study_streak"
    const val KEY_STUDY_EXAM_NAME = "widget_study_exam_name"
    const val KEY_STUDY_EXAM_DAYS = "widget_study_exam_days"
    const val KEY_STUDY_DECKS = "widget_study_decks"

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /**
     * Reads a value that may have been stored as Long, Int or String.
     *
     * `home_widget` serialises a Dart `int` as Int or Long depending on its
     * magnitude, and older builds of this app wrote some of these as strings.
     * A bare `getLong` threw ClassCastException and killed the widget update.
     */
    fun readLong(prefs: SharedPreferences, key: String, fallback: Long = 0L): Long {
        return when (val raw = prefs.all[key]) {
            is Long -> raw
            is Int -> raw.toLong()
            is String -> raw.toLongOrNull() ?: fallback
            else -> fallback
        }
    }

    fun readInt(prefs: SharedPreferences, key: String, fallback: Int = 0): Int =
        readLong(prefs, key, fallback.toLong()).toInt()

    /** Reads a string, treating blank values as absent. */
    fun readText(prefs: SharedPreferences, key: String): String? {
        val raw = prefs.all[key] ?: return null
        val text = raw.toString()
        return if (text.isBlank()) null else text
    }

    /** True when cached data is older than [maxAgeMillis]. */
    fun isStale(prefs: SharedPreferences, maxAgeMillis: Long): Boolean {
        val last = readLong(prefs, KEY_LAST_FETCH)
        return (System.currentTimeMillis() - last) > maxAgeMillis
    }

    /**
     * Opens AURA, optionally jumping straight to an in-app [route].
     *
     * [requestCode] must differ per distinct intent inside one widget: Android
     * caches PendingIntents by request code and ignores extras when matching,
     * so reusing 0 everywhere would make every button open the same screen.
     */
    fun openAppIntent(context: Context, route: String?, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (route != null) putExtra(EXTRA_ROUTE, route)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Broadcast that makes [provider] re-render and refetch. */
    fun refreshIntent(
        context: Context,
        provider: Class<*>,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(context, provider).apply { action = ACTION_REFRESH }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Every placed widget id for [provider]. */
    fun widgetIds(context: Context, provider: Class<*>): IntArray {
        val manager = AppWidgetManager.getInstance(context)
        return manager.getAppWidgetIds(ComponentName(context, provider))
    }
}

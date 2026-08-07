package com.aura.mobile.aura_mobile.widget

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** One news headline shown in the briefing widget. */
data class WidgetHeadline(
    val title: String,
    val source: String,
    val link: String
)

/**
 * Cache and fetcher for the headlines shown by [AuraBriefingWidget].
 *
 * Headlines live in a single JSON array so the widget is not limited to the
 * three hardcoded slots the previous layout had — the list widget renders as
 * many as the user's chosen widget height allows.
 */
object WidgetNewsStore {

    private const val TAG = "WidgetNewsStore"
    private const val FEED = "https://news.google.com/rss?hl=en-IN&gl=IN&ceid=IN:en"
    private const val MAX_ITEMS = 15

    /** Data older than this is refetched on the next render. */
    const val MAX_AGE_MILLIS = 15 * 60 * 1000L

    private val executor = Executors.newSingleThreadExecutor()

    fun read(context: Context): List<WidgetHeadline> {
        val raw = WidgetPrefs.readText(WidgetPrefs.prefs(context), WidgetPrefs.KEY_HEADLINES_JSON)
            ?: return readLegacy(context)
        return try {
            val array = JSONArray(raw)
            val items = ArrayList<WidgetHeadline>(array.length())
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                val title = obj.optString("title")
                if (title.isBlank()) continue
                items.add(
                    WidgetHeadline(
                        title = title,
                        source = obj.optString("source"),
                        link = obj.optString("link")
                    )
                )
            }
            if (items.isEmpty()) readLegacy(context) else items
        } catch (e: Exception) {
            Log.e(TAG, "Headline JSON parse failed: ${e.message}")
            readLegacy(context)
        }
    }

    /**
     * Falls back to the old flat `widget_headline_1..3` keys so a widget placed
     * before this change still shows something before the first refresh.
     */
    private fun readLegacy(context: Context): List<WidgetHeadline> {
        val prefs = WidgetPrefs.prefs(context)
        val items = mutableListOf<WidgetHeadline>()
        for (i in 1..3) {
            val title = WidgetPrefs.readText(prefs, "widget_headline_$i") ?: continue
            val source = WidgetPrefs.readText(prefs, "widget_headline_${i}_source") ?: ""
            items.add(WidgetHeadline(title, source, ""))
        }
        return items
    }

    private fun write(context: Context, headlines: List<WidgetHeadline>) {
        val array = JSONArray()
        for (headline in headlines) {
            array.put(
                JSONObject().apply {
                    put("title", headline.title)
                    put("source", headline.source)
                    put("link", headline.link)
                }
            )
        }
        WidgetPrefs.prefs(context).edit().apply {
            putString(WidgetPrefs.KEY_HEADLINES_JSON, array.toString())
            // Keep the legacy keys in sync for older placed widgets.
            putString(WidgetPrefs.KEY_HEADLINE_1, headlines.firstOrNull()?.title ?: "")
            putString(WidgetPrefs.KEY_HEADLINE_1_SOURCE, headlines.firstOrNull()?.source ?: "")
            putLong(WidgetPrefs.KEY_LAST_FETCH, System.currentTimeMillis())
            apply()
        }
    }

    /**
     * Fetches headlines off the main thread, caches them, then runs [onDone] on
     * the caller's looper-free background thread. Never throws.
     */
    fun refreshAsync(context: Context, onDone: () -> Unit) {
        executor.execute {
            try {
                val headlines = fetchFeed()
                if (headlines.isNotEmpty()) write(context, headlines)
            } catch (e: Exception) {
                Log.e(TAG, "News refresh failed: ${e.message}")
            } finally {
                onDone()
            }
        }
    }

    private fun fetchFeed(): List<WidgetHeadline> {
        val headlines = mutableListOf<WidgetHeadline>()
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(FEED).openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 10_000
                requestMethod = "GET"
                setRequestProperty("User-Agent", "AuraMobile/1.0")
            }
            if (connection.responseCode != 200) return headlines

            val content = connection.inputStream.bufferedReader().readText()

            val itemRegex = Regex("<item>(.*?)</item>", RegexOption.DOT_MATCHES_ALL)
            val titleRegex = Regex("<title><!\\[CDATA\\[(.*?)]]></title>|<title>(.*?)</title>")
            val sourceRegex = Regex("<source[^>]*>(.*?)</source>")
            val linkRegex = Regex("<link>(.*?)</link>")

            for (item in itemRegex.findAll(content).take(MAX_ITEMS)) {
                val body = item.groupValues[1]
                val titleMatch = titleRegex.find(body)
                val title = titleMatch?.let {
                    it.groupValues[1].ifEmpty { it.groupValues[2] }
                }?.trim().orEmpty()

                if (title.isEmpty() || title.contains("Google News")) continue

                headlines.add(
                    WidgetHeadline(
                        title = decodeEntities(title),
                        source = decodeEntities(sourceRegex.find(body)?.groupValues?.get(1)?.trim().orEmpty()),
                        link = linkRegex.find(body)?.groupValues?.get(1)?.trim().orEmpty()
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "RSS fetch error: ${e.message}")
        } finally {
            try {
                connection?.disconnect()
            } catch (_: Exception) {
            }
        }
        return headlines
    }

    /** RSS titles arrive HTML-escaped; raw `&amp;#39;` in a widget looks broken. */
    private fun decodeEntities(value: String): String = value
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&nbsp;", " ")
}

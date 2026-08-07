package com.aura.mobile.aura_mobile.widget

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.aura.mobile.aura_mobile.R

/**
 * Feeds the scrollable headline list inside [AuraBriefingWidget].
 *
 * A plain layout can only hold a fixed number of headlines, which is why the
 * old widget showed exactly three. A collection widget lets the list scroll, so
 * the user sees as many headlines as their widget size allows and can flick
 * through the rest.
 */
class NewsWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        NewsRemoteViewsFactory(applicationContext)
}

private class NewsRemoteViewsFactory(
    private val context: Context
) : RemoteViewsService.RemoteViewsFactory {

    private var headlines: List<WidgetHeadline> = emptyList()

    override fun onCreate() {
        headlines = WidgetNewsStore.read(context)
    }

    /**
     * Called on every `notifyAppWidgetViewDataChanged`. Reads the cache only —
     * network work belongs to the provider, because this runs on the launcher's
     * binder thread and blocking here stalls the list.
     */
    override fun onDataSetChanged() {
        headlines = WidgetNewsStore.read(context)
    }

    override fun onDestroy() {
        headlines = emptyList()
    }

    override fun getCount(): Int = headlines.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_news_item)

        // The adapter can be queried after the data shrank; bailing out with an
        // empty row avoids an IndexOutOfBounds inside the launcher process.
        val headline = headlines.getOrNull(position) ?: return views

        views.setTextViewText(R.id.news_item_title, headline.title)
        views.setTextViewText(
            R.id.news_item_source,
            headline.source.ifBlank { "News" }
        )
        views.setTextViewText(R.id.news_item_index, "${position + 1}")

        // Per-row click. The provider sets a PendingIntentTemplate; this fill-in
        // carries the row's own article link.
        val fillIn = Intent().apply {
            putExtra(AuraBriefingWidget.EXTRA_ARTICLE_LINK, headline.link)
        }
        views.setOnClickFillInIntent(R.id.news_item_root, fillIn)

        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        headlines.getOrNull(position)?.title?.hashCode()?.toLong() ?: position.toLong()

    override fun hasStableIds(): Boolean = true
}

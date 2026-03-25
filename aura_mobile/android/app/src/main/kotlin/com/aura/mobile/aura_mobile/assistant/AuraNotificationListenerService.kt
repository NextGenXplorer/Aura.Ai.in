package com.aura.mobile.aura_mobile.assistant

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.text.TextUtils
import android.util.Log

class AuraNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "AuraNotifListener"
        private const val MAX_NOTIFICATIONS = 200

        /** In-memory store of captured notifications, newest first. */
        private val notifications = mutableListOf<Map<String, Any?>>()
        private val lock = Any()

        // ── Package filters ──────────────────────────────────────────────────
        /** System / low-value packages whose notifications should be ignored. */
        private val IGNORED_PACKAGES = setOf(
            "android",
            "com.android.systemui",
            "com.android.providers.downloads",
            "com.android.vending",          // Play Store progress
            "com.android.shell",            // USB debugging
            "com.android.server.telecom",
            "com.google.android.gms",       // Play Services internal
            "com.google.android.gsf",
            "com.google.android.packageinstaller",
            "com.aura.mobile.aura_mobile",  // Our own notifications
        )

        /** Category / flag combos we consider low-value. */
        private val IGNORED_CATEGORIES = setOf(
            Notification.CATEGORY_TRANSPORT,   // media playback controls
            Notification.CATEGORY_SERVICE,     // foreground-service ongoing
            Notification.CATEGORY_SYSTEM,      // system-level noise
            Notification.CATEGORY_PROGRESS,    // download progress bars
        )

        // ── Public API ───────────────────────────────────────────────────────

        /**
         * Returns notifications captured since [sinceMillis] (epoch ms).
         * Returns newest-first.
         */
        fun getRecentNotifications(sinceMillis: Long): List<Map<String, Any?>> {
            synchronized(lock) {
                return notifications.filter {
                    (it["postTime"] as? Long ?: 0L) >= sinceMillis
                }.toList()
            }
        }

        /**
         * Returns notifications grouped by app package name.
         * Each entry: { "appName": String, "packageName": String, "count": Int, "notifications": List }
         */
        fun getGroupedByApp(): List<Map<String, Any?>> {
            synchronized(lock) {
                return notifications
                    .groupBy { it["packageName"] as? String ?: "unknown" }
                    .map { (pkg, items) ->
                        mapOf(
                            "appName" to (items.firstOrNull()?.get("appName") ?: pkg),
                            "packageName" to pkg,
                            "count" to items.size,
                            "notifications" to items,
                        )
                    }
                    .sortedByDescending { it["count"] as Int }
            }
        }

        /** Clear all stored notifications. */
        fun clearAll() {
            synchronized(lock) {
                notifications.clear()
            }
        }

        /**
         * Check whether the user has granted NotificationListenerService permission.
         */
        fun isServiceEnabled(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false

            val componentName = ComponentName(context, AuraNotificationListenerService::class.java)
            return flat.split(":").any {
                val cn = ComponentName.unflattenFromString(it)
                cn != null && cn == componentName
            }
        }
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "NotificationListenerService connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "NotificationListenerService disconnected")
    }

    // ── Core capture logic ───────────────────────────────────────────────────

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val packageName = sbn.packageName ?: return

        // Filter: ignored packages
        if (IGNORED_PACKAGES.contains(packageName)) return

        // Filter: ongoing / group summary / non-clearable system noise
        if (sbn.isOngoing) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        // Filter: ignored categories
        val category = notification.category
        if (category != null && IGNORED_CATEGORIES.contains(category)) return

        // Extract content
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()

        // Filter: empty notifications (no meaningful content)
        if (title.isNullOrBlank() && text.isNullOrBlank()) return

        // Use big text if available (more content), otherwise fall back to text
        val displayText = if (!bigText.isNullOrBlank()) bigText else text

        // Get app display name
        val appName = getAppDisplayName(packageName)

        val entry: Map<String, Any?> = mapOf(
            "packageName" to packageName,
            "appName" to appName,
            "title" to (title ?: ""),
            "text" to (displayText ?: ""),
            "category" to (category ?: ""),
            "postTime" to sbn.postTime,
        )

        synchronized(lock) {
            // Add newest at front
            notifications.add(0, entry)

            // Prune old entries if we exceed max
            while (notifications.size > MAX_NOTIFICATIONS) {
                notifications.removeAt(notifications.size - 1)
            }
        }

        Log.d(TAG, "Captured: [$appName] $title — ${displayText?.take(60)}")
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // We keep the notification in our store even after dismissal —
        // the digest wants a history of what arrived, not just what's active.
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun getAppDisplayName(packageName: String): String {
        return try {
            val pm = applicationContext.packageManager
            val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(packageName, 0)
            }
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            packageName.substringAfterLast(".")
                .replaceFirstChar { it.uppercase() }
        }
    }
}

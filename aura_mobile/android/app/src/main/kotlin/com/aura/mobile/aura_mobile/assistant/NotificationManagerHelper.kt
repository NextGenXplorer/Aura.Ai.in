package com.aura.mobile.aura_mobile.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import com.aura.mobile.aura_mobile.MainActivity
import com.aura.mobile.aura_mobile.R

class NotificationManagerHelper(private val context: Context) {

    companion object {
        const val CHANNEL_ID          = "AuraRemindersChannel"
        const val CHANNEL_PRE_ID      = "AuraPreRemindersChannel"
        const val CHANNEL_NAME        = "Aura Reminders"
        const val CHANNEL_PRE_NAME    = "Aura Upcoming Alerts"
        const val SNOOZE_ACTION       = "com.aura.mobile.ACTION_SNOOZE"
        const val MARK_DONE_ACTION    = "com.aura.mobile.ACTION_MARK_DONE"
        const val EXTRA_REMINDER_ID   = "extra_reminder_id"
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    init {
        createNotificationChannels()
    }

    /** Creates both the main alarm channel and the quieter pre-reminder channel */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // ── Main alarm channel (IMPORTANCE_HIGH + alarm sound) ──────────
            val alarmSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            val alarmAudioAttr = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val mainChannel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "High priority notifications for Aura reminders — fires when reminder time arrives"
                enableLights(true)
                lightColor = Color.CYAN
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                setSound(alarmSoundUri, alarmAudioAttr)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            // ── Pre-reminder channel (IMPORTANCE_DEFAULT + notification sound) ─
            val notifSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val notifAudioAttr = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val preChannel = NotificationChannel(CHANNEL_PRE_ID, CHANNEL_PRE_NAME, NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Early-warning notifications (1 hour before or 1 day before event)"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300)
                setSound(notifSoundUri, notifAudioAttr)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            notificationManager.createNotificationChannel(mainChannel)
            notificationManager.createNotificationChannel(preChannel)
        }
    }

    fun showReminderNotification(id: Int, title: String, isPreReminder: Boolean = false) {
        val channelId    = if (isPreReminder) CHANNEL_PRE_ID else CHANNEL_ID
        val displayTitle = if (isPreReminder) "⏰ Upcoming: $title" else "🔔 $title"
        val subText      = if (isPreReminder) "Early reminder" else "Time to act!"

        // ── Tap → open app ──────────────────────────────────────────────────
        val contentIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_REMINDER_ID, id)
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context, id, contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ── Full-screen intent (pops up even on locked screen) ───────────────
        val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_REMINDER_ID, id)
            putExtra("is_reminder_alarm", true)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context, id + 30000, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ── Mark Done action ─────────────────────────────────────────────────
        val doneIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = MARK_DONE_ACTION
            putExtra(EXTRA_REMINDER_ID, id)
        }
        val donePendingIntent = PendingIntent.getBroadcast(
            context, id + 10000, doneIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ── Snooze action (10 minutes) ───────────────────────────────────────
        val snoozeIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = SNOOZE_ACTION
            putExtra(EXTRA_REMINDER_ID, id)
            putExtra("title", title)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context, id + 20000, snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(displayTitle)
            .setContentText(subText)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$displayTitle\n$subText"))
            .setPriority(if (isPreReminder) NotificationCompat.PRIORITY_DEFAULT else NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)          // Keep visible until user acts
            .setOngoing(!isPreReminder)    // Main reminders stay in tray until dismissed
            .setContentIntent(contentPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "✔ Done", donePendingIntent)
            .addAction(android.R.drawable.ic_popup_sync, "💤 Snooze 10m", snoozePendingIntent)

        // Full-screen intent only on actual reminders (not pre-reminders)
        if (!isPreReminder) {
            builder.setFullScreenIntent(fullScreenPendingIntent, true)
        }

        notificationManager.notify(id, builder.build())
    }

    fun cancelNotification(id: Int) {
        notificationManager.cancel(id)
    }
}

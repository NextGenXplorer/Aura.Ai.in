package com.aura.mobile.aura_mobile.assistant

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
        const val CHANNEL_ID = "AuraRemindersChannel"
        const val CHANNEL_NAME = "Aura Reminders"
        const val SNOOZE_ACTION = "com.aura.mobile.ACTION_SNOOZE"
        const val MARK_DONE_ACTION = "com.aura.mobile.ACTION_MARK_DONE"
        const val EXTRA_REMINDER_ID = "extra_reminder_id"
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "High priority notifications for Aura smart reminders"
                enableLights(true)
                lightColor = Color.CYAN
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
                
                val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                    
                setSound(defaultSoundUri, audioAttributes)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun showReminderNotification(id: Int, title: String, isPreReminder: Boolean = false) {
        val displayTitle = if (isPreReminder) "Upcoming: $title" else title

        // Intent to open Main App
        val contentIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context, id, contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Mark Done Action
        val doneIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = MARK_DONE_ACTION
            putExtra(EXTRA_REMINDER_ID, id)
        }
        val donePendingIntent = PendingIntent.getBroadcast(
            context, id + 10000, doneIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Snooze Action (Only for actual reminders, not pre-reminders usually, but we can allow it)
        val snoozeIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = SNOOZE_ACTION
            putExtra(EXTRA_REMINDER_ID, id)
            putExtra("title", title)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context, id + 20000, snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notificationBuilder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher) // Fallback icon, ideally use a transparent white icon
            .setContentTitle("Aura Reminder")
            .setContentText(displayTitle)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(contentPendingIntent)
            .addAction(0, "Mark Done", donePendingIntent)
            .addAction(0, "Snooze 10m", snoozePendingIntent)

        notificationManager.notify(id, notificationBuilder.build())
    }
    
    fun cancelNotification(id: Int) {
        notificationManager.cancel(id)
    }
}

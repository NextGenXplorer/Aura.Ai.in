package com.aura.mobile.aura_mobile.assistant

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.Calendar

class AlarmScheduler(private val context: Context) {

    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    fun scheduleReminder(reminder: ReminderModel) {
        // Schedule Main Alarm
        val mainIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = "ALARM_TRIGGERED"
            putExtra("reminder_id", reminder.id)
            putExtra("title", reminder.title)
            putExtra("is_pre_reminder", false)
        }
        
        val mainPendingIntent = PendingIntent.getBroadcast(
            context,
            reminder.id, // Use reminder ID as request code
            mainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        reminder.eventDateTime,
                        mainPendingIntent
                    )
                } else {
                    Log.w("AuraAlarm", "Cannot schedule exact alarm. Missing permission.")
                }
            } else {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    reminder.eventDateTime,
                    mainPendingIntent
                )
            }
        } catch (e: SecurityException) {
            Log.e("AuraAlarm", "SecurityException scheduling exact alarm: ${e.message}")
        }

        // Schedule Pre-Reminder if enabled
        if (reminder.preReminderEnabled) {
            schedulePreReminder(reminder)
        }
    }

    private fun schedulePreReminder(reminder: ReminderModel) {
        val now = System.currentTimeMillis()
        val eventTime = reminder.eventDateTime
        
        // Calculate pre-reminder time: 1 hr before for today, 24 hr before for future
        val calEvent = Calendar.getInstance().apply { timeInMillis = eventTime }
        val calNow = Calendar.getInstance().apply { timeInMillis = now }
        
        val isSameDay = calEvent.get(Calendar.YEAR) == calNow.get(Calendar.YEAR) &&
                calEvent.get(Calendar.DAY_OF_YEAR) == calNow.get(Calendar.DAY_OF_YEAR)

        val oneHourMillis = 60 * 60 * 1000L
        val oneDayMillis = 24 * 60 * 60 * 1000L

        val preReminderTime = if (isSameDay) {
            eventTime - oneHourMillis
        } else {
            eventTime - oneDayMillis
        }

        // Only schedule if pre-reminder time is still in the future
        if (preReminderTime > now + 60000L) { // at least 1 min in the future
            val preIntent = Intent(context, ReminderReceiver::class.java).apply {
                action = "ALARM_TRIGGERED"
                putExtra("reminder_id", reminder.id)
                putExtra("title", reminder.title)
                putExtra("is_pre_reminder", true)
            }
            
            // Offset the request code for the pre-reminder by adding a large constant
            val prePendingIntent = PendingIntent.getBroadcast(
                context,
                reminder.id + 50000, 
                preIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            preReminderTime,
                            prePendingIntent
                        )
                    }
                } else {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        preReminderTime,
                        prePendingIntent
                    )
                }
            } catch (e: SecurityException) {
                Log.e("AuraAlarm", "SecurityException scheduling pre-reminder: ${e.message}")
            }
        }
    }

    fun scheduleSnooze(id: Int, title: String) {
        val snoozeTime = System.currentTimeMillis() + (10 * 60 * 1000L) // 10 minutes

        val snoozeIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = "ALARM_TRIGGERED"
            putExtra("reminder_id", id)
            putExtra("title", "Snoozed: $title")
            putExtra("is_pre_reminder", false)
        }
        
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context,
            id + 60000, // Different request code for snooze
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        snoozeTime,
                        snoozePendingIntent
                    )
                }
            } else {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    snoozeTime,
                    snoozePendingIntent
                )
            }
        } catch (e: SecurityException) {
            Log.e("AuraAlarm", "SecurityException scheduling snooze: ${e.message}")
        }
    }

    fun cancelAlarm(id: Int) {
        val mainIntent = Intent(context, ReminderReceiver::class.java)
        val mainPendingIntent = PendingIntent.getBroadcast(
            context, id, mainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(mainPendingIntent)

        val preIntent = Intent(context, ReminderReceiver::class.java)
        val prePendingIntent = PendingIntent.getBroadcast(
            context, id + 50000, preIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(prePendingIntent)
    }
}

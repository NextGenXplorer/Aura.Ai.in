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

    fun scheduleReminder(reminder: ReminderModel): Boolean {
        // Schedule Main Alarm
        val mainIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = "ALARM_TRIGGERED"
            putExtra("reminder_id", reminder.id)
            putExtra("title", reminder.title)
            putExtra("is_pre_reminder", false)
        }
        
        val mainPendingIntent = PendingIntent.getBroadcast(
            context,
            reminder.id,
            mainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val scheduled = scheduleExactOrApproximate(reminder.eventDateTime, mainPendingIntent, "main alarm #${reminder.id}")

        // Schedule Pre-Reminder if enabled
        if (reminder.preReminderEnabled) {
            schedulePreReminder(reminder)
        }
        return scheduled
    }

    /** Schedules an exact alarm using setAlarmClock which bypasses Doze and exact-alarm restrictions */
    private fun scheduleExactOrApproximate(timeMillis: Long, pendingIntent: PendingIntent, label: String): Boolean {
        return try {
            // Create a generic intent for the 'showIntent' which is required by some OEMs for setAlarmClock
            val showIntent = Intent(context, com.aura.mobile.aura_mobile.MainActivity::class.java)
            val showPendingIntent = PendingIntent.getActivity(
                context, 0, showIntent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val alarmClockInfo = AlarmManager.AlarmClockInfo(timeMillis, showPendingIntent)
            alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
            
            Log.d("AuraAlarm", "AlarmClock perfectly scheduled for $label")
            true
        } catch (e: Exception) {
            Log.e("AuraAlarm", "Exception scheduling AlarmClock for $label: ${e.message}")
            try {
                // Absolute fallback
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeMillis, pendingIntent)
            } catch (e2: Exception) {
               alarmManager.setWindow(AlarmManager.RTC_WAKEUP, timeMillis, 1000L, pendingIntent)
            }
            true
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

        // Only schedule if pre-reminder time is still in the future (at least 1 min)
        if (preReminderTime > now + 60_000L) {
            val preIntent = Intent(context, ReminderReceiver::class.java).apply {
                action = "ALARM_TRIGGERED"
                putExtra("reminder_id", reminder.id)
                putExtra("title", reminder.title)
                putExtra("is_pre_reminder", true)
            }
            val prePendingIntent = PendingIntent.getBroadcast(
                context,
                reminder.id + 50000,
                preIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            scheduleExactOrApproximate(preReminderTime, prePendingIntent, "pre-reminder #${reminder.id}")
        }
    }

    fun scheduleSnooze(id: Int, title: String) {
        val snoozeTime = System.currentTimeMillis() + (10 * 60 * 1000L) // 10 minutes

        val snoozeIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = "ALARM_TRIGGERED"
            putExtra("reminder_id", id)
            putExtra("title", title) // Keep original title, ReminderReceiver knows it's a snooze re-fire
            putExtra("is_pre_reminder", false)
        }
        
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context,
            id + 60000, // Different request code for snooze
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            val showIntent = Intent(context, com.aura.mobile.aura_mobile.MainActivity::class.java)
            val showPendingIntent = PendingIntent.getActivity(
                context, 0, showIntent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmClockInfo = AlarmManager.AlarmClockInfo(snoozeTime, showPendingIntent)
            alarmManager.setAlarmClock(alarmClockInfo, snoozePendingIntent)
        } catch (e: Exception) {
            try {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, snoozeTime, snoozePendingIntent)
            } catch (e2: Exception) {
                alarmManager.setWindow(AlarmManager.RTC_WAKEUP, snoozeTime, 1000L, snoozePendingIntent)
            }
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

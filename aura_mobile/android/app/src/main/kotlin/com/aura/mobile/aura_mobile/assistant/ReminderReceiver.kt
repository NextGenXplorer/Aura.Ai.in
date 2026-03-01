package com.aura.mobile.aura_mobile.assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d("AuraAlarm", "Received broadcast: $action")

        val notificationHelper = NotificationManagerHelper(context)
        val alarmScheduler = AlarmScheduler(context)

        when (action) {
            "ALARM_TRIGGERED" -> {
                val reminderId = intent.getIntExtra("reminder_id", -1)
                val title = intent.getStringExtra("title") ?: "Reminder"
                val isPreReminder = intent.getBooleanExtra("is_pre_reminder", false)

                if (reminderId != -1) {
                    notificationHelper.showReminderNotification(reminderId, title, isPreReminder)
                    
                    // Note: If you want to automatically clean up elapsed normal reminders,
                    // you can invoke ReminderRepository(context).deleteReminder(reminderId) here 
                    // AFTER displaying, but it's often better to let the user "Mark Done" first.
                }
            }
            NotificationManagerHelper.SNOOZE_ACTION -> {
                val reminderId = intent.getIntExtra(NotificationManagerHelper.EXTRA_REMINDER_ID, -1)
                val title = intent.getStringExtra("title") ?: "Reminder"

                if (reminderId != -1) {
                    // Schedule snooze alarm for 10 minutes
                    alarmScheduler.scheduleSnooze(reminderId, title)
                    
                    // Clear the current notification
                    notificationHelper.cancelNotification(reminderId)
                    Log.d("AuraAlarm", "Snoozed reminder $reminderId for 10m.")
                }
            }
            NotificationManagerHelper.MARK_DONE_ACTION -> {
                val reminderId = intent.getIntExtra(NotificationManagerHelper.EXTRA_REMINDER_ID, -1)
                if (reminderId != -1) {
                    // Clear the notification
                    notificationHelper.cancelNotification(reminderId)
                    
                    // Delete from database
                    val repository = ReminderRepository(context)
                    repository.deleteReminder(reminderId)
                    Log.d("AuraAlarm", "Marked done & deleted reminder $reminderId.")
                }
            }
        }
    }
}

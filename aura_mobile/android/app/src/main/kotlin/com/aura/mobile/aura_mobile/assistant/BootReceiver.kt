package com.aura.mobile.aura_mobile.assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == Intent.ACTION_BOOT_COMPLETED || 
            action == "android.intent.action.QUICKBOOT_POWERON" || 
            action == "com.htc.intent.action.QUICKBOOT_POWERON") {
            
            Log.d("AuraAlarm", "Boot completed. Rescheduling alarms...")
            
            val repository = ReminderRepository(context)
            val alarmScheduler = AlarmScheduler(context)
            
            val upcomingReminders = repository.getAllUpcomingReminders()
            
            var count = 0
            for (reminder in upcomingReminders) {
                alarmScheduler.scheduleReminder(reminder)
                count++
            }
            
            Log.d("AuraAlarm", "Rescheduled $count reminders.")
        }
    }
}

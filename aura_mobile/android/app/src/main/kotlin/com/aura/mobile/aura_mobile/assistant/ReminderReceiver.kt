package com.aura.mobile.aura_mobile.assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import android.os.Bundle

class ReminderReceiver : BroadcastReceiver() {
    private var tts: TextToSpeech? = null

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
                    
                    // Announce the reminder out loud using Text-To-Speech
                    if (!isPreReminder) {
                        speakReminder(context, title)
                    }
                }
            }
            NotificationManagerHelper.SNOOZE_ACTION -> {
                val reminderId = intent.getIntExtra(NotificationManagerHelper.EXTRA_REMINDER_ID, -1)
                val title = intent.getStringExtra("title") ?: "Reminder"

                if (reminderId != -1) {
                    alarmScheduler.scheduleSnooze(reminderId, title)
                    notificationHelper.cancelNotification(reminderId)
                    Log.d("AuraAlarm", "Snoozed reminder $reminderId for 10m.")
                }
            }
            NotificationManagerHelper.MARK_DONE_ACTION -> {
                val reminderId = intent.getIntExtra(NotificationManagerHelper.EXTRA_REMINDER_ID, -1)
                if (reminderId != -1) {
                    notificationHelper.cancelNotification(reminderId)
                    val repository = ReminderRepository(context)
                    repository.deleteReminder(reminderId)
                    Log.d("AuraAlarm", "Marked done & deleted reminder $reminderId.")
                }
            }
        }
    }

    private fun speakReminder(context: Context, title: String) {
        // goAsync() keeps the BroadcastReceiver alive for up to 10 seconds while async work is done
        val pendingResult = goAsync()
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    override fun onDone(utteranceId: String?) {
                        shutdownTtsAndFinish(pendingResult)
                    }
                    override fun onError(utteranceId: String?) {
                        shutdownTtsAndFinish(pendingResult)
                    }
                })
                
                val textToSpeak = "Aura Reminder: $title"
                val params = Bundle()
                params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "reminder_tts")
                
                val result = tts?.speak(textToSpeak, TextToSpeech.QUEUE_FLUSH, params, "reminder_tts")
                
                if (result == TextToSpeech.ERROR) {
                    shutdownTtsAndFinish(pendingResult)
                }
            } else {
                Log.e("AuraAlarm", "TTS Initialization failed")
                pendingResult.finish()
            }
        }
    }

    private fun shutdownTtsAndFinish(pendingResult: PendingResult) {
        try {
            tts?.stop()
            tts?.shutdown()
            tts = null
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            pendingResult.finish()
        }
    }
}

package com.aura.mobile.aura_mobile.assistant

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.telephony.SmsManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.os.BatteryManager
import android.provider.AlarmClock
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DeviceControlService(private val context: Context) {

    /** Represents a single contact match with display name and phone number */
    data class ContactMatch(val displayName: String, val number: String)

    /** Find all contacts whose display name contains [name], returning up to 10 results */
    fun findContacts(name: String): List<ContactMatch> {
        val results = mutableListOf<ContactMatch>()
        try {
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ),
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                arrayOf("%$name%"),
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
            )
            cursor?.use { c ->
                val nameIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                val seen = mutableSetOf<String>()
                while (c.moveToNext() && results.size < 10) {
                    val displayName = if (nameIdx != -1) c.getString(nameIdx) else continue
                    val number = if (numIdx != -1) c.getString(numIdx) else continue
                    // Deduplicate by number
                    val key = "${displayName.lowercase()}|${number.replace(" ", "")}"
                    if (seen.add(key)) {
                        results.add(ContactMatch(displayName, number))
                    }
                }
            }
        } catch (e: Exception) {
            // Missing permission handled by caller
        }
        return results
    }

    /** Call a specific phone number directly */
    fun callByNumber(number: String, label: String, ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Intent.ACTION_CALL)
            intent.data = Uri.parse("tel:${number.replace(" ", "")}")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Calling $label")
        } catch (e: Exception) {
            val intent = Intent(Intent.ACTION_DIAL)
            intent.data = Uri.parse("tel:${number.replace(" ", "")}")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }

    fun executeCommand(command: ParsedCommand, ttsManager: TtsManager?) {
        when (command) {
            is ParsedCommand.OpenApp -> openApp(command.appName, ttsManager)
            is ParsedCommand.CallContact -> callContact(command.contactName, ttsManager)
            is ParsedCommand.SendSms -> {
                // Should only be called if properly confirmed. AssistantForegroundService will handle confirmation logic.
            }
            is ParsedCommand.SendEmail -> {
                // Handled in handleRecognizedText directly via requestEmailDraft
            }
            is ParsedCommand.TurnTorch -> turnTorch(command.state, ttsManager)
            is ParsedCommand.SetTimer -> setTimer(command.minutes, ttsManager)
            is ParsedCommand.SetAlarm -> setAlarm(command.hour, command.minute, ttsManager)
            is ParsedCommand.WebSearch -> searchWeb(command.query, ttsManager)
            is ParsedCommand.PlayYouTube -> searchYouTube(command.query, ttsManager)
            is ParsedCommand.GetTime -> speakTime(ttsManager)
            is ParsedCommand.GetDate -> speakDate(ttsManager)
            is ParsedCommand.GetBattery -> speakBattery(ttsManager)
            is ParsedCommand.MaxVolume -> setVolume(true, ttsManager)
            is ParsedCommand.MuteVolume -> setVolume(false, ttsManager)
            is ParsedCommand.OpenCamera -> openCamera(ttsManager)
            is ParsedCommand.OpenWifiSettings -> openWifiSettings(ttsManager)
            is ParsedCommand.OpenBluetoothSettings -> openBluetoothSettings(ttsManager)
            is ParsedCommand.OpenSettings -> openSettings(ttsManager)
            is ParsedCommand.Unknown -> {
                ttsManager?.speak("I didn't understand the command.")
            }
        }
    }

    fun openApp(appName: String, ttsManager: TtsManager? = null) {
        val pm = context.packageManager
        val packages = pm.getInstalledPackages(0)
        
        var bestMatchPkg: String? = null
        var bestMatchLabel: String? = null
        val query = appName.lowercase()

        for (pkg in packages) {
            val appInfo = pkg.applicationInfo
            if (appInfo == null) continue

            val label = pm.getApplicationLabel(appInfo).toString()
            if (label.lowercase() == query) {
                bestMatchPkg = pkg.packageName
                bestMatchLabel = label
                break // Exact match found
            }
            if (label.lowercase().contains(query)) {
                if (bestMatchPkg == null) {
                   bestMatchPkg = pkg.packageName
                   bestMatchLabel = label
                }
            }
        }

        if (bestMatchPkg != null) {
            try {
                val launchIntent = pm.getLaunchIntentForPackage(bestMatchPkg)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(launchIntent)
                    ttsManager?.speak("Opening $bestMatchLabel")
                } else {
                    ttsManager?.speak("Could not open $appName")
                }
            } catch (e: Exception) {
                ttsManager?.speak("Error opening $appName")
            }
        } else {
            ttsManager?.speak("App $appName not found")
        }
    }

    fun callContact(name: String, ttsManager: TtsManager? = null) {
        val matches = findContacts(name)
        if (matches.isEmpty()) {
            ttsManager?.speak("Contact $name not found")
            return
        }
        // Only one match — call immediately
        val first = matches.first()
        callByNumber(first.number, first.displayName, ttsManager)
    }

    fun sendSMSDirect(name: String, message: String, ttsManager: TtsManager? = null) {
        var number: String? = null
        try {
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                null,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                arrayOf("%$name%"),
                null
            )
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                if (index != -1) number = cursor.getString(index)
                cursor.close()
            }
        } catch (e: Exception) {
        }

        if (number != null) {
            try {
                val smsManager = SmsManager.getDefault()
                smsManager.sendTextMessage(number, null, message, null, null)
                ttsManager?.speak("Message sent to $name")
            } catch (e: Exception) {
                ttsManager?.speak("Failed to send message")
            }
        } else {
             ttsManager?.speak("Contact $name not found for messaging")
        }
    }

    fun turnTorch(state: Boolean, ttsManager: TtsManager? = null) {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            var cameraId: String? = null
            for (id in cameraManager.cameraIdList) {
                val characteristics = cameraManager.getCameraCharacteristics(id)
                val hasFlash = characteristics.get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE)
                if (hasFlash == true) {
                    cameraId = id
                    break
                }
            }
            if (cameraId != null) {
                cameraManager.setTorchMode(cameraId, state)
                ttsManager?.speak(if (state) "Torch turned on" else "Torch turned off")
            } else {
                ttsManager?.speak("No flashlight found")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Error toggling torch")
        }
    }

    fun openCamera(ttsManager: TtsManager? = null) {
        try {
             // For simplicity, opening the default camera intent
             // In foreground service, starting an activity requires FLAG_ACTIVITY_NEW_TASK
            val intent = Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Opening camera")
        } catch (e: Exception) {
            ttsManager?.speak("Error opening camera")
        }
    }

    fun openWifiSettings(ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Opening Wi-Fi settings")
        } catch (e: Exception) { }
    }

    fun openBluetoothSettings(ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Opening Bluetooth settings")
        } catch (e: Exception) { }
    }

    fun openSettings(ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Settings.ACTION_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Opening settings")
        } catch (e: Exception) { }
    }

    private fun setTimer(minutes: Int, ttsManager: TtsManager?) {
        try {
            val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(AlarmClock.EXTRA_MESSAGE, "AURA Timer")
                putExtra(AlarmClock.EXTRA_LENGTH, minutes * 60)
                putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            }
            context.startActivity(intent)
            ttsManager?.speak("Timer set for $minutes minutes")
        } catch (e: Exception) {
            ttsManager?.speak("Failed to set timer")
        }
    }

    private fun setAlarm(hour: Int, minute: Int, ttsManager: TtsManager?) {
        try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(AlarmClock.EXTRA_MESSAGE, "AURA Alarm")
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            }
            context.startActivity(intent)
            ttsManager?.speak("Alarm set for $hour and $minute minutes")
        } catch (e: Exception) {
            ttsManager?.speak("Failed to set alarm")
        }
    }

    private fun searchWeb(query: String, ttsManager: TtsManager?) {
        try {
            val intent = Intent(Intent.ACTION_WEB_SEARCH).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(android.app.SearchManager.QUERY, query)
            }
            context.startActivity(intent)
            
            // Clean up the query for TTS so it doesn't say "magnifying glass" or emojis
            val cleanQuery = query.replace(Regex("[\\x{1F300}-\\x{1F6FF}|\\x{1F900}-\\x{1F9FF}|\\x{2600}-\\x{26FF}|\\x{2700}-\\x{27BF}]", RegexOption.IGNORE_CASE), "").trim()
            
            ttsManager?.speak("Searching Google for $cleanQuery")
        } catch (e: Exception) {
            ttsManager?.speak("Could not open web search")
        }
    }

    private fun searchYouTube(query: String, ttsManager: TtsManager?) {
        try {
            val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                putExtra(android.app.SearchManager.QUERY, query)
                setPackage("com.google.android.youtube")
            }
            context.startActivity(intent)
            ttsManager?.speak("Playing $query on YouTube")
        } catch (e: Exception) {
            // Fallback to web search if youtube app is not installed
            searchWeb("$query youtube", ttsManager)
        }
    }

    private fun speakTime(ttsManager: TtsManager?) {
        val time = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date())
        ttsManager?.speak("It is currently $time")
    }

    private fun speakDate(ttsManager: TtsManager?) {
        val date = SimpleDateFormat("EEEE, MMMM dth", Locale.getDefault()).format(Date())
        ttsManager?.speak("Today is $date")
    }

    private fun speakBattery(ttsManager: TtsManager?) {
        try {
            val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val batLevel = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            ttsManager?.speak("Your battery is at $batLevel percent")
        } catch (e: Exception) {
            ttsManager?.speak("I cannot check the battery right now")
        }
    }

    private fun setVolume(max: Boolean, ttsManager: TtsManager?) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val flags = AudioManager.FLAG_SHOW_UI
            
            if (max) {
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, flags)
                ttsManager?.speak("Volume set to maximum")
            } else {
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, 0, flags)
                ttsManager?.speak("Volume muted")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Failed to change volume")
        }
    }
}

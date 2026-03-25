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
import android.content.ClipboardManager
import android.app.NotificationManager

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
            is ParsedCommand.SetReminder -> setReminder(command.text, command.timeInMillis, ttsManager)
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
            is ParsedCommand.Navigate -> navigate(command.destination, ttsManager)
            is ParsedCommand.PlayMusic -> playMusic(command.query, ttsManager)
            is ParsedCommand.ToggleSetting -> toggleSetting(command.setting, command.state, ttsManager)
            is ParsedCommand.ReadClipboard -> readClipboard(ttsManager)
            is ParsedCommand.FindMyPhone -> findMyPhone(ttsManager)
            is ParsedCommand.TakeSelfie -> takeSelfie(ttsManager)

            // ═══ NEW FEATURES ═══
            is ParsedCommand.ViewCalendar -> viewCalendar(ttsManager)
            is ParsedCommand.CreateEvent -> createEvent(command.title, command.timeInMillis, ttsManager)
            is ParsedCommand.GetNextEvent -> getNextEvent(ttsManager)
            is ParsedCommand.MediaControl -> controlMedia(command.action, ttsManager)
            is ParsedCommand.SetBrightness -> setBrightness(command.level, ttsManager)
            is ParsedCommand.Screenshot -> takeScreenshot(ttsManager)
            is ParsedCommand.ReadMessages -> readMessages(command.appName, ttsManager)
            is ParsedCommand.ReadNotifications -> readNotifications(ttsManager)
            is ParsedCommand.CreateNote -> createNote(command.content, ttsManager)
            is ParsedCommand.Calculate -> calculate(command.expression, ttsManager)
            is ParsedCommand.Convert -> convert(command.amount, command.fromUnit, command.toUnit, ttsManager)

            // ═══ SMART APP ACTIONS ═══
            is ParsedCommand.SendWhatsApp -> sendWhatsAppMessage(command.contactName, command.message, ttsManager)
            is ParsedCommand.SearchOnApp -> searchOnApp(command.appName, command.query, ttsManager)
            is ParsedCommand.UpiPayment -> openUpiPayment(command.upiId, command.amount, command.note, ttsManager)
            is ParsedCommand.PlayOnSpotify -> playOnSpotify(command.query, ttsManager)
            is ParsedCommand.BookRide -> bookRide(command.destination, command.app, ttsManager)
            is ParsedCommand.OrderFood -> orderFood(command.restaurant, command.app, ttsManager)
            is ParsedCommand.ShareText -> shareText(command.text, command.app, ttsManager)
            is ParsedCommand.OpenProfile -> openProfile(command.platform, command.username, ttsManager)

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

    private fun setReminder(text: String, timeInMillis: Long, ttsManager: TtsManager?) {
        try {
            val repository = ReminderRepository(context)
            val scheduler = AlarmScheduler(context)
            
            val reminder = ReminderModel(
                title = text,
                description = "",
                eventDateTime = timeInMillis,
                preReminderEnabled = true
            )
            val id = repository.addReminder(reminder)
            val savedReminder = reminder.copy(id = id.toInt())
            scheduler.scheduleReminder(savedReminder)
            
            val timeString = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(timeInMillis))
            ttsManager?.speak("Reminder set for $timeString")
        } catch (e: Exception) {
            ttsManager?.speak("Failed to set reminder")
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

    fun navigate(destination: String, ttsManager: TtsManager? = null) {
        try {
            // Use universal geo intent first which is more standard
            val uri = Uri.parse("google.navigation:q=${Uri.encode(destination)}")
            val intent = Intent(Intent.ACTION_VIEW, uri)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            // Try specific maps intent
            context.startActivity(intent)
            ttsManager?.speak("Navigating to $destination")
        } catch (e: Exception) {
            try {
                // Fallback to geo:0,0?q=... which almost every mapping app supports
                val geoUri = Uri.parse("geo:0,0?q=${Uri.encode(destination)}")
                val geoIntent = Intent(Intent.ACTION_VIEW, geoUri)
                geoIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(geoIntent)
                ttsManager?.speak("Finding directions for $destination")
            } catch (e2: Exception) {
                // Final fallback: Search web
                searchWeb("directions to $destination", ttsManager)
            }
        }
    }

    fun playMusic(query: String, ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                putExtra(android.app.SearchManager.QUERY, query)
            }
            context.startActivity(intent)
            ttsManager?.speak("Playing $query")
        } catch (e: Exception) {
            ttsManager?.speak("Could not find a music app to play $query")
        }
    }

    fun toggleSetting(setting: String, state: Boolean, ttsManager: TtsManager? = null) {
        when (setting.lowercase()) {
            "wifi" -> { openWifiSettings(ttsManager); ttsManager?.speak("Opening Wi-Fi setup") }
            "bluetooth" -> { openBluetoothSettings(ttsManager); ttsManager?.speak("Opening Bluetooth setup") }
            "donotdisturb", "dnd" -> toggleDnd(state, ttsManager)
            else -> ttsManager?.speak("I cannot change the $setting setting directly.")
        }
    }

    private fun toggleDnd(state: Boolean, ttsManager: TtsManager?) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (notificationManager.isNotificationPolicyAccessGranted) {
                if (state) {
                    notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
                    ttsManager?.speak("Do not disturb is now on")
                } else {
                    notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                    ttsManager?.speak("Do not disturb is now off")
                }
            } else {
                ttsManager?.speak("I need permission to change do not disturb settings.")
                val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
            }
        } catch (e: Exception) {
            ttsManager?.speak("Error changing do not disturb settings")
        }
    }

    fun readClipboard(ttsManager: TtsManager? = null) {
        try {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            if (clipboard.hasPrimaryClip() && clipboard.primaryClip?.itemCount ?: 0 > 0) {
                val text = clipboard.primaryClip?.getItemAt(0)?.text?.toString()
                if (!text.isNullOrBlank()) {
                    ttsManager?.speak("Your clipboard says: $text")
                } else {
                    ttsManager?.speak("Your clipboard is empty or isn't text.")
                }
            } else {
                ttsManager?.speak("Your clipboard is empty.")
            }
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't read your clipboard.")
        }
    }

    fun findMyPhone(ttsManager: TtsManager? = null) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxRing = audioManager.getStreamMaxVolume(AudioManager.STREAM_RING)
            val maxMusic = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            
            // Set volumes to max
            audioManager.setStreamVolume(AudioManager.STREAM_RING, maxRing, 0)
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxMusic, 0)
            
            ttsManager?.speak("I am right here! Identifying location now.")
        } catch (e: Exception) {
            ttsManager?.speak("Failed to ring phone.")
        }
    }

    fun takeSelfie(ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.putExtra("android.intent.extras.CAMERA_FACING", 1) // FRONT CAMERA (old way)
            intent.putExtra("android.intent.extra.USE_FRONT_CAMERA", true) // FRONT CAMERA (new way)
            intent.putExtra("com.google.assistant.extra.USE_FRONT_CAMERA", true) // FRONT CAMERA (assistant way)

            context.startActivity(intent)
            ttsManager?.speak("Get ready for a selfie!")
        } catch (e: Exception) {
            ttsManager?.speak("Error opening front camera")
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NEW FEATURES - Implementation Methods
    // ═══════════════════════════════════════════════════════════════════════════

    // ─── 1. CALENDAR & EVENTS ──────────────────────────────────────────────────

    fun viewCalendar(ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Intent.ACTION_VIEW)
            intent.data = Uri.parse("content://com.android.calendar/time")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ttsManager?.speak("Opening your calendar")
        } catch (e: Exception) {
            // Fallback: Open any calendar app
            try {
                val fallbackIntent = Intent(Intent.ACTION_MAIN)
                fallbackIntent.addCategory(Intent.CATEGORY_APP_CALENDAR)
                fallbackIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(fallbackIntent)
                ttsManager?.speak("Opening calendar")
            } catch (e2: Exception) {
                ttsManager?.speak("I couldn't open your calendar app")
            }
        }
    }

    fun createEvent(title: String, timeInMillis: Long, ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Intent.ACTION_INSERT)
            intent.data = android.provider.CalendarContract.Events.CONTENT_URI
            intent.putExtra(android.provider.CalendarContract.Events.TITLE, title)
            intent.putExtra(android.provider.CalendarContract.EXTRA_EVENT_BEGIN_TIME, timeInMillis)
            intent.putExtra(android.provider.CalendarContract.EXTRA_EVENT_END_TIME, timeInMillis + 3_600_000L) // 1 hour duration
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            context.startActivity(intent)

            val timeString = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(timeInMillis))
            ttsManager?.speak("Creating event $title at $timeString")
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't create the calendar event")
        }
    }

    fun getNextEvent(ttsManager: TtsManager? = null) {
        try {
            val cursor = context.contentResolver.query(
                android.provider.CalendarContract.Events.CONTENT_URI,
                arrayOf(
                    android.provider.CalendarContract.Events.TITLE,
                    android.provider.CalendarContract.Events.DTSTART
                ),
                "${android.provider.CalendarContract.Events.DTSTART} >= ?",
                arrayOf(System.currentTimeMillis().toString()),
                "${android.provider.CalendarContract.Events.DTSTART} ASC"
            )

            cursor?.use { c ->
                if (c.moveToFirst()) {
                    val titleIdx = c.getColumnIndex(android.provider.CalendarContract.Events.TITLE)
                    val startIdx = c.getColumnIndex(android.provider.CalendarContract.Events.DTSTART)

                    if (titleIdx != -1 && startIdx != -1) {
                        val title = c.getString(titleIdx) ?: "Untitled event"
                        val startTime = c.getLong(startIdx)
                        val timeString = SimpleDateFormat("EEEE, h:mm a", Locale.getDefault()).format(Date(startTime))

                        ttsManager?.speak("Your next event is $title on $timeString")
                        return
                    }
                }
            }
            ttsManager?.speak("You have no upcoming events")
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't check your calendar")
        }
    }

    // ─── 2. MEDIA CONTROLS ─────────────────────────────────────────────────────

    fun controlMedia(action: String, ttsManager: TtsManager? = null) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

            val keyCode = when (action) {
                "play" -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY
                "pause" -> android.view.KeyEvent.KEYCODE_MEDIA_PAUSE
                "next" -> android.view.KeyEvent.KEYCODE_MEDIA_NEXT
                "previous" -> android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS
                else -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            }

            // Send media button event
            val downEvent = android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, keyCode)
            val upEvent = android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, keyCode)

            audioManager.dispatchMediaKeyEvent(downEvent)
            audioManager.dispatchMediaKeyEvent(upEvent)

            val actionText = when (action) {
                "next" -> "Skipping to next"
                "previous" -> "Going back to previous"
                "pause" -> "Pausing"
                "play" -> "Resuming playback"
                else -> "Done"
            }
            ttsManager?.speak(actionText)
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't control media playback")
        }
    }

    fun setBrightness(level: Int, ttsManager: TtsManager? = null) {
        try {
            // Check if we can write system settings
            if (Settings.System.canWrite(context)) {
                val brightnessValue = (level * 255 / 100).coerceIn(0, 255)
                Settings.System.putInt(
                    context.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS,
                    brightnessValue
                )

                // Disable auto-brightness
                Settings.System.putInt(
                    context.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS_MODE,
                    Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
                )

                val levelText = when (level) {
                    in 0..20 -> "low"
                    in 21..40 -> "dim"
                    in 41..60 -> "medium"
                    in 61..80 -> "bright"
                    else -> "maximum"
                }
                ttsManager?.speak("Brightness set to $levelText")
            } else {
                // Request permission
                ttsManager?.speak("I need permission to change brightness")
                val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                intent.data = Uri.parse("package:${context.packageName}")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
            }
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't change the brightness")
        }
    }

    fun takeScreenshot(ttsManager: TtsManager? = null) {
        try {
            // Most reliable method: Open screenshot tile via accessibility service
            // For now, inform user to use hardware buttons
            ttsManager?.speak("Please press Power and Volume Down together to take a screenshot")

            // Alternative: Some devices support screenshot via accessibility service
            // This would require setting up AccessibilityService which is complex
        } catch (e: Exception) {
            ttsManager?.speak("Screenshot feature not available")
        }
    }

    // ─── 3. READ MESSAGES/NOTIFICATIONS ────────────────────────────────────────

    fun readMessages(appName: String?, ttsManager: TtsManager? = null) {
        // Note: Reading messages requires NotificationListenerService permission
        // For now, we'll open the messaging app
        try {
            val intent = when (appName?.lowercase()) {
                "whatsapp" -> {
                    Intent(Intent.ACTION_MAIN).apply {
                        setPackage("com.whatsapp")
                        addCategory(Intent.CATEGORY_LAUNCHER)
                    }
                }
                "telegram" -> {
                    Intent(Intent.ACTION_MAIN).apply {
                        setPackage("org.telegram.messenger")
                        addCategory(Intent.CATEGORY_LAUNCHER)
                    }
                }
                "sms" -> {
                    Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_APP_MESSAGING)
                    }
                }
                else -> {
                    Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_APP_MESSAGING)
                    }
                }
            }

            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)

            val appText = appName?.let { "$it " } ?: ""
            ttsManager?.speak("Opening ${appText}messages")
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't open messages")
        }
    }

    fun readNotifications(ttsManager: TtsManager? = null) {
        try {
            // Open notification panel by sending broadcast
            @Suppress("DEPRECATION")
            val it = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
            context.sendBroadcast(it)

            // Expand status bar
            val statusBarService = context.getSystemService("statusbar")
            val statusBarClass = Class.forName("android.app.StatusBarManager")
            val method = statusBarClass.getMethod("expandNotificationsPanel")
            method.invoke(statusBarService)

            ttsManager?.speak("Opening notifications")
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't open notifications. Pull down from the top of your screen.")
        }
    }

    // ─── 4. QUICK NOTES ────────────────────────────────────────────────────────

    fun createNote(content: String, ttsManager: TtsManager? = null) {
        try {
            // Try to use shared preferences as simple note storage
            val prefs = context.getSharedPreferences("AuraQuickNotes", Context.MODE_PRIVATE)
            val timestamp = System.currentTimeMillis()
            val noteKey = "note_$timestamp"

            prefs.edit().putString(noteKey, content).apply()

            // Also try to open notes app with the content
            try {
                val intent = Intent(Intent.ACTION_INSERT_OR_EDIT).apply {
                    type = "vnd.android.cursor.item/note"
                    putExtra("title", "AURA Note")
                    putExtra("note", content)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                // If no notes app, just store locally
            }

            ttsManager?.speak("Note saved: $content")
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't save the note")
        }
    }

    // ─── 5. CALCULATOR & CONVERTER ─────────────────────────────────────────────

    fun calculate(expression: String, ttsManager: TtsManager? = null) {
        try {
            // Parse and evaluate simple math expressions
            val cleanExpr = expression.lowercase()
                .replace("what's", "")
                .replace("what is", "")
                .replace("calculate", "")
                .replace("compute", "")
                .trim()

            // Handle percentage: "15% of 250"
            val percentRegex = Regex("(\\d+(?:\\.\\d+)?)\\s*%\\s*of\\s*(\\d+(?:\\.\\d+)?)")
            val percentMatch = percentRegex.find(cleanExpr)
            if (percentMatch != null) {
                val percent = percentMatch.groupValues[1].toDouble()
                val number = percentMatch.groupValues[2].toDouble()
                val result = (percent / 100.0) * number
                ttsManager?.speak("$percent percent of $number is ${result.format()}")
                return
            }

            // Handle basic operations
            val mathRegex = Regex("(\\d+(?:\\.\\d+)?)\\s*([+\\-*/×÷])\\s*(\\d+(?:\\.\\d+)?)")
            val mathMatch = mathRegex.find(cleanExpr)
            if (mathMatch != null) {
                val a = mathMatch.groupValues[1].toDouble()
                val op = mathMatch.groupValues[2]
                val b = mathMatch.groupValues[3].toDouble()

                val result = when (op) {
                    "+", "plus" -> a + b
                    "-", "minus" -> a - b
                    "*", "×", "times", "multiply" -> a * b
                    "/", "÷", "divide" -> a / b
                    else -> 0.0
                }

                ttsManager?.speak("The answer is ${result.format()}")
                return
            }

            ttsManager?.speak("I couldn't understand that calculation")
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't perform that calculation")
        }
    }

    fun convert(amount: Double, fromUnit: String, toUnit: String, ttsManager: TtsManager? = null) {
        try {
            val from = fromUnit.lowercase()
            val to = toUnit.lowercase()
            var result: Double? = null
            var resultUnit = to

            // Distance conversions
            when {
                from in listOf("km", "kilometer", "kilometers", "kilometre", "kilometres") &&
                to in listOf("mi", "mile", "miles") -> {
                    result = amount * 0.621371
                    resultUnit = "miles"
                }
                from in listOf("mi", "mile", "miles") &&
                to in listOf("km", "kilometer", "kilometers", "kilometre", "kilometres") -> {
                    result = amount * 1.60934
                    resultUnit = "kilometers"
                }
                from in listOf("m", "meter", "meters", "metre", "metres") &&
                to in listOf("ft", "feet", "foot") -> {
                    result = amount * 3.28084
                    resultUnit = "feet"
                }
                from in listOf("ft", "feet", "foot") &&
                to in listOf("m", "meter", "meters", "metre", "metres") -> {
                    result = amount * 0.3048
                    resultUnit = "meters"
                }

                // Weight conversions
                from in listOf("kg", "kilogram", "kilograms") &&
                to in listOf("lb", "lbs", "pound", "pounds") -> {
                    result = amount * 2.20462
                    resultUnit = "pounds"
                }
                from in listOf("lb", "lbs", "pound", "pounds") &&
                to in listOf("kg", "kilogram", "kilograms") -> {
                    result = amount * 0.453592
                    resultUnit = "kilograms"
                }

                // Temperature conversions
                from in listOf("c", "celsius") && to in listOf("f", "fahrenheit") -> {
                    result = (amount * 9/5) + 32
                    resultUnit = "Fahrenheit"
                }
                from in listOf("f", "fahrenheit") && to in listOf("c", "celsius") -> {
                    result = (amount - 32) * 5/9
                    resultUnit = "Celsius"
                }

                // Volume conversions
                from in listOf("l", "liter", "liters", "litre", "litres") &&
                to in listOf("gal", "gallon", "gallons") -> {
                    result = amount * 0.264172
                    resultUnit = "gallons"
                }
                from in listOf("gal", "gallon", "gallons") &&
                to in listOf("l", "liter", "liters", "litre", "litres") -> {
                    result = amount * 3.78541
                    resultUnit = "liters"
                }
            }

            if (result != null) {
                ttsManager?.speak("$amount $from is ${result.format()} $resultUnit")
            } else {
                ttsManager?.speak("I don't know how to convert $from to $to")
            }
        } catch (e: Exception) {
            ttsManager?.speak("I couldn't perform that conversion")
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SMART APP ACTIONS - Deep link workflows for popular apps
    // ═══════════════════════════════════════════════════════════════════════════

    fun sendWhatsAppMessage(contactName: String, message: String, ttsManager: TtsManager? = null) {
        try {
            // First try to resolve contact to get phone number
            val matches = findContacts(contactName)
            if (matches.isNotEmpty()) {
                val number = matches.first().number.replace(Regex("[\\s\\-()]"), "")
                val encodedMsg = Uri.encode(message)
                val intent = Intent(Intent.ACTION_VIEW)
                intent.data = Uri.parse("https://api.whatsapp.com/send?phone=$number&text=$encodedMsg")
                intent.setPackage("com.whatsapp")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(intent)
                    ttsManager?.speak("Opening WhatsApp chat with ${matches.first().displayName}")
                    return
                } catch (e: Exception) {
                    // WhatsApp not installed, try without package
                    intent.setPackage(null)
                    context.startActivity(intent)
                    ttsManager?.speak("Opening WhatsApp chat in browser")
                    return
                }
            }
            // No contact found - open WhatsApp with message via ACTION_SEND
            val sendIntent = Intent(Intent.ACTION_SEND)
            sendIntent.type = "text/plain"
            sendIntent.setPackage("com.whatsapp")
            sendIntent.putExtra(Intent.EXTRA_TEXT, message)
            sendIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(sendIntent)
                ttsManager?.speak("Opening WhatsApp to send message")
            } catch (e: Exception) {
                ttsManager?.speak("WhatsApp is not installed on this device")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Could not open WhatsApp")
        }
    }

    fun searchOnApp(appName: String, query: String, ttsManager: TtsManager? = null) {
        try {
            val encodedQuery = Uri.encode(query)
            val (packageName, searchUri) = when (appName.lowercase()) {
                "amazon" -> Pair("com.amazon.mShop.android.shopping", "https://www.amazon.in/s?k=$encodedQuery")
                "flipkart" -> Pair("com.flipkart.android", "https://www.flipkart.com/search?q=$encodedQuery")
                "google" -> Pair("com.google.android.googlequicksearchbox", "https://www.google.com/search?q=$encodedQuery")
                "myntra" -> Pair("com.myntra.android", "https://www.myntra.com/$encodedQuery")
                "swiggy" -> Pair("in.swiggy.android", "https://www.swiggy.com/search?query=$encodedQuery")
                "zomato" -> Pair("com.application.zomato", "https://www.zomato.com/search?q=$encodedQuery")
                else -> Pair(null, "https://www.google.com/search?q=$encodedQuery+$appName")
            }

            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(searchUri))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (packageName != null) {
                intent.setPackage(packageName)
            }
            try {
                context.startActivity(intent)
                ttsManager?.speak("Searching for $query on $appName")
            } catch (e: Exception) {
                // App not installed, fallback to browser
                val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(searchUri))
                browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(browserIntent)
                ttsManager?.speak("Searching for $query on $appName in browser")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Could not search on $appName")
        }
    }

    fun openUpiPayment(upiId: String?, amount: String?, note: String?, ttsManager: TtsManager? = null) {
        try {
            val uriBuilder = StringBuilder("upi://pay?")
            if (!upiId.isNullOrBlank()) {
                uriBuilder.append("pa=${Uri.encode(upiId)}")
            }
            if (!amount.isNullOrBlank()) {
                uriBuilder.append("&am=$amount")
            }
            if (!note.isNullOrBlank()) {
                uriBuilder.append("&tn=${Uri.encode(note)}")
            }
            uriBuilder.append("&cu=INR")

            val intent = Intent(Intent.ACTION_VIEW)
            intent.data = Uri.parse(uriBuilder.toString())
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)

            val amountText = if (!amount.isNullOrBlank()) " of ₹$amount" else ""
            ttsManager?.speak("Opening UPI payment$amountText")
        } catch (e: Exception) {
            ttsManager?.speak("No UPI payment app found")
        }
    }

    fun playOnSpotify(query: String, ttsManager: TtsManager? = null) {
        try {
            val encodedQuery = Uri.encode(query)
            val intent = Intent(Intent.ACTION_VIEW)
            intent.data = Uri.parse("spotify:search:$encodedQuery")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.setPackage("com.spotify.music")
            try {
                context.startActivity(intent)
                ttsManager?.speak("Searching $query on Spotify")
            } catch (e: Exception) {
                // Fallback to web
                val webIntent = Intent(Intent.ACTION_VIEW)
                webIntent.data = Uri.parse("https://open.spotify.com/search/$encodedQuery")
                webIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(webIntent)
                ttsManager?.speak("Opening Spotify search in browser")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Could not open Spotify")
        }
    }

    fun playOnYouTubeMusic(query: String, ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                putExtra(android.app.SearchManager.QUERY, query)
                setPackage("com.google.android.apps.youtube.music")
            }
            context.startActivity(intent)
            ttsManager?.speak("Playing $query on YouTube Music")
        } catch (e: Exception) {
            // Fallback to YouTube
            try {
                searchYouTube(query, ttsManager)
            } catch (e2: Exception) {
                ttsManager?.speak("Could not open YouTube Music")
            }
        }
    }

    fun bookRide(destination: String, appPreference: String?, ttsManager: TtsManager? = null) {
        val encodedDest = Uri.encode(destination)
        // Try Uber first if preferred or no preference
        if (appPreference == null || appPreference.lowercase() == "uber") {
            try {
                val intent = Intent(Intent.ACTION_VIEW)
                intent.data = Uri.parse("uber://?action=setPickup&dropoff[formatted_address]=$encodedDest")
                intent.setPackage("com.ubercab")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                ttsManager?.speak("Booking Uber ride to $destination")
                return
            } catch (e: Exception) {
                if (appPreference?.lowercase() == "uber") {
                    ttsManager?.speak("Uber is not installed")
                    return
                }
            }
        }
        // Try Ola
        if (appPreference == null || appPreference.lowercase() == "ola") {
            try {
                val intent = Intent(Intent.ACTION_VIEW)
                intent.data = Uri.parse("olacabs://app/launch?drop_address=$encodedDest")
                intent.setPackage("com.olacabs.customer")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                ttsManager?.speak("Booking Ola ride to $destination")
                return
            } catch (e: Exception) {
                if (appPreference?.lowercase() == "ola") {
                    ttsManager?.speak("Ola is not installed")
                    return
                }
            }
        }
        // Fallback: navigate with maps
        ttsManager?.speak("No ride app found, opening navigation to $destination")
        navigate(destination, ttsManager)
    }

    fun orderFood(restaurant: String?, appPreference: String?, ttsManager: TtsManager? = null) {
        val targetPackage = when (appPreference?.lowercase()) {
            "swiggy" -> "in.swiggy.android"
            "zomato" -> "com.application.zomato"
            else -> null
        }

        // If a specific app is requested, try it first
        if (targetPackage != null) {
            try {
                val intent = context.packageManager.getLaunchIntentForPackage(targetPackage)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    val appLabel = appPreference ?: "food app"
                    val restaurantText = if (!restaurant.isNullOrBlank()) " for $restaurant" else ""
                    ttsManager?.speak("Opening $appLabel$restaurantText")
                    return
                }
            } catch (e: Exception) { }
        }

        // Try Swiggy then Zomato
        for ((pkg, label) in listOf("in.swiggy.android" to "Swiggy", "com.application.zomato" to "Zomato")) {
            try {
                val intent = context.packageManager.getLaunchIntentForPackage(pkg)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    val restaurantText = if (!restaurant.isNullOrBlank()) " for $restaurant" else ""
                    ttsManager?.speak("Opening $label$restaurantText")
                    return
                }
            } catch (e: Exception) { }
        }

        ttsManager?.speak("No food delivery app found on this device")
    }

    fun shareText(text: String, appName: String?, ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Intent.ACTION_SEND)
            intent.type = "text/plain"
            intent.putExtra(Intent.EXTRA_TEXT, text)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            val packageName = when (appName?.lowercase()) {
                "whatsapp" -> "com.whatsapp"
                "instagram" -> "com.instagram.android"
                "telegram" -> "org.telegram.messenger"
                "twitter", "x" -> "com.twitter.android"
                "facebook" -> "com.facebook.katana"
                else -> null
            }

            if (packageName != null) {
                intent.setPackage(packageName)
            }

            try {
                context.startActivity(intent)
                val appText = appName ?: "share menu"
                ttsManager?.speak("Sharing to $appText")
            } catch (e: Exception) {
                // App not installed, open general share sheet
                val chooser = Intent.createChooser(intent, "Share via")
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(chooser)
                ttsManager?.speak("Opening share menu")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Could not share content")
        }
    }

    fun openInstagramProfile(username: String, ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Intent.ACTION_VIEW)
            intent.data = Uri.parse("https://instagram.com/$username")
            intent.setPackage("com.instagram.android")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                ttsManager?.speak("Opening $username on Instagram")
            } catch (e: Exception) {
                // Fallback to browser
                val browserIntent = Intent(Intent.ACTION_VIEW)
                browserIntent.data = Uri.parse("https://instagram.com/$username")
                browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(browserIntent)
                ttsManager?.speak("Opening $username's Instagram in browser")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Could not open Instagram profile")
        }
    }

    fun searchYouTubeVideo(query: String, ttsManager: TtsManager? = null) {
        try {
            val intent = Intent(Intent.ACTION_SEARCH)
            intent.setPackage("com.google.android.youtube")
            intent.putExtra(android.app.SearchManager.QUERY, query)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                ttsManager?.speak("Searching $query on YouTube")
            } catch (e: Exception) {
                // Fallback to browser
                val encodedQuery = Uri.encode(query)
                val browserIntent = Intent(Intent.ACTION_VIEW)
                browserIntent.data = Uri.parse("https://www.youtube.com/results?search_query=$encodedQuery")
                browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(browserIntent)
                ttsManager?.speak("Searching $query on YouTube in browser")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Could not search YouTube")
        }
    }

    fun openTwitterSearch(query: String, ttsManager: TtsManager? = null) {
        try {
            val encodedQuery = Uri.encode(query)
            val intent = Intent(Intent.ACTION_VIEW)
            intent.data = Uri.parse("https://twitter.com/search?q=$encodedQuery")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // Try Twitter/X app first
            intent.setPackage("com.twitter.android")
            try {
                context.startActivity(intent)
                ttsManager?.speak("Searching $query on Twitter")
            } catch (e: Exception) {
                // Fallback to browser
                intent.setPackage(null)
                context.startActivity(intent)
                ttsManager?.speak("Searching $query on Twitter in browser")
            }
        } catch (e: Exception) {
            ttsManager?.speak("Could not search Twitter")
        }
    }

    fun openProfile(platform: String, username: String, ttsManager: TtsManager? = null) {
        when (platform.lowercase()) {
            "instagram" -> openInstagramProfile(username, ttsManager)
            "twitter", "x" -> {
                try {
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.data = Uri.parse("https://twitter.com/$username")
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    intent.setPackage("com.twitter.android")
                    try {
                        context.startActivity(intent)
                        ttsManager?.speak("Opening $username on Twitter")
                    } catch (e: Exception) {
                        intent.setPackage(null)
                        context.startActivity(intent)
                        ttsManager?.speak("Opening $username on Twitter in browser")
                    }
                } catch (e: Exception) {
                    ttsManager?.speak("Could not open Twitter profile")
                }
            }
            "youtube" -> {
                try {
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.data = Uri.parse("https://www.youtube.com/@$username")
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    ttsManager?.speak("Opening $username on YouTube")
                } catch (e: Exception) {
                    ttsManager?.speak("Could not open YouTube profile")
                }
            }
            "linkedin" -> {
                try {
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.data = Uri.parse("https://www.linkedin.com/in/$username")
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    ttsManager?.speak("Opening $username on LinkedIn")
                } catch (e: Exception) {
                    ttsManager?.speak("Could not open LinkedIn profile")
                }
            }
            "facebook" -> {
                try {
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.data = Uri.parse("https://www.facebook.com/$username")
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    ttsManager?.speak("Opening $username on Facebook")
                } catch (e: Exception) {
                    ttsManager?.speak("Could not open Facebook profile")
                }
            }
            else -> ttsManager?.speak("I don't support opening profiles on $platform yet")
        }
    }

    // Helper function to format doubles nicely
    private fun Double.format(): String {
        return if (this % 1.0 == 0.0) {
            this.toInt().toString()
        } else {
            String.format("%.2f", this)
        }
    }
}

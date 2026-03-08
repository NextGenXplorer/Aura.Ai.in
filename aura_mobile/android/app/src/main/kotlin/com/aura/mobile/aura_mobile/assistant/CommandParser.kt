package com.aura.mobile.aura_mobile.assistant

sealed class ParsedCommand {
    data class OpenApp(val appName: String) : ParsedCommand()
    data class CallContact(val contactName: String) : ParsedCommand()
    data class SendSms(val contactName: String, val message: String) : ParsedCommand()
    data class SendEmail(val address: String) : ParsedCommand()
    data class TurnTorch(val state: Boolean) : ParsedCommand()
    data class SetTimer(val minutes: Int) : ParsedCommand()
    data class SetAlarm(val hour: Int, val minute: Int) : ParsedCommand()
    data class SetReminder(val text: String, val timeInMillis: Long) : ParsedCommand()
    data class WebSearch(val query: String) : ParsedCommand()
    data class PlayYouTube(val query: String) : ParsedCommand()
    object GetTime : ParsedCommand()
    object GetDate : ParsedCommand()
    object GetBattery : ParsedCommand()
    object MaxVolume : ParsedCommand()
    object MuteVolume : ParsedCommand()
    object OpenCamera : ParsedCommand()
    object OpenWifiSettings : ParsedCommand()
    object OpenBluetoothSettings : ParsedCommand()
    object OpenSettings : ParsedCommand()
    object Unknown : ParsedCommand()
}

object CommandParser {
    fun parse(rawText: String): ParsedCommand {
        var text = rawText.lowercase().trim()

        // 1. Remove filler words to make parsing robust
        val fillers = listOf(
            "can you ", "could you ", "please ", "for me", "hey aura ", "aura ",
            "just ", "quickly ", "i want to ", "i need to ", "i'd like to ",
            "i would like to ", "go ahead and ", "would you ", "will you ",
            "kindly ", "hey ", "yo ", "help me "
        )
        for (filler in fillers) {
            text = text.replace(filler, "")
        }
        text = text.trim()

        // YouTube Search / Play
        val youtubeRegex = Regex("^(play|search|look for|find|put on)\\s+(.+?)\\s+(on|in)\\s+youtube$|^(play|search|look for|find|put on)\\s+youtube\\s+(for|with)?\\s*(.+)$|youtube\\s+(play|search|for)\\s+(.+)")
        val ytMatch = youtubeRegex.find(text)
        if (ytMatch != null) {
            val query = ytMatch.groupValues.drop(1).find { it.isNotBlank() && it != "play" && it != "search" && it != "look for" && it != "find" && it != "put on" && it != "on" && it != "in" && it != "for" && it != "with" }?.trim()
            if (!query.isNullOrEmpty()) {
                return ParsedCommand.PlayYouTube(query)
            }
        }
        if (text.startsWith("youtube ")) {
            val query = text.removePrefix("youtube ").trim()
            if (query.isNotEmpty()) return ParsedCommand.PlayYouTube(query)
        }

        // Call Contact (robust regex)
        // Matches: call mom, dial dad, phone john, ring up sarah, give alex a ring, make a call to peter
        val callRegex = Regex("^(call|dial|phone|ring|ring up|make a call to|give)\\s+(.+?)(?:\\s+a\\s+(call|ring|buzz))?$")
        val callMatch = callRegex.find(text)
        if (callMatch != null) {
            var contactName = callMatch.groupValues[2].trim()
            // Strip trailing time/context phrases like "at 9pm", "now", "please"
            contactName = contactName
                .replace(Regex("\\s+(at|by|around)\\s+\\d+\\s*(am|pm)?", RegexOption.IGNORE_CASE), "")
                .replace(Regex("\\s+(now|right now|immediately|asap|please)$", RegexOption.IGNORE_CASE), "")
                .trim()
            if (contactName.isNotEmpty() && contactName != "me" && contactName != "it") {
                return ParsedCommand.CallContact(contactName)
            }
        }

        // Send SMS/Text (robust regex)
        // Matches: text mom hi, send message to dad saying hello, message john, drop a text to sarah that i am late
        val smsRegex = Regex("^(text|message|sms|send a message to|send message to|send a text to|send text to|send an sms to|shoot a message to|drop a text to)\\s+(.+?)(?:\\s+(saying|that|with message|as)\\s+(.+))?$")
        val smsMatch = smsRegex.find(text)
        if (smsMatch != null) {
            val verb = smsMatch.groupValues[1]
            var contactName = smsMatch.groupValues[2].trim()
            var message = smsMatch.groupValues[4].trim()

            // Handle case where "text mom hi" or "text hyy to pooja" puts everything into group 2
            if (message.isEmpty() && (verb == "text" || verb == "message" || verb == "sms")) {
                // First check for " to " separator: "text hyy to pooja" -> body=hyy, name=pooja
                if (contactName.contains(" to ")) {
                    val toIdx = contactName.indexOf(" to ")
                    val potentialBody = contactName.substring(0, toIdx).trim()
                    val potentialName = contactName.substring(toIdx + 4).trim()
                    if (potentialName.isNotEmpty() && potentialBody.isNotEmpty()) {
                        contactName = potentialName
                        message = potentialBody
                    }
                } else {
                    // No "to" separator: "text Pooja how are you" -> name=Pooja, body=how are you
                    val parts = contactName.split(Regex("\\s+"), limit = 2)
                    if (parts.size == 2) {
                        contactName = parts[0]
                        message = parts[1]
                    }
                }
            }
            if (contactName.isNotEmpty()) {
                // Cleanup "to" if it slipped in (e.g., "message to mom")
                if (contactName.startsWith("to ")) contactName = contactName.removePrefix("to ").trim()
                return ParsedCommand.SendSms(contactName, message)
            }
        }

        // Email Draft (robust regex)
        // Matches: email john at gmail dot com, send an email to peter, mail, gmail
        val emailRegex = Regex("^(email|send an email to|send email to|mail|gmail|send a mail to|draft an email to|compose an email to)\\s+(.+)$")
        val emailMatch = emailRegex.find(text)
        if (emailMatch != null) {
            var rawAddress = emailMatch.groupValues[2].trim()
            if (rawAddress.isNotEmpty()) {
                // Convert common conversational phonetics into valid email formats
                rawAddress = rawAddress.replace(" at ", "@")
                    .replace(" dot ", ".")
                    .replace(" ", "")
                return ParsedCommand.SendEmail(rawAddress)
            }
        }

        // Open App (robust regex)
        // Matches: open whatsapp, launch spotify, start Netflix, pull up chrome
        val openRegex = Regex("^(open|launch|start|fire up|pull up|bring up|load|run)\\s+(.+?)(?:\\s+app|\\s+application)?$")
        val openMatch = openRegex.find(text)
        if (openMatch != null && !text.contains("camera") && !text.contains("settings") && !text.contains("wifi") && !text.contains("bluetooth")) {
            val appName = openMatch.groupValues[2].trim()
            if (appName.isNotEmpty()) {
                return ParsedCommand.OpenApp(appName)
            }
        }

        // Torch Control
        val turnOnTorchRegex = Regex("\\b(turn on|enable|switch on|start)\\b.*\\b(torch|flashlight|light|flash)\\b|\\b(torch|flashlight|light|flash)\\b.*\\b(on)\\b|light up (my )?(phone|path|way)|let there be light")
        if (turnOnTorchRegex.containsMatchIn(text)) {
            return ParsedCommand.TurnTorch(true)
        }
        val turnOffTorchRegex = Regex("\\b(turn off|disable|switch off|stop|kill)\\b.*\\b(torch|flashlight|light|flash)\\b|\\b(torch|flashlight|light|flash)\\b.*\\b(off)\\b|darkness")
        if (turnOffTorchRegex.containsMatchIn(text)) {
            return ParsedCommand.TurnTorch(false)
        }

        // Time & Date
        val timeRegex = Regex("\\b(time|what time|current time|clock)\\b")
        if (timeRegex.containsMatchIn(text) && !text.contains("timer")) return ParsedCommand.GetTime
        
        val dateRegex = Regex("\\b(date|what day|today's date|current date|what is today)\\b")
        if (dateRegex.containsMatchIn(text)) return ParsedCommand.GetDate

        // Battery
        val batteryRegex = Regex("\\b(battery|juice|power left|charge)\\b")
        if (batteryRegex.containsMatchIn(text)) return ParsedCommand.GetBattery

        // Volume
        val maxVolRegex = Regex("\\b(max volume|volume to max|turn it up|maximum volume|loudest)\\b")
        if (maxVolRegex.containsMatchIn(text)) return ParsedCommand.MaxVolume
        
        val muteRegex = Regex("\\b(mute|silence|quiet|no sound|turn volume off)\\b")
        if (muteRegex.containsMatchIn(text)) return ParsedCommand.MuteVolume

        // Timers & Alarms
        val timerRegex = Regex("\\b(timer|countdown)\\b.*?(\\d+)\\s*(min|minute|sec|second|hour|hr)")
        val timerMatch = timerRegex.find(text)
        if (timerMatch != null) {
             val amount = timerMatch.groupValues[2].toIntOrNull()
             val unit = timerMatch.groupValues[3]
             if (amount != null) {
                 // Convert to minutes for basic handler
                 val minutes = when {
                     unit.startsWith("hour") || unit.startsWith("hr") -> amount * 60
                     unit.startsWith("sec") -> if (amount >= 60) amount / 60 else 1 
                     else -> amount
                 }
                 return ParsedCommand.SetTimer(minutes)
             }
        }

        // Reminders (e.g. remind me to call dad in 10 minutes, remind me in 5 minutes to take pills)
        val reminderRegex = Regex("^(remind\\s+(me|us)\\s+(to|about)?|set\\s+a\\s+reminder\\s+(to|about)?|notify\\s+(me|us)\\s+(to|about)?|schedule\\s+a\\s+reminder\\s+(to|about)?)\\s+(.+)$")
        val reminderMatch = reminderRegex.find(text)
        if (reminderMatch != null) {
            val fullReminderText = reminderMatch.groupValues[8].trim()
            
            // 1. Try relative time (in X minutes/hours)
            val relativeTimeRegex = Regex("\\b(in|after)\\s+(\\d+)\\s*(min|minute|minutes|hr|hour|hours|day|days)\\b")
            val relativeMatch = relativeTimeRegex.find(fullReminderText)
            
            var targetTime = 0L
            var timePhraseToStrip = ""

            if (relativeMatch != null) {
                val amount = relativeMatch.groupValues[2].toLongOrNull() ?: 0L
                val unit = relativeMatch.groupValues[3]
                
                val timeToAddInMillis = when {
                    unit.startsWith("min") -> amount * 60 * 1000L
                    unit.startsWith("h") -> amount * 60 * 60 * 1000L
                    unit.startsWith("day") -> amount * 24 * 60 * 60 * 1000L
                    else -> 0L
                }
                
                if (timeToAddInMillis > 0L) {
                    targetTime = System.currentTimeMillis() + timeToAddInMillis
                    timePhraseToStrip = relativeMatch.value
                }
            } else {
                // 2. Try specific date/time (e.g., "on 20/10/2026")
                val specificDateRegex = Regex("\\b(?:on\\s+)?(\\d{1,2})[-/](\\d{1,2})(?:[-/](\\d{2,4}))?\\b")
                val specificTimeRegex = Regex("\\b(?:at\\s+)?(1[0-2]|0?[1-9]|2[0-3])(?::([0-5][0-9]))?\\s*(am|pm)?\\b", RegexOption.IGNORE_CASE)
                
                val dateMatch = specificDateRegex.find(fullReminderText)
                val timeMatch = specificTimeRegex.find(fullReminderText)
                
                if (dateMatch != null || timeMatch != null) {
                    val calendar = java.util.Calendar.getInstance()
                    val now = System.currentTimeMillis()
                    
                    if (dateMatch != null) {
                        val day = dateMatch.groupValues[1].toInt()
                        val month = dateMatch.groupValues[2].toInt() - 1 // Calendar months are 0-indexed
                        var year = if (dateMatch.groupValues[3].isNotEmpty()) dateMatch.groupValues[3].toInt() else calendar.get(java.util.Calendar.YEAR)
                        if (year < 100) year += 2000
                        
                        calendar.set(java.util.Calendar.YEAR, year)
                        calendar.set(java.util.Calendar.MONTH, month)
                        calendar.set(java.util.Calendar.DAY_OF_MONTH, day)
                        timePhraseToStrip += dateMatch.value + " "
                    }
                    
                    if (timeMatch != null) {
                        var hour = timeMatch.groupValues[1].toInt()
                        val minuteStr = timeMatch.groupValues[2]
                        val minute = if (minuteStr.isNotEmpty()) minuteStr.toInt() else 0
                        val ampm = timeMatch.groupValues[3].lowercase()
                        
                        if (ampm == "pm" && hour < 12) hour += 12
                        if (ampm == "am" && hour == 12) hour = 0
                        
                        calendar.set(java.util.Calendar.HOUR_OF_DAY, hour)
                        calendar.set(java.util.Calendar.MINUTE, minute)
                        timePhraseToStrip += timeMatch.value + " "
                    } else {
                         // Default to 9 AM if no time is provided
                         calendar.set(java.util.Calendar.HOUR_OF_DAY, 9)
                         calendar.set(java.util.Calendar.MINUTE, 0)
                    }
                    
                    calendar.set(java.util.Calendar.SECOND, 0)
                    calendar.set(java.util.Calendar.MILLISECOND, 0)
                    targetTime = calendar.timeInMillis
                    
                    // If no date was specified and the time has already passed today, roll over to tomorrow
                    if (dateMatch == null && targetTime < now) {
                        calendar.add(java.util.Calendar.DAY_OF_MONTH, 1)
                        targetTime = calendar.timeInMillis
                    }
                }
            }

            if (targetTime > System.currentTimeMillis()) {
                // Clean up title
                var reminderTitle = fullReminderText
                if (timePhraseToStrip.isNotEmpty()) {
                    reminderTitle = reminderTitle.replace(timePhraseToStrip.trim(), "").trim()
                }
                
                // Remove trailing/leading prepositions
                reminderTitle = reminderTitle.replace(Regex("^(to|on|at|about)\\s+", RegexOption.IGNORE_CASE), "").trim()
                reminderTitle = reminderTitle.replace(Regex("\\s+(to|on|at|about)$", RegexOption.IGNORE_CASE), "").trim()

                if (reminderTitle.isEmpty()) reminderTitle = "Reminder"
                
                return ParsedCommand.SetReminder(reminderTitle, targetTime)
            }
        }

        // Web Search
        val searchRegex = Regex("^(search|google|look up|find|search for|google for)\\s+(.+)$")
        val searchMatch = searchRegex.find(text)
        if (searchMatch != null) {
            val query = searchMatch.groupValues[2].trim()
            if (query.isNotEmpty()) return ParsedCommand.WebSearch(query)
        }

        // Open Camera
        val cameraRegex = Regex("\\b(camera|photo|picture|pic|selfie|snap)\\b")
        if (cameraRegex.containsMatchIn(text) && (text.contains("open") || text.contains("take") || text.contains("snap") || text.contains("shoot") || text.contains("capture"))) {
            return ParsedCommand.OpenCamera
        }

        // Settings (Wifi, Bluetooth, System)
        val wifiRegex = Regex("\\b(wifi|wi-fi|internet)\\b.*\\b(settings|menu|net)\\b|\\b(open|show)\\b.*\\b(wifi|wi-fi)\\b")
        if (wifiRegex.containsMatchIn(text)) return ParsedCommand.OpenWifiSettings
        
        val bluetoothRegex = Regex("\\b(bluetooth|blue tooth)\\b.*\\b(settings|menu)\\b|\\b(open|show)\\b.*\\b(bluetooth|blue tooth)\\b")
        if (bluetoothRegex.containsMatchIn(text)) return ParsedCommand.OpenBluetoothSettings
        
        val settingsRegex = Regex("\\b(settings|preferences|configuration)\\b|\\b(open|show)\\b.*\\b(settings)\\b")
        if (settingsRegex.containsMatchIn(text)) return ParsedCommand.OpenSettings

        return ParsedCommand.Unknown
    }
}


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
    data class PlayMusic(val query: String) : ParsedCommand()
    data class Navigate(val destination: String) : ParsedCommand()
    data class ToggleSetting(val setting: String, val state: Boolean) : ParsedCommand()
    object ReadClipboard : ParsedCommand()
    object FindMyPhone : ParsedCommand()
    object TakeSelfie : ParsedCommand()

    // ═══ NEW FEATURES (5 High-Value Additions) ═══
    // 1. Calendar & Events
    object ViewCalendar : ParsedCommand()
    data class CreateEvent(val title: String, val timeInMillis: Long) : ParsedCommand()
    object GetNextEvent : ParsedCommand()

    // 2. Media Controls
    data class MediaControl(val action: String) : ParsedCommand() // play, pause, next, previous
    data class SetBrightness(val level: Int) : ParsedCommand() // 0-100
    object Screenshot : ParsedCommand()

    // 3. Read Messages/Notifications
    data class ReadMessages(val appName: String?) : ParsedCommand() // null = all messages
    object ReadNotifications : ParsedCommand()

    // 4. Quick Notes
    data class CreateNote(val content: String) : ParsedCommand()

    // 5. Calculator & Converter
    data class Calculate(val expression: String) : ParsedCommand()
    data class Convert(val amount: Double, val fromUnit: String, val toUnit: String) : ParsedCommand()

    // ═══ SMART APP ACTIONS ═══
    data class SendWhatsApp(val contactName: String, val message: String) : ParsedCommand()
    data class SearchOnApp(val appName: String, val query: String) : ParsedCommand()
    data class UpiPayment(val upiId: String?, val amount: String?, val note: String?) : ParsedCommand()
    data class PlayOnSpotify(val query: String) : ParsedCommand()
    data class BookRide(val destination: String, val app: String?) : ParsedCommand()
    data class OrderFood(val restaurant: String?, val app: String?) : ParsedCommand()
    data class ShareText(val text: String, val app: String?) : ParsedCommand()
    data class OpenProfile(val platform: String, val username: String) : ParsedCommand()

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

        // Navigation (Google Maps)
        val navigateRegex = Regex("^(?:navigate|take me|drive|give me directions|directions)\\s+(?:to\\s+)?(.+)$")
        val navMatch = navigateRegex.find(text)
        if (navMatch != null) {
            val destination = navMatch.groupValues[1].trim()
            if (destination.isNotEmpty()) {
                return ParsedCommand.Navigate(destination)
            }
        }

        // Play Music (Spotify/Apple Music)
        val musicRegex = Regex("^(?:play)\\s+(.+?)(?:\\s+on\\s+(?:spotify|apple music|music))?$")
        val musicMatch = musicRegex.find(text)
        if (musicMatch != null && !text.contains("youtube")) {
            val query = musicMatch.groupValues[1].trim()
            if (query.isNotEmpty() && query != "music" && query != "some music") {
                return ParsedCommand.PlayMusic(query)
            }
        }

        // Take Selfie
        val selfieRegex = Regex("\\b(?:take a selfie|selfie|front camera)\\b")
        if (selfieRegex.containsMatchIn(text)) {
            return ParsedCommand.TakeSelfie
        }

        // Find My Phone
        val findPhoneRegex = Regex("\\b(?:find my phone|where is my phone|ping my phone|play a sound|ring my phone)\\b")
        if (findPhoneRegex.containsMatchIn(text)) {
            return ParsedCommand.FindMyPhone
        }

        // Read Clipboard
        val clipboardRegex = Regex("\\b(?:read my clipboard|what is on my clipboard|read clipboard|what did i copy)\\b")
        if (clipboardRegex.containsMatchIn(text)) {
            return ParsedCommand.ReadClipboard
        }

        // System Toggles (Wi-Fi, Bluetooth, DND)
        val toggleRegex = Regex("^(turn|switch)\\s+(on|off)\\s+(wifi|wi-fi|bluetooth|do not disturb|dnd)$")
        val toggleMatch = toggleRegex.find(text)
        if (toggleMatch != null) {
            val state = toggleMatch.groupValues[2] == "on"
            val setting = toggleMatch.groupValues[3].replace("-", "")
            return ParsedCommand.ToggleSetting(setting, state)
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

        // ─── Reminders & Notifications ───────────────────────────────────────────
        // Trigger phrases: remind me, set a reminder, notify me, alert me, ping me,
        //   add a reminder, schedule a reminder, set an alarm for, create a reminder
        val reminderRegex = Regex(
            """^(remind\s+(me|us)(\s+(to|about))?|""" +
            """set\s+(a\s+)?reminder(\s+(to|about|for))?|""" +
            """notify\s+(me|us)(\s+(to|about|at|on))?|""" +
            """schedule\s+(a\s+)?reminder(\s+(to|for))?|""" +
            """alert\s+(me|us)(\s+(to|about))?|""" +
            """ping\s+(me|us)(\s+(to|about))?|""" +
            """add\s+(a\s+)?reminder(\s+(to|about|for))?|""" +
            """create\s+(a\s+)?reminder(\s+(to|for))?)\s+(.+)$"""
        )
        val reminderMatch = reminderRegex.find(text)
        if (reminderMatch != null) {
            // Last captured group is the full body after the trigger phrase
            val fullReminderText = reminderMatch.groupValues.last { it.isNotEmpty() && 
                it != "me" && it != "us" && it != "to" && it != "about" && it != "for" && 
                it != "at" && it != "on" && it != "a" }.trim()

            var targetTime = 0L
            var timePhraseToStrip = ""
            val now = System.currentTimeMillis()
            val calendar = java.util.Calendar.getInstance()

            // ── 1. RELATIVE: "in X minutes/hours/days" ──────────────────────
            val relativeRegex = Regex(
                """(?:in|after)\s+(\d+)\s*(min(?:ute)?s?|hr|hour?s?|day?s?)""",
                RegexOption.IGNORE_CASE
            )
            val relMatch = relativeRegex.find(fullReminderText)
            if (relMatch != null) {
                val amount = relMatch.groupValues[1].toLongOrNull() ?: 0L
                val unit = relMatch.groupValues[2].lowercase()
                val millis = when {
                    unit.startsWith("min") -> amount * 60_000L
                    unit.startsWith("h")   -> amount * 3_600_000L
                    unit.startsWith("d")   -> amount * 86_400_000L
                    else -> 0L
                }
                if (millis > 0L) {
                    targetTime = now + millis
                    timePhraseToStrip = relMatch.value
                }
            }

            // ── 2. TONIGHT / TODAY / TOMORROW at X ──────────────────────────
            if (targetTime == 0L) {
                val tonightRegex = Regex("""tonight\s+at\s+(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)?""", RegexOption.IGNORE_CASE)
                val todayAtRegex  = Regex("""(?:today\s+)?at\s+(1[0-2]|0?[1-9]|2[0-3])(?::([0-5]\d))?\s*(am|pm)?""", RegexOption.IGNORE_CASE)
                val tomorrowRegex = Regex("""tomorrow\s+(?:at\s+)?(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)?""", RegexOption.IGNORE_CASE)

                fun applyTimeToCalendar(hr: String, mn: String, ap: String) {
                    var h = hr.toInt()
                    val m = if (mn.isNotEmpty()) mn.toInt() else 0
                    val isPm = ap.lowercase() == "pm"
                    val isAm = ap.lowercase() == "am"
                    if (isPm && h < 12) h += 12
                    if (isAm && h == 12) h = 0
                    // If no AM/PM specified and hour ≤ 8, assume PM (e.g. "at 7" = 7 PM)
                    if (ap.isEmpty() && h in 1..8) h += 12
                    calendar.set(java.util.Calendar.HOUR_OF_DAY, h)
                    calendar.set(java.util.Calendar.MINUTE, m)
                    calendar.set(java.util.Calendar.SECOND, 0)
                    calendar.set(java.util.Calendar.MILLISECOND, 0)
                }

                val tomorrowM = tomorrowRegex.find(fullReminderText)
                val tonightM  = tonightRegex.find(fullReminderText)
                val todayAtM  = todayAtRegex.find(fullReminderText)

                when {
                    tomorrowM != null -> {
                        calendar.add(java.util.Calendar.DAY_OF_MONTH, 1)
                        applyTimeToCalendar(tomorrowM.groupValues[1], tomorrowM.groupValues[2], tomorrowM.groupValues[3])
                        targetTime = calendar.timeInMillis
                        timePhraseToStrip = tomorrowM.value
                    }
                    tonightM != null -> {
                        applyTimeToCalendar(tonightM.groupValues[1], tonightM.groupValues[2], tonightM.groupValues[3])
                        if (calendar.timeInMillis < now) calendar.add(java.util.Calendar.DAY_OF_MONTH, 1)
                        targetTime = calendar.timeInMillis
                        timePhraseToStrip = tonightM.value
                    }
                    todayAtM != null -> {
                        applyTimeToCalendar(todayAtM.groupValues[1], todayAtM.groupValues[2], todayAtM.groupValues[3])
                        if (calendar.timeInMillis < now) calendar.add(java.util.Calendar.DAY_OF_MONTH, 1)
                        targetTime = calendar.timeInMillis
                        timePhraseToStrip = todayAtM.value
                    }
                }
            }

            // ── 3. NEXT WEEKDAY: "next Monday", "next Friday at 9 AM" ────────
            if (targetTime == 0L) {
                val weekdayMap = mapOf(
                    "monday" to java.util.Calendar.MONDAY, "tuesday" to java.util.Calendar.TUESDAY,
                    "wednesday" to java.util.Calendar.WEDNESDAY, "thursday" to java.util.Calendar.THURSDAY,
                    "friday" to java.util.Calendar.FRIDAY, "saturday" to java.util.Calendar.SATURDAY,
                    "sunday" to java.util.Calendar.SUNDAY, "mon" to java.util.Calendar.MONDAY,
                    "tue" to java.util.Calendar.TUESDAY, "wed" to java.util.Calendar.WEDNESDAY,
                    "thu" to java.util.Calendar.THURSDAY, "fri" to java.util.Calendar.FRIDAY,
                    "sat" to java.util.Calendar.SATURDAY, "sun" to java.util.Calendar.SUNDAY
                )
                val weekdayRegex = Regex(
                    """(?:next\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|""" +
                    """mon|tue|wed|thu|fri|sat|sun)(?:\s+at\s+(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)?)?""",
                    RegexOption.IGNORE_CASE
                )
                val wdMatch = weekdayRegex.find(fullReminderText)
                if (wdMatch != null) {
                    val targetDow = weekdayMap[wdMatch.groupValues[1].lowercase()] ?: -1
                    if (targetDow != -1) {
                        val daysDiff = ((targetDow - calendar.get(java.util.Calendar.DAY_OF_WEEK) + 7) % 7).let { if (it == 0) 7 else it }
                        calendar.add(java.util.Calendar.DAY_OF_MONTH, daysDiff)
                        val timeHr = wdMatch.groupValues[2]
                        val timeMn = wdMatch.groupValues[3]
                        val timeAp = wdMatch.groupValues[4]
                        if (timeHr.isNotEmpty()) {
                            var h = timeHr.toInt()
                            val m = if (timeMn.isNotEmpty()) timeMn.toInt() else 0
                            if (timeAp.lowercase() == "pm" && h < 12) h += 12
                            if (timeAp.lowercase() == "am" && h == 12) h = 0
                            if (timeAp.isEmpty() && h in 1..8) h += 12
                            calendar.set(java.util.Calendar.HOUR_OF_DAY, h)
                            calendar.set(java.util.Calendar.MINUTE, m)
                        } else {
                            calendar.set(java.util.Calendar.HOUR_OF_DAY, 9)
                            calendar.set(java.util.Calendar.MINUTE, 0)
                        }
                        calendar.set(java.util.Calendar.SECOND, 0)
                        calendar.set(java.util.Calendar.MILLISECOND, 0)
                        targetTime = calendar.timeInMillis
                        timePhraseToStrip = wdMatch.value
                    }
                }
            }

            // ── 4. NAMED MONTH DAY: "on October 7", "on 7th October", "on 7 oct" ──
            if (targetTime == 0L) {
                val monthMap = mapOf(
                    "jan" to 0, "january" to 0, "feb" to 1, "february" to 1, "mar" to 2, "march" to 2,
                    "apr" to 3, "april" to 3, "may" to 4, "jun" to 5, "june" to 5,
                    "jul" to 6, "july" to 6, "aug" to 7, "august" to 7, "sep" to 8, "september" to 8,
                    "oct" to 9, "october" to 9, "nov" to 10, "november" to 10, "dec" to 11, "december" to 11
                )
                val namedMonthRegex = Regex(
                    """(?:on\s+)?(?:(\d{1,2})(?:st|nd|rd|th)?\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|""" +
                    """apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|""" +
                    """nov(?:ember)?|dec(?:ember)?)|(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|""" +
                    """apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|""" +
                    """nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?)(?:\s*,?\s*(\d{4}))?""" +
                    """(?:\s+at\s+(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)?)?""",
                    RegexOption.IGNORE_CASE
                )
                val nmMatch = namedMonthRegex.find(fullReminderText)
                if (nmMatch != null) {
                    val groups = nmMatch.groupValues
                    // Day-first format: "7th October" → groups[1]=7, groups[2]=October
                    // Month-first format: "October 7" → groups[3]=October, groups[4]=7
                    val day: Int
                    val monthStr: String
                    if (groups[1].isNotEmpty()) {
                        day = groups[1].toInt()
                        monthStr = groups[2].lowercase()
                    } else {
                        monthStr = groups[3].lowercase()
                        day = groups[4].toIntOrNull() ?: 1
                    }
                    val monthIdx = monthMap.entries.find { monthStr.startsWith(it.key.substring(0, minOf(3, it.key.length))) }?.value ?: -1
                    if (monthIdx != -1 && day in 1..31) {
                        var year = groups[5].toIntOrNull() ?: calendar.get(java.util.Calendar.YEAR)
                        calendar.set(java.util.Calendar.YEAR, year)
                        calendar.set(java.util.Calendar.MONTH, monthIdx)
                        calendar.set(java.util.Calendar.DAY_OF_MONTH, day)

                        val timeHr = groups[6]
                        val timeMn = groups[7]
                        val timeAp = groups[8]
                        if (timeHr.isNotEmpty()) {
                            var h = timeHr.toInt()
                            val m = if (timeMn.isNotEmpty()) timeMn.toInt() else 0
                            if (timeAp.lowercase() == "pm" && h < 12) h += 12
                            if (timeAp.lowercase() == "am" && h == 12) h = 0
                            if (timeAp.isEmpty() && h in 1..8) h += 12
                            calendar.set(java.util.Calendar.HOUR_OF_DAY, h)
                            calendar.set(java.util.Calendar.MINUTE, m)
                        } else {
                            calendar.set(java.util.Calendar.HOUR_OF_DAY, 9)
                            calendar.set(java.util.Calendar.MINUTE, 0)
                        }
                        calendar.set(java.util.Calendar.SECOND, 0)
                        calendar.set(java.util.Calendar.MILLISECOND, 0)

                        // If no year given and date has passed, roll to next year
                        if (groups[5].isEmpty() && calendar.timeInMillis < now) {
                            calendar.add(java.util.Calendar.YEAR, 1)
                        }
                        targetTime = calendar.timeInMillis
                        timePhraseToStrip = nmMatch.value
                    }
                }
            }

            // ── 5. NUMERIC DATE: "on 7/10", "on 20-10-2026" ────────────────
            if (targetTime == 0L) {
                val numericDateRegex = Regex("""(?:on\s+)?(\d{1,2})[-/](\d{1,2})(?:[-/](\d{2,4}))?""")
                val specificTimeRegex = Regex("""(?:at\s+)?(1[0-2]|0?[1-9]|2[0-3])(?::([0-5][0-9]))?\s*(am|pm)?""", RegexOption.IGNORE_CASE)
                val dateMatch2 = numericDateRegex.find(fullReminderText)
                val timeMatch2 = specificTimeRegex.find(fullReminderText)
                if (dateMatch2 != null || timeMatch2 != null) {
                    if (dateMatch2 != null) {
                        val day = dateMatch2.groupValues[1].toInt()
                        val month = dateMatch2.groupValues[2].toInt() - 1
                        var year = if (dateMatch2.groupValues[3].isNotEmpty()) dateMatch2.groupValues[3].toInt() else calendar.get(java.util.Calendar.YEAR)
                        if (year < 100) year += 2000
                        calendar.set(java.util.Calendar.YEAR, year)
                        calendar.set(java.util.Calendar.MONTH, month)
                        calendar.set(java.util.Calendar.DAY_OF_MONTH, day)
                        timePhraseToStrip += dateMatch2.value + " "
                    }
                    if (timeMatch2 != null) {
                        var h = timeMatch2.groupValues[1].toInt()
                        val m = if (timeMatch2.groupValues[2].isNotEmpty()) timeMatch2.groupValues[2].toInt() else 0
                        val ap = timeMatch2.groupValues[3].lowercase()
                        if (ap == "pm" && h < 12) h += 12
                        if (ap == "am" && h == 12) h = 0
                        if (ap.isEmpty() && h in 1..8) h += 12
                        calendar.set(java.util.Calendar.HOUR_OF_DAY, h)
                        calendar.set(java.util.Calendar.MINUTE, m)
                        timePhraseToStrip += timeMatch2.value + " "
                    } else {
                        calendar.set(java.util.Calendar.HOUR_OF_DAY, 9)
                        calendar.set(java.util.Calendar.MINUTE, 0)
                    }
                    calendar.set(java.util.Calendar.SECOND, 0)
                    calendar.set(java.util.Calendar.MILLISECOND, 0)
                    targetTime = calendar.timeInMillis
                    if (dateMatch2 == null && targetTime < now) {
                        calendar.add(java.util.Calendar.DAY_OF_MONTH, 1)
                        targetTime = calendar.timeInMillis
                    }
                }
            }

            if (targetTime > now) {
                // Build clean title by stripping the time phrase and command filler
                var reminderTitle = fullReminderText
                if (timePhraseToStrip.isNotEmpty()) {
                    reminderTitle = reminderTitle.replace(timePhraseToStrip.trim(), "", ignoreCase = true).trim()
                }
                // Strip common preposition artifacts
                reminderTitle = reminderTitle
                    .replace(Regex("""^(to|on|at|about|that|me|us)\s+""", RegexOption.IGNORE_CASE), "")
                    .replace(Regex("""\s+(to|on|at|about)$""", RegexOption.IGNORE_CASE), "")
                    .replace(Regex("""\s{2,}"""), " ")
                    .trim()
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

        // ═══════════════════════════════════════════════════════════════════════
        // NEW FEATURES - 5 High-Value Additions
        // ═══════════════════════════════════════════════════════════════════════

        // ─── 1. CALENDAR & EVENTS ────────────────────────────────────────────
        val viewCalendarRegex = Regex("\\b(show|view|check|what's on|open)\\b.*\\b(calendar|schedule|agenda|appointments|meetings)\\b|\\b(calendar|schedule|agenda)\\b")
        if (viewCalendarRegex.containsMatchIn(text)) return ParsedCommand.ViewCalendar

        val nextEventRegex = Regex("\\b(next|upcoming)\\b.*\\b(event|meeting|appointment)\\b|what('?s| is) (next|my next|up next)")
        if (nextEventRegex.containsMatchIn(text)) return ParsedCommand.GetNextEvent

        // Create calendar event: "schedule meeting tomorrow at 3pm", "add event next Monday"
        val createEventRegex = Regex("^(schedule|create|add|make|set up)\\s+(an?\\s+)?(event|meeting|appointment)\\s+(.+)$")
        val eventMatch = createEventRegex.find(text)
        if (eventMatch != null) {
            val eventDetails = eventMatch.groupValues[4].trim()
            // Reuse the reminder time parsing logic since it's already comprehensive
            var targetTime = 0L
            val now = System.currentTimeMillis()
            val calendar = java.util.Calendar.getInstance()

            // Try to parse time from event details (reuse reminder logic)
            val relativeRegex = Regex("(?:in|after)\\s+(\\d+)\\s*(min(?:ute)?s?|hr|hour?s?|day?s?)", RegexOption.IGNORE_CASE)
            val relMatch = relativeRegex.find(eventDetails)
            if (relMatch != null) {
                val amount = relMatch.groupValues[1].toLongOrNull() ?: 0L
                val unit = relMatch.groupValues[2].lowercase()
                val millis = when {
                    unit.startsWith("min") -> amount * 60_000L
                    unit.startsWith("h")   -> amount * 3_600_000L
                    unit.startsWith("d")   -> amount * 86_400_000L
                    else -> 0L
                }
                if (millis > 0L) targetTime = now + millis
            }

            // Try "tomorrow at X" or "today at X"
            if (targetTime == 0L) {
                val tomorrowRegex = Regex("tomorrow\\s+(?:at\\s+)?(1[0-2]|0?[1-9])(?::([0-5]\\d))?\\s*(am|pm)?", RegexOption.IGNORE_CASE)
                val todayAtRegex  = Regex("(?:today\\s+)?at\\s+(1[0-2]|0?[1-9]|2[0-3])(?::([0-5]\\d))?\\s*(am|pm)?", RegexOption.IGNORE_CASE)

                val tomorrowM = tomorrowRegex.find(eventDetails)
                val todayM = todayAtRegex.find(eventDetails)

                if (tomorrowM != null) {
                    calendar.add(java.util.Calendar.DAY_OF_MONTH, 1)
                    var h = tomorrowM.groupValues[1].toInt()
                    val m = if (tomorrowM.groupValues[2].isNotEmpty()) tomorrowM.groupValues[2].toInt() else 0
                    val ap = tomorrowM.groupValues[3].lowercase()
                    if (ap == "pm" && h < 12) h += 12
                    if (ap == "am" && h == 12) h = 0
                    if (ap.isEmpty() && h in 1..8) h += 12
                    calendar.set(java.util.Calendar.HOUR_OF_DAY, h)
                    calendar.set(java.util.Calendar.MINUTE, m)
                    calendar.set(java.util.Calendar.SECOND, 0)
                    targetTime = calendar.timeInMillis
                } else if (todayM != null) {
                    var h = todayM.groupValues[1].toInt()
                    val m = if (todayM.groupValues[2].isNotEmpty()) todayM.groupValues[2].toInt() else 0
                    val ap = todayM.groupValues[3].lowercase()
                    if (ap == "pm" && h < 12) h += 12
                    if (ap == "am" && h == 12) h = 0
                    if (ap.isEmpty() && h in 1..8) h += 12
                    calendar.set(java.util.Calendar.HOUR_OF_DAY, h)
                    calendar.set(java.util.Calendar.MINUTE, m)
                    calendar.set(java.util.Calendar.SECOND, 0)
                    if (calendar.timeInMillis < now) calendar.add(java.util.Calendar.DAY_OF_MONTH, 1)
                    targetTime = calendar.timeInMillis
                }
            }

            // Default to 1 hour from now if no time found
            if (targetTime == 0L) targetTime = now + 3_600_000L

            return ParsedCommand.CreateEvent(eventDetails, targetTime)
        }

        // ─── 2. MEDIA CONTROLS ───────────────────────────────────────────────
        val mediaControlRegex = Regex("\\b(play|pause|resume|stop|next|skip|previous|back)\\b.*\\b(song|music|track|video|media)?\\b|^(play|pause|resume|next|skip|previous)$")
        if (mediaControlRegex.containsMatchIn(text)) {
            val action = when {
                text.contains("pause") || text.contains("stop") -> "pause"
                text.contains("play") || text.contains("resume") -> "play"
                text.contains("next") || text.contains("skip") -> "next"
                text.contains("previous") || text.contains("back") -> "previous"
                else -> "play"
            }
            // Don't intercept "play X on youtube" or "play X music" queries
            if (!text.contains("youtube") && !text.matches(Regex("play\\s+.+\\s+(on|in|music|song)"))) {
                return ParsedCommand.MediaControl(action)
            }
        }

        val brightnessRegex = Regex("\\b(brightness|screen brightness|display brightness)\\b|\\b(increase|decrease|set|adjust)\\b.*\\b(brightness)\\b")
        if (brightnessRegex.containsMatchIn(text)) {
            val level = when {
                text.contains("max") || text.contains("full") || text.contains("100") -> 100
                text.contains("min") || text.contains("low") || text.contains("dim") -> 10
                text.contains("medium") || text.contains("50") -> 50
                text.contains("increase") || text.contains("up") -> 75
                text.contains("decrease") || text.contains("down") -> 25
                else -> {
                    // Try to extract percentage
                    val numRegex = Regex("(\\d+)\\s*%?")
                    val match = numRegex.find(text)
                    match?.groupValues?.get(1)?.toIntOrNull()?.coerceIn(0, 100) ?: 50
                }
            }
            return ParsedCommand.SetBrightness(level)
        }

        val screenshotRegex = Regex("\\b(take|capture|grab|get)\\b.*\\b(screenshot|screen shot|screen capture|screen grab)\\b|^screenshot$")
        if (screenshotRegex.containsMatchIn(text)) return ParsedCommand.Screenshot

        // ─── 3. READ MESSAGES/NOTIFICATIONS ──────────────────────────────────
        val readMessagesRegex = Regex("\\b(read|check|show)\\b.*\\b(messages|texts|sms)\\b|\\bmessages\\b")
        if (readMessagesRegex.containsMatchIn(text)) {
            // Check for app-specific: "read whatsapp messages"
            val appName = when {
                text.contains("whatsapp") -> "whatsapp"
                text.contains("telegram") -> "telegram"
                text.contains("sms") || text.contains("text") -> "sms"
                else -> null
            }
            return ParsedCommand.ReadMessages(appName)
        }

        val readNotificationsRegex = Regex("\\b(read|check|show|what are|list)\\b.*\\b(notifications|alerts)\\b|^notifications$")
        if (readNotificationsRegex.containsMatchIn(text)) return ParsedCommand.ReadNotifications

        // ─── 4. QUICK NOTES ──────────────────────────────────────────────────
        val noteRegex = Regex("^(note|create note|make note|add note|write note|note to self|remember this|jot down|write down)\\s+(.+)$")
        val noteMatch = noteRegex.find(text)
        if (noteMatch != null) {
            val content = noteMatch.groupValues[2].trim()
            if (content.isNotEmpty()) return ParsedCommand.CreateNote(content)
        }

        // ─── 5. CALCULATOR & CONVERTER ───────────────────────────────────────
        // Calculator: "what's 15% of 250", "calculate 25 + 37", "15 times 8"
        val calcRegex = Regex("\\b(calculate|compute|what('?s| is))\\b.*|^\\d+\\s*[+\\-*/×÷]\\s*\\d+")
        if (calcRegex.containsMatchIn(text)) {
            return ParsedCommand.Calculate(text)
        }

        // Converter: "convert 50 USD to INR", "how many km in 10 miles"
        val convertRegex = Regex("\\b(convert|change)\\s+(\\d+(?:\\.\\d+)?)\\s+(\\w+)\\s+(?:to|into)\\s+(\\w+)\\b|\\bhow\\s+many\\s+(\\w+)\\s+in\\s+(\\d+(?:\\.\\d+)?)\\s+(\\w+)\\b")
        val convertMatch = convertRegex.find(text)
        if (convertMatch != null) {
            val groups = convertMatch.groupValues
            if (groups[2].isNotEmpty()) {
                // Format: "convert 50 USD to INR"
                val amount = groups[2].toDoubleOrNull() ?: 0.0
                val from = groups[3]
                val to = groups[4]
                return ParsedCommand.Convert(amount, from, to)
            } else if (groups[6].isNotEmpty()) {
                // Format: "how many km in 10 miles"
                val amount = groups[6].toDoubleOrNull() ?: 0.0
                val from = groups[7]
                val to = groups[5]
                return ParsedCommand.Convert(amount, from, to)
            }
        }

        // ═══════════════════════════════════════════════════════════════════════

        // ═══ SMART APP ACTIONS - Parsing ═══════════════════════════════════════

        // WhatsApp message: "send whatsapp to Mom saying I'll be late" / "whatsapp Mom hello" / "message Mom on whatsapp"
        val whatsappRegex = Regex(
            "(?:send\\s+(?:a\\s+)?whatsapp\\s+(?:message\\s+)?to\\s+(.+?)\\s+(?:saying|that|with message|as)\\s+(.+))|" +
            "(?:whatsapp\\s+(.+?)\\s+(?:saying|that)?\\s*(.+))|" +
            "(?:message\\s+(.+?)\\s+on\\s+whatsapp\\s*(?:saying|that)?\\s*(.*))",
            RegexOption.IGNORE_CASE
        )
        val waMatch = whatsappRegex.find(text)
        if (waMatch != null) {
            val g = waMatch.groupValues
            val contact = (g[1].ifEmpty { g[3].ifEmpty { g[5] } }).trim()
            val msg = (g[2].ifEmpty { g[4].ifEmpty { g[6] } }).trim()
            if (contact.isNotEmpty()) {
                return ParsedCommand.SendWhatsApp(contact, msg)
            }
        }

        // Search on App: "search iPhone on Amazon" / "search shoes on Flipkart" / "find pizza on Swiggy"
        val searchAppRegex = Regex(
            "(?:search|find|look for|look up)\\s+(.+?)\\s+(?:on|in)\\s+(amazon|flipkart|swiggy|zomato|google|myntra|meesho|ajio)",
            RegexOption.IGNORE_CASE
        )
        val searchAppMatch = searchAppRegex.find(text)
        if (searchAppMatch != null) {
            val query = searchAppMatch.groupValues[1].trim()
            val appName = searchAppMatch.groupValues[2].trim()
            if (query.isNotEmpty()) {
                return ParsedCommand.SearchOnApp(appName, query)
            }
        }

        // UPI Payment: "pay 500 to rahul@upi" / "pay Rahul 500 on GPay"
        val upiRegex = Regex(
            "(?:pay|send)\\s+(?:(?:rs\\.?|₹)?\\s*(\\d+)\\s+to\\s+(.+?)(?:\\s+(?:on|via|using)\\s+\\w+)?|" +
            "(.+?)\\s+(?:rs\\.?|₹)?\\s*(\\d+)\\s*(?:on|via|using)?\\s*(?:gpay|phonpe|paytm|upi)?)",
            RegexOption.IGNORE_CASE
        )
        val upiMatch = upiRegex.find(text)
        if (upiMatch != null && (text.contains("pay") || text.contains("upi") || text.contains("gpay") || text.contains("phonpe") || text.contains("paytm"))) {
            val g = upiMatch.groupValues
            val amount = g[1].ifEmpty { g[4] }.trim()
            val upiIdOrName = g[2].ifEmpty { g[3] }.trim()
            val upiId = if (upiIdOrName.contains("@")) upiIdOrName else null
            val note = if (upiId == null) upiIdOrName else null
            return ParsedCommand.UpiPayment(upiId, amount.ifEmpty { null }, note)
        }

        // Play on Spotify: "play Arijit Singh on Spotify"
        val spotifyRegex = Regex("(?:play|listen to)\\s+(.+?)\\s+(?:on|in)\\s+spotify", RegexOption.IGNORE_CASE)
        val spotifyMatch = spotifyRegex.find(text)
        if (spotifyMatch != null) {
            val query = spotifyMatch.groupValues[1].trim()
            if (query.isNotEmpty()) return ParsedCommand.PlayOnSpotify(query)
        }

        // Book Ride: "book uber to airport" / "book ola to office" / "book ride to mall"
        val rideRegex = Regex(
            "(?:book|get|call)\\s+(?:a\\s+)?(?:(uber|ola|ride|cab|taxi)\\s+to\\s+(.+)|ride\\s+to\\s+(.+?)\\s*(?:on|via|using)\\s+(uber|ola))",
            RegexOption.IGNORE_CASE
        )
        val rideMatch = rideRegex.find(text)
        if (rideMatch != null) {
            val g = rideMatch.groupValues
            val app = g[1].ifEmpty { g[4] }.trim().let { if (it == "ride" || it == "cab" || it == "taxi") null else it }
            val destination = g[2].ifEmpty { g[3] }.trim()
            if (destination.isNotEmpty()) return ParsedCommand.BookRide(destination, app)
        }

        // Order Food: "order from Swiggy" / "order food from Zomato" / "order pizza"
        val orderRegex = Regex(
            "(?:order|get)\\s+(?:(?:food|something)?\\s*(?:from|on|via)\\s+(swiggy|zomato)|(.+?)\\s+(?:from|on|via)\\s+(swiggy|zomato)|(.+))",
            RegexOption.IGNORE_CASE
        )
        val orderMatch = orderRegex.find(text)
        if (orderMatch != null && (text.contains("order") || text.contains("swiggy") || text.contains("zomato"))) {
            val g = orderMatch.groupValues
            val app = g[1].ifEmpty { g[3] }.trim().ifEmpty { null }
            val restaurant = g[2].ifEmpty { g[4] }.trim().ifEmpty { null }
            if (text.contains("swiggy") || text.contains("zomato") || text.startsWith("order food") || text.startsWith("order from")) {
                return ParsedCommand.OrderFood(restaurant, app)
            }
        }

        // Share Text: "share this to WhatsApp" / "share to Instagram"
        val shareRegex = Regex(
            "(?:share|send)\\s+(?:(.+?)\\s+)?(?:to|on|via)\\s+(whatsapp|instagram|telegram|twitter|facebook|x)",
            RegexOption.IGNORE_CASE
        )
        val shareMatch = shareRegex.find(text)
        if (shareMatch != null) {
            val content = shareMatch.groupValues[1].trim().ifEmpty { "" }
            val app = shareMatch.groupValues[2].trim()
            return ParsedCommand.ShareText(content, app)
        }

        // Open Profile: "open @username on Instagram" / "check @elonmusk on Twitter"
        val profileRegex = Regex(
            "(?:open|check|visit|show|go to|see)\\s+@?(\\w+)\\s+(?:on|in)\\s+(instagram|twitter|x|facebook|youtube|linkedin)",
            RegexOption.IGNORE_CASE
        )
        val profileMatch = profileRegex.find(text)
        if (profileMatch != null) {
            val username = profileMatch.groupValues[1].trim()
            val platform = profileMatch.groupValues[2].trim().let { if (it.lowercase() == "x") "twitter" else it }
            if (username.isNotEmpty()) return ParsedCommand.OpenProfile(platform, username)
        }

        // ═══════════════════════════════════════════════════════════════════════

        // Open App (robust regex) - Moved to very end to avoid matching specific system commands
        // Matches: open whatsapp, launch spotify, start Netflix, pull up chrome
        val openRegex = Regex("^(open|launch|start|fire up|pull up|bring up|load|run)\\s+(.+?)(?:\\s+app|\\s+application)?$")
        val openMatch = openRegex.find(text)
        if (openMatch != null && !text.contains("camera") && !text.contains("settings") && !text.contains("wifi") && !text.contains("bluetooth")) {
            val appName = openMatch.groupValues[2].trim()
            if (appName.isNotEmpty()) {
                return ParsedCommand.OpenApp(appName)
            }
        }

        return ParsedCommand.Unknown
    }
}


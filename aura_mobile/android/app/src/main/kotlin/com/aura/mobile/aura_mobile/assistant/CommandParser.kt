package com.aura.mobile.aura_mobile.assistant

sealed class ParsedCommand {
    data class OpenApp(val appName: String) : ParsedCommand()
    data class CallContact(val contactName: String) : ParsedCommand()
    data class SendSms(val contactName: String, val message: String) : ParsedCommand()
    data class TurnTorch(val state: Boolean) : ParsedCommand()
    data class SetTimer(val minutes: Int) : ParsedCommand()
    data class SetAlarm(val hour: Int, val minute: Int) : ParsedCommand()
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
        val fillers = listOf("can you ", "could you ", "please ", "for me", "hey aura ", "aura ", "just ", "quickly ")
        for (filler in fillers) {
            text = text.replace(filler, "")
        }
        text = text.trim()

        // YouTube Search / Play
        if (text.contains("on youtube") || text.contains("in youtube") || text.startsWith("play ") || text.startsWith("youtube ")) {
            var query = text.replace("play ", "")
                .replace("on youtube", "")
                .replace("in youtube", "")
                .replace("open ", "")
                .replace("search for ", "")
                .replace("youtube ", "")
                .trim()
            if (query.isNotEmpty() && (text.contains("youtube") || text.startsWith("play "))) {
                return ParsedCommand.PlayYouTube(query)
            }
        }

        // Open App
        if ((text.startsWith("open ") || text.startsWith("launch ") || text.startsWith("start ")) && 
            !text.contains("camera") && !text.contains("settings") && !text.contains("wifi") && !text.contains("bluetooth")) {
            val appName = text.replace("open ", "").replace("launch ", "").replace("start ", "").trim()
            if (appName.isNotEmpty()) return ParsedCommand.OpenApp(appName)
        }

        // Call Contact
        if (text.startsWith("call ")) {
            val contactName = text.removePrefix("call ").trim()
            if (contactName.isNotEmpty()) return ParsedCommand.CallContact(contactName)
        }
        if (text.startsWith("dial ")) {
            val contactName = text.removePrefix("dial ").trim()
            if (contactName.isNotEmpty()) return ParsedCommand.CallContact(contactName)
        }

        // Send SMS
        // Format 1: "send message to [name] saying [message]"
        if (text.startsWith("send message to ")) {
            val remainder = text.removePrefix("send message to ").trim()
            val splitBySaying = remainder.split(" saying ")
            if (splitBySaying.size == 2) {
                return ParsedCommand.SendSms(splitBySaying[0].trim(), splitBySaying[1].trim())
            }
            if (remainder.isNotEmpty()) {
                return ParsedCommand.SendSms(remainder, "") // Ask for message later
            }
        }
        
        // Format 2: "text [name] [message]"
        if (text.startsWith("text ")) {
            val remainder = text.removePrefix("text ").trim()
            val firstSpace = remainder.indexOf(' ')
            if (firstSpace != -1) {
                val name = remainder.substring(0, firstSpace).trim()
                val msg = remainder.substring(firstSpace + 1).trim()
                return ParsedCommand.SendSms(name, msg)
            }
        }

        // Torch Control
        if (text.contains("turn on torch") || text.contains("flashlight on") || text.contains("torch on")) {
            return ParsedCommand.TurnTorch(true)
        }
        if (text.contains("turn off torch") || text.contains("flashlight off") || text.contains("torch off")) {
            return ParsedCommand.TurnTorch(false)
        }

        // Time & Date
        if (text.contains("what time is it") || text == "time") {
            return ParsedCommand.GetTime
        }
        if (text.contains("what is today") || text.contains("today's date") || text == "date") {
            return ParsedCommand.GetDate
        }

        // Battery
        if (text.contains("battery") || text.contains("how much juice")) {
            return ParsedCommand.GetBattery
        }

        // Volume
        if (text.contains("max volume") || text.contains("volume to max") || text.contains("turn it up")) {
            return ParsedCommand.MaxVolume
        }
        if (text.contains("mute") || text.contains("silence my phone")) {
            return ParsedCommand.MuteVolume
        }

        // Timers & Alarms (Basic regex parsing)
        if (text.contains("timer for")) {
            val words = text.split(" ")
            for (i in words.indices) {
                if (words[i] == "timer" || words[i] == "for") {
                    val num = words.getOrNull(i + 1)?.toIntOrNull()
                        ?: words.getOrNull(i + 2)?.toIntOrNull()
                    if (num != null) {
                        return ParsedCommand.SetTimer(num)
                    }
                }
            }
        }

        // Web Search
        if (text.startsWith("search ") || text.startsWith("google ") || text.startsWith("look up ")) {
            val query = text.replace("search for ", "").replace("search ", "")
                            .replace("google ", "").replace("look up ", "").trim()
            if (query.isNotEmpty()) return ParsedCommand.WebSearch(query)
        }

        // Open Camera
        if (text.contains("open camera") || text.contains("take photo") || text.contains("take a picture")) {
            return ParsedCommand.OpenCamera
        }

        // Open Settings
        if (text.contains("wifi settings")) {
            return ParsedCommand.OpenWifiSettings
        }
        if (text.contains("bluetooth settings")) {
            return ParsedCommand.OpenBluetoothSettings
        }
        if (text.contains("open settings")) {
            return ParsedCommand.OpenSettings
        }

        return ParsedCommand.Unknown
    }
}

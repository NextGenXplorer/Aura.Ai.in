import java.util.regex.RegexOption

fun parse(rawText: String) {
    var text = rawText.lowercase().trim()
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

    val whatsappRegex = Regex("\\b(whatsapp|whats\\s*app)\\b", RegexOption.IGNORE_CASE)
    if (whatsappRegex.containsMatchIn(text)) {
        var remaining = text
            .replace(whatsappRegex, "")
            .replace(Regex("^\\s*(send|text|message|msg|write)?\\s*(to\\s+)?", RegexOption.IGNORE_CASE), "")
            .trim()
        if (remaining.isNotEmpty()) {
            val tokens = remaining.split(Regex("\\s+"), limit = 2)
            val contactName = tokens[0].trim()
            val message = if (tokens.size > 1) tokens[1].trim() else ""
            if (contactName.isNotEmpty() && contactName != "me" && contactName != "to") {
                println("ParsedCommand.SendWhatsApp('$contactName', '$message')")
                return
            }
        }
    }

    val callRegex = Regex("^(call|phone|ring\\s*up|buzz)\\s+(.+)$", RegexOption.IGNORE_CASE)
    val callMatch = callRegex.find(text)
    if (callMatch != null) {
        val contactName = callMatch.groupValues[2].trim()
        println("ParsedCommand.CallContact('$contactName')")
        return
    }

    // fallback test
    if (text.startsWith("call ")) {
        println("ParsedCommand.CallContact('${text.removePrefix("call ").trim()}')")
        return
    }

    println("Unknown")
}

fun main() {
    val inputs = listOf(
        "whatsapp to mithun",
        "whatsapp mithun",
        "whatsapp to mithun hi",
        "can you whatsapp to mithun"
    )
    for (input in inputs) {
        print("\"$input\" -> ")
        parse(input)
    }
}

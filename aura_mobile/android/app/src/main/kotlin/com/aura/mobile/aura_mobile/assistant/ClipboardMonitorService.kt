package com.aura.mobile.aura_mobile.assistant

import android.content.ClipboardManager
import android.content.Context
import android.util.Log

/**
 * Monitors clipboard changes and classifies content via regex.
 *
 * Controlled from MainActivity through a MethodChannel — Flutter can enable/disable
 * monitoring at runtime. When a clipboard change is detected, the registered callback
 * is invoked with the clipboard text and its classified content type.
 *
 * Usage (from MainActivity):
 * ```
 * ClipboardMonitorService.start(context) { content, contentType ->
 *     clipboardChannel?.invokeMethod("onClipboardContent", mapOf(
 *         "content" to content,
 *         "contentType" to contentType
 *     ))
 * }
 * ```
 */
class ClipboardMonitorService {

    companion object {
        private const val TAG = "AuraClipboard"

        /** Whether the monitor is currently active. */
        @Volatile
        var isActive: Boolean = false
            private set

        /** Last detected content type (url, phone, email, code, address, text). */
        @Volatile
        var lastContentType: String = "text"
            private set

        /** Last detected clipboard text. */
        @Volatile
        var lastClipText: String = ""
            private set

        // ── Internal state ──────────────────────────────────────────────
        private var clipboardManager: ClipboardManager? = null
        private var callback: ((content: String, contentType: String) -> Unit)? = null
        private var lastClipTimestamp: Long = 0L
        private const val DEBOUNCE_MS = 500L

        private val clipChangedListener = ClipboardManager.OnPrimaryClipChangedListener {
            handleClipChanged()
        }

        // ── Public API ──────────────────────────────────────────────────

        /**
         * Start monitoring clipboard changes.
         *
         * @param context  Application or activity context.
         * @param onClip   Called on the main thread whenever new clipboard content
         *                 is detected, with `(content, contentType)`.
         */
        fun start(context: Context, onClip: (content: String, contentType: String) -> Unit) {
            if (isActive) return
            callback = onClip
            clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            clipboardManager?.addPrimaryClipChangedListener(clipChangedListener)
            isActive = true
            Log.d(TAG, "Clipboard monitoring started")
        }

        /**
         * Stop monitoring clipboard changes and release resources.
         */
        fun stop(context: Context) {
            if (!isActive) return
            clipboardManager?.removePrimaryClipChangedListener(clipChangedListener)
            clipboardManager = null
            callback = null
            isActive = false
            Log.d(TAG, "Clipboard monitoring stopped")
        }

        // ── Internal ────────────────────────────────────────────────────

        private fun handleClipChanged() {
            val now = System.currentTimeMillis()
            if (now - lastClipTimestamp < DEBOUNCE_MS) return
            lastClipTimestamp = now

            val clip = clipboardManager?.primaryClip ?: return
            if (clip.itemCount == 0) return

            val item = clip.getItemAt(0)
            // coerceToText requires a Context — use the application context stored in the manager
            val text = item.text?.toString()
            if (text.isNullOrBlank()) return

            // Skip if identical to previous clip
            if (text == lastClipText) return

            val contentType = classifyContent(text)
            lastContentType = contentType
            lastClipText = text

            Log.d(TAG, "Clipboard changed: type=$contentType, text=${text.take(80)}")

            callback?.invoke(text, contentType)
        }

        /**
         * Classify clipboard content using regex patterns.
         * Returns one of: url, phone, email, code, address, text
         */
        private fun classifyContent(text: String): String {
            val trimmed = text.trim()

            // URL — starts with http/https or common patterns like www.
            if (trimmed.matches(Regex("^(https?://|www\\.)\\S+$", RegexOption.IGNORE_CASE))) {
                return "url"
            }

            // Email — standard email pattern
            if (trimmed.matches(Regex("^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$"))) {
                return "email"
            }

            // Phone number — digits with optional +, spaces, dashes, parens; 7-15 actual digits
            if (trimmed.matches(Regex("^[+]?[\\d\\s\\-().]{7,20}$")) &&
                trimmed.replace(Regex("[^\\d]"), "").length in 7..15) {
                return "phone"
            }

            // Code snippet — multi-line text containing typical programming tokens
            val codeIndicators = listOf(
                "fun ", "val ", "var ", "class ", "import ", "package ",           // Kotlin
                "function ", "const ", "let ", "=>", "return ",                     // JS/TS
                "def ", "self.", "print(", "if __name__",                          // Python
                "public ", "private ", "void ", "static ", "int ",                 // Java/C
                "<?php", "<%", "#!/",                                              // PHP/scripts
                "{", "}", "();", "->", "::", "//", "/*",                           // General
            )
            if (trimmed.lines().size > 1 && codeIndicators.any { trimmed.contains(it) }) {
                return "code"
            }

            // Address — contains common address keywords alongside numbers
            if (trimmed.matches(Regex(
                ".*\\d+.*\\b(street|st|avenue|ave|road|rd|boulevard|blvd|lane|ln|" +
                "drive|dr|court|ct|floor|apt|suite|ste|block|sector|pin|zip)\\b.*",
                RegexOption.IGNORE_CASE
            ))) {
                return "address"
            }
            // Fallback address heuristic: contains a 5-6 digit number (ZIP/PIN) and a comma
            if (trimmed.contains(",") && trimmed.matches(Regex(".*\\b\\d{5,6}\\b.*"))) {
                return "address"
            }

            return "text"
        }
    }
}

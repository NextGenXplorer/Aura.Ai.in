package com.aura.mobile.aura_mobile.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class ScreenContextAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "AuraScreenContext"
        private const val DEBOUNCE_DELAY_MS = 500L
        private const val MAX_TREE_DEPTH = 30
        private const val MAX_CONTENT_LENGTH = 15_000

        @Volatile
        var currentScreenContent: String = ""
            private set

        @Volatile
        var currentPackageName: String = ""
            private set

        @Volatile
        var currentActivityName: String = ""
            private set

        /**
         * Returns the current screen context as a formatted string.
         */
        @JvmStatic
        fun getScreenContext(): String {
            if (currentScreenContent.isBlank()) {
                return ""
            }
            val sb = StringBuilder()
            if (currentPackageName.isNotBlank()) {
                sb.append("App: $currentPackageName\n")
            }
            if (currentActivityName.isNotBlank()) {
                sb.append("Screen: $currentActivityName\n")
            }
            sb.append("Content:\n$currentScreenContent")
            return sb.toString()
        }

        /**
         * Checks whether this accessibility service is enabled in system settings.
         */
        @JvmStatic
        fun isServiceEnabled(context: Context): Boolean {
            val serviceName = "${context.packageName}/${ScreenContextAccessibilityService::class.java.canonicalName}"
            try {
                val enabledServices = Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                ) ?: return false
                val colonSplitter = TextUtils.SimpleStringSplitter(':')
                colonSplitter.setString(enabledServices)
                while (colonSplitter.hasNext()) {
                    val componentName = colonSplitter.next()
                    if (componentName.equals(serviceName, ignoreCase = true)) {
                        return true
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error checking accessibility service status: ${e.message}")
            }
            return false
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var pendingRunnable: Runnable? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Screen Context Accessibility Service connected")

        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
            notificationTimeout = DEBOUNCE_DELAY_MS
        }
        serviceInfo = info
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                // Update package and activity info immediately
                event.packageName?.let { currentPackageName = it.toString() }
                event.className?.let { currentActivityName = it.toString() }
                scheduleContentExtraction()
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                scheduleContentExtraction()
            }
        }
    }

    /**
     * Debounces content extraction to avoid excessive processing
     * during rapid UI updates (scrolling, animations, etc.).
     */
    private fun scheduleContentExtraction() {
        pendingRunnable?.let { handler.removeCallbacks(it) }
        val runnable = Runnable { extractScreenContent() }
        pendingRunnable = runnable
        handler.postDelayed(runnable, DEBOUNCE_DELAY_MS)
    }

    /**
     * Traverses the accessibility node tree and extracts all visible text.
     */
    private fun extractScreenContent() {
        val rootNode = rootInActiveWindow ?: return
        try {
            val textParts = mutableListOf<String>()
            traverseNode(rootNode, textParts, 0)
            val content = textParts
                .filter { it.isNotBlank() }
                .distinct()
                .joinToString("\n")
            currentScreenContent = if (content.length > MAX_CONTENT_LENGTH) {
                content.substring(0, MAX_CONTENT_LENGTH)
            } else {
                content
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting screen content: ${e.message}")
        } finally {
            try {
                rootNode.recycle()
            } catch (_: Exception) {
                // Node may already be recycled
            }
        }
    }

    /**
     * Recursively traverses the node tree to collect text and content descriptions.
     */
    private fun traverseNode(
        node: AccessibilityNodeInfo?,
        textParts: MutableList<String>,
        depth: Int
    ) {
        if (node == null || depth > MAX_TREE_DEPTH) return

        try {
            // Extract text content
            node.text?.toString()?.trim()?.let { text ->
                if (text.isNotBlank()) {
                    textParts.add(text)
                }
            }

            // Extract content description (accessibility labels)
            node.contentDescription?.toString()?.trim()?.let { desc ->
                if (desc.isNotBlank() && !textParts.contains(desc)) {
                    textParts.add(desc)
                }
            }

            // Recurse into child nodes
            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                if (child != null) {
                    try {
                        traverseNode(child, textParts, depth + 1)
                    } finally {
                        try {
                            child.recycle()
                        } catch (_: Exception) {
                            // Child may already be recycled
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error traversing node at depth $depth: ${e.message}")
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Screen Context Accessibility Service interrupted")
        pendingRunnable?.let { handler.removeCallbacks(it) }
    }

    override fun onDestroy() {
        super.onDestroy()
        pendingRunnable?.let { handler.removeCallbacks(it) }
        currentScreenContent = ""
        currentPackageName = ""
        currentActivityName = ""
        Log.d(TAG, "Screen Context Accessibility Service destroyed")
    }
}

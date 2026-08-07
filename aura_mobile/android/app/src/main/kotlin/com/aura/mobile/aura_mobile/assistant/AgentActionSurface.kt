package com.aura.mobile.aura_mobile.assistant

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

/**
 * The action + targeted-query surface for Interactive Agent Mode.
 *
 * Feature: interactive-agent-mode (Task 4).
 *
 * This is deliberately a SEPARATE object from [ScreenContextAccessibilityService]
 * so the existing read-only capture path is untouched. Every operation here is
 * gated by [actionsEnabled], which is false unless a session is active, so with
 * the flag off this object performs no work and mutates nothing (Req 1.4, 13.8).
 *
 * Design guarantees implemented here:
 *  - No AccessibilityNodeInfo handle ever leaves this object. findNodes returns
 *    plain maps with a per-round integer token; callers act by token (Req 7.7, D4).
 *  - Node work runs on a dedicated HandlerThread, never the main looper, so it
 *    cannot ANR the UI (Req 13.2, D4).
 *  - The signature walk is bounded to [SIGNATURE_WALK_DEPTH] / [SIGNATURE_WALK_NODES]
 *    (Req 13.6, 13.9, D2).
 *  - Every action refuses when actions are disabled or the window is secure
 *    (Req 6.7).
 */
object AgentActionSurface {

    private const val TAG = "AuraAgentSurface"

    // Bounds for the cheap structural signature walk (Req 13.6, 13.9 / D2).
    private const val SIGNATURE_WALK_DEPTH = 6
    private const val SIGNATURE_WALK_NODES = 40

    /** Master gate. False unless a session is active (Req 1.4, 13.8). */
    @Volatile
    var actionsEnabled: Boolean = false
        private set

    /** The live service, set on connect and cleared on destroy. */
    @Volatile
    private var service: AccessibilityService? = null

    private var thread: HandlerThread? = null
    private var agentHandler: Handler? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Nodes matched in the most recent findNodes round, keyed by the token
     * handed to Dart. Valid only until the next findNodes call, a screen change,
     * or disable — after which they are recycled. Access only on the agent thread.
     */
    private val roundNodes = HashMap<Int, AccessibilityNodeInfo>()
    private var tokenSeq = 0

    /** Called by the service in onServiceConnected. */
    fun attach(svc: AccessibilityService) {
        service = svc
    }

    /** Called by the service in onDestroy / onInterrupt. */
    fun detach() {
        setEnabled(false)
        service = null
    }

    /**
     * Enable or disable the action surface. Starting a session spins up the
     * agent thread; ending one tears it down and clears any node handles so a
     * long session accumulates nothing (Req 7.7).
     */
    fun setEnabled(enabled: Boolean): Boolean {
        if (enabled == actionsEnabled) return true
        if (enabled) {
            if (service == null) return false
            val t = HandlerThread("aura-agent").apply { start() }
            thread = t
            agentHandler = Handler(t.looper)
            actionsEnabled = true
        } else {
            actionsEnabled = false
            agentHandler?.post { clearRound() }
            thread?.quitSafely()
            thread = null
            agentHandler = null
        }
        return true
    }

    // ── Public async API. Each posts to the agent thread and returns on main. ──

    fun screenSignature(callback: (Map<String, Any?>) -> Unit) {
        runOnAgent(callback, emptyMap()) {
            val root = service?.rootInActiveWindow ?: return@runOnAgent emptyMap()
            try {
                val ids = ArrayList<String>(SIGNATURE_WALK_NODES)
                val counter = intArrayOf(0)
                walkForSignature(root, 0, ids, counter)
                val secure = isSecureWindow(root)
                mapOf(
                    "packageName" to (root.packageName?.toString() ?: ""),
                    "activityName" to ScreenContextAccessibilityService.currentActivityName,
                    "structureHash" to ids.joinToString("|").hashCode(),
                    "nodeCount" to counter[0],
                    "isSecureWindow" to secure,
                )
            } finally {
                recycleQuietly(root)
            }
        }
    }

    fun findNodes(
        query: Map<String, Any?>,
        limit: Int,
        callback: (List<Map<String, Any?>>) -> Unit,
    ) {
        runOnAgent(callback, emptyList()) {
            if (!actionsEnabled) return@runOnAgent emptyList()
            val root = service?.rootInActiveWindow ?: return@runOnAgent emptyList()
            try {
                if (isSecureWindow(root)) return@runOnAgent emptyList()
                clearRound()
                val matches = queryNodes(root, query, limit)
                matches.map { (token, node) ->
                    val b = Rect().also { node.getBoundsInScreen(it) }
                    mapOf(
                        "handleToken" to token,
                        "viewId" to node.viewIdResourceName,
                        "text" to (node.text?.toString()),
                        "editable" to node.isEditable,
                        "clickable" to node.isClickable,
                        "left" to b.left,
                        "top" to b.top,
                        "right" to b.right,
                        "bottom" to b.bottom,
                    )
                }
            } finally {
                recycleQuietly(root)
            }
        }
    }

    fun tapNode(token: Int, callback: (String) -> Unit) {
        actOnToken(token, callback) { node ->
            val target = nearestClickable(node) ?: return@actOnToken RESULT_NO_TARGET
            if (target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) RESULT_OK
            else RESULT_ACTION_FAILED
        }
    }

    fun setNodeText(token: Int, value: String, callback: (String) -> Unit) {
        actOnToken(token, callback) { node ->
            if (!node.isEditable) return@actOnToken RESULT_NO_TARGET
            val args = Bundle().apply {
                putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                    value,
                )
            }
            if (node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) RESULT_OK
            else RESULT_ACTION_FAILED
        }
    }

    fun scrollNode(token: Int, forward: Boolean, callback: (String) -> Unit) {
        actOnToken(token, callback) { node ->
            val action = if (forward) {
                AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            } else {
                AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            }
            val target = nearestScrollable(node) ?: return@actOnToken RESULT_NO_TARGET
            if (target.performAction(action)) RESULT_OK else RESULT_ACTION_FAILED
        }
    }

    fun performGlobal(action: String, callback: (String) -> Unit) {
        runOnAgent(callback, RESULT_DISABLED) {
            if (!actionsEnabled) return@runOnAgent RESULT_DISABLED
            val svc = service ?: return@runOnAgent RESULT_NO_SERVICE
            val globalAction = when (action) {
                "back" -> AccessibilityService.GLOBAL_ACTION_BACK
                "home" -> AccessibilityService.GLOBAL_ACTION_HOME
                else -> return@runOnAgent RESULT_ACTION_FAILED
            }
            if (svc.performGlobalAction(globalAction)) RESULT_OK else RESULT_ACTION_FAILED
        }
    }

    // ── Result codes returned to Dart as plain strings. ──
    const val RESULT_OK = "ok"
    const val RESULT_DISABLED = "actions_disabled"
    const val RESULT_SECURE = "secure_window"
    const val RESULT_NO_SERVICE = "no_service"
    const val RESULT_NO_TARGET = "no_target"
    const val RESULT_ACTION_FAILED = "action_failed"
    const val RESULT_STALE_TOKEN = "stale_token"

    // ── Internals ──

    private fun <T> runOnAgent(
        callback: (T) -> Unit,
        fallback: T,
        work: () -> T,
    ) {
        val handler = agentHandler
        if (!actionsEnabled || handler == null) {
            mainHandler.post { callback(fallback) }
            return
        }
        handler.post {
            val out = try {
                work()
            } catch (e: Exception) {
                Log.e(TAG, "agent op failed: ${e.message}")
                fallback
            }
            mainHandler.post { callback(out) }
        }
    }

    private fun actOnToken(
        token: Int,
        callback: (String) -> Unit,
        action: (AccessibilityNodeInfo) -> String,
    ) {
        runOnAgent(callback, RESULT_DISABLED) {
            if (!actionsEnabled) return@runOnAgent RESULT_DISABLED
            val root = service?.rootInActiveWindow
            if (root != null) {
                try {
                    if (isSecureWindow(root)) return@runOnAgent RESULT_SECURE
                } finally {
                    recycleQuietly(root)
                }
            }
            val node = roundNodes[token] ?: return@runOnAgent RESULT_STALE_TOKEN
            action(node)
        }
    }

    /** Bounded shallow walk producing stable identifiers for the signature. */
    private fun walkForSignature(
        node: AccessibilityNodeInfo?,
        depth: Int,
        ids: MutableList<String>,
        counter: IntArray,
    ) {
        if (node == null) return
        if (depth > SIGNATURE_WALK_DEPTH) return
        if (counter[0] >= SIGNATURE_WALK_NODES) return
        counter[0]++
        val id = node.viewIdResourceName
            ?: node.text?.toString()?.take(12)
            ?: node.className?.toString()
            ?: ""
        ids.add("$depth:$id")
        val childCount = node.childCount
        var i = 0
        while (i < childCount && counter[0] < SIGNATURE_WALK_NODES) {
            val child = node.getChild(i)
            if (child != null) {
                try {
                    walkForSignature(child, depth + 1, ids, counter)
                } finally {
                    recycleQuietly(child)
                }
            }
            i++
        }
    }

    /**
     * Targeted lookup by view id, then text, then content description. Never a
     * full-tree traversal (Req 6.3): uses the framework's indexed finders.
     * Matched nodes are retained in [roundNodes] under fresh tokens.
     */
    private fun queryNodes(
        root: AccessibilityNodeInfo,
        query: Map<String, Any?>,
        limit: Int,
    ): List<Pair<Int, AccessibilityNodeInfo>> {
        val viewId = query["viewId"] as? String
        val text = query["text"] as? String
        val desc = query["contentDescription"] as? String
        val requireEditable = query["requireEditable"] == true
        val requireClickable = query["requireClickable"] == true

        val found: List<AccessibilityNodeInfo> = when {
            viewId != null -> root.findAccessibilityNodeInfosByViewId(viewId)
            text != null -> root.findAccessibilityNodeInfosByText(text)
            desc != null -> root.findAccessibilityNodeInfosByText(desc)
            else -> emptyList()
        } ?: emptyList()

        val out = ArrayList<Pair<Int, AccessibilityNodeInfo>>()
        for (node in found) {
            if (out.size >= limit) {
                recycleQuietly(node)
                continue
            }
            val ok = (!requireEditable || node.isEditable) &&
                    (!requireClickable || (node.isClickable || nearestClickable(node) != null))
            if (ok) {
                val token = tokenSeq++
                roundNodes[token] = node
                out.add(token to node)
            } else {
                recycleQuietly(node)
            }
        }
        return out
    }

    private fun nearestClickable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        var current = node
        var hops = 0
        while (current != null && hops < 6) {
            if (current.isClickable) return current
            current = current.parent
            hops++
        }
        return null
    }

    private fun nearestScrollable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        var current = node
        var hops = 0
        while (current != null && hops < 6) {
            if (current.isScrollable) return current
            current = current.parent
            hops++
        }
        return null
    }

    /**
     * A window is treated as secure — and therefore never driven — when it
     * hosts a password field. FLAG_SECURE windows are not exposed to the
     * accessibility tree at all (the framework withholds their contents), so a
     * password-field probe is the reliable, readable signal available to us.
     */
    private fun isSecureWindow(root: AccessibilityNodeInfo): Boolean {
        return try {
            hasPasswordField(root)
        } catch (e: Exception) {
            false
        }
    }

    private fun hasPasswordField(node: AccessibilityNodeInfo?, depth: Int = 0): Boolean {
        if (node == null || depth > SIGNATURE_WALK_DEPTH) return false
        if (node.isPassword) return true
        val childCount = node.childCount
        var i = 0
        while (i < childCount) {
            val child = node.getChild(i)
            if (child != null) {
                try {
                    if (hasPasswordField(child, depth + 1)) return true
                } finally {
                    recycleQuietly(child)
                }
            }
            i++
        }
        return false
    }

    private fun clearRound() {
        for (node in roundNodes.values) {
            recycleQuietly(node)
        }
        roundNodes.clear()
    }

    private fun recycleQuietly(node: AccessibilityNodeInfo?) {
        try {
            node?.recycle()
        } catch (_: Exception) {
            // Already recycled.
        }
    }
}

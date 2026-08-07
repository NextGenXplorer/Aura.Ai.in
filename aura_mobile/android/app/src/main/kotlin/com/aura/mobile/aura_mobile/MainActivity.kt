package com.aura.mobile.aura_mobile

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.BroadcastReceiver
import android.telephony.SmsManager
import android.app.role.RoleManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import com.aura.mobile.aura_mobile.assistant.AssistantForegroundService
import com.aura.mobile.aura_mobile.assistant.AlarmScheduler
import com.aura.mobile.aura_mobile.assistant.ReminderModel
import com.aura.mobile.aura_mobile.assistant.ReminderRepository
import com.aura.mobile.aura_mobile.assistant.ClipboardMonitorService
import com.aura.mobile.aura_mobile.assistant.ScreenContextAccessibilityService
import com.aura.mobile.aura_mobile.assistant.AgentActionSurface
import com.aura.mobile.aura_mobile.assistant.AuraNotificationListenerService
import com.aura.mobile.aura_mobile.brain.AuraBrainRuntimeBridge

class MainActivity: FlutterActivity() {
    companion object {
        const val ACTION_OPEN_BRAIN_SETUP =
            "com.aura.mobile.aura_mobile.action.OPEN_BRAIN_SETUP"
        const val EXTRA_BRAIN_DESTINATION = "destination"
        const val BRAIN_DESTINATION_MODEL_SETUP = "modelSetup"

        /**
         * Extra set by the Quick Settings tile to ask the app to turn the voice
         * assistant on. Starting a microphone foreground service directly from a
         * tile is blocked on Android 12+, so the tile brings the activity to the
         * foreground and we start the service once resumed (a valid state).
         */
        const val EXTRA_START_ASSISTANT = "start_assistant"

        var pendingProcessTextQuery: String? = null
        var pendingShareContent: String? = null

        /**
         * Destination requested by a home screen widget tap.
         *
         * Stored rather than delivered directly because a widget can cold-start
         * the app, in which case the Dart side is not listening yet. Flutter
         * polls this on startup and on resume.
         */
        var pendingWidgetRoute: String? = null

        /** Routes a widget is allowed to request. */
        private val ALLOWED_WIDGET_ROUTES = setOf(
            "chat",
            "voice",
            "camera_scan",
            "image_studio",
            "daily_briefing",
            "study_dashboard",
            "flashcard_review",
            "quiz"
        )

        fun isAllowedWidgetRoute(route: String?): Boolean =
            route != null && ALLOWED_WIDGET_ROUTES.contains(route)
    }

    private val CHANNEL = "com.aura.ai/memory"
    private val APP_CONTROL_CHANNEL = "com.aura.ai/app_control"
    private val ASSISTANT_STATE_CHANNEL = "com.aura.ai/assistant_state"
    private val ASSISTANT_AI_CHANNEL = "com.aura.ai/assistant_ai"
    private val CLIPBOARD_CHANNEL = "com.aura.ai/clipboard"
    private val SCREEN_CONTEXT_CHANNEL = "com.aura.ai/screen_context"
    private val NOTIFICATIONS_CHANNEL = "com.aura.ai/notifications"
    private val SHARE_CHANNEL = "com.aura.mobile/share"
    private val WIDGET_CHANNEL = "com.aura.mobile/widget"
    // Interactive Agent Mode (additive): action + query surface channel.
    private val AGENT_CONTROL_CHANNEL = "com.aura.ai/agent_control"

    private var assistantStateSink: EventChannel.EventSink? = null
    private var assistantAiChannel: MethodChannel? = null
    private var clipboardChannel: MethodChannel? = null
    private var screenContextChannel: MethodChannel? = null
    private var notificationsChannel: MethodChannel? = null
    private var agentControlChannel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null
    private var widgetChannel: MethodChannel? = null

    /** Set when a QS-tile launch asks us to start the assistant once resumed. */
    private var pendingStartAssistant = false

    /** Tracks whether we are in the resumed (foreground) state. */
    private var isActivityResumed = false

    private val assistantStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val state = intent?.getStringExtra("state")
            if (state != null) {
                assistantStateSink?.success(state)
            }
        }
    }

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent != null) {
                val data = mapOf(
                    "packageName" to intent.getStringExtra("packageName"),
                    "appName" to intent.getStringExtra("appName"),
                    "title" to intent.getStringExtra("title"),
                    "text" to intent.getStringExtra("text")
                )
                runOnUiThread {
                    notificationsChannel?.invokeMethod("onNotificationReceived", data)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        handleProcessTextIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleProcessTextIntent(intent)
        // If the activity is already in the foreground (e.g. tile tapped while
        // the app is open), onResume will not fire, so start here instead.
        if (pendingStartAssistant && isActivityResumed) {
            pendingStartAssistant = false
            startAssistantForeground()
        }
    }

    private fun handleProcessTextIntent(intent: Intent?) {
        if (intent == null) return

        // Quick Settings tile asked us to turn the assistant on. Defer the
        // actual service start to onResume, when the activity is in a foreground
        // state that permits starting a microphone foreground service.
        if (intent.getBooleanExtra(EXTRA_START_ASSISTANT, false)) {
            intent.removeExtra(EXTRA_START_ASSISTANT)
            pendingStartAssistant = true
        }

        // A widget tap arrives on the normal launch intent, so check the extra
        // before branching on the action. Unknown values are dropped so an
        // external app cannot drive arbitrary navigation.
        val widgetRoute = intent.getStringExtra(
            com.aura.mobile.aura_mobile.widget.WidgetPrefs.EXTRA_ROUTE
        )
        if (widgetRoute != null) {
            intent.removeExtra(com.aura.mobile.aura_mobile.widget.WidgetPrefs.EXTRA_ROUTE)
            if (isAllowedWidgetRoute(widgetRoute)) {
                pendingWidgetRoute = widgetRoute
                deliverPendingWidgetRoute()
            } else {
                Log.w("AuraMainActivity", "Rejected unknown widget route: $widgetRoute")
            }
        }

        if (ACTION_OPEN_BRAIN_SETUP == intent.action) {
            val destination = intent.getStringExtra(EXTRA_BRAIN_DESTINATION)
            val hasUntrustedData = intent.data != null || intent.clipData != null
            if (destination == BRAIN_DESTINATION_MODEL_SETUP && !hasUntrustedData) {
                AuraBrainRuntimeBridge.requestOpenSetup()
            } else {
                Log.w("AuraMainActivity", "Rejected invalid Brain setup intent")
            }
        } else if (Intent.ACTION_PROCESS_TEXT == intent.action) {
            val selectedText = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            if (selectedText != null && selectedText.isNotEmpty()) {
                Log.d("AuraMainActivity", "PROCESS_TEXT received: $selectedText")
                pendingProcessTextQuery = selectedText
                deliverPendingProcessTextQuery()
            }
        } else if (Intent.ACTION_SEND == intent.action && intent.type?.startsWith("text/") == true) {
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            if (sharedText != null && sharedText.isNotEmpty()) {
                Log.d("AuraMainActivity", "ACTION_SEND received: ${sharedText.take(100)}")
                pendingShareContent = sharedText
                deliverSharedContent(sharedText, subject)
            }
        }
    }

    private fun deliverPendingProcessTextQuery() {
        val query = pendingProcessTextQuery
        val channel = clipboardChannel
        if (query != null && channel != null) {
            runOnUiThread {
                Log.d("AuraMainActivity", "Delivering PROCESS_TEXT query: $query")
                channel.invokeMethod("onProcessTextIntent", query, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        Log.d("AuraMainActivity", "Successfully delivered PROCESS_TEXT query")
                        pendingProcessTextQuery = null
                    }
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        Log.e("AuraMainActivity", "Error delivering PROCESS_TEXT: $errorMessage")
                    }
                    override fun notImplemented() {
                        Log.d("AuraMainActivity", "onProcessTextIntent not implemented on Dart side yet (will poll)")
                    }
                })
            }
        }
    }

    /**
     * Pushes a pending widget route to Dart. Keeps the value on failure so the
     * poll in `getPendingRoute` can still pick it up.
     */
    private fun deliverPendingWidgetRoute() {
        val route = pendingWidgetRoute ?: return
        val channel = widgetChannel ?: return
        runOnUiThread {
            channel.invokeMethod("onWidgetRoute", route, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    pendingWidgetRoute = null
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e("AuraMainActivity", "Widget route delivery failed: $errorMessage")
                }

                override fun notImplemented() {
                    // Dart will poll instead.
                }
            })
        }
    }

    private fun deliverSharedContent(text: String, title: String?) {
        val channel = shareChannel
        if (channel != null) {
            runOnUiThread {
                channel.invokeMethod("onSharedContent", mapOf(
                    "text" to text,
                    "title" to (title ?: "")
                ))
                pendingShareContent = null
            }
        }
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true
        // Re-deliver any pending AI query that arrived while activity was paused
        val pending = AssistantForegroundService.pendingAiQuery
        if (pending != null && assistantAiChannel != null) {
            AssistantForegroundService.pendingAiQuery = null
            Log.d("AuraMainActivity", "onResume: Delivering pending query: $pending")
            assistantAiChannel?.invokeMethod("processAIQuery", pending)
        }
        deliverPendingProcessTextQuery()
        deliverPendingWidgetRoute()
        // Re-deliver pending share content
        val pendingShare = pendingShareContent
        if (pendingShare != null) {
            deliverSharedContent(pendingShare, null)
        }
        // A Quick Settings tile requested that we turn the assistant on. We are
        // now resumed (foreground), so a microphone FGS start is permitted.
        if (pendingStartAssistant) {
            pendingStartAssistant = false
            startAssistantForeground()
        }
    }

    override fun onPause() {
        isActivityResumed = false
        super.onPause()
    }

    /**
     * Starts the assistant foreground service from a foreground (resumed)
     * context. If the overlay permission is missing we open its settings page
     * instead, because the assistant's UI cannot draw without it.
     */
    private fun startAssistantForeground() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M &&
            !android.provider.Settings.canDrawOverlays(this)
        ) {
            val settingsIntent = Intent(
                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                android.net.Uri.parse("package:$packageName")
            )
            startActivity(settingsIntent)
            return
        }
        val serviceIntent = Intent(this, com.aura.mobile.aura_mobile.assistant.AssistantForegroundService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AuraBrainRuntimeBridge.attachUiEngine(flutterEngine)

        // Event Channel for Assistant State
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ASSISTANT_STATE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    assistantStateSink = events
                    val filter = IntentFilter("com.aura.mobile.assistant.STATE_CHANGE")
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(assistantStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(assistantStateReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    assistantStateSink = null
                    try {
                        unregisterReceiver(assistantStateReceiver)
                    } catch (e: Exception) {
                        // Receiver might not be registered
                    }
                }
            }
        )

        // Assistant AI Channel — bridges native voice assistant to Flutter AI pipeline
        assistantAiChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ASSISTANT_AI_CHANNEL)
        assistantAiChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendAIResponse" -> {
                    // Legacy full response — treat as single chunk + complete
                    val response = call.arguments as? String ?: ""
                    AssistantForegroundService.onAiChunk?.invoke(response)
                    AssistantForegroundService.onAiComplete?.invoke()
                    result.success(null)
                }
                "sendAIChunk" -> {
                    val chunk = call.arguments as? String ?: ""
                    AssistantForegroundService.onAiChunk?.invoke(chunk)
                    result.success(null)
                }
                "sendAIComplete" -> {
                    AssistantForegroundService.onAiComplete?.invoke()
                    result.success(null)
                }
                "getPendingQuery" -> {
                    // Flutter polls for pending queries — reliable fallback
                    val query = AssistantForegroundService.pendingAiQuery
                    if (query != null) {
                        AssistantForegroundService.pendingAiQuery = null
                        Log.d("AuraMainActivity", "getPendingQuery: returning '$query'")
                        result.success(query)
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Register as the AI request handler — direct call, no broadcasts
        AssistantForegroundService.aiRequestHandler = { query ->
            Log.d("AuraMainActivity", "aiRequestHandler called with: $query")
            // ALWAYS store as pending so Flutter's polling can pick it up
            AssistantForegroundService.pendingAiQuery = query
            // Also try direct method channel (works sometimes)
            val channel = assistantAiChannel
            if (channel != null) {
                runOnUiThread {
                    Log.d("AuraMainActivity", "Also trying direct invokeMethod")
                    channel.invokeMethod("processAIQuery", query)
                }
            }
        }

        // Register the Email Draft handler — direct call to switch Flutter context
        AssistantForegroundService.startEmailDraftHandler = { address ->
            runOnUiThread {
                assistantAiChannel?.invokeMethod("startEmailDraft", address)
            }
        }

        // If a query was pending (Flutter was dead when it arrived), forward it now
        val pending = AssistantForegroundService.pendingAiQuery
        if (pending != null) {
            AssistantForegroundService.pendingAiQuery = null
            assistantAiChannel?.invokeMethod("processAIQuery", pending)
        }
        
        // If an email draft was pending
        val pendingEmail = AssistantForegroundService.pendingEmailDraftAddress
        if (pendingEmail != null) {
            AssistantForegroundService.pendingEmailDraftAddress = null
            assistantAiChannel?.invokeMethod("startEmailDraft", pendingEmail)
        }

        // Memory Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getAvailableMemory") {
                val availMem = getAvailableMemory()
                if (availMem != -1L) result.success(availMem) else result.error("UNAVAILABLE", "RAM not available.", null)
            } else if (call.method == "getTotalMemory") {
                 val totalMem = getTotalMemory()
                 if (totalMem != -1L) result.success(totalMem) else result.error("UNAVAILABLE", "RAM not available.", null)
            } else {
                result.notImplemented()
            }
        }

        // App Control Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openApp" -> {
                    val appName = call.argument<String>("appName")
                    if (appName != null) {
                        launchApp(appName, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "App name is required", null)
                    }
                }
                "closeApp" -> {
                    // Android doesn't support force closing apps easily without root/accessibility
                    // We can just try to go to home screen or ignore for now to avoid crashes
                    result.success("Closing apps programmatically is restricted on Android.")
                }
                "saveImageToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("filename") ?: "aura_${System.currentTimeMillis()}.jpg"
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "Image bytes are required", null)
                    } else {
                        try {
                            val saved = saveImageToGallery(bytes, name)
                            if (saved) result.success("Saved to gallery")
                            else result.error("SAVE_FAILED", "Could not write image", null)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                }
                "openSettings" -> {
                    val type = call.argument<String>("type")
                    openSettings(type, result)
                }
                "openCamera" -> {
                    openCamera(result)
                }
                "dialContact" -> {
                    val name = call.argument<String>("name")
                    dialContact(name, result)
                }
                "sendSMS" -> {
                    val name = call.argument<String>("name")
                    val message = call.argument<String>("message")
                    sendSMS(name, message, result)
                }
                "sendSMSDirect" -> {
                    val number = call.argument<String>("number")
                    val message = call.argument<String>("message")
                    if (number != null && message != null) {
                        sendSMSDirect(number, message, result)
                    } else {
                        result.error("INVALID", "Number and message required", null)
                    }
                }
                "launchEmailApp" -> {
                    val address = call.argument<String>("address") ?: ""
                    val subject = call.argument<String>("subject") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    
                    val emailIntent = android.content.Intent(android.content.Intent.ACTION_SENDTO).apply {
                        data = android.net.Uri.parse("mailto:") // only email apps should handle this
                        putExtra(android.content.Intent.EXTRA_EMAIL, arrayOf(address))
                        putExtra(android.content.Intent.EXTRA_SUBJECT, subject)
                        putExtra(android.content.Intent.EXTRA_TEXT, body)
                        addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    try {
                        startActivity(emailIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EMAIL_FAILED", "Could not launch email app: ${e.message}", null)
                    }
                }
                "callPhoneDirect" -> {
                    val number = call.argument<String>("number")
                    if (number != null) {
                        callPhoneDirect(number, result)
                    } else {
                        result.error("INVALID", "Number required", null)
                    }
                }
                "toggleTorch" -> {
                    val state = call.argument<Boolean>("state")
                    if (state != null) {
                        toggleTorch(state, result)
                    } else {
                        result.error("INVALID", "State required", null)
                    }
                }
                "scheduleReminder" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Reminder"
                        val desc = call.argument<String>("description") ?: ""
                        // Safer casting for Long from Flutter (can arrive as Int if small)
                        val timeArg = call.argument<Any>("timeInMillis")
                        val timeInMillis = when (timeArg) {
                            is Long -> timeArg
                            is Int -> timeArg.toLong()
                            is Number -> timeArg.toLong()
                            else -> 0L
                        }
                        
                        val preReminder = call.argument<Boolean>("preReminderEnabled") ?: false

                        Log.d("AuraAlarm", "Native: Received scheduleReminder - Title: $title, Time: $timeInMillis")

                        if (timeInMillis == 0L) {
                            Log.e("AuraAlarm", "Native: Invalid time (0L)")
                            result.error("INVALID", "Time required", null)
                            return@setMethodCallHandler
                        }

                        val reminder = ReminderModel(
                            title = title,
                            description = desc,
                            eventDateTime = timeInMillis,
                            preReminderEnabled = preReminder
                        )

                        val repo = ReminderRepository(this@MainActivity)
                        val id = repo.addReminder(reminder)
                        Log.d("AuraAlarm", "Native: Added reminder to DB, ID: $id")
                        
                        val modelWithId = reminder.copy(id = id.toInt())
                        val scheduler = AlarmScheduler(this@MainActivity)
                        val scheduled = scheduler.scheduleReminder(modelWithId)
                        
                        Log.d("AuraAlarm", "Native: Scheduled status: $scheduled")
                        result.success(scheduled)
                    } catch (e: Exception) {
                        Log.e("AuraAlarm", "Native: Failed to schedule: ${e.message}")
                        e.printStackTrace()
                        result.error("FAILED", "Could not schedule reminder: ${e.message}", null)
                    }
                }
                "startAssistant" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M && !android.provider.Settings.canDrawOverlays(this@MainActivity)) {
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:$packageName")
                        )
                        startActivityForResult(intent, 1234)
                        result.error("NEEDS_OVERLAY_PERMISSION", "Please grant Display Over Other Apps permission.", null)
                    } else {
                        val serviceIntent = android.content.Intent(this@MainActivity, com.aura.mobile.aura_mobile.assistant.AssistantForegroundService::class.java)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success("Assistant Started")
                    }
                }
                "stopAssistant" -> {
                    val serviceIntent = android.content.Intent(this@MainActivity, com.aura.mobile.aura_mobile.assistant.AssistantForegroundService::class.java)
                    stopService(serviceIntent)
                    result.success("Assistant Stopped")
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission(result)
                }
                "isAssistantRunning" -> {
                    result.success(isServiceRunning(com.aura.mobile.aura_mobile.assistant.AssistantForegroundService::class.java))
                }
                "setGestureMode" -> {
                    val mode = call.argument<String>("mode") ?: "both"
                    val intent = android.content.Intent("com.aura.mobile.assistant.SET_GESTURE_MODE")
                    intent.putExtra("mode", mode)
                    sendBroadcast(intent)
                    result.success("Gesture mode set to $mode")
                }
                // ═══ SMART APP ACTIONS ═══
                "sendWhatsApp" -> {
                    val contact = call.argument<String>("contact") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val deviceControl = com.aura.mobile.aura_mobile.assistant.DeviceControlService(this@MainActivity)
                    deviceControl.sendWhatsAppMessage(contact, message)
                    result.success("WhatsApp message initiated")
                }
                "searchOnApp" -> {
                    val appName = call.argument<String>("appName") ?: ""
                    val query = call.argument<String>("query") ?: ""
                    val deviceControl = com.aura.mobile.aura_mobile.assistant.DeviceControlService(this@MainActivity)
                    deviceControl.searchOnApp(appName, query)
                    result.success("Search initiated on $appName")
                }
                "makeUpiPayment" -> {
                    val upiId = call.argument<String>("upiId")
                    val amount = call.argument<String>("amount")
                    val note = call.argument<String>("note")
                    val deviceControl = com.aura.mobile.aura_mobile.assistant.DeviceControlService(this@MainActivity)
                    deviceControl.openUpiPayment(upiId, amount, note)
                    result.success("UPI payment initiated")
                }
                "playOnSpotify" -> {
                    val query = call.argument<String>("query") ?: ""
                    val deviceControl = com.aura.mobile.aura_mobile.assistant.DeviceControlService(this@MainActivity)
                    deviceControl.playOnSpotify(query)
                    result.success("Spotify playback initiated")
                }
                "bookRide" -> {
                    val destination = call.argument<String>("destination") ?: ""
                    val app = call.argument<String>("app")
                    val deviceControl = com.aura.mobile.aura_mobile.assistant.DeviceControlService(this@MainActivity)
                    deviceControl.bookRide(destination, app)
                    result.success("Ride booking initiated")
                }
                "orderFood" -> {
                    val restaurant = call.argument<String>("restaurant")
                    val app = call.argument<String>("app")
                    val deviceControl = com.aura.mobile.aura_mobile.assistant.DeviceControlService(this@MainActivity)
                    deviceControl.orderFood(restaurant, app)
                    result.success("Food order initiated")
                }
                "shareText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val app = call.argument<String>("app")
                    val deviceControl = com.aura.mobile.aura_mobile.assistant.DeviceControlService(this@MainActivity)
                    deviceControl.shareText(text, app)
                    result.success("Share initiated")
                }
                "openProfile" -> {
                    val platform = call.argument<String>("platform") ?: ""
                    val username = call.argument<String>("username") ?: ""
                    val deviceControl = com.aura.mobile.aura_mobile.assistant.DeviceControlService(this@MainActivity)
                    deviceControl.openProfile(platform, username)
                    result.success("Profile opened")
                }
                else -> result.notImplemented()
            }
        }

        // ═══ Smart Clipboard AI Channel ═══
        // ═══ Home Screen Widget Channel ═══
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
        widgetChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingRoute" -> {
                    val route = pendingWidgetRoute
                    pendingWidgetRoute = null
                    result.success(route)
                }
                else -> result.notImplemented()
            }
        }
        deliverPendingWidgetRoute()

        clipboardChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
        clipboardChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableClipboardMonitor" -> {
                    val enable = call.arguments as? Boolean ?: true
                    if (enable) {
                        ClipboardMonitorService.start(this@MainActivity) { content, contentType ->
                            runOnUiThread {
                                clipboardChannel?.invokeMethod("onClipboardContent", mapOf(
                                    "content" to content,
                                    "contentType" to contentType
                                ))
                            }
                        }
                    } else {
                        ClipboardMonitorService.stop(this@MainActivity)
                    }
                    result.success(true)
                }
                "isClipboardMonitorActive" -> {
                    result.success(ClipboardMonitorService.isActive)
                }
                "getPendingProcessText" -> {
                    val query = pendingProcessTextQuery
                    if (query != null) {
                        pendingProcessTextQuery = null
                        Log.d("AuraMainActivity", "getPendingProcessText: returning '$query'")
                        result.success(query)
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        deliverPendingProcessTextQuery()

        // ═══ Screen Context AI Channel ═══
        screenContextChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CONTEXT_CHANNEL)
        screenContextChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getScreenContent" -> {
                    // Dart's ScreenContext.fromMap expects a structured payload.
                    // Returning a bare String here made every capture fail.
                    val pkg = ScreenContextAccessibilityService.currentPackageName
                    val appLabel = if (pkg.isBlank()) "Unknown" else try {
                        val pm = applicationContext.packageManager
                        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
                    } catch (e: Exception) {
                        pkg
                    }
                    result.success(
                        mapOf(
                            "packageName" to pkg,
                            "appName" to appLabel,
                            "screenText" to ScreenContextAccessibilityService.currentScreenContent,
                            "windowTitle" to ScreenContextAccessibilityService.currentActivityName
                        )
                    )
                }
                "isAccessibilityEnabled" -> {
                    result.success(ScreenContextAccessibilityService.isServiceEnabled(this@MainActivity))
                }
                "openAccessibilitySettings" -> {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ═══ Interactive Agent Mode: Action + Query Channel (additive) ═══
        // Every method delegates to AgentActionSurface, which does node work on a
        // dedicated thread and refuses when the surface is disabled or the window
        // is secure. No AccessibilityNodeInfo handle crosses this boundary.
        agentControlChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AGENT_CONTROL_CHANNEL)
        agentControlChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isServiceEnabled" -> {
                    result.success(ScreenContextAccessibilityService.isServiceEnabled(this@MainActivity))
                }
                "openAccessibilitySettings" -> {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "setActionsEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    result.success(AgentActionSurface.setEnabled(enabled))
                }
                "getScreenSignature" -> {
                    AgentActionSurface.screenSignature { sig -> result.success(sig) }
                }
                "findNodes" -> {
                    @Suppress("UNCHECKED_CAST")
                    val query = (call.argument<Map<String, Any?>>("query")) ?: emptyMap()
                    val limit = call.argument<Int>("limit") ?: 5
                    AgentActionSurface.findNodes(query, limit) { nodes -> result.success(nodes) }
                }
                "tapNode" -> {
                    val token = call.argument<Int>("handleToken") ?: -1
                    AgentActionSurface.tapNode(token) { code -> result.success(code) }
                }
                "setNodeText" -> {
                    val token = call.argument<Int>("handleToken") ?: -1
                    val value = call.argument<String>("value") ?: ""
                    AgentActionSurface.setNodeText(token, value) { code -> result.success(code) }
                }
                "scrollNode" -> {
                    val token = call.argument<Int>("handleToken") ?: -1
                    val forward = call.argument<Boolean>("forward") ?: true
                    AgentActionSurface.scrollNode(token, forward) { code -> result.success(code) }
                }
                "performGlobal" -> {
                    val action = call.argument<String>("action") ?: ""
                    AgentActionSurface.performGlobal(action) { code -> result.success(code) }
                }
                else -> result.notImplemented()
            }
        }

        // ═══ Smart Notification Digest Channel ═══
        notificationsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATIONS_CHANNEL)
        notificationsChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerEnabled" -> {
                    result.success(AuraNotificationListenerService.isServiceEnabled(this@MainActivity))
                }
                "openNotificationListenerSettings" -> {
                    try {
                        val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "getRecentNotifications" -> {
                    val sinceMillis = when (val arg = call.argument<Any>("sinceMillis")) {
                        is Long -> arg
                        is Int -> arg.toLong()
                        is Number -> arg.toLong()
                        else -> System.currentTimeMillis() - 24 * 60 * 60 * 1000L // default: last 24h
                    }
                    result.success(AuraNotificationListenerService.getRecentNotifications(sinceMillis))
                }
                "getGroupedNotifications" -> {
                    result.success(AuraNotificationListenerService.getGroupedByApp())
                }
                "clearNotifications" -> {
                    AuraNotificationListenerService.clearAll()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        val notifFilter = IntentFilter("com.aura.mobile.assistant.NOTIFICATION_POSTED")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(notificationReceiver, notifFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(notificationReceiver, notifFilter)
        }

        // ═══ Share Receiver Channel (Smart Summarizer) ═══
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    val pending = pendingShareContent
                    if (pending != null) {
                        pendingShareContent = null
                        result.success(mapOf("text" to pending, "title" to ""))
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // If there's pending share content (app was cold-started via share), deliver it
        if (pendingShareContent != null) {
            deliverSharedContent(pendingShareContent!!, null)
        }
    }

    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            if (!android.provider.Settings.canDrawOverlays(this)) {
                val intent = android.content.Intent(
                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, 1234)
                result.success("Requested Settings")
            } else {
                result.success("Already Granted")
            }
        } else {
            result.success("Not required below M")
        }
    }

    private fun launchApp(appName: String, result: MethodChannel.Result) {
        // [FIX] Handle navigation requests sent through openApp channel
        if (appName.startsWith("navigate:")) {
            val destination = appName.substringAfter("navigate:")
            val deviceControl = com.aura.mobile.aura_mobile.assistant.DeviceControlService(this@MainActivity)
            deviceControl.navigate(destination)
            result.success("Navigating to $destination")
            return
        }

        val pm = packageManager
        val packages = pm.getInstalledPackages(0)

        // Simple fuzzy match algorithm
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
                // Keep the first partial match or improve logic
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
                    startActivity(launchIntent)
                    result.success("Launched $bestMatchLabel")
                } else {
                    result.error("LAUNCH_FAILED", "Could not create intent for $bestMatchPkg", null)
                }
            } catch (e: Exception) {
                 result.error("ERROR", e.message, null)
            }
        } else {
            result.error("APP_NOT_FOUND", "Could not find app '$appName'", null)
        }
    }

    private fun openSettings(type: String?, result: MethodChannel.Result) {
        try {
            val intent = when (type) {
                "wifi" -> android.content.Intent(android.provider.Settings.ACTION_WIFI_SETTINGS)
                "bluetooth" -> android.content.Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
                else -> android.content.Intent(android.provider.Settings.ACTION_SETTINGS)
            }
            startActivity(intent)
            result.success("Settings opened")
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun openCamera(result: MethodChannel.Result) {
         try {
            val intent = android.content.Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE)
            startActivity(intent)
            result.success("Camera opened")
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun dialContact(name: String?, result: MethodChannel.Result) {
        if (name == null) {
             result.error("INVALID", "Name required", null)
             return
        }

        // Check if it looks like a number
        if (name.all { it.isDigit() || it == '+' || it == ' ' || it == '-' }) {
             val intent = android.content.Intent(android.content.Intent.ACTION_DIAL)
             intent.data = android.net.Uri.parse("tel:$name")
             startActivity(intent)
             result.success("Dialing $name")
             return
        }

        // Try to find contact by name
        try {
            val resolver = contentResolver
            val cursor = resolver.query(
                android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                null,
                "${android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                arrayOf("%$name%"),
                null
            )

            var number: String? = null
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                if (index != -1) number = cursor.getString(index)
                cursor.close()
            }

            if (number != null) {
                 val intent = android.content.Intent(android.content.Intent.ACTION_DIAL)
                 intent.data = android.net.Uri.parse("tel:$number")
                 startActivity(intent)
                 result.success("Dialing $name ($number)")
            } else {
                 // Fallback to searching in contacts app
                 val intent = android.content.Intent(android.content.Intent.ACTION_VIEW)
                 intent.data = android.net.Uri.withAppendedPath(android.provider.ContactsContract.Contacts.CONTENT_FILTER_URI, android.net.Uri.encode(name))
                 startActivity(intent)
                 result.success("Searching contact $name")
            }

        } catch (e: Exception) {
             val intent = android.content.Intent(android.content.Intent.ACTION_DIAL)
             startActivity(intent)
             result.success("Opened Dialer (Contact search failed or permission denied)")
        }
    }

    private fun sendSMS(name: String?, message: String?, result: MethodChannel.Result) {
         if (name == null) {
             result.error("INVALID", "Name/Number required", null)
             return
         }

         // 1. Resolve number (reuse logic or duplication)
         var number = name
         if (!name.all { it.isDigit() || it == '+' || it == ' ' || it == '-' }) {
             try {
                val cursor = contentResolver.query(
                    android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    null,
                    "${android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                    arrayOf("%$name%"),
                    null
                )
                if (cursor != null && cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                    if (index != -1) number = cursor.getString(index)
                    cursor.close()
                }
             } catch (e: Exception) {
                 // Ignore
             }
         }

         try {
             val intent = android.content.Intent(android.content.Intent.ACTION_SENDTO)
             intent.data = android.net.Uri.parse("smsto:$number")
             intent.putExtra("sms_body", message ?: "")
             startActivity(intent)
             result.success("Opened SMS app for $number")
         } catch (e: Exception) {
             result.error("ERROR", e.message, null)
         }
    }

    // Existing helper methods
    private fun getAvailableMemory(): Long {
        val memoryInfo = ActivityManager.MemoryInfo()
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        activityManager.getMemoryInfo(memoryInfo)
        return memoryInfo.availMem
    }

    private fun getTotalMemory(): Long {
        val memoryInfo = ActivityManager.MemoryInfo()
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        activityManager.getMemoryInfo(memoryInfo)
        return memoryInfo.totalMem
    }

    private fun sendSMSDirect(number: String, message: String, result: MethodChannel.Result) {
        try {
            val smsManager = SmsManager.getDefault()
            smsManager.sendTextMessage(number, null, message, null, null)
            result.success("SMS Sent to $number")
        } catch (e: Exception) {
            result.error("SMS_FAILED", e.message, null)
        }
    }

    private fun callPhoneDirect(number: String, result: MethodChannel.Result) {
        try {
            val intent = android.content.Intent(android.content.Intent.ACTION_CALL)
            intent.data = android.net.Uri.parse("tel:$number")
            startActivity(intent)
            result.success("Call initiated to $number")
        } catch (e: Exception) {
            result.error("CALL_FAILED", e.message, null)
        }
    }

    private fun toggleTorch(state: Boolean, result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) {
            result.error("UNSUPPORTED", "Torch requires Android M+", null)
            return
        }
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
            // Find a camera with flash support
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
                result.success("Torch toggled to $state")
            } else {
                result.error("NO_FLASH", "No camera with flash found", null)
            }
        } catch (e: Exception) {
            result.error("TORCH_ERROR", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        for (service in manager.getRunningServices(Int.MAX_VALUE)) {
            if (serviceClass.name == service.service.className) {
                return true
            }
        }
        return false
    }

    /**
     * Writes [bytes] into the device's Pictures/AURA album using MediaStore.
     * On API 29+ this needs no runtime permission (scoped storage); on older
     * versions it falls back to the public Pictures directory (WRITE perms are
     * handled by the picker/permission flow elsewhere).
     */
    private fun saveImageToGallery(bytes: ByteArray, filename: String): Boolean {
        val safeName = if (filename.contains('.')) filename else "$filename.jpg"
        val mime = when {
            safeName.endsWith(".png", true) -> "image/png"
            safeName.endsWith(".webp", true) -> "image/webp"
            else -> "image/jpeg"
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, safeName)
                put(android.provider.MediaStore.Images.Media.MIME_TYPE, mime)
                put(
                    android.provider.MediaStore.Images.Media.RELATIVE_PATH,
                    android.os.Environment.DIRECTORY_PICTURES + "/AURA"
                )
                put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(
                android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                values
            ) ?: return false
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return false
            values.clear()
            values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return true
        } else {
            @Suppress("DEPRECATION")
            val picturesDir = android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_PICTURES
            )
            val auraDir = java.io.File(picturesDir, "AURA")
            if (!auraDir.exists()) auraDir.mkdirs()
            val outFile = java.io.File(auraDir, safeName)
            java.io.FileOutputStream(outFile).use { it.write(bytes) }
            // Make it visible in the gallery.
            android.media.MediaScannerConnection.scanFile(
                this, arrayOf(outFile.absolutePath), arrayOf(mime), null
            )
            return true
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        AuraBrainRuntimeBridge.detachUiEngine(flutterEngine)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(notificationReceiver)
        } catch (e: Exception) {
            // Ignore
        }
        // Clear handler to prevent stale refs to dead Flutter engine
        AssistantForegroundService.aiRequestHandler = null
    }
}

package com.aura.mobile.aura_mobile.brain

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArraySet

internal object AuraBrainRuntimeBridge {
    const val CHANNEL = "com.aura.mobile.aura_mobile/brain/v1"

    interface Listener {
        fun onStatusChanged(statusJson: String)
        fun onRequestEvent(requestId: String, eventJson: String)
        fun onRuntimeUnavailable()
    }

    private data class PendingCall(
        val method: String,
        val arguments: Any?,
        val onError: (() -> Unit)?,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArraySet<Listener>()
    private val pendingCalls = ArrayDeque<PendingCall>()
    private var endpointEngine: FlutterEngine? = null
    private var headlessEngine: FlutterEngine? = null
    private var pendingUiEngine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var dartReady = false
    private var openSetupPending = false
    @Volatile
    var cachedStatusJson: String =
        "{\"protocolVersion\":1,\"status\":\"starting\",\"modelInstalled\":false," +
            "\"modelLoaded\":false,\"busy\":false,\"activeRequestId\":null," +
            "\"message\":\"Aura Brain is starting.\"}"
        private set

    fun addListener(listener: Listener) {
        listeners.add(listener)
    }

    fun removeListener(listener: Listener) {
        listeners.remove(listener)
    }

    fun attachUiEngine(engine: FlutterEngine) {
        mainHandler.post {
            if (headlessEngine != null) {
                pendingUiEngine = engine
                return@post
            }
            configureEndpoint(engine)
        }
    }

    fun detachUiEngine(engine: FlutterEngine) {
        mainHandler.post {
            if (pendingUiEngine === engine) pendingUiEngine = null
            if (endpointEngine !== engine || headlessEngine === engine) return@post
            clearEndpoint()
        }
    }

    fun ensureRuntime(context: Context) {
        mainHandler.post {
            if (endpointEngine != null) return@post
            try {
                val appContext = context.applicationContext
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(appContext)
                loader.ensureInitializationComplete(appContext, null)
                val engine = FlutterEngine(appContext, null, false)
                engine.plugins.add(dev.flutterberlin.flutter_gemma.FlutterGemmaPlugin())
                engine.plugins.add(com.example.large_file_handler.LargeFileHandlerPlugin())
                engine.plugins.add(com.bbflight.background_downloader.BDPlugin())
                engine.plugins.add(io.flutter.plugins.pathprovider.PathProviderPlugin())
                engine.plugins.add(
                    io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin(),
                )
                headlessEngine = engine
                configureEndpoint(engine)
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "auraBrainMain",
                    ),
                )
            } catch (_: Throwable) {
                clearEndpoint()
                headlessEngine = null
                listeners.forEach { it.onRuntimeUnavailable() }
            }
        }
    }
    private fun configureEndpoint(engine: FlutterEngine) {
        endpointEngine = engine
        dartReady = false
        val nextChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = nextChannel
        nextChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "statusChanged" -> {
                    val args = call.arguments as? Map<*, *>
                    val status = args?.get("statusJson") as? String
                    if (status != null) {
                        cachedStatusJson = status
                        dartReady = true
                        listeners.forEach { it.onStatusChanged(status) }
                        flushPendingCalls()
                        deliverPendingSetup()
                    }
                    result.success(null)
                }
                "requestEvent" -> {
                    val args = call.arguments as? Map<*, *>
                    val requestId = args?.get("requestId") as? String
                    val eventJson = args?.get("eventJson") as? String
                    if (requestId != null && eventJson != null) {
                        listeners.forEach {
                            it.onRequestEvent(requestId, eventJson)
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        probeDart(engine, 0)
    }

    private fun probeDart(engine: FlutterEngine, attempt: Int) {
        mainHandler.postDelayed({
            if (endpointEngine !== engine || dartReady) return@postDelayed
            channel?.invokeMethod(
                "initialize",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val status = result as? String ?: return
                        cachedStatusJson = status
                        dartReady = true
                        listeners.forEach { it.onStatusChanged(status) }
                        flushPendingCalls()
                        deliverPendingSetup()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        if (attempt < 4) probeDart(engine, attempt + 1)
                    }

                    override fun notImplemented() {
                        if (attempt < 4) probeDart(engine, attempt + 1)
                    }
                },
            )
        }, 200L * (attempt + 1))
    }

    fun invoke(
        context: Context,
        method: String,
        arguments: Any?,
        onError: (() -> Unit)? = null,
    ) {
        mainHandler.post {
            if (endpointEngine == null) ensureRuntime(context)
            val pending = PendingCall(method, arguments, onError)
            if (!dartReady || channel == null) {
                pendingCalls.addLast(pending)
            } else {
                invokeNow(pending)
            }
        }
    }
    private fun flushPendingCalls() {
        while (dartReady && pendingCalls.isNotEmpty()) {
            invokeNow(pendingCalls.removeFirst())
        }
    }

    private fun invokeNow(pending: PendingCall) {
        channel?.invokeMethod(
            pending.method,
            pending.arguments,
            object : MethodChannel.Result {
                override fun success(result: Any?) = Unit

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) {
                    pending.onError?.invoke()
                }

                override fun notImplemented() {
                    pending.onError?.invoke()
                }
            },
        ) ?: pending.onError?.invoke()
    }

    fun requestOpenSetup() {
        mainHandler.post {
            openSetupPending = true
            deliverPendingSetup()
        }
    }

    private fun deliverPendingSetup() {
        if (!openSetupPending || !dartReady) return
        openSetupPending = false
        channel?.invokeMethod("openModelSetup", null)
    }

    fun shutdownHeadless() {
        mainHandler.post {
            val engine = headlessEngine ?: return@post
            channel?.invokeMethod("shutdown", null)
            mainHandler.postDelayed({
                if (headlessEngine === engine) {
                    clearEndpoint()
                    headlessEngine = null
                    engine.destroy()
                    pendingUiEngine?.let {
                        pendingUiEngine = null
                        configureEndpoint(it)
                    }
                }
            }, 250L)
        }
    }

    private fun clearEndpoint() {
        channel?.setMethodCallHandler(null)
        channel = null
        endpointEngine = null
        dartReady = false
        pendingCalls.clear()
    }
}

package com.aura.mobile.aura_mobile.brain

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.RemoteException
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap

class AuraBrainService : Service(), AuraBrainRuntimeBridge.Listener {
    companion object {
        const val PROTOCOL_VERSION = 1
        const val MAX_REQUEST_BYTES = 128 * 1024
        const val PERMISSION =
            "com.aura.mobile.aura_mobile.permission.USE_AURA_BRAIN"
        private val TERMINAL_EVENTS = setOf(
            "completed",
            "cancelled",
            "error",
        )
        private const val CAPABILITIES_JSON =
            "{\"protocolVersion\":1,\"capabilities\":[\"healthCheck\"," +
                "\"summarizePage\",\"streaming\",\"cancellation\",\"localOnly\"]}"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val callbacks = ConcurrentHashMap<String, CallbackRecord>()
    private lateinit var callerValidator: AuraBrainCallerValidator

    override fun onCreate() {
        super.onCreate()
        callerValidator = AuraBrainCallerValidator(this)
        AuraBrainRuntimeBridge.addListener(this)
        AuraBrainRuntimeBridge.ensureRuntime(this)
    }
    private val binder = object : IAuraBrainService.Stub() {
        override fun getProtocolVersion(): Int {
            callerValidator.enforce(Binder.getCallingUid())
            return PROTOCOL_VERSION
        }

        override fun getStatusJson(): String {
            callerValidator.enforce(Binder.getCallingUid())
            return AuraBrainRuntimeBridge.cachedStatusJson
        }

        override fun getCapabilitiesJson(): String {
            callerValidator.enforce(Binder.getCallingUid())
            return CAPABILITIES_JSON
        }

        override fun startRequest(
            requestJson: String?,
            callback: IAuraBrainCallback?,
        ) {
            val callingUid = Binder.getCallingUid()
            callerValidator.enforce(callingUid)
            if (requestJson == null || callback == null) {
                throw IllegalArgumentException("Request JSON and callback are required.")
            }

            val requestId = try {
                validateNativeEnvelope(requestJson)
            } catch (error: NativeRequestException) {
                sendDirectError(
                    callback,
                    error.requestId,
                    error.code,
                    error.safeMessage,
                )
                return
            }

            val record = CallbackRecord(requestId, callingUid, callback)
            synchronized(callbacks) {
                if (callbacks.containsKey(requestId)) {
                    sendDirectError(
                        callback,
                        requestId,
                        "invalidRequest",
                        "An active request already uses this requestId.",
                    )
                    return
                }
                if (callbacks.isNotEmpty()) {
                    sendDirectError(
                        callback,
                        requestId,
                        "brainBusy",
                        "Aura Brain Protocol V1 allows one request at a time.",
                    )
                    return
                }
                try {
                    callback.asBinder().linkToDeath(record, 0)
                } catch (_: RemoteException) {
                    return
                }
                callbacks[requestId] = record
            }

            mainHandler.post {
                AuraBrainRuntimeBridge.invoke(
                    this@AuraBrainService,
                    "startRequest",
                    requestJson,
                ) { failRequest(requestId, "serviceUnavailable") }
            }
        }
        override fun cancelRequest(requestId: String?) {
            val callingUid = Binder.getCallingUid()
            callerValidator.enforce(callingUid)
            if (requestId.isNullOrBlank()) return
            val record = callbacks[requestId] ?: return
            if (record.callingUid != callingUid &&
                callingUid != android.os.Process.myUid()
            ) {
                throw SecurityException("A caller may cancel only its own request.")
            }
            mainHandler.post {
                AuraBrainRuntimeBridge.invoke(
                    this@AuraBrainService,
                    "cancelRequest",
                    requestId,
                ) { failRequest(requestId, "serviceUnavailable") }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onUnbind(intent: Intent?): Boolean {
        cancelAllForDisconnect()
        return false
    }

    override fun onDestroy() {
        cancelAllForDisconnect()
        AuraBrainRuntimeBridge.removeListener(this)
        AuraBrainRuntimeBridge.shutdownHeadless()
        super.onDestroy()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (callbacks.isEmpty() && level >= TRIM_MEMORY_RUNNING_LOW) {
            AuraBrainRuntimeBridge.shutdownHeadless()
        }
    }

    private fun validateNativeEnvelope(requestJson: String): String {
        if (requestJson.toByteArray(StandardCharsets.UTF_8).size > MAX_REQUEST_BYTES) {
            throw NativeRequestException(
                "invalid-request",
                "contextTooLarge",
                "The serialized request exceeds 128 KiB.",
            )
        }
        val root = try {
            JSONObject(requestJson)
        } catch (_: Exception) {
            throw NativeRequestException(
                "invalid-request",
                "invalidRequest",
                "Request JSON is malformed.",
            )
        }
        val requestId = root.optString("requestId", "").trim()
        if (requestId.isBlank() || requestId.length > 200) {
            throw NativeRequestException(
                "invalid-request",
                "invalidRequest",
                "requestId is invalid.",
            )
        }
        if (!root.has("protocolVersion") ||
            root.optInt("protocolVersion", -1) != PROTOCOL_VERSION
        ) {
            throw NativeRequestException(
                requestId,
                "unsupportedProtocol",
                "Only Aura Brain Protocol Version 1 is supported.",
            )
        }
        val task = root.optString("task", "")
        if (task != "healthCheck" && task != "summarizePage") {
            throw NativeRequestException(
                requestId,
                "unsupportedTask",
                "The requested task is not supported by Protocol V1.",
            )
        }
        return requestId
    }

    override fun onStatusChanged(statusJson: String) = Unit

    override fun onRequestEvent(requestId: String, eventJson: String) {
        val record = callbacks[requestId] ?: return
        try {
            record.callback.onEvent(requestId, eventJson)
        } catch (_: RemoteException) {
            handleCallbackDeath(requestId)
            return
        }
        val type = try {
            JSONObject(eventJson).optString("type", "")
        } catch (_: Exception) {
            ""
        }
        if (type in TERMINAL_EVENTS) removeCallback(requestId)
    }

    override fun onRuntimeUnavailable() {
        callbacks.keys.toList().forEach {
            failRequest(it, "serviceUnavailable")
        }
    }

    private fun sendDirectError(
        callback: IAuraBrainCallback,
        requestId: String,
        code: String,
        message: String,
    ) {
        mainHandler.post {
            try {
                callback.onEvent(requestId, errorEvent(requestId, code, message))
            } catch (_: RemoteException) {
                // The client disconnected before the asynchronous error delivery.
            }
        }
    }
    private fun failRequest(requestId: String, code: String) {
        val record = callbacks[requestId] ?: return
        val message = if (code == "serviceUnavailable") {
            "Aura Brain runtime is unavailable."
        } else {
            "The local request failed."
        }
        try {
            record.callback.onEvent(
                requestId,
                errorEvent(requestId, code, message),
            )
        } catch (_: RemoteException) {
            // Callback death cleanup below is still required.
        }
        removeCallback(requestId)
    }

    private fun errorEvent(
        requestId: String,
        code: String,
        message: String,
    ): String = JSONObject()
        .put("protocolVersion", PROTOCOL_VERSION)
        .put("requestId", requestId)
        .put("type", "error")
        .put("content", JSONObject.NULL)
        .put("errorCode", code)
        .put("message", message)
        .toString()

    private fun removeCallback(requestId: String) {
        val record = callbacks.remove(requestId) ?: return
        record.callback.asBinder().unlinkToDeath(record, 0)
    }

    private fun handleCallbackDeath(requestId: String) {
        val removed = callbacks.remove(requestId) ?: return
        removed.callback.asBinder().unlinkToDeath(removed, 0)
        AuraBrainRuntimeBridge.invoke(
            this,
            "cancelRequest",
            requestId,
        )
    }

    private fun cancelAllForDisconnect() {
        callbacks.keys.toList().forEach { requestId ->
            val record = callbacks.remove(requestId) ?: return@forEach
            record.callback.asBinder().unlinkToDeath(record, 0)
            AuraBrainRuntimeBridge.invoke(
                this,
                "cancelRequest",
                requestId,
            )
        }
    }
    private inner class CallbackRecord(
        val requestId: String,
        val callingUid: Int,
        val callback: IAuraBrainCallback,
    ) : IBinder.DeathRecipient {
        override fun binderDied() {
            mainHandler.post { handleCallbackDeath(requestId) }
        }
    }

    private class NativeRequestException(
        val requestId: String,
        val code: String,
        val safeMessage: String,
    ) : Exception()
}

package com.aura.mobile.aura_mobile.assistant

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log

/**
 * Invisible trampoline used by the Quick Settings tile to turn the voice
 * assistant on WITHOUT opening the full app.
 *
 * Android 12+ forbids starting a microphone foreground service from the
 * background (a Quick Settings tile counts as background). The allowed path is
 * to have a visible/foreground activity start it. This activity uses a fully
 * transparent theme and finishes immediately, so the user just sees the shade
 * collapse — no app UI flashes up — while Android still treats the service
 * start as foreground-initiated.
 */
class AssistantLauncherActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // No content view — this activity is transparent and finishes at once.
    }

    override fun onResume() {
        super.onResume()
        startAssistant()
        // We are done; disappear immediately so nothing is shown to the user.
        finish()
        overridePendingTransition(0, 0)
    }

    private fun startAssistant() {
        // The assistant's on-screen UI needs the overlay permission. If it is
        // missing, send the user to grant it rather than starting a headless
        // service with no visible feedback.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (e: Exception) {
                Log.e("AssistantLauncher", "Cannot open overlay settings: ${e.message}")
            }
            return
        }

        val serviceIntent = Intent(this, AssistantForegroundService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e("AssistantLauncher", "Failed to start assistant: ${e.message}")
        }
    }
}

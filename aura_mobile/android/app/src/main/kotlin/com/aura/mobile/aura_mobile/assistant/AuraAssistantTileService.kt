package com.aura.mobile.aura_mobile.assistant

import android.app.ActivityManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.aura.mobile.aura_mobile.R

/**
 * Quick Settings tile that turns the AURA Voice Assistant on/off, right from the
 * notification shade next to Wi-Fi / mobile-data toggles.
 *
 * It mirrors the exact start/stop path used by MainActivity's `startAssistant` /
 * `stopAssistant` method-channel handlers, so the drawer switch and this tile
 * stay consistent (the Dart side re-syncs its flag on resume via
 * VoiceAssistantService.syncServiceState()).
 *
 * Safety: starting the assistant needs the "Display over other apps" (overlay)
 * permission. If it is missing we send the user to the settings screen instead
 * of silently starting a service with no visible UI. Foreground-service starts
 * from a tile can be blocked on newer Android; we fall back to launching the app.
 */
@RequiresApi(Build.VERSION_CODES.N)
class AuraAssistantTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        updateTile()
    }

    override fun onClick() {
        super.onClick()

        if (isAssistantRunning()) {
            // Stopping a service from a tile is always allowed.
            stopAssistant()
            updateTile()
            return
        }

        // Starting a microphone foreground service directly from a Quick Settings
        // tile is blocked on Android 12+ (the app is not in a foreground state).
        // So we bounce through a transparent trampoline activity that starts the
        // service from a foreground context and finishes instantly — the user
        // does NOT see the full app open.
        val launch = Intent(this, AssistantLauncherActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
        }
        startActivityCompat(launch)
    }

    private fun stopAssistant() {
        stopService(Intent(this, AssistantForegroundService::class.java))
    }

    /** Starts an activity and collapses the shade, handling the API 34 change. */
    private fun startActivityCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pi = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            startActivityAndCollapse(pi)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    @Suppress("DEPRECATION")
    private fun isAssistantRunning(): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val target = AssistantForegroundService::class.java.name
        for (service in manager.getRunningServices(Int.MAX_VALUE)) {
            if (target == service.service.className) return true
        }
        return false
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val running = isAssistantRunning()
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "AURA Assistant"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (running) "On" else "Off"
        }
        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile_mic)
        tile.contentDescription =
            if (running) "AURA Assistant is on" else "AURA Assistant is off"
        tile.updateTile()
    }
}

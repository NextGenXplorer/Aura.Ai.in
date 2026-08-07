package com.aura.mobile.aura_mobile.brain

import android.content.Context
import android.content.pm.PackageManager
import android.os.Process

/** Central allowlist for deliberately approved Aura Brain clients. */
internal object AuraBrainAllowedClients {
    val packageNames: Set<String> = setOf(
        "com.quilonix.quilonix",
    )
}

internal class AuraBrainCallerValidator(private val context: Context) {
    fun enforce(callingUid: Int): String {
        if (callingUid == Process.myUid()) return context.packageName

        val packages = context.packageManager.getPackagesForUid(callingUid)
            ?.toSet()
            .orEmpty()
        val allowed = packages.firstOrNull {
            it in AuraBrainAllowedClients.packageNames
        } ?: throw SecurityException("Caller is not approved for Aura Brain.")

        val signatureResult = context.packageManager.checkSignatures(
            context.packageName,
            allowed,
        )
        if (signatureResult != PackageManager.SIGNATURE_MATCH) {
            throw SecurityException("Caller signing identity does not match Aura.")
        }
        return allowed
    }
}

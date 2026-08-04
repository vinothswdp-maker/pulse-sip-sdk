package com.pulse.sipsdk

import android.content.Context
import org.json.JSONObject

/** SIP credentials/settings needed to register — mirrors PulseSipConfig on the Dart side. */
data class PulseSipConfig(
    val webSocketUrl: String,
    val sipUser: String,
    val sipPassword: String,
    val sipDomain: String,
    val displayName: String? = null,
    val pushContactParams: Map<String, String> = emptyMap(),
    /** Only set true against a dev server you control. Never true in production. */
    val allowBadCertificate: Boolean = false,
) {
    fun toArgs(force: Boolean): Map<String, Any?> = mapOf(
        "webSocketUrl" to webSocketUrl,
        "sipUser" to sipUser,
        "sipPassword" to sipPassword,
        "sipDomain" to sipDomain,
        "displayName" to displayName,
        "pushContactParams" to pushContactParams,
        "allowBadCertificate" to allowBadCertificate,
        "force" to force,
    )

    /**
     * Saves this config so [PulseSipSdk.onPushReceived] can still re-register
     * after the process was killed and restarted (the in-memory copy is lost
     * on process death, which is exactly when a push wakes the app up).
     * [sipPassword] is encrypted with an Android Keystore key before being
     * written to disk.
     */
    fun persist(context: Context) {
        val json = JSONObject().apply {
            put("webSocketUrl", webSocketUrl)
            put("sipUser", sipUser)
            put("sipPasswordEnc", PulseSecureStore.encrypt(sipPassword))
            put("sipDomain", sipDomain)
            put("displayName", displayName)
            put("pushContactParams", JSONObject(pushContactParams))
            put("allowBadCertificate", allowBadCertificate)
        }
        prefs(context).edit().putString(KEY_LAST_CONFIG, json.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "pulse_sip_sdk_prefs"
        private const val KEY_LAST_CONFIG = "last_config"

        private fun prefs(context: Context) =
            context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        /** Loads the config last saved via [persist], or null if none was saved yet. */
        fun loadPersisted(context: Context): PulseSipConfig? {
            val raw = prefs(context).getString(KEY_LAST_CONFIG, null) ?: return null
            return try {
                val json = JSONObject(raw)
                val paramsJson = json.optJSONObject("pushContactParams")
                val params = mutableMapOf<String, String>()
                paramsJson?.keys()?.forEach { key -> params[key] = paramsJson.getString(key) }
                PulseSipConfig(
                    webSocketUrl = json.getString("webSocketUrl"),
                    sipUser = json.getString("sipUser"),
                    sipPassword = PulseSecureStore.decrypt(json.getString("sipPasswordEnc")),
                    sipDomain = json.getString("sipDomain"),
                    displayName = json.opt("displayName") as? String,
                    pushContactParams = params,
                    allowBadCertificate = json.optBoolean("allowBadCertificate", false),
                )
            } catch (e: Exception) {
                null
            }
        }

        /** Clears the persisted config, e.g. on logout. */
        fun clearPersisted(context: Context) {
            prefs(context).edit().remove(KEY_LAST_CONFIG).apply()
        }
    }
}

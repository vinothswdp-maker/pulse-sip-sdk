package com.pulse.sipsdk

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Fetches a [PulseSipConfig] from a per-customer config URL, so the host app
 * never needs to hardcode SIP credentials — see [PulseSipSdk.registerWithConfigUrl].
 * Expects a JSON body shaped like [PulseSipConfig]'s fields, e.g.:
 * ```json
 * {
 *   "webSocketUrl": "wss://sip.example.com:8089/ws",
 *   "sipUser": "1001",
 *   "sipPassword": "secret",
 *   "sipDomain": "sip.example.com",
 *   "displayName": "Jane",
 *   "pushContactParams": {"pn-provider": "fcm"},
 *   "allowBadCertificate": false
 * }
 * ```
 */
internal object PulseRemoteConfig {
    private const val TIMEOUT_MS = 10_000

    /** Performs a blocking HTTP GET — call from a background thread only. */
    fun fetch(configUrl: String): PulseSipConfig {
        require(configUrl.startsWith("https://")) {
            "configUrl must be https:// — refusing to send/receive SIP credentials over plaintext HTTP"
        }

        val connection = URL(configUrl).openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = TIMEOUT_MS
        connection.readTimeout = TIMEOUT_MS
        try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                error("Config fetch failed: HTTP ${connection.responseCode}")
            }
            val body = connection.inputStream.bufferedReader().readText()
            return parse(JSONObject(body))
        } finally {
            connection.disconnect()
        }
    }

    private fun parse(json: JSONObject): PulseSipConfig {
        val paramsJson = json.optJSONObject("pushContactParams")
        val params = mutableMapOf<String, String>()
        paramsJson?.keys()?.forEach { key -> params[key] = paramsJson.getString(key) }
        return PulseSipConfig(
            webSocketUrl = json.getString("webSocketUrl"),
            sipUser = json.getString("sipUser"),
            sipPassword = json.getString("sipPassword"),
            sipDomain = json.getString("sipDomain"),
            displayName = json.opt("displayName") as? String,
            pushContactParams = params,
            allowBadCertificate = json.optBoolean("allowBadCertificate", false),
        )
    }
}

package com.pulse.sipsdk

/** SIP credentials/settings needed to register — mirrors PulseSipConfig on the Dart side. */
data class PulseSipConfig(
    val webSocketUrl: String,
    val sipUser: String,
    val sipPassword: String,
    val sipDomain: String,
    val displayName: String? = null,
    val pushContactParams: Map<String, String> = emptyMap(),
) {
    fun toArgs(force: Boolean): Map<String, Any?> = mapOf(
        "webSocketUrl" to webSocketUrl,
        "sipUser" to sipUser,
        "sipPassword" to sipPassword,
        "sipDomain" to sipDomain,
        "displayName" to displayName,
        "pushContactParams" to pushContactParams,
        "force" to force,
    )
}

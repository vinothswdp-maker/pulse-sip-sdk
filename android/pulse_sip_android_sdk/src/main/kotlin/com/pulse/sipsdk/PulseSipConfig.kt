package com.pulse.sipsdk

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
}

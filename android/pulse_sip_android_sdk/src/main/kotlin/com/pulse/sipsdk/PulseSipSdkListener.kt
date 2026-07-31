package com.pulse.sipsdk

/** Call state/registration callbacks. All methods are called on the main thread. */
interface PulseSipSdkListener {
    fun onRegistrationChanged(registered: Boolean, message: String) {}
    fun onIncomingCall(callId: String?, callerName: String, callerNumber: String) {}
    fun onCallStateChanged(callId: String?, state: String) {}
    fun onCallEnded() {}
}

package com.pulse.sipsdk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Handles Accept/Decline taps from the incoming-call notification. */
class CallActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_ACCEPT = "com.pulse.sipsdk.action.ACCEPT"
        const val ACTION_DECLINE = "com.pulse.sipsdk.action.DECLINE"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_ACCEPT -> {
                PulseSipSdk.initialize(context.applicationContext)
                PulseSipSdk.acceptCall()
                PulseCallNotifications.dismissIncoming(context)
            }
            ACTION_DECLINE -> {
                PulseSipSdk.initialize(context.applicationContext)
                PulseSipSdk.rejectCall()
                PulseCallNotifications.dismissIncoming(context)
            }
        }
    }
}

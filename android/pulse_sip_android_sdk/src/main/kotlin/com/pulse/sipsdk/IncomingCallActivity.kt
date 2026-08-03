package com.pulse.sipsdk

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/**
 * Minimal lockscreen-capable incoming-call screen. Launched via a
 * full-screen-intent notification when a call arrives. Host apps that want
 * their own branded UI can ignore this and build their own screen driven by
 * [PulseSipSdkListener.onIncomingCall] instead — this Activity is only shown
 * when the notification's full-screen intent fires (e.g. locked screen).
 */
class IncomingCallActivity : Activity() {
    companion object {
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_CALLER_NUMBER = "caller_number"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        setContentView(R.layout.pulse_activity_incoming_call)

        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Unknown"
        val callerNumber = intent.getStringExtra(EXTRA_CALLER_NUMBER) ?: ""

        findViewById<TextView>(R.id.pulse_caller_name).text = callerName
        findViewById<TextView>(R.id.pulse_caller_number).text = callerNumber

        PulseSipSdk.initialize(applicationContext)

        findViewById<Button>(R.id.pulse_btn_accept).setOnClickListener {
            PulseSipSdk.acceptCall()
            PulseCallNotifications.dismissIncoming(this)
            finish()
        }
        findViewById<Button>(R.id.pulse_btn_decline).setOnClickListener {
            PulseSipSdk.rejectCall()
            PulseCallNotifications.dismissIncoming(this)
            finish()
        }
    }

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            )
        }
    }
}

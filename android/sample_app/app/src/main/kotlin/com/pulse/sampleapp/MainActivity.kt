package com.pulse.sampleapp

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.pulse.sipsdk.PulseSipConfig
import com.pulse.sipsdk.PulseSipSdk
import com.pulse.sipsdk.PulseSipSdkListener
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Manual test harness for pulse_sip_android_sdk — exercises the exact public
 * API a real native-Android customer would use, against a real SIP server.
 * Not a polished app; just enough UI to drive register/call/accept/reject.
 */
class MainActivity : Activity(), PulseSipSdkListener {

    private lateinit var editWsUrl: EditText
    private lateinit var editSipUser: EditText
    private lateinit var editSipPassword: EditText
    private lateinit var editSipDomain: EditText
    private lateinit var editCallTarget: EditText
    private lateinit var textLog: TextView

    private var speakerOn = false
    private var muted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        editWsUrl = findViewById(R.id.edit_ws_url)
        editSipUser = findViewById(R.id.edit_sip_user)
        editSipPassword = findViewById(R.id.edit_sip_password)
        editSipDomain = findViewById(R.id.edit_sip_domain)
        editCallTarget = findViewById(R.id.edit_call_target)
        textLog = findViewById(R.id.text_log)

        requestRuntimePermissions()

        PulseSipSdk.setListener(this)

        findViewById<Button>(R.id.btn_register).setOnClickListener { onRegisterClicked() }
        findViewById<Button>(R.id.btn_call).setOnClickListener { onCallClicked() }
        findViewById<Button>(R.id.btn_accept).setOnClickListener {
            log("acceptCall()")
            PulseSipSdk.acceptCall { log("acceptCall result=$it") }
        }
        findViewById<Button>(R.id.btn_reject).setOnClickListener {
            log("rejectCall()")
            PulseSipSdk.rejectCall { log("rejectCall result=$it") }
        }
        findViewById<Button>(R.id.btn_hangup).setOnClickListener {
            log("hangUp()")
            PulseSipSdk.hangUp { log("hangUp result=$it") }
        }
        findViewById<Button>(R.id.btn_mute).setOnClickListener {
            muted = !muted
            PulseSipSdk.toggleMute()
            log("toggleMute() -> muted=$muted")
        }
        findViewById<Button>(R.id.btn_speaker).setOnClickListener {
            speakerOn = !speakerOn
            PulseSipSdk.setSpeakerOn(speakerOn)
            log("setSpeakerOn($speakerOn)")
        }
    }

    private fun onRegisterClicked() {
        val config = PulseSipConfig(
            webSocketUrl = editWsUrl.text.toString().trim(),
            sipUser = editSipUser.text.toString().trim(),
            sipPassword = editSipPassword.text.toString(),
            sipDomain = editSipDomain.text.toString().trim(),
        )
        log("register(webSocketUrl=${config.webSocketUrl}, sipUser=${config.sipUser}, sipDomain=${config.sipDomain})")
        PulseSipSdk.register(config) { success -> log("register() command result=$success") }
    }

    private fun onCallClicked() {
        val target = editCallTarget.text.toString().trim()
        if (target.isEmpty()) {
            log("Enter a number/extension to call first")
            return
        }
        log("makeCall($target)")
        PulseSipSdk.makeCall(target) { log("makeCall result=$it") }
    }

    private fun requestRuntimePermissions() {
        val needed = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            needed += Manifest.permission.RECORD_AUDIO
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            needed += Manifest.permission.POST_NOTIFICATIONS
        }
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), 1001)
        }
    }

    private fun log(message: String) {
        val ts = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())
        runOnUiThread {
            textLog.text = "[$ts] $message\n${textLog.text}"
        }
    }

    override fun onRegistrationChanged(registered: Boolean, message: String) {
        log("EVENT onRegistrationChanged(registered=$registered, message=$message)")
    }

    override fun onIncomingCall(callId: String?, callerName: String, callerNumber: String) {
        log("EVENT onIncomingCall(callId=$callId, callerName=$callerName, callerNumber=$callerNumber)")
    }

    override fun onCallStateChanged(callId: String?, state: String) {
        log("EVENT onCallStateChanged(callId=$callId, state=$state)")
    }

    override fun onCallEnded() {
        log("EVENT onCallEnded()")
    }
}

package com.pulse.sipsdk

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the process (and the embedded Flutter/SIP engine) alive while a call
 * is ringing or active, so Android doesn't kill it in the background.
 * [PulseSipSdk] starts/stops this automatically — host apps don't call it
 * directly.
 */
class PulseCallForegroundService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val label = intent?.getStringExtra(EXTRA_LABEL) ?: "Call in progress"
        val notification = PulseCallNotifications.buildOngoingCallNotification(this, label)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                PulseCallNotifications.ONGOING_NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
            )
        } else {
            startForeground(PulseCallNotifications.ONGOING_NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val EXTRA_LABEL = "label"

        fun start(context: Context, label: String = "Call in progress") {
            val intent = Intent(context, PulseCallForegroundService::class.java)
                .putExtra(EXTRA_LABEL, label)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PulseCallForegroundService::class.java))
        }
    }
}

package com.pulse.sipsdk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/** Builds/manages the two notification states a call SDK needs: ringing and ongoing. */
internal object PulseCallNotifications {
    private const val CHANNEL_ID = "pulse_sip_calls"
    const val ONGOING_NOTIFICATION_ID = 5501
    const val INCOMING_NOTIFICATION_ID = 5502

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming and ongoing SIP calls"
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    fun buildIncomingCallNotification(
        context: Context,
        callerName: String,
        callerNumber: String,
        fullScreenIntent: Intent,
    ): android.app.Notification {
        ensureChannel(context)
        val contentIntent = PendingIntent.getActivity(
            context,
            INCOMING_NOTIFICATION_ID,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(callerName)
            .setContentText(callerNumber)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(contentIntent, true)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(acceptAction(context))
            .addAction(declineAction(context))
            .build()
    }

    fun buildOngoingCallNotification(context: Context, label: String): android.app.Notification {
        ensureChannel(context)
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_outgoing)
            .setContentTitle(label)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .build()
    }

    fun dismissIncoming(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(INCOMING_NOTIFICATION_ID)
    }

    private fun acceptAction(context: Context): NotificationCompat.Action {
        val intent = Intent(context, CallActionReceiver::class.java).setAction(CallActionReceiver.ACTION_ACCEPT)
        val pending = PendingIntent.getBroadcast(
            context,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Action(0, "Accept", pending)
    }

    private fun declineAction(context: Context): NotificationCompat.Action {
        val intent = Intent(context, CallActionReceiver::class.java).setAction(CallActionReceiver.ACTION_DECLINE)
        val pending = PendingIntent.getBroadcast(
            context,
            2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Action(0, "Decline", pending)
    }
}

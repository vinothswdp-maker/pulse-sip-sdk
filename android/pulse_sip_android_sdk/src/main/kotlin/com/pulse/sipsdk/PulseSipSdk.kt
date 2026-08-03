package com.pulse.sipsdk

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Public native entry point for the SIP calling SDK. Internally embeds a
 * headless Flutter engine that runs the actual SIP registration/call logic
 * (pulse_sip_core, via the pulse_sip_bridge Dart entrypoint) — callers only
 * ever see this Kotlin API, never Flutter/Dart.
 */
object PulseSipSdk {
    private const val ENGINE_CACHE_KEY = "pulse_sip_engine"
    private const val COMMAND_CHANNEL = "com.pulse.sip_bridge/commands"
    private const val EVENT_CHANNEL = "com.pulse.sip_bridge/events"

    private var engine: FlutterEngine? = null
    private var commandChannel: MethodChannel? = null
    private var listener: PulseSipSdkListener? = null
    private var appContext: Context? = null
    private var lastConfig: PulseSipConfig? = null
    private var hasActiveOrRingingCall = false
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Call once, as early as possible (e.g. Application.onCreate), to warm up the engine. */
    fun initialize(context: Context) {
        appContext = context.applicationContext
        if (engine != null) return

        val cached = FlutterEngineCache.getInstance().get(ENGINE_CACHE_KEY)
        val flutterEngine = cached ?: FlutterEngine(context.applicationContext).also {
            it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            FlutterEngineCache.getInstance().put(ENGINE_CACHE_KEY, it)
        }
        engine = flutterEngine

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        commandChannel = MethodChannel(messenger, COMMAND_CHANNEL)
        MethodChannel(messenger, EVENT_CHANNEL).setMethodCallHandler(::handleEvent)
    }

    fun setListener(listener: PulseSipSdkListener?) {
        this.listener = listener
    }

    fun register(config: PulseSipConfig, force: Boolean = false, onResult: ((Boolean) -> Unit)? = null) {
        lastConfig = config
        invoke("register", config.toArgs(force), onResult)
    }

    fun unregister(onResult: ((Boolean) -> Unit)? = null) = invoke("unregister", null, onResult)

    fun makeCall(target: String, onResult: ((Boolean) -> Unit)? = null) = invoke("makeCall", target, onResult)

    fun acceptCall(onResult: ((Boolean) -> Unit)? = null) = invoke("acceptCall", null, onResult)

    fun rejectCall(onResult: ((Boolean) -> Unit)? = null) = invoke("rejectCall", null, onResult)

    fun hangUp(onResult: ((Boolean) -> Unit)? = null) = invoke("hangUp", null, onResult)

    fun mute() = invoke("mute", null, null)

    fun unmute() = invoke("unmute", null, null)

    fun toggleMute() = invoke("toggleMute", null, null)

    fun holdCall(enable: Boolean) = invoke("holdCall", enable, null)

    fun sendDTMF(digit: String) = invoke("sendDTMF", digit, null)

    fun setSpeakerOn(enable: Boolean) = invoke("setSpeakerOn", enable, null)

    fun toggleSpeaker() = invoke("toggleSpeaker", null, null)

    fun isRegistered(onResult: (Boolean) -> Unit) {
        commandChannel?.invokeMethod("isRegistered", null, object : MethodChannel.Result {
            override fun success(result: Any?) = onResult(result == true)
            override fun error(code: String, message: String?, details: Any?) = onResult(false)
            override fun notImplemented() = onResult(false)
        })
    }

    /**
     * Call this from your own FirebaseMessagingService.onMessageReceived (or equivalent) when a
     * data-only push arrives telling you a call may be coming. It wakes the engine, starts the
     * foreground service so the process survives, and re-registers if the connection had dropped
     * while the app was in the background/killed.
     */
    fun onPushReceived(context: Context, data: Map<String, String> = emptyMap()) {
        initialize(context)
        PulseCallForegroundService.start(context.applicationContext, "Incoming call…")
        lastConfig?.let { register(it) }
    }

    /** Releases the underlying Flutter engine. Only call this if the SDK is truly done being used. */
    fun dispose() {
        FlutterEngineCache.getInstance().remove(ENGINE_CACHE_KEY)
        engine?.destroy()
        engine = null
        commandChannel = null
        appContext?.let { PulseCallForegroundService.stop(it) }
    }

    private fun invoke(method: String, arguments: Any?, onResult: ((Boolean) -> Unit)?) {
        val channel = commandChannel
            ?: error("PulseSipSdk.initialize(context) must be called before use")
        channel.invokeMethod(method, arguments, object : MethodChannel.Result {
            override fun success(result: Any?) {
                onResult?.invoke(true)
            }

            override fun error(code: String, message: String?, details: Any?) {
                onResult?.invoke(false)
            }

            override fun notImplemented() {
                onResult?.invoke(false)
            }
        })
    }

    private fun handleEvent(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "onRegistrationChanged" -> listener?.onRegistrationChanged(
                args?.get("registered") == true,
                args?.get("message") as? String ?: "",
            )
            "onIncomingCall" -> {
                val callerName = args?.get("callerName") as? String ?: "Unknown"
                val callerNumber = args?.get("callerNumber") as? String ?: ""
                hasActiveOrRingingCall = true
                showIncomingCall(callerName, callerNumber)
                listener?.onIncomingCall(args?.get("callId") as? String, callerName, callerNumber)
            }
            "onCallStateChanged" -> {
                val state = args?.get("state") as? String ?: ""
                if (state.contains("CONFIRMED", ignoreCase = true) ||
                    state.contains("ACCEPTED", ignoreCase = true)
                ) {
                    appContext?.let {
                        PulseCallNotifications.dismissIncoming(it)
                        PulseCallForegroundService.start(it, "Call in progress")
                    }
                }
                listener?.onCallStateChanged(args?.get("callId") as? String, state)
            }
            "onCallEnded" -> {
                hasActiveOrRingingCall = false
                appContext?.let {
                    PulseCallNotifications.dismissIncoming(it)
                    PulseCallForegroundService.stop(it)
                }
                listener?.onCallEnded()
            }
        }
        result.success(null)
    }

    private fun showIncomingCall(callerName: String, callerNumber: String) {
        val context = appContext ?: return
        mainHandler.post {
            PulseCallForegroundService.start(context, "Incoming call…")

            val fullScreenIntent = Intent(context, IncomingCallActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(IncomingCallActivity.EXTRA_CALLER_NAME, callerName)
                putExtra(IncomingCallActivity.EXTRA_CALLER_NUMBER, callerNumber)
            }

            val notification = PulseCallNotifications.buildIncomingCallNotification(
                context,
                callerName,
                callerNumber,
                fullScreenIntent,
            )
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.notify(PulseCallNotifications.INCOMING_NOTIFICATION_ID, notification)
        }
    }
}

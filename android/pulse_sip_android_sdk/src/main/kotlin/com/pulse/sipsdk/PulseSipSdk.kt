package com.pulse.sipsdk

import android.content.Context
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

    /** Call once, as early as possible (e.g. Application.onCreate), to warm up the engine. */
    fun initialize(context: Context) {
        if (engine != null) return

        val cached = FlutterEngineCache.getInstance().get(ENGINE_CACHE_KEY)
        val flutterEngine = cached ?: FlutterEngine(context).also {
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

    fun isRegistered(onResult: (Boolean) -> Unit) {
        commandChannel?.invokeMethod("isRegistered", null, object : MethodChannel.Result {
            override fun success(result: Any?) = onResult(result == true)
            override fun error(code: String, message: String?, details: Any?) = onResult(false)
            override fun notImplemented() = onResult(false)
        })
    }

    /** Releases the underlying Flutter engine. Only call this if the SDK is truly done being used. */
    fun dispose() {
        FlutterEngineCache.getInstance().remove(ENGINE_CACHE_KEY)
        engine?.destroy()
        engine = null
        commandChannel = null
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
            "onIncomingCall" -> listener?.onIncomingCall(
                args?.get("callId") as? String,
                args?.get("callerName") as? String ?: "Unknown",
                args?.get("callerNumber") as? String ?: "",
            )
            "onCallStateChanged" -> listener?.onCallStateChanged(
                args?.get("callId") as? String,
                args?.get("state") as? String ?: "",
            )
            "onCallEnded" -> listener?.onCallEnded()
        }
        result.success(null)
    }
}

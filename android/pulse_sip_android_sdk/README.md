# pulse_sip_android_sdk

Native Android (Kotlin/Java) SDK for SIP registration and incoming/outgoing
calls. No Flutter knowledge needed to use it — internally it embeds a
headless Flutter engine that runs the actual SIP logic, but the only API
surface you touch is `PulseSipSdk` (plain Kotlin).

## What you need from us

Two artifacts, built from this repo:

1. `pulse_sip_android_sdk-release.aar` — this library
   (`android/pulse_sip_android_sdk/build/outputs/aar/`)
2. A local Maven repo folder containing the embedded Flutter engine + SIP
   plugin classes (`packages/pulse_sip_bridge/build/host/outputs/repo/`)

We hand you both together (as a zip, or hosted on a Maven server if you'd
rather add one dependency line instead of files).

## Gradle setup

Drop the `.aar` into your app module's `libs/` folder, and point Gradle at
the repo folder from artifact #2 (adjust the path to wherever you unpacked
it):

```gradle
// app/build.gradle
repositories {
    google()
    mavenCentral()
    maven { url "libs/pulse_sip_bridge_repo" }          // artifact #2, unpacked
    maven { url "https://storage.googleapis.com/download.flutter.io" }
    maven { url "https://jitpack.io" }                   // transitive: audioswitch
}

android {
    buildTypes {
        profile { initWith debug }   // required — Flutter ships 3 build-type variants
    }
}

dependencies {
    implementation files("libs/pulse_sip_android_sdk-release.aar")  // artifact #1

    debugImplementation   "com.pulse.pulse_sip_bridge:flutter_debug:1.0"
    profileImplementation "com.pulse.pulse_sip_bridge:flutter_profile:1.0"
    releaseImplementation "com.pulse.pulse_sip_bridge:flutter_release:1.0"
}
```

## Permissions

The AAR manifest already declares `INTERNET`, `RECORD_AUDIO`, and
`MODIFY_AUDIO_SETTINGS` (auto-merged into your app's manifest). You still
need to **request `RECORD_AUDIO` at runtime** yourself before calling
`register()` or making/answering a call — the SDK does not do this for you.

## Usage

```kotlin
class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Warm up the engine early so the first register()/makeCall() isn't slow.
        PulseSipSdk.initialize(this)
    }
}

class CallActivity : AppCompatActivity(), PulseSipSdkListener {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PulseSipSdk.setListener(this)

        val config = PulseSipConfig(
            webSocketUrl = "wss://sip.example.com:8089/ws",
            sipUser = "1001",
            sipPassword = "secret",
            sipDomain = "sip.example.com",
        )
        PulseSipSdk.register(config) { success ->
            // called back on the main thread
        }
    }

    fun call(number: String) = PulseSipSdk.makeCall(number)

    override fun onIncomingCall(callId: String?, callerName: String, callerNumber: String) {
        // Show your own incoming-call UI here, then:
        // PulseSipSdk.acceptCall()  or  PulseSipSdk.rejectCall()
    }

    override fun onRegistrationChanged(registered: Boolean, message: String) { /* ... */ }
    override fun onCallStateChanged(callId: String?, state: String) { /* ... */ }
    override fun onCallEnded() { /* ... */ }
}
```

## Not included yet

This SDK covers SIP registration and call control only. It does **not**
include a lockscreen/background incoming-call UI, a foreground service to
keep the app alive, or push-notification wake-up (FCM/APNs) — you're
responsible for those on the native side for now, or wait for the next SDK
module that adds them.

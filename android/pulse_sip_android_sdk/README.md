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

The AAR manifest already declares `INTERNET`, `RECORD_AUDIO`,
`MODIFY_AUDIO_SETTINGS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_PHONE_CALL`,
`MANAGE_OWN_CALLS`, `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT`, and
`WAKE_LOCK` (auto-merged into your app's manifest). You still need to
**request `RECORD_AUDIO` and `POST_NOTIFICATIONS` at runtime** yourself
before calling `register()` or making/answering a call — the SDK does not
do this for you.

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

### Speaker control

```kotlin
PulseSipSdk.setSpeakerOn(true)
PulseSipSdk.toggleSpeaker()
```

### Background calling (foreground service + lockscreen UI)

An incoming call now automatically:
1. Starts `PulseCallForegroundService` (keeps the process alive, `phoneCall`
   foreground-service type) so Android doesn't kill it in the background.
2. Posts a high-priority notification with Accept/Decline actions.
3. Fires a full-screen intent to `IncomingCallActivity` (a minimal built-in
   lockscreen call screen) when the device is locked — your app doesn't need
   its own Activity for this unless you want custom branding, in which case
   just handle `onIncomingCall` yourself and never launch `IncomingCallActivity`.

When you get a data-only push (FCM) that a call may be arriving (from your
own Firebase project — this SDK doesn't own your FCM setup), call:

```kotlin
// inside your own FirebaseMessagingService.onMessageReceived
PulseSipSdk.onPushReceived(applicationContext, remoteMessage.data)
```

This wakes the engine, starts the foreground service, and re-registers using
the last config you passed to `register()` — so the SIP connection is live
by the time the real INVITE arrives.

## Not included yet / not verified

- **Never tested against a real SIP server or on a physical device** — the
  code compiles and the AAR builds, but the actual call flow (register,
  ringing, audio) has not been run end-to-end yet. Verify this before
  shipping to any real user.
- No iOS equivalent (Android only, for now).
- No video calling (audio-only).
- No call transfer/merge/conference — single call (or one held + one active)
  only, by design (out of SDK scope).

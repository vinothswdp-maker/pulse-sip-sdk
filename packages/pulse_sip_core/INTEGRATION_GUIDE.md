# pulse_sip_core — Flutter Integration Guide

SIP registration + calling for Flutter apps: register, make/receive calls,
mute/hold/DTMF. This guide is everything you need to wire it into your app —
for the terse API reference see [README.md](README.md).

## 1. Install

Extract the zip you were given next to your app (as a sibling folder), then
add it as a path dependency in your `pubspec.yaml`:

```yaml
dependencies:
  pulse_sip_core:
    path: ../pulse_sip_core
```

Run `flutter pub get`.

## 2. Permissions

The plugin's Android manifest already declares `INTERNET`,
`ACCESS_NETWORK_STATE`, `RECORD_AUDIO`, and `MODIFY_AUDIO_SETTINGS` — these
merge into your app automatically, you don't need to add them to your own
manifest.

**`RECORD_AUDIO` is still a runtime ("dangerous") permission** — Android
requires you to explicitly request it before registering or calling, even
though it's declared in the manifest. Skipping this crashes the app the
instant a call starts (native `SIGABRT` inside WebRTC's network monitor).
Use a package like [`permission_handler`](https://pub.dev/packages/permission_handler):

```dart
import 'package:permission_handler/permission_handler.dart';

await Permission.microphone.request();
```

Request it once, early (e.g. on your login/home screen's `initState`),
before the first `registerAccount`/`registerWithCredentials` call.

iOS needs the usual `NSMicrophoneUsageDescription` entry in your own
`Info.plist` (the plugin can't add this for you — it's a user-facing string
only your app can word).

## 3. Create the engine

One instance, kept alive for the lifetime of your app (e.g. a singleton, or
held by whatever state-management approach you use):

```dart
import 'package:pulse_sip_core/pulse_sip_core.dart';

final sip = PulseSipCoreEngine();
```

## 4. Register

Two ways — pick whichever matches how your app already gets SIP credentials.

### 4a. Company code + username + password (recommended)

Logs in against the Pulse account backend (ConnectHub) with the same
account code / username / password your app already uses to log a person
in, and registers with whichever SIP extension that account resolves to —
**your app never needs to know a SIP domain or extension at all**.

```dart
try {
  await sip.registerWithCredentials(
    companyCode: 'PTPL',   // fixed per your app build — see note below
    username: email,        // whatever the person typed at login
    password: password,
  );
} catch (e) {
  print('Registration failed: $e'); // wrong credentials, network error, etc.
}
```

**About `companyCode`**: this SDK build is per-customer, so every person
using your app belongs to the same company — `companyCode` is a constant
you hardcode once (given to you along with the SDK), not something the end
user ever types or sees. Only `username`/`password` come from your app's
existing login screen.

**The single-login pattern**: call this right after your own app's login
succeeds, reusing the exact same username/password the person just typed —
don't show a second login screen. One login screen, one button, both your
app's session and SIP registration happen behind it:

```dart
Future<void> onLoginPressed() async {
  await yourExistingAppLoginApi(email, password);        // your app's login
  await sip.registerWithCredentials(                      // SIP, same values
    companyCode: kCompanyCode,
    username: email,
    password: password,
  );
  Navigator.pushReplacementNamed(context, '/home');
}
```

### 4b. Raw SIP credentials

If you already have `webSocketUrl`/`sipUser`/`sipPassword`/`sipDomain` from
your own source:

```dart
final config = PulseSipConfig(
  webSocketUrl: 'wss://sip.example.com:8089/ws',
  sipUser: '1001',
  sipPassword: 'secret',
  sipDomain: 'sip.example.com',
);

try {
  await sip.registerAccount(config);
} catch (e) {
  print('Registration failed: $e');
}
```

### Error handling (applies to both)

`registerAccount`/`registerWithCredentials` **throw** if registration
doesn't actually succeed — a timeout (10s) or the server rejecting it both
throw, they never silently report success. Always wrap the call in
`try`/`catch`. For the *live* registered/unregistered state afterwards
(e.g. the connection drops later), use:

```dart
sip.addRegistrationListener((registered, message) {
  print('Registered: $registered ($message)');
});
```

## 5. Make an outgoing call

```dart
await sip.makeCall('1002'); // bare extension/number — domain comes from registration
```

## 6. Handle an incoming call

```dart
sip.addIncomingCallListener((call, callerName, callerNumber) {
  // Show your own incoming-call UI here, then:
  sip.acceptCall(call);   // or:
  sip.rejectCall();
});
```

## 7. During a call

```dart
await sip.hangUp();

sip.mute();
sip.unmute();
sip.toggleMute();

await sip.holdCall(true);   // or sip.hold()
await sip.holdCall(false);  // or sip.unhold()
await sip.toggleHold();

await sip.sendDTMF('5');

await sip.setSpeakerOn(true);
await sip.toggleSpeaker();
```

Live state as a call progresses:

```dart
sip.addCallStateListener((call, state) {
  print('Call state: ${state.state}'); // ringing, confirmed, ended, ...
});
sip.addCallEndedListener(() {
  print('Call ended');
});
```

Useful getters at any point: `sip.isRegistered`, `sip.isConnected`,
`sip.hasActiveCall`, `sip.isMuted`, `sip.isOnHold`, `sip.isSpeakerOn`,
`sip.currentCall`.

## 8. What's out of scope

- **App killed / backgrounded**: this package is pure Dart/Flutter logic —
  when your app's process is killed, nothing survives, including the SIP
  connection. Receiving calls while killed requires native Android/iOS
  work on your end (a foreground service + a push (FCM/APNs) wake-up that
  re-calls `registerWithCredentials`) — this SDK doesn't include that
  wiring. Ask us if you need this built.
- **Video, conferencing, call transfer**: audio-only, single active call
  (plus one held), by design.
- **Contacts, call history**: app-specific concerns, left to you — wire
  them up from the listener callbacks above.

## 9. Minimal end-to-end example

```dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pulse_sip_core/pulse_sip_core.dart';

const kCompanyCode = 'PTPL'; // fixed for your app build

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final sip = PulseSipCoreEngine();
  String status = 'Not registered';

  @override
  void initState() {
    super.initState();
    Permission.microphone.request();
    sip.addRegistrationListener((registered, message) {
      setState(() => status = registered ? 'Registered' : 'Failed: $message');
    });
    sip.addIncomingCallListener((call, name, number) {
      sip.acceptCall(call); // or show UI first, then acceptCall/rejectCall
    });
  }

  Future<void> register(String email, String password) async {
    try {
      await sip.registerWithCredentials(
        companyCode: kCompanyCode,
        username: email,
        password: password,
      );
    } catch (e) {
      setState(() => status = 'Registration failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(status));
}
```

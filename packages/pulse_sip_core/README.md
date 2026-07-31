# pulse_sip_core

Core SIP registration + incoming/outgoing call engine, extracted for reuse as
an SDK. Built on `sip_ua` + `flutter_webrtc`.

## Scope

This package deliberately covers **only** SIP registration and basic call
control:

- `connect()` / `registerAccount()` / `unregister()`
- `makeCall()` / `acceptCall()` / `rejectCall()` / `hangUp()`
- `mute()` / `unmute()` / `holdCall()` / `sendDTMF()`
- Listener callbacks for registration state, incoming calls, call state,
  and call-ended events

It intentionally does **not** include conferencing, contact lookups, call
history logging, or any native background-service/push-wiring — those are
app-specific concerns. A host app wires them up via the listener callbacks.

## Usage

```dart
final sip = PulseSipCoreEngine();

sip.addRegistrationListener((registered, message) {
  print('Registered: $registered ($message)');
});
sip.addIncomingCallListener((call, callerName, callerNumber) {
  // show your own incoming-call UI, then call sip.acceptCall() / rejectCall()
});

final config = PulseSipConfig(
  webSocketUrl: 'wss://sip.example.com:8089/ws',
  sipUser: '1001',
  sipPassword: 'secret',
  sipDomain: 'sip.example.com',
);

await sip.registerAccount(config);
await sip.makeCall('1002');
```

## Status

Flutter/Dart core only, verified with `flutter analyze` (no issues). Not yet
wired to a native Android/iOS call-UI or background-service layer — that is
a separate wrapper step (see project notes).

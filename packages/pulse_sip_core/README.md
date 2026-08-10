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

try {
  await sip.registerAccount(config);
} catch (e) {
  print('Registration failed: $e'); // e.g. timed out, or the server rejected it
}
await sip.makeCall('1002');
```

`registerAccount`/`registerWithCredentials` throw if registration doesn't
actually succeed (timeout, or the SIP server rejects it) — always wrap the
call, and also use `addRegistrationListener` for the live registered/
unregistered state afterwards (e.g. after a network drop).

### Registering with company code + username + password (no SIP domain either)

If you'd rather not hand the app a raw SIP domain/extension, `registerWithCredentials`
logs in against the Pulse account backend (ConnectHub) with the same account
code/username/password used to log into the Pulse platform, and registers
with whichever SIP extension/proxy that account resolves to — the app never
needs to know a SIP domain or extension:

```dart
await sip.registerWithCredentials(
  companyCode: 'PTPL',
  username: 'Vinoth',
  password: 'Pulse@123',
);
```

## Status

Flutter/Dart core only, verified with `flutter analyze` (no issues). Not yet
wired to a native Android/iOS call-UI or background-service layer — that is
a separate wrapper step (see project notes).

# Pulse SIP SDK

SIP registration + incoming/outgoing calling, packaged for two kinds of
customers from one codebase:

```
pulse-sip-sdk/
├── packages/
│   ├── pulse_sip_core/     Flutter plugin — the actual SIP logic (sip_ua + flutter_webrtc)
│   └── pulse_sip_bridge/   Flutter module — embeds pulse_sip_core, built as an Android AAR
└── android/
    └── pulse_sip_android_sdk/   Kotlin library for native Android apps — see its README
```

## Which one do I need?

- **Building a Flutter app?** Depend on `packages/pulse_sip_core` directly
  (git + path dependency, or a local path dependency if you're in this repo).
  See [`packages/pulse_sip_core/README.md`](packages/pulse_sip_core/README.md).
- **Building a native Android app (Kotlin/Java, no Flutter)?** Use
  `android/pulse_sip_android_sdk` — see
  [`android/pulse_sip_android_sdk/README.md`](android/pulse_sip_android_sdk/README.md)
  for the full integration guide.

## Why two Flutter projects (`pulse_sip_core` + `pulse_sip_bridge`)?

Flutter's tooling only lets you build a distributable Android AAR from a
**module**-type project, not a **plugin**-type project — so the actual SIP
logic lives once in `pulse_sip_core` (a plugin, consumable directly by
Flutter apps), and `pulse_sip_bridge` is a thin module that depends on it
purely so it can be compiled into an AAR for native Android apps. There is
no duplicated logic — `pulse_sip_bridge/lib/main.dart` just re-exposes
`pulse_sip_core`'s engine over a MethodChannel.

## Scope

Registration, connect/disconnect, make/accept/reject/hangup, mute, hold,
DTMF. No conferencing, no contacts, no call history, no background-service/
push wiring yet — those are left to the host app, or to a future SDK module.

/// Configuration required to connect and register a SIP account.
///
/// This holds only generic SIP/WebRTC settings — no app-specific fields
/// (no contacts, no login models, no campaign/conference data). Host apps
/// build this from whatever credential source they use.
class PulseSipConfig {
  /// SIP signaling WebSocket URL, e.g. wss://sip.example.com:8089/ws
  final String webSocketUrl;

  /// SIP extension / auth user (the part before '@' in the SIP URI).
  final String sipUser;

  final String sipPassword;

  /// Domain or server IP used to build the SIP URI (sip:user@domain).
  final String sipDomain;

  final String? displayName;

  /// Stable per-device instance id (used by some servers for push-aware
  /// registration). If null, the engine generates and persists one.
  final String? instanceId;

  final List<Map<String, String>> iceServers;

  /// Extra Contact URI params used for push-notification-aware registration,
  /// e.g. pn-provider=fcm, pn-param=sender-id, pn-prid=token.
  /// Leave empty if the host app doesn't need push-triggered incoming calls.
  final Map<String, String> pushContactParams;

  final List<String> extraRegisterHeaders;

  final int registerExpiresSeconds;

  final String userAgent;

  /// Whether to accept a self-signed/invalid TLS certificate on the
  /// signaling WebSocket. Defaults to false (secure) — only set true for a
  /// server you control during development, never in production.
  final bool allowBadCertificate;

  const PulseSipConfig({
    required this.webSocketUrl,
    required this.sipUser,
    required this.sipPassword,
    required this.sipDomain,
    this.displayName,
    this.instanceId,
    this.iceServers = const [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    this.pushContactParams = const {},
    this.extraRegisterHeaders = const [],
    this.registerExpiresSeconds = 2592000,
    this.userAgent = 'PulseSipCore/1.0',
    this.allowBadCertificate = false,
  });
}

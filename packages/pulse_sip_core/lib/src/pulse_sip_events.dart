import 'package:sip_ua/sip_ua.dart';

/// Fired whenever registration state changes.
typedef PulseRegistrationListener =
    void Function(bool registered, String message);

/// Fired when a new inbound INVITE arrives.
typedef PulseIncomingCallListener =
    void Function(Call call, String callerName, String callerNumber);

/// Fired whenever the active call ends (either side), for any reason.
typedef PulseCallEndedListener = void Function();

/// Fired on every SIP call state transition (ringing, connected, ended...).
typedef PulseCallStateListener = void Function(Call call, CallState state);

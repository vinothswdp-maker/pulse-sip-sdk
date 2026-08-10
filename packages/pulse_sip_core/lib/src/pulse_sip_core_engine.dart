import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:uuid/uuid.dart';

import 'pulse_remote_config.dart';
import 'pulse_sip_config.dart';
import 'pulse_sip_events.dart';

/// Core SIP registration + incoming/outgoing call engine.
///
/// Scope is intentionally limited to what a calling SDK needs: connect,
/// register/unregister, make/accept/reject/hangup a call, mute/hold/DTMF,
/// and state callbacks. It has no knowledge of contacts, conferencing,
/// call history, or any specific host app — those are the host app's
/// responsibility, wired up through the listener callbacks below.
class PulseSipCoreEngine extends ChangeNotifier implements SipUaHelperListener {
  PulseSipCoreEngine() {
    _helper.addSipUaHelperListener(this);
  }

  final SIPUAHelper _helper = SIPUAHelper();

  PulseSipConfig? _config;
  String? _instanceId;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isRegistered = false;
  bool _isRegistering = false;
  bool _isIntentionalDisconnect = false;

  Call? _currentCall;
  bool _isMuted = false;
  bool _isOnHold = false;
  bool _isSpeakerOn = false;

  Completer<void>? _connectCompleter;
  Completer<void>? _registerCompleter;
  Timer? _registrationMonitor;

  final List<PulseRegistrationListener> _registrationListeners = [];
  final List<PulseIncomingCallListener> _incomingCallListeners = [];
  final List<PulseCallEndedListener> _callEndedListeners = [];
  final List<PulseCallStateListener> _callStateListeners = [];

  bool get isConnected => _isConnected;
  bool get isRegistered => _isRegistered;
  bool get isMuted => _isMuted;
  bool get isOnHold => _isOnHold;
  bool get isSpeakerOn => _isSpeakerOn;
  Call? get currentCall => _currentCall;
  bool get hasActiveCall => _currentCall != null;

  void addRegistrationListener(PulseRegistrationListener listener) =>
      _registrationListeners.add(listener);
  void removeRegistrationListener(PulseRegistrationListener listener) =>
      _registrationListeners.remove(listener);

  void addIncomingCallListener(PulseIncomingCallListener listener) =>
      _incomingCallListeners.add(listener);
  void removeIncomingCallListener(PulseIncomingCallListener listener) =>
      _incomingCallListeners.remove(listener);

  void addCallEndedListener(PulseCallEndedListener listener) =>
      _callEndedListeners.add(listener);
  void removeCallEndedListener(PulseCallEndedListener listener) =>
      _callEndedListeners.remove(listener);

  void addCallStateListener(PulseCallStateListener listener) =>
      _callStateListeners.add(listener);
  void removeCallStateListener(PulseCallStateListener listener) =>
      _callStateListeners.remove(listener);

  Future<void> _ensureInstanceId() async {
    if (_instanceId != null) return;
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('pulse_sip_instance_id');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString('pulse_sip_instance_id', id);
    }
    _instanceId = id;
  }

  UaSettings _buildSettings(PulseSipConfig config) {
    final s = UaSettings();
    s.webSocketUrl = config.webSocketUrl;
    s.instanceId = config.instanceId ?? _instanceId;
    s.webSocketSettings = WebSocketSettings()
      ..allowBadCertificate = config.allowBadCertificate
      ..userAgent = config.userAgent;

    s.uri = 'sip:${config.sipUser}@${config.sipDomain}';
    s.authorizationUser = config.sipUser;
    s.password = config.sipPassword;
    s.displayName = config.displayName ?? config.sipUser;
    s.userAgent = config.userAgent;
    s.transportType = TransportType.WS;
    s.sessionTimers = false;
    s.iceServers = config.iceServers;
    s.dtmfMode = DtmfMode.RFC2833;

    if (config.pushContactParams.isNotEmpty) {
      s.registerParams.extraContactUriParams = config.pushContactParams;
    }
    if (config.extraRegisterHeaders.isNotEmpty) {
      s.registerParams.extraHeaders = config.extraRegisterHeaders;
    }
    s.register_expires = config.registerExpiresSeconds;
    return s;
  }

  /// Opens the SIP WebSocket transport. Call [registerAccount] afterwards
  /// (or just call [registerAccount] directly — it connects for you).
  Future<void> connect(PulseSipConfig config, {bool force = false}) async {
    _config = config;
    _isIntentionalDisconnect = false;

    if (!force && _isConnected) return;
    if (_isConnecting) return;
    _isConnecting = true;

    await _ensureInstanceId();

    try {
      _connectCompleter?.completeError('cancelled');
      _connectCompleter = Completer<void>();

      await _helper.start(_buildSettings(config));

      await _connectCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
    } catch (e) {
      _isConnecting = false;
      if (e.toString() != 'cancelled') rethrow;
    } finally {
      _connectCompleter = null;
      _isConnecting = false;
    }
  }

  /// Connects (if needed) and sends REGISTER. Safe to call repeatedly.
  Future<void> registerAccount(
    PulseSipConfig config, {
    bool force = false,
  }) async {
    if (_isIntentionalDisconnect) return;

    if (force && (_isRegistered || _isConnected)) {
      _helper.register();
      return;
    }

    if (!force && (_isRegistered || _isRegistering)) return;

    _isRegistering = true;
    try {
      if (!_isConnected) {
        await connect(config, force: force);
      }
      if (_isConnected) {
        _helper.register();
      }
    } finally {
      _isRegistering = false;
    }

    if (!_isRegistered) {
      _registerCompleter?.completeError('cancelled');
      _registerCompleter = Completer<void>();
      try {
        await _registerCompleter!.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError(
            'SIP registration timed out after 10s — check network/proxy reachability',
          ),
        );
      } catch (e) {
        // 'cancelled' means a newer registerAccount() call superseded this one —
        // not a failure of this call, so it stays silent (matches connect()'s
        // handling of the same signal). Anything else (timeout, or the SIP
        // server explicitly rejecting registration) is a real failure and must
        // propagate — silently swallowing it here would let callers believe
        // registration succeeded when it didn't.
        if (e.toString() != 'cancelled') rethrow;
      } finally {
        _registerCompleter = null;
      }
    }
    _startRegistrationMonitor(config);
  }

  /// Logs in with [companyCode]/[username]/[password] (your Pulse account
  /// code, username, and password) and registers with the SIP extension/
  /// proxy the login resolves to — your app never needs to know a SIP
  /// domain or extension, only the same three values used to log in.
  Future<void> registerWithCredentials({
    required String companyCode,
    required String username,
    required String password,
    bool force = false,
  }) async {
    final config = await PulseRemoteConfig.authenticate(
      companyCode: companyCode,
      username: username,
      password: password,
    );
    await registerAccount(config, force: force);
  }

  Future<void> unregister({bool all = true, bool quick = false}) async {
    if (!_isConnected) return;
    _registrationMonitor?.cancel();
    _registrationMonitor = null;
    _helper.unregister(all);
    _isRegistered = false;
    await Future.delayed(
      quick ? const Duration(milliseconds: 200) : const Duration(seconds: 1),
    );
  }

  void _startRegistrationMonitor(PulseSipConfig config) {
    _registrationMonitor?.cancel();
    _registrationMonitor = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isIntentionalDisconnect &&
          !_isRegistered &&
          _currentCall == null &&
          !_isRegistering &&
          !_isConnecting) {
        registerAccount(config);
      }
    });
  }

  void stopRegistrationMonitor() {
    _registrationMonitor?.cancel();
    _registrationMonitor = null;
  }

  Map<String, dynamic> _callOptions() {
    return {
      'mediaConstraints': {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      },
      'pcConfig': {
        'iceServers': _config?.iceServers ?? const [],
        'iceTransportPolicy': 'all',
        'iceCandidatePoolSize': 10,
      },
    };
  }

  /// Places an outgoing call to [target] (a bare extension/number — the SDK
  /// builds the full sip:target@domain URI from the active config's domain).
  Future<void> makeCall(String target) async {
    final config = _config;
    if (!_isRegistered || config == null) {
      throw StateError('SIP not registered — call registerAccount() first');
    }
    if (_currentCall != null) {
      throw StateError('A call is already active');
    }
    final uri = 'sip:$target@${config.sipDomain}';
    await _helper.call(uri, voiceOnly: true, customOptions: _callOptions());
  }

  /// Answers the currently ringing call ([call] optional if there's exactly
  /// one call already tracked by the engine).
  Future<void> acceptCall([Call? call]) async {
    if (call != null) _currentCall = call;
    final active = _currentCall;
    if (active == null) {
      throw StateError('No incoming call to accept');
    }
    active.answer(_callOptions());
  }

  Future<void> rejectCall() async {
    final call = _currentCall;
    try {
      call?.hangup({'status_code': 486});
    } finally {
      _currentCall = null;
      notifyListeners();
    }
  }

  Future<void> hangUp() async {
    final call = _currentCall;
    try {
      call?.hangup();
    } finally {
      _currentCall = null;
      _isMuted = false;
      _isOnHold = false;
      notifyListeners();
      for (final l in List<PulseCallEndedListener>.from(_callEndedListeners)) {
        l();
      }
    }
  }

  void mute() {
    _currentCall?.mute(true, false);
    _isMuted = true;
    notifyListeners();
  }

  void unmute() {
    _currentCall?.unmute(true, false);
    _isMuted = false;
    notifyListeners();
  }

  void toggleMute() => _isMuted ? unmute() : mute();

  Future<void> setSpeakerOn(bool enable) async {
    try {
      await Helper.setSpeakerphoneOn(enable);
      _isSpeakerOn = enable;
      notifyListeners();
    } catch (e) {
      debugPrint('PulseSipCoreEngine.setSpeakerOn failed: $e');
    }
  }

  Future<void> toggleSpeaker() => setSpeakerOn(!_isSpeakerOn);

  Future<void> holdCall(bool enable) async {
    final call = _currentCall;
    if (call == null) return;
    try {
      if (enable) {
        call.hold();
        _isOnHold = true;
      } else {
        call.unhold();
        _isOnHold = false;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('PulseSipCoreEngine.holdCall failed: $e');
    }
  }

  Future<void> hold() => holdCall(true);

  Future<void> unhold() => holdCall(false);

  Future<void> toggleHold() => holdCall(!_isOnHold);

  Future<void> sendDTMF(String digit) async {
    _currentCall?.sendDTMF(digit);
  }

  void disconnect() {
    _isIntentionalDisconnect = true;
    stopRegistrationMonitor();
    _helper.stop();
    _isConnected = false;
    _isRegistered = false;
    notifyListeners();
  }

  @override
  void callStateChanged(Call call, CallState state) {
    if (_currentCall == null || _currentCall == call) {
      _currentCall = call;
    }
    notifyListeners();

    final isIncoming =
        call.direction?.toString().toLowerCase().contains('incoming') ??
            false;
    if (isIncoming &&
        (state.state == CallStateEnum.CALL_INITIATION ||
            state.state == CallStateEnum.PROGRESS)) {
      final number = call.remote_identity ?? 'Unknown';
      final name = call.remote_display_name ?? number;
      for (final l in List<PulseIncomingCallListener>.from(
        _incomingCallListeners,
      )) {
        l(call, name, number);
      }
    }

    if (state.state == CallStateEnum.ENDED ||
        state.state == CallStateEnum.FAILED) {
      _currentCall = null;
      _isMuted = false;
      _isOnHold = false;
      for (final l in List<PulseCallEndedListener>.from(_callEndedListeners)) {
        l();
      }
      notifyListeners();
    }

    for (final l in List<PulseCallStateListener>.from(_callStateListeners)) {
      l(call, state);
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    if (state.state == RegistrationStateEnum.REGISTERED) {
      _isRegistered = true;
      if (_registerCompleter != null && !_registerCompleter!.isCompleted) {
        _registerCompleter!.complete();
      }
      for (final l in List<PulseRegistrationListener>.from(
        _registrationListeners,
      )) {
        l(true, 'Registered');
      }
    } else {
      _isRegistered = false;
      if (_registerCompleter != null && !_registerCompleter!.isCompleted) {
        _registerCompleter!.completeError(
          'registration_failed: ${state.state}',
        );
      }
      for (final l in List<PulseRegistrationListener>.from(
        _registrationListeners,
      )) {
        l(false, state.state.toString());
      }
    }
    notifyListeners();
  }

  @override
  void transportStateChanged(TransportState state) {
    if (state.state == TransportStateEnum.CONNECTED) {
      _isConnected = true;
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.complete();
      }
      if (!_isRegistered && !_isRegistering && _config != null) {
        registerAccount(_config!);
      }
    } else if (state.state == TransportStateEnum.DISCONNECTED) {
      _isConnected = false;
      _isRegistered = false;
      if (!_isIntentionalDisconnect &&
          _currentCall == null &&
          !_isConnecting &&
          !_isRegistering &&
          _config != null) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isIntentionalDisconnect &&
              !_isConnected &&
              _currentCall == null &&
              _config != null) {
            registerAccount(_config!);
          }
        });
      }
    }
    notifyListeners();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}
}

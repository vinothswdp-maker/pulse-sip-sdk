import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse_sip_core/pulse_sip_core.dart';

/// Headless entrypoint embedded into a native Android/iOS host app.
///
/// The host runs this Dart entrypoint inside a `FlutterEngine` with no
/// visible UI attached and drives [PulseSipCoreEngine] purely through the
/// two MethodChannels below — the native side never touches Dart directly.
const MethodChannel _commandChannel = MethodChannel(
  'com.pulse.sip_bridge/commands',
);
const MethodChannel _eventChannel = MethodChannel('com.pulse.sip_bridge/events');

PulseSipCoreEngine? _engine;
PulseSipConfig? _lastConfig;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _bootstrapSipBridge();
  runApp(const _BridgeStatusApp());
}

void _bootstrapSipBridge() {
  final engine = PulseSipCoreEngine();
  _engine = engine;

  engine.addRegistrationListener((registered, message) {
    _eventChannel.invokeMethod('onRegistrationChanged', {
      'registered': registered,
      'message': message,
    });
  });

  engine.addIncomingCallListener((call, callerName, callerNumber) {
    _eventChannel.invokeMethod('onIncomingCall', {
      'callId': call.id,
      'callerName': callerName,
      'callerNumber': callerNumber,
    });
  });

  engine.addCallStateListener((call, state) {
    _eventChannel.invokeMethod('onCallStateChanged', {
      'callId': call.id,
      'state': state.state.toString(),
    });
  });

  engine.addCallEndedListener(() {
    _eventChannel.invokeMethod('onCallEnded', {});
  });

  _commandChannel.setMethodCallHandler(_handleCommand);
}

PulseSipConfig _configFromMap(Map<dynamic, dynamic> args) {
  return PulseSipConfig(
    webSocketUrl: args['webSocketUrl'] as String,
    sipUser: args['sipUser'] as String,
    sipPassword: args['sipPassword'] as String,
    sipDomain: args['sipDomain'] as String,
    displayName: args['displayName'] as String?,
    pushContactParams:
        (args['pushContactParams'] as Map?)?.cast<String, String>() ??
        const {},
    allowBadCertificate: args['allowBadCertificate'] == true,
  );
}

Future<dynamic> _handleCommand(MethodCall call) async {
  final engine = _engine;
  if (engine == null) throw StateError('Bridge engine not initialized');

  switch (call.method) {
    case 'register':
      final args = call.arguments as Map;
      _lastConfig = _configFromMap(args);
      await engine.registerAccount(
        _lastConfig!,
        force: args['force'] == true,
      );
      return null;
    case 'unregister':
      await engine.unregister();
      return null;
    case 'makeCall':
      await engine.makeCall(call.arguments as String);
      return null;
    case 'acceptCall':
      await engine.acceptCall();
      return null;
    case 'rejectCall':
      await engine.rejectCall();
      return null;
    case 'hangUp':
      await engine.hangUp();
      return null;
    case 'mute':
      engine.mute();
      return null;
    case 'unmute':
      engine.unmute();
      return null;
    case 'toggleMute':
      engine.toggleMute();
      return null;
    case 'holdCall':
      await engine.holdCall(call.arguments as bool);
      return null;
    case 'sendDTMF':
      await engine.sendDTMF(call.arguments as String);
      return null;
    case 'setSpeakerOn':
      await engine.setSpeakerOn(call.arguments as bool);
      return null;
    case 'toggleSpeaker':
      await engine.toggleSpeaker();
      return null;
    case 'isRegistered':
      return engine.isRegistered;
    case 'isConnected':
      return engine.isConnected;
    default:
      throw MissingPluginException('Unknown method: ${call.method}');
  }
}

/// Minimal visible app used only when running this module standalone
/// (`flutter run`) for local testing. The embedded/native usage path never
/// shows this — the host app supplies its own UI.
class _BridgeStatusApp extends StatelessWidget {
  const _BridgeStatusApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('pulse_sip_bridge running headless')),
      ),
    );
  }
}

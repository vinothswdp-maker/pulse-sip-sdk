import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pulse_sip_core/pulse_sip_core.dart';

/// Manual test harness for pulse_sip_core — exercises the exact public API a
/// real Flutter customer would use, against a real SIP server. Not a
/// polished app; just enough UI to drive register/call/accept/reject.
void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _sip = PulseSipCoreEngine();
  final _navigatorKey = GlobalKey<NavigatorState>();

  final _companyCodeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _callTargetController = TextEditingController();

  final _log = <String>[];
  bool _muted = false;
  bool _speakerOn = false;

  @override
  void initState() {
    super.initState();
    _requestRuntimePermissions();

    _sip.addRegistrationListener((registered, message) {
      _addLog('EVENT onRegistrationChanged(registered=$registered, message=$message)');
      _showResultDialog(
        registered ? 'Registered ✅' : 'Registration failed ❌',
        message,
      );
    });
    _sip.addIncomingCallListener((call, callerName, callerNumber) {
      _addLog('EVENT onIncomingCall(callerName=$callerName, callerNumber=$callerNumber)');
    });
    _sip.addCallStateListener((call, state) {
      _addLog('EVENT onCallStateChanged(state=${state.state})');
    });
    _sip.addCallEndedListener(() {
      _addLog('EVENT onCallEnded()');
    });
  }

  Future<void> _requestRuntimePermissions() async {
    await [Permission.microphone, Permission.notification].request();
  }

  void _addLog(String message) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final ts = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    setState(() {
      _log.insert(0, '[$ts] $message');
    });
  }

  void _showResultDialog(String title, String message) {
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) return;
    showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _onRegisterWithCredentialsPressed() async {
    final companyCode = _companyCodeController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    _addLog('registerWithCredentials(companyCode=$companyCode, username=$username)');
    try {
      await _sip.registerWithCredentials(
        companyCode: companyCode,
        username: username,
        password: password,
      );
      _addLog('registerWithCredentials() succeeded');
    } catch (e) {
      _addLog('registerWithCredentials() FAILED: $e');
      _showResultDialog('Login/registration failed ❌', '$e');
    }
  }

  Future<void> _onCallPressed() async {
    final target = _callTargetController.text.trim();
    if (target.isEmpty) {
      _addLog('Enter a number/extension to call first');
      return;
    }
    _addLog('makeCall($target)');
    try {
      await _sip.makeCall(target);
    } catch (e) {
      _addLog('makeCall() FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      home: Scaffold(
        appBar: AppBar(title: const Text('pulse_sip_core test harness')),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _companyCodeController,
                decoration: const InputDecoration(labelText: 'Company code'),
              ),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _onRegisterWithCredentialsPressed,
                child: const Text('Register (company code + username + password)'),
              ),
              const Divider(height: 24),
              TextField(
                controller: _callTargetController,
                decoration: const InputDecoration(labelText: 'Call target (number/extension)'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(onPressed: _onCallPressed, child: const Text('Call')),
                  ElevatedButton(
                    onPressed: () async {
                      _addLog('acceptCall()');
                      try {
                        await _sip.acceptCall();
                      } catch (e) {
                        _addLog('acceptCall() FAILED: $e');
                      }
                    },
                    child: const Text('Accept'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      _addLog('rejectCall()');
                      await _sip.rejectCall();
                    },
                    child: const Text('Reject'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      _addLog('hangUp()');
                      await _sip.hangUp();
                    },
                    child: const Text('Hangup'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      _sip.toggleMute();
                      setState(() => _muted = !_muted);
                      _addLog('toggleMute() -> muted=$_muted');
                    },
                    child: const Text('Toggle mute'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      _speakerOn = !_speakerOn;
                      await _sip.setSpeakerOn(_speakerOn);
                      _addLog('setSpeakerOn($_speakerOn)');
                      setState(() {});
                    },
                    child: const Text('Toggle speaker'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await _sip.toggleHold();
                      _addLog('toggleHold() -> onHold=${_sip.isOnHold}');
                      setState(() {});
                    },
                    child: const Text('Toggle hold'),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (context, index) => Text(
                    _log[index],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sip.disconnect();
    super.dispose();
  }
}

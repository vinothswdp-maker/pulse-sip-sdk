import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pulse_sip_core_platform_interface.dart';

/// An implementation of [PulseSipCorePlatform] that uses method channels.
class MethodChannelPulseSipCore extends PulseSipCorePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('pulse_sip_core');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}

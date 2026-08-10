import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'pulse_sip_core_method_channel.dart';

abstract class PulseSipCorePlatform extends PlatformInterface {
  /// Constructs a PulseSipCorePlatform.
  PulseSipCorePlatform() : super(token: _token);

  static final Object _token = Object();

  static PulseSipCorePlatform _instance = MethodChannelPulseSipCore();

  /// The default instance of [PulseSipCorePlatform] to use.
  ///
  /// Defaults to [MethodChannelPulseSipCore].
  static PulseSipCorePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PulseSipCorePlatform] when
  /// they register themselves.
  static set instance(PulseSipCorePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}

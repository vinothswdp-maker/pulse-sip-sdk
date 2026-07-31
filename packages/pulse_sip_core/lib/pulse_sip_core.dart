import 'pulse_sip_core_platform_interface.dart';

export 'src/pulse_sip_config.dart';
export 'src/pulse_sip_events.dart';
export 'src/pulse_sip_core_engine.dart';

class PulseSipCore {
  Future<String?> getPlatformVersion() {
    return PulseSipCorePlatform.instance.getPlatformVersion();
  }
}

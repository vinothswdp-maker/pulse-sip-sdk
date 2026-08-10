import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_sip_core/pulse_sip_core.dart';
import 'package:pulse_sip_core/pulse_sip_core_platform_interface.dart';
import 'package:pulse_sip_core/pulse_sip_core_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPulseSipCorePlatform
    with MockPlatformInterfaceMixin
    implements PulseSipCorePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final PulseSipCorePlatform initialPlatform = PulseSipCorePlatform.instance;

  test('$MethodChannelPulseSipCore is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelPulseSipCore>());
  });

  test('getPlatformVersion', () async {
    PulseSipCore pulseSipCorePlugin = PulseSipCore();
    MockPulseSipCorePlatform fakePlatform = MockPulseSipCorePlatform();
    PulseSipCorePlatform.instance = fakePlatform;

    expect(await pulseSipCorePlugin.getPlatformVersion(), '42');
  });
}

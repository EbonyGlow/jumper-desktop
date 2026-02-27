import 'package:flutter_test/flutter_test.dart';
import 'package:jumper_sdk_platform/jumper_sdk_platform.dart';
import 'package:jumper_sdk_platform/jumper_sdk_platform_platform_interface.dart';
import 'package:jumper_sdk_platform/jumper_sdk_platform_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockJumperSdkPlatformPlatform
    with MockPlatformInterfaceMixin
    implements JumperSdkPlatformPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<Map<String, Object?>> getCoreState() async => <String, Object?>{'status': 'running'};

  @override
  Future<void> restartCore({
    String? reason,
    Map<String, Object?>? launchOptions,
    String? networkMode,
  }) async {}

  @override
  Future<void> startCore({
    required String profileId,
    Map<String, Object?>? launchOptions,
    String? networkMode,
  }) async {}

  @override
  Future<void> stopCore() async {}

  @override
  Stream<Map<String, Object?>> watchCoreEvents() => const Stream.empty();

  @override
  Stream<Map<String, Object?>> watchKernelLogs() => const Stream.empty();

  @override
  Future<Map<String, Object?>> inspectRuntime({
    required String version,
    required String platformArch,
    String? basePath,
  }) async => <String, Object?>{'ready': true};

  @override
  Future<Map<String, Object?>> setupRuntime({
    required String version,
    required String platformArch,
    String? basePath,
  }) async => <String, Object?>{'installed': true};

  @override
  Future<void> enableSystemProxy({
    required String host,
    required int port,
  }) async {}

  @override
  Future<void> disableSystemProxy() async {}

  @override
  Future<Map<String, Object?>> getSystemProxyStatus() async => <String, Object?>{
    'enabled': false,
  };

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<bool> getNotificationPermissionStatus() async => true;

  @override
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> showTray({
    required String title,
    String? tooltip,
  }) async {}

  @override
  Future<void> updateTray({
    required String title,
    String? tooltip,
  }) async {}

  @override
  Future<void> hideTray() async {}

  @override
  Future<Map<String, Object?>> getTrayStatus() async => <String, Object?>{
    'visible': false,
  };

  @override
  Future<void> resetTunnel() async {}

  @override
  Future<Map<String, Object?>> getPlatformCapabilities() async => <String, Object?>{
    'tunnelSupported': true,
    'systemProxySupported': true,
    'notifySupported': true,
    'traySupported': true,
  };
}

void main() {
  final JumperSdkPlatformPlatform initialPlatform = JumperSdkPlatformPlatform.instance;

  test('$MethodChannelJumperSdkPlatform is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelJumperSdkPlatform>());
  });

  test('getPlatformVersion', () async {
    JumperSdkPlatform jumperSdkPlatformPlugin = JumperSdkPlatform();
    MockJumperSdkPlatformPlatform fakePlatform = MockJumperSdkPlatformPlatform();
    JumperSdkPlatformPlatform.instance = fakePlatform;

    expect(await jumperSdkPlatformPlugin.getPlatformVersion(), '42');
  });
}

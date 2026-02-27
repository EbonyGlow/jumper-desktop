import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jumper_sdk/jumper_sdk.dart';
import 'package:jumper_sdk_platform/jumper_sdk_platform.dart';

class _FakePlatform extends JumperSdkPlatform {
  String? enabledHost;
  int? enabledPort;
  bool disabledCalled = false;

  @override
  Future<void> enableSystemProxy({
    required String host,
    required int port,
  }) async {
    enabledHost = host;
    enabledPort = port;
  }

  @override
  Future<void> disableSystemProxy() async {
    disabledCalled = true;
  }

  @override
  Future<Map<String, Object?>> getSystemProxyStatus() async {
    return <String, Object?>{
      'enabled': true,
      'host': '127.0.0.1',
      'port': 7890,
    };
  }

  bool permissionGranted = true;
  String? notificationTitle;
  String? notificationBody;
  bool trayVisible = false;
  String? trayTitle;
  String? trayTooltip;
  bool resetTunnelCalled = false;
  String? startedNetworkMode;

  @override
  Future<bool> requestNotificationPermission() async => permissionGranted;

  @override
  Future<bool> getNotificationPermissionStatus() async => permissionGranted;

  @override
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    notificationTitle = title;
    notificationBody = body;
  }

  @override
  Future<void> showTray({
    required String title,
    String? tooltip,
  }) async {
    trayVisible = true;
    trayTitle = title;
    trayTooltip = tooltip;
  }

  @override
  Future<void> updateTray({
    required String title,
    String? tooltip,
  }) async {
    trayTitle = title;
    trayTooltip = tooltip;
  }

  @override
  Future<void> hideTray() async {
    trayVisible = false;
  }

  @override
  Future<Map<String, Object?>> getTrayStatus() async {
    return <String, Object?>{
      'visible': trayVisible,
      'title': trayTitle ?? '',
    };
  }

  @override
  Future<void> resetTunnel() async {
    resetTunnelCalled = true;
  }

  @override
  Future<void> startCore({
    required String profileId,
    Map<String, Object?>? launchOptions,
    String? networkMode,
  }) async {
    startedNetworkMode = networkMode;
  }

  @override
  Future<Map<String, Object?>> getPlatformCapabilities() async {
    return <String, Object?>{
      'tunnelSupported': true,
      'systemProxySupported': true,
      'notifySupported': true,
      'traySupported': true,
    };
  }
}

void main() {
  test('exposes sdk client', () {
    final sdk = JumperSdkClient();
    expect(sdk, isA<KernelRuntimeService>());
    expect(sdk, isA<TunnelCapability>());
  });

  test('runtime bootstrap writes config and returns launch options', () async {
    final tempDir = await Directory.systemTemp.createTemp('jumper-sdk-test-');
    try {
      final launchOptions = await JumperRuntimeBootstrap.prepareLaunchOptions(
        appBasePath: tempDir.path,
        config: <String, Object?>{
          'log': <String, Object?>{'level': 'info'},
        },
      );

      expect(File(launchOptions.arguments[3]).existsSync(), isTrue);
      expect(launchOptions.arguments.first, 'run');
      expect(launchOptions.binaryPath.contains('sing-box'), isTrue);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('system proxy capability delegates to platform', () async {
    final fake = _FakePlatform();
    final sdk = JumperSdkClient(platform: fake);

    await sdk.enableProxy(host: '127.0.0.1', port: 7890);
    expect(fake.enabledHost, '127.0.0.1');
    expect(fake.enabledPort, 7890);

    final status = await sdk.status();
    expect(status.enabled, isTrue);
    expect(status.host, '127.0.0.1');
    expect(status.port, 7890);

    await sdk.disableProxy();
    expect(fake.disabledCalled, isTrue);
  });

  test('notify capability delegates to platform', () async {
    final fake = _FakePlatform();
    final sdk = JumperSdkClient(platform: fake);

    final requested = await sdk.requestPermission();
    final status = await sdk.permissionStatus();
    await sdk.sendNotification(title: 'Jumper', body: 'Runtime started');

    expect(requested, isTrue);
    expect(status, isTrue);
    expect(fake.notificationTitle, 'Jumper');
    expect(fake.notificationBody, 'Runtime started');
  });

  test('tray capability delegates to platform', () async {
    final fake = _FakePlatform();
    final sdk = JumperSdkClient(platform: fake);

    await sdk.showTray(title: 'Jumper', tooltip: 'Ready');
    expect(fake.trayVisible, isTrue);
    expect(fake.trayTitle, 'Jumper');

    await sdk.updateTray(title: 'Jumper*', tooltip: 'Running');
    expect(fake.trayTitle, 'Jumper*');
    expect(fake.trayTooltip, 'Running');

    final trayStatus = await sdk.trayStatus();
    expect(trayStatus.visible, isTrue);
    expect(trayStatus.title, 'Jumper*');

    await sdk.hideTray();
    expect(fake.trayVisible, isFalse);
  });

  test('tunnel capability defaults to tunnel network mode', () async {
    final fake = _FakePlatform();
    final sdk = JumperSdkClient(platform: fake);

    await sdk.startCore(profileId: 'default');
    expect(fake.startedNetworkMode, 'tunnel');
  });

  test('tunnel reset delegates to platform', () async {
    final fake = _FakePlatform();
    final sdk = JumperSdkClient(platform: fake);

    await sdk.resetTunnel();
    expect(fake.resetTunnelCalled, isTrue);
  });

  test('capability guard blocks disabled system proxy', () async {
    final fake = _FakePlatform();
    final sdk = JumperSdkClient(
      platform: fake,
      capabilities: const SdkCapabilitiesConfig(
        allowSystemProxyCapability: false,
      ),
    );

    expect(
      () => sdk.enableProxy(host: '127.0.0.1', port: 7890),
      throwsA(isA<JumperSdkException>()),
    );
  });

  test('capability discovery delegates to platform', () async {
    final fake = _FakePlatform();
    final sdk = JumperSdkClient(platform: fake);
    final capabilities = await sdk.getCapabilities();

    expect(capabilities.tunnelSupported, isTrue);
    expect(capabilities.systemProxySupported, isTrue);
    expect(capabilities.notifySupported, isTrue);
    expect(capabilities.traySupported, isTrue);
  });
}

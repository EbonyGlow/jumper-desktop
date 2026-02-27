import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumper_sdk_platform/jumper_sdk_platform_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelJumperSdkPlatform platform = MethodChannelJumperSdkPlatform();
  const MethodChannel channel = MethodChannel('jumper_sdk_platform');
  MethodCall? lastCall;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          lastCall = methodCall;
          if (methodCall.method == 'getSystemProxyStatus') {
            return <String, Object?>{
              'enabled': true,
              'host': '127.0.0.1',
              'port': 7890,
            };
          }
          if (methodCall.method == 'requestNotificationPermission') {
            return true;
          }
          if (methodCall.method == 'getNotificationPermissionStatus') {
            return true;
          }
          if (methodCall.method == 'getTrayStatus') {
            return <String, Object?>{
              'visible': true,
              'title': 'Jumper',
            };
          }
          if (methodCall.method == 'getPlatformCapabilities') {
            return <String, Object?>{
              'tunnelSupported': true,
              'systemProxySupported': false,
              'notifySupported': false,
              'traySupported': false,
            };
          }
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('enableSystemProxy sends payload', () async {
    await platform.enableSystemProxy(host: '127.0.0.1', port: 7890);
    expect(lastCall?.method, 'enableSystemProxy');
    expect(lastCall?.arguments, <String, Object?>{'host': '127.0.0.1', 'port': 7890});
  });

  test('startCore sends network mode', () async {
    await platform.startCore(
      profileId: 'default',
      launchOptions: const <String, Object?>{'binaryPath': '/tmp/sing-box'},
      networkMode: 'tunnel',
    );
    expect(lastCall?.method, 'startCore');
    expect(lastCall?.arguments, <String, Object?>{
      'profileId': 'default',
      'launchOptions': <String, Object?>{'binaryPath': '/tmp/sing-box'},
      'networkMode': 'tunnel',
    });
  });

  test('disableSystemProxy calls method', () async {
    await platform.disableSystemProxy();
    expect(lastCall?.method, 'disableSystemProxy');
  });

  test('getSystemProxyStatus parses map', () async {
    final status = await platform.getSystemProxyStatus();
    expect(lastCall?.method, 'getSystemProxyStatus');
    expect(status['enabled'], true);
    expect(status['host'], '127.0.0.1');
    expect(status['port'], 7890);
  });

  test('requestNotificationPermission returns bool', () async {
    final granted = await platform.requestNotificationPermission();
    expect(lastCall?.method, 'requestNotificationPermission');
    expect(granted, isTrue);
  });

  test('getNotificationPermissionStatus returns bool', () async {
    final granted = await platform.getNotificationPermissionStatus();
    expect(lastCall?.method, 'getNotificationPermissionStatus');
    expect(granted, isTrue);
  });

  test('showNotification sends payload', () async {
    await platform.showNotification(title: 'hello', body: 'world');
    expect(lastCall?.method, 'showNotification');
    expect(lastCall?.arguments, <String, Object?>{'title': 'hello', 'body': 'world'});
  });

  test('showTray sends payload', () async {
    await platform.showTray(title: 'Jumper', tooltip: 'Runtime ready');
    expect(lastCall?.method, 'showTray');
    expect(lastCall?.arguments, <String, Object?>{
      'title': 'Jumper',
      'tooltip': 'Runtime ready',
    });
  });

  test('updateTray sends payload', () async {
    await platform.updateTray(title: 'Jumper*', tooltip: 'Running');
    expect(lastCall?.method, 'updateTray');
    expect(lastCall?.arguments, <String, Object?>{
      'title': 'Jumper*',
      'tooltip': 'Running',
    });
  });

  test('hideTray calls method', () async {
    await platform.hideTray();
    expect(lastCall?.method, 'hideTray');
  });

  test('getTrayStatus parses map', () async {
    final status = await platform.getTrayStatus();
    expect(lastCall?.method, 'getTrayStatus');
    expect(status['visible'], true);
    expect(status['title'], 'Jumper');
  });

  test('resetTunnel calls method', () async {
    await platform.resetTunnel();
    expect(lastCall?.method, 'resetTunnel');
  });

  test('getPlatformCapabilities parses map', () async {
    final capabilities = await platform.getPlatformCapabilities();
    expect(lastCall?.method, 'getPlatformCapabilities');
    expect(capabilities['tunnelSupported'], true);
    expect(capabilities['systemProxySupported'], false);
    expect(capabilities['notifySupported'], false);
    expect(capabilities['traySupported'], false);
  });
}

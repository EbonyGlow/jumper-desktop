import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'jumper_sdk_platform_platform_interface.dart';

/// An implementation of [JumperSdkPlatformPlatform] that uses method channels.
class MethodChannelJumperSdkPlatform extends JumperSdkPlatformPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('jumper_sdk_platform');
  final _coreEventsChannel = const EventChannel('jumper_sdk_platform/core_events');
  final _kernelLogsChannel = const EventChannel('jumper_sdk_platform/kernel_logs');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<void> startCore({
    required String profileId,
    Map<String, Object?>? launchOptions,
    String? networkMode,
  }) async {
    final payload = <String, Object?>{
      'profileId': profileId,
      'launchOptions': launchOptions,
      'networkMode': networkMode,
    };
    await methodChannel.invokeMethod<void>('startCore', payload);
  }

  @override
  Future<void> stopCore() async {
    await methodChannel.invokeMethod<void>('stopCore');
  }

  @override
  Future<void> restartCore({
    String? reason,
    Map<String, Object?>? launchOptions,
    String? networkMode,
  }) async {
    final payload = <String, Object?>{
      'reason': reason,
      'launchOptions': launchOptions,
      'networkMode': networkMode,
    };
    await methodChannel.invokeMethod<void>('restartCore', payload);
  }

  @override
  Future<Map<String, Object?>> getCoreState() async {
    final result = await methodChannel.invokeMapMethod<String, Object?>('getCoreState');
    return result ?? <String, Object?>{'status': 'stopped'};
  }

  @override
  Stream<Map<String, Object?>> watchCoreEvents() {
    return _coreEventsChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .cast<Map>()
        .map((event) => event.cast<String, Object?>());
  }

  @override
  Stream<Map<String, Object?>> watchKernelLogs() {
    return _kernelLogsChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .cast<Map>()
        .map((event) => event.cast<String, Object?>());
  }

  @override
  Future<Map<String, Object?>> setupRuntime({
    required String version,
    required String platformArch,
    String? basePath,
  }) async {
    final payload = <String, Object?>{
      'version': version,
      'platformArch': platformArch,
      'basePath': basePath,
    };
    final result = await methodChannel.invokeMapMethod<String, Object?>(
      'setupRuntime',
      payload,
    );
    return result ?? <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> inspectRuntime({
    required String version,
    required String platformArch,
    String? basePath,
  }) async {
    final payload = <String, Object?>{
      'version': version,
      'platformArch': platformArch,
      'basePath': basePath,
    };
    final result = await methodChannel.invokeMapMethod<String, Object?>(
      'inspectRuntime',
      payload,
    );
    return result ?? <String, Object?>{};
  }

  @override
  Future<void> enableSystemProxy({
    required String host,
    required int port,
  }) async {
    final payload = <String, Object?>{
      'host': host,
      'port': port,
    };
    await methodChannel.invokeMethod<void>('enableSystemProxy', payload);
  }

  @override
  Future<void> disableSystemProxy() async {
    await methodChannel.invokeMethod<void>('disableSystemProxy');
  }

  @override
  Future<Map<String, Object?>> getSystemProxyStatus() async {
    final result = await methodChannel.invokeMapMethod<String, Object?>(
      'getSystemProxyStatus',
    );
    return result ?? <String, Object?>{'enabled': false};
  }

  @override
  Future<bool> requestNotificationPermission() async {
    final result = await methodChannel.invokeMethod<bool>(
      'requestNotificationPermission',
    );
    return result ?? false;
  }

  @override
  Future<bool> getNotificationPermissionStatus() async {
    final result = await methodChannel.invokeMethod<bool>(
      'getNotificationPermissionStatus',
    );
    return result ?? false;
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    final payload = <String, Object?>{
      'title': title,
      'body': body,
    };
    await methodChannel.invokeMethod<void>('showNotification', payload);
  }

  @override
  Future<void> showTray({
    required String title,
    String? tooltip,
  }) async {
    final payload = <String, Object?>{
      'title': title,
      'tooltip': tooltip,
    };
    await methodChannel.invokeMethod<void>('showTray', payload);
  }

  @override
  Future<void> updateTray({
    required String title,
    String? tooltip,
  }) async {
    final payload = <String, Object?>{
      'title': title,
      'tooltip': tooltip,
    };
    await methodChannel.invokeMethod<void>('updateTray', payload);
  }

  @override
  Future<void> hideTray() async {
    await methodChannel.invokeMethod<void>('hideTray');
  }

  @override
  Future<Map<String, Object?>> getTrayStatus() async {
    final result = await methodChannel.invokeMapMethod<String, Object?>(
      'getTrayStatus',
    );
    return result ?? <String, Object?>{'visible': false};
  }

  @override
  Future<void> resetTunnel() async {
    await methodChannel.invokeMethod<void>('resetTunnel');
  }

  @override
  Future<Map<String, Object?>> getPlatformCapabilities() async {
    final result = await methodChannel.invokeMapMethod<String, Object?>(
      'getPlatformCapabilities',
    );
    return result ??
        <String, Object?>{
          'tunnelSupported': false,
          'systemProxySupported': false,
          'notifySupported': false,
          'traySupported': false,
        };
  }
}

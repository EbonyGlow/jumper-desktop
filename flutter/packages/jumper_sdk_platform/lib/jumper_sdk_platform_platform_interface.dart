import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'jumper_sdk_platform_method_channel.dart';

abstract class JumperSdkPlatformPlatform extends PlatformInterface {
  /// Constructs a JumperSdkPlatformPlatform.
  JumperSdkPlatformPlatform() : super(token: _token);

  static final Object _token = Object();

  static JumperSdkPlatformPlatform _instance = MethodChannelJumperSdkPlatform();

  /// The default instance of [JumperSdkPlatformPlatform] to use.
  ///
  /// Defaults to [MethodChannelJumperSdkPlatform].
  static JumperSdkPlatformPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [JumperSdkPlatformPlatform] when
  /// they register themselves.
  static set instance(JumperSdkPlatformPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> startCore({
    required String profileId,
    Map<String, Object?>? launchOptions,
    String? networkMode,
  }) {
    throw UnimplementedError('startCore() has not been implemented.');
  }

  Future<void> stopCore() {
    throw UnimplementedError('stopCore() has not been implemented.');
  }

  Future<void> restartCore({
    String? reason,
    Map<String, Object?>? launchOptions,
    String? networkMode,
  }) {
    throw UnimplementedError('restartCore() has not been implemented.');
  }

  Future<Map<String, Object?>> getCoreState() {
    throw UnimplementedError('getCoreState() has not been implemented.');
  }

  Stream<Map<String, Object?>> watchCoreEvents() {
    throw UnimplementedError('watchCoreEvents() has not been implemented.');
  }

  Stream<Map<String, Object?>> watchKernelLogs() {
    throw UnimplementedError('watchKernelLogs() has not been implemented.');
  }

  Future<Map<String, Object?>> setupRuntime({
    required String version,
    required String platformArch,
    String? basePath,
  }) {
    throw UnimplementedError('setupRuntime() has not been implemented.');
  }

  Future<Map<String, Object?>> inspectRuntime({
    required String version,
    required String platformArch,
    String? basePath,
  }) {
    throw UnimplementedError('inspectRuntime() has not been implemented.');
  }

  Future<void> enableSystemProxy({
    required String host,
    required int port,
  }) {
    throw UnimplementedError('enableSystemProxy() has not been implemented.');
  }

  Future<void> disableSystemProxy() {
    throw UnimplementedError('disableSystemProxy() has not been implemented.');
  }

  Future<Map<String, Object?>> getSystemProxyStatus() {
    throw UnimplementedError('getSystemProxyStatus() has not been implemented.');
  }

  Future<bool> requestNotificationPermission() {
    throw UnimplementedError('requestNotificationPermission() has not been implemented.');
  }

  Future<bool> getNotificationPermissionStatus() {
    throw UnimplementedError('getNotificationPermissionStatus() has not been implemented.');
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) {
    throw UnimplementedError('showNotification() has not been implemented.');
  }

  Future<void> showTray({
    required String title,
    String? tooltip,
  }) {
    throw UnimplementedError('showTray() has not been implemented.');
  }

  Future<void> updateTray({
    required String title,
    String? tooltip,
  }) {
    throw UnimplementedError('updateTray() has not been implemented.');
  }

  Future<void> hideTray() {
    throw UnimplementedError('hideTray() has not been implemented.');
  }

  Future<Map<String, Object?>> getTrayStatus() {
    throw UnimplementedError('getTrayStatus() has not been implemented.');
  }

  Future<void> resetTunnel() {
    throw UnimplementedError('resetTunnel() has not been implemented.');
  }

  Future<Map<String, Object?>> getPlatformCapabilities() {
    throw UnimplementedError('getPlatformCapabilities() has not been implemented.');
  }
}

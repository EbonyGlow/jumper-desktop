
import 'jumper_sdk_platform_platform_interface.dart';

class JumperSdkPlatform {
  Future<String?> getPlatformVersion() {
    return JumperSdkPlatformPlatform.instance.getPlatformVersion();
  }

  Future<void> startCore({
    required String profileId,
    Map<String, Object?>? launchOptions,
    String? networkMode,
  }) {
    return JumperSdkPlatformPlatform.instance.startCore(
      profileId: profileId,
      launchOptions: launchOptions,
      networkMode: networkMode,
    );
  }

  Future<void> stopCore() {
    return JumperSdkPlatformPlatform.instance.stopCore();
  }

  Future<void> restartCore({
    String? reason,
    Map<String, Object?>? launchOptions,
    String? networkMode,
  }) {
    return JumperSdkPlatformPlatform.instance.restartCore(
      reason: reason,
      launchOptions: launchOptions,
      networkMode: networkMode,
    );
  }

  Future<Map<String, Object?>> getCoreState() {
    return JumperSdkPlatformPlatform.instance.getCoreState();
  }

  Stream<Map<String, Object?>> watchCoreEvents() {
    return JumperSdkPlatformPlatform.instance.watchCoreEvents();
  }

  Stream<Map<String, Object?>> watchKernelLogs() {
    return JumperSdkPlatformPlatform.instance.watchKernelLogs();
  }

  Future<Map<String, Object?>> setupRuntime({
    required String version,
    required String platformArch,
    String? basePath,
  }) {
    return JumperSdkPlatformPlatform.instance.setupRuntime(
      version: version,
      platformArch: platformArch,
      basePath: basePath,
    );
  }

  Future<Map<String, Object?>> inspectRuntime({
    required String version,
    required String platformArch,
    String? basePath,
  }) {
    return JumperSdkPlatformPlatform.instance.inspectRuntime(
      version: version,
      platformArch: platformArch,
      basePath: basePath,
    );
  }

  Future<void> enableSystemProxy({
    required String host,
    required int port,
  }) {
    return JumperSdkPlatformPlatform.instance.enableSystemProxy(
      host: host,
      port: port,
    );
  }

  Future<void> disableSystemProxy() {
    return JumperSdkPlatformPlatform.instance.disableSystemProxy();
  }

  Future<Map<String, Object?>> getSystemProxyStatus() {
    return JumperSdkPlatformPlatform.instance.getSystemProxyStatus();
  }

  Future<bool> requestNotificationPermission() {
    return JumperSdkPlatformPlatform.instance.requestNotificationPermission();
  }

  Future<bool> getNotificationPermissionStatus() {
    return JumperSdkPlatformPlatform.instance.getNotificationPermissionStatus();
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) {
    return JumperSdkPlatformPlatform.instance.showNotification(
      title: title,
      body: body,
    );
  }

  Future<void> showTray({
    required String title,
    String? tooltip,
  }) {
    return JumperSdkPlatformPlatform.instance.showTray(
      title: title,
      tooltip: tooltip,
    );
  }

  Future<void> updateTray({
    required String title,
    String? tooltip,
  }) {
    return JumperSdkPlatformPlatform.instance.updateTray(
      title: title,
      tooltip: tooltip,
    );
  }

  Future<void> hideTray() {
    return JumperSdkPlatformPlatform.instance.hideTray();
  }

  Future<Map<String, Object?>> getTrayStatus() {
    return JumperSdkPlatformPlatform.instance.getTrayStatus();
  }

  Future<void> resetTunnel() {
    return JumperSdkPlatformPlatform.instance.resetTunnel();
  }

  Future<Map<String, Object?>> getPlatformCapabilities() {
    return JumperSdkPlatformPlatform.instance.getPlatformCapabilities();
  }
}

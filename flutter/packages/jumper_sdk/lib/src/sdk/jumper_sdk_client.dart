import 'dart:convert';
import 'dart:io';

import 'package:jumper_sdk_platform/jumper_sdk_platform.dart';

import '../contracts/services.dart';
import '../models/sdk_models.dart';

class JumperSdkClient
    implements
        KernelRuntimeService,
        CoreApiClient,
        SystemProxyCapability,
        NotifyCapability,
        TrayCapability,
        TunnelCapability,
        CapabilityDiscovery {
  JumperSdkClient({
    JumperSdkPlatform? platform,
    Uri? coreApiBaseUri,
    String? coreApiSecret,
    JumperRuntimeLaunchOptions? runtimeLaunchOptions,
    SdkCapabilitiesConfig capabilities = const SdkCapabilitiesConfig(),
  }) : _platform = platform ?? JumperSdkPlatform(),
       _coreApiBaseUri = coreApiBaseUri ?? Uri.parse('http://127.0.0.1:20123'),
       _coreApiSecret = coreApiSecret,
       _runtimeLaunchOptions = runtimeLaunchOptions,
       _capabilities = capabilities;

  final JumperSdkPlatform _platform;
  final Uri _coreApiBaseUri;
  final String? _coreApiSecret;
  final JumperRuntimeLaunchOptions? _runtimeLaunchOptions;
  final SdkCapabilitiesConfig _capabilities;

  @override
  Future<CoreState> getState() async {
    final state = await _platform.getCoreState();
    return CoreState.fromMap(state);
  }

  @override
  Future<void> restartCore({String? reason}) {
    _ensureNetworkModeSupported();
    return _platform.restartCore(
      reason: reason,
      launchOptions: _buildLaunchOptions(),
      networkMode: _capabilities.networkMode.name,
    );
  }

  @override
  Future<void> startCore({required String profileId}) {
    _ensureNetworkModeSupported();
    return _platform.startCore(
      profileId: profileId,
      launchOptions: _buildLaunchOptions(),
      networkMode: _capabilities.networkMode.name,
    );
  }

  @override
  Future<void> stopCore() {
    return _platform.stopCore();
  }

  @override
  Stream<CoreEvent> watchCoreEvents() {
    return _platform.watchCoreEvents().map(CoreEvent.fromMap);
  }

  @override
  Stream<KernelLogEvent> watchLogs() {
    return _platform.watchKernelLogs().map((event) {
      return KernelLogEvent(
        level: (event['level'] as String?) ?? 'info',
        message: (event['message'] as String?) ?? '',
        timestampMs:
            (event['timestampMs'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      );
    });
  }

  @override
  Future<void> closeAllConnections() async {
    await _requestJson(method: 'DELETE', path: '/connections');
  }

  @override
  Future<void> closeConnection({required String id}) async {
    await _requestJson(method: 'DELETE', path: '/connections/$id');
  }

  @override
  Future<CoreConfigs> getConfigs() async {
    final payload = await _requestJson(method: 'GET', path: '/configs');
    return CoreConfigs(config: payload);
  }

  @override
  Future<ConnectionsSnapshot> getConnections() async {
    final payload = await _requestJson(method: 'GET', path: '/connections');
    final rawConnections = payload['connections'];
    if (rawConnections is List) {
      final list = rawConnections
          .whereType<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList();
      return ConnectionsSnapshot(connections: list);
    }
    return const ConnectionsSnapshot(connections: <Map<String, Object?>>[]);
  }

  @override
  Future<ProxiesSnapshot> getProxies() async {
    final payload = await _requestJson(method: 'GET', path: '/proxies');
    final raw = payload['proxies'];
    if (raw is Map) {
      return ProxiesSnapshot(groups: raw.cast<String, Object?>());
    }
    return const ProxiesSnapshot(groups: <String, Object?>{});
  }

  @override
  Future<void> setConfigs(CoreConfigs configs) async {
    await _requestJson(method: 'PATCH', path: '/configs', body: configs.config);
  }

  @override
  Future<void> useProxy({required String group, required String proxy}) async {
    await _requestJson(
      method: 'PUT',
      path: '/proxies/$group',
      body: <String, Object?>{'name': proxy},
    );
  }

  @override
  Stream<ConnectionsSnapshot> watchConnections() {
    return const Stream<ConnectionsSnapshot>.empty();
  }

  @override
  Stream<MemoryStatEvent> watchMemory() {
    return const Stream<MemoryStatEvent>.empty();
  }

  @override
  Stream<TrafficStatEvent> watchTraffic() {
    return const Stream<TrafficStatEvent>.empty();
  }

  Future<Map<String, Object?>> setupRuntime({
    required String version,
    required String platformArch,
    String? basePath,
  }) {
    return _platform.setupRuntime(
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
    return _platform.inspectRuntime(
      version: version,
      platformArch: platformArch,
      basePath: basePath,
    );
  }

  @override
  Future<void> enableProxy({required String host, required int port}) {
    _ensureCapability(
      enabled: _capabilities.allowSystemProxyCapability,
      code: 'SDK-CAPABILITY-SYSTEM-PROXY-DISABLED',
      message: 'System proxy capability is disabled by SDK configuration',
    );
    return _platform.enableSystemProxy(host: host, port: port);
  }

  @override
  Future<void> disableProxy() {
    _ensureCapability(
      enabled: _capabilities.allowSystemProxyCapability,
      code: 'SDK-CAPABILITY-SYSTEM-PROXY-DISABLED',
      message: 'System proxy capability is disabled by SDK configuration',
    );
    return _platform.disableSystemProxy();
  }

  @override
  Future<SystemProxyStatus> status() async {
    _ensureCapability(
      enabled: _capabilities.allowSystemProxyCapability,
      code: 'SDK-CAPABILITY-SYSTEM-PROXY-DISABLED',
      message: 'System proxy capability is disabled by SDK configuration',
    );
    final map = await _platform.getSystemProxyStatus();
    return SystemProxyStatus.fromMap(map);
  }

  @override
  Future<bool> requestPermission() {
    _ensureCapability(
      enabled: _capabilities.allowNotifyCapability,
      code: 'SDK-CAPABILITY-NOTIFY-DISABLED',
      message: 'Notification capability is disabled by SDK configuration',
    );
    return _platform.requestNotificationPermission();
  }

  @override
  Future<bool> permissionStatus() {
    _ensureCapability(
      enabled: _capabilities.allowNotifyCapability,
      code: 'SDK-CAPABILITY-NOTIFY-DISABLED',
      message: 'Notification capability is disabled by SDK configuration',
    );
    return _platform.getNotificationPermissionStatus();
  }

  @override
  Future<void> sendNotification({
    required String title,
    required String body,
  }) {
    _ensureCapability(
      enabled: _capabilities.allowNotifyCapability,
      code: 'SDK-CAPABILITY-NOTIFY-DISABLED',
      message: 'Notification capability is disabled by SDK configuration',
    );
    return _platform.showNotification(title: title, body: body);
  }

  @override
  Future<void> showTray({
    required String title,
    String? tooltip,
  }) {
    _ensureCapability(
      enabled: _capabilities.allowTrayCapability,
      code: 'SDK-CAPABILITY-TRAY-DISABLED',
      message: 'Tray capability is disabled by SDK configuration',
    );
    return _platform.showTray(title: title, tooltip: tooltip);
  }

  @override
  Future<void> updateTray({
    required String title,
    String? tooltip,
  }) {
    _ensureCapability(
      enabled: _capabilities.allowTrayCapability,
      code: 'SDK-CAPABILITY-TRAY-DISABLED',
      message: 'Tray capability is disabled by SDK configuration',
    );
    return _platform.updateTray(title: title, tooltip: tooltip);
  }

  @override
  Future<void> hideTray() {
    _ensureCapability(
      enabled: _capabilities.allowTrayCapability,
      code: 'SDK-CAPABILITY-TRAY-DISABLED',
      message: 'Tray capability is disabled by SDK configuration',
    );
    return _platform.hideTray();
  }

  @override
  Future<TrayStatus> trayStatus() async {
    _ensureCapability(
      enabled: _capabilities.allowTrayCapability,
      code: 'SDK-CAPABILITY-TRAY-DISABLED',
      message: 'Tray capability is disabled by SDK configuration',
    );
    final map = await _platform.getTrayStatus();
    return TrayStatus.fromMap(map);
  }

  @override
  Future<void> enableTunnel({
    String stack = 'mixed',
    String? device,
  }) async {
    _ensureCapability(
      enabled: _capabilities.allowTunnelCapability,
      code: 'SDK-CAPABILITY-TUNNEL-DISABLED',
      message: 'Tunnel capability is disabled by SDK configuration',
    );
    final tunPatch = <String, Object?>{
      'enable': true,
      'stack': stack,
    };
    if (device != null) {
      tunPatch['device'] = device;
    }
    await _requestJson(
      method: 'PATCH',
      path: '/configs',
      body: <String, Object?>{
        'tun': tunPatch,
      },
    );
  }

  @override
  Future<void> disableTunnel() async {
    _ensureCapability(
      enabled: _capabilities.allowTunnelCapability,
      code: 'SDK-CAPABILITY-TUNNEL-DISABLED',
      message: 'Tunnel capability is disabled by SDK configuration',
    );
    await _requestJson(
      method: 'PATCH',
      path: '/configs',
      body: const <String, Object?>{
        'tun': <String, Object?>{
          'enable': false,
        },
      },
    );
  }

  @override
  Future<void> resetTunnel() async {
    _ensureCapability(
      enabled: _capabilities.allowTunnelCapability,
      code: 'SDK-CAPABILITY-TUNNEL-DISABLED',
      message: 'Tunnel capability is disabled by SDK configuration',
    );
    await _platform.resetTunnel();
  }

  @override
  Future<TunnelStatus> tunnelStatus() async {
    _ensureCapability(
      enabled: _capabilities.allowTunnelCapability,
      code: 'SDK-CAPABILITY-TUNNEL-DISABLED',
      message: 'Tunnel capability is disabled by SDK configuration',
    );
    final payload = await _requestJson(method: 'GET', path: '/configs');
    final tun = payload['tun'];
    if (tun is Map) {
      final map = tun.cast<String, Object?>();
      return TunnelStatus(
        enabled: (map['enable'] as bool?) ?? false,
        stack: map['stack'] as String?,
        device: map['device'] as String?,
      );
    }
    return const TunnelStatus(enabled: false);
  }

  @override
  Future<PlatformCapabilities> getCapabilities() async {
    final map = await _platform.getPlatformCapabilities();
    return PlatformCapabilities.fromMap(map);
  }

  Map<String, Object?>? _buildLaunchOptions() {
    if (_runtimeLaunchOptions != null) {
      final base = _runtimeLaunchOptions.toMap();
      base['networkMode'] = _capabilities.networkMode.name;
      return base;
    }
    return <String, Object?>{
      'networkMode': _capabilities.networkMode.name,
    };
  }

  void _ensureCapability({
    required bool enabled,
    required String code,
    required String message,
  }) {
    if (enabled) {
      return;
    }
    throw JumperSdkException(code, message);
  }

  void _ensureNetworkModeSupported() {
    switch (_capabilities.networkMode) {
      case JumperNetworkMode.tunnel:
        _ensureCapability(
          enabled: _capabilities.allowTunnelCapability,
          code: 'SDK-CAPABILITY-TUNNEL-DISABLED',
          message: 'Tunnel network mode requires tunnel capability',
        );
        break;
      case JumperNetworkMode.systemProxy:
        _ensureCapability(
          enabled: _capabilities.allowSystemProxyCapability,
          code: 'SDK-CAPABILITY-SYSTEM-PROXY-DISABLED',
          message: 'System proxy network mode requires system proxy capability',
        );
        break;
    }
  }

  Future<Map<String, Object?>> _requestJson({
    required String method,
    required String path,
    Map<String, Object?>? body,
  }) async {
    final client = HttpClient();
    try {
      final requestUri = _coreApiBaseUri.resolve(path);
      final request = await client.openUrl(method, requestUri);
      request.headers.contentType = ContentType.json;
      if (_coreApiSecret != null && _coreApiSecret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_coreApiSecret');
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final payloadText = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw JumperSdkException(
          'SDK-COREAPI-${response.statusCode}',
          'Core API request failed: $method $path',
          payloadText,
        );
      }
      if (payloadText.trim().isEmpty) {
        return <String, Object?>{};
      }
      final decoded = jsonDecode(payloadText);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
      return <String, Object?>{};
    } on JumperSdkException {
      rethrow;
    } catch (error) {
      throw JumperSdkException(
        'SDK-COREAPI-REQUEST',
        'Core API request exception: $method $path',
        error,
      );
    } finally {
      client.close(force: true);
    }
  }
}

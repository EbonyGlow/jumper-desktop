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
       _coreApiBaseUri = coreApiBaseUri ?? Uri.parse('http://127.0.0.1:19900'),
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
            (event['timestampMs'] as int?) ??
            DateTime.now().millisecondsSinceEpoch,
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
  Future<Map<String, int>> testGroupDelay({
    required String group,
    required String url,
    int timeoutMs = 5000,
  }) async {
    final encodedGroup = Uri.encodeComponent(group);
    final payload = await _requestJson(
      method: 'GET',
      path:
          '/proxies/$encodedGroup/delay?url=${Uri.encodeComponent(url)}&timeout=$timeoutMs',
    );
    final results = <String, int>{};
    payload.forEach((key, value) {
      if (value is int) {
        results[key.toString()] = value;
      }
    });
    return results;
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
  Future<void> sendNotification({required String title, required String body}) {
    _ensureCapability(
      enabled: _capabilities.allowNotifyCapability,
      code: 'SDK-CAPABILITY-NOTIFY-DISABLED',
      message: 'Notification capability is disabled by SDK configuration',
    );
    return _platform.showNotification(title: title, body: body);
  }

  @override
  Future<void> showTray({required String title, String? tooltip}) {
    _ensureCapability(
      enabled: _capabilities.allowTrayCapability,
      code: 'SDK-CAPABILITY-TRAY-DISABLED',
      message: 'Tray capability is disabled by SDK configuration',
    );
    return _platform.showTray(title: title, tooltip: tooltip);
  }

  @override
  Future<void> updateTray({required String title, String? tooltip}) {
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
  Future<void> enableTunnel({String stack = 'mixed', String? device}) async {
    _ensureCapability(
      enabled: _capabilities.allowTunnelCapability,
      code: 'SDK-CAPABILITY-TUNNEL-DISABLED',
      message: 'Tunnel capability is disabled by SDK configuration',
    );
    if (await _applyTunnelToLaunchConfig(
      enabled: true,
      stack: stack,
      device: device,
    )) {
      await restartCore(reason: 'tunnel_enabled');
      return;
    }

    // Fallback for SDK consumers that rely on the old /configs patch API.
    final tunPatch = <String, Object?>{'enable': true, 'stack': stack};
    if (device != null) tunPatch['device'] = device;
    await _requestJson(
      method: 'PATCH',
      path: '/configs',
      body: <String, Object?>{'tun': tunPatch},
    );
  }

  @override
  Future<void> disableTunnel() async {
    _ensureCapability(
      enabled: _capabilities.allowTunnelCapability,
      code: 'SDK-CAPABILITY-TUNNEL-DISABLED',
      message: 'Tunnel capability is disabled by SDK configuration',
    );
    if (await _applyTunnelToLaunchConfig(enabled: false)) {
      await restartCore(reason: 'tunnel_disabled');
      return;
    }

    // Fallback for SDK consumers that rely on the old /configs patch API.
    await _requestJson(
      method: 'PATCH',
      path: '/configs',
      body: const <String, Object?>{
        'tun': <String, Object?>{'enable': false},
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
    final fromLaunchConfig = await _readTunnelStatusFromLaunchConfig();
    if (fromLaunchConfig != null) {
      return fromLaunchConfig;
    }

    // Fallback for SDK consumers that rely on the old /configs API.
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
    return <String, Object?>{'networkMode': _capabilities.networkMode.name};
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
      final endpoint = await _resolveCoreApiEndpoint();
      final requestUri = endpoint.baseUri.resolve(path);
      final request = await client.openUrl(method, requestUri);
      request.headers.contentType = ContentType.json;
      if (endpoint.secret != null && endpoint.secret!.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${endpoint.secret}',
        );
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

  Future<_ResolvedCoreApiEndpoint> _resolveCoreApiEndpoint() async {
    final launchConfigPath = _resolveLaunchConfigPath();
    if (launchConfigPath != null) {
      try {
        final file = File(launchConfigPath);
        if (file.existsSync()) {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map) {
            final config = decoded.cast<String, Object?>();
            final experimental = config['experimental'];
            if (experimental is Map) {
              final expMap = experimental.cast<String, Object?>();
              final clashApi = expMap['clash_api'];
              if (clashApi is Map) {
                final clashMap = clashApi.cast<String, Object?>();
                final controller = clashMap['external_controller']
                    ?.toString()
                    .trim();
                final secret = clashMap['secret']?.toString();
                final uri = _parseControllerUri(controller);
                if (uri != null) {
                  return _ResolvedCoreApiEndpoint(
                    baseUri: uri,
                    secret: (secret?.isEmpty ?? true) ? _coreApiSecret : secret,
                  );
                }
              }
            }
          }
        }
      } catch (_) {
        // Keep fallback endpoint if config parsing fails.
      }
    }
    return _ResolvedCoreApiEndpoint(
      baseUri: _coreApiBaseUri,
      secret: _coreApiSecret,
    );
  }

  Uri? _parseControllerUri(String? controller) {
    if (controller == null || controller.isEmpty) {
      return null;
    }
    final normalized = controller.contains('://')
        ? controller
        : 'http://$controller';
    return Uri.tryParse(normalized);
  }

  String? _resolveLaunchConfigPath() {
    final options = _runtimeLaunchOptions;
    if (options == null) return null;
    final args = options.arguments;
    for (var i = 0; i < args.length - 1; i++) {
      if (args[i] == '-c' && args[i + 1].trim().isNotEmpty) {
        return args[i + 1].trim();
      }
    }
    return null;
  }

  Future<bool> _applyTunnelToLaunchConfig({
    required bool enabled,
    String stack = 'mixed',
    String? device,
  }) async {
    final configPath = _resolveLaunchConfigPath();
    if (configPath == null) {
      return false;
    }
    final file = File(configPath);
    if (!file.existsSync()) {
      return false;
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return false;
    }
    final config = decoded.cast<String, Object?>();
    final inboundsRaw = config['inbounds'];
    final inbounds = <Map<String, Object?>>[];
    if (inboundsRaw is List) {
      for (final item in inboundsRaw) {
        if (item is Map) {
          inbounds.add(item.cast<String, Object?>());
        }
      }
    }

    Map<String, Object?>? tunInbound;
    for (final inbound in inbounds) {
      if ((inbound['type'] as String?)?.toLowerCase() == 'tun') {
        tunInbound = inbound;
        break;
      }
    }
    tunInbound ??= <String, Object?>{
      'type': 'tun',
      'tag': 'tun-in',
      'address': <String>['172.18.0.1/30', 'fdfe:dcba:9876::1/126'],
      'auto_route': true,
      'strict_route': true,
    };
    tunInbound['enable'] = enabled;
    tunInbound['stack'] = stack;
    if (device != null && device.isNotEmpty) {
      tunInbound['interface_name'] = device;
    }
    if (!inbounds.contains(tunInbound)) {
      inbounds.insert(0, tunInbound);
    }
    config['inbounds'] = inbounds;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
    return true;
  }

  Future<TunnelStatus?> _readTunnelStatusFromLaunchConfig() async {
    final configPath = _resolveLaunchConfigPath();
    if (configPath == null) {
      return null;
    }
    final file = File(configPath);
    if (!file.existsSync()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return null;
    }
    final config = decoded.cast<String, Object?>();
    final inbounds = config['inbounds'];
    if (inbounds is! List) {
      return const TunnelStatus(enabled: false);
    }
    for (final item in inbounds) {
      if (item is! Map) continue;
      final inbound = item.cast<String, Object?>();
      if ((inbound['type'] as String?)?.toLowerCase() != 'tun') continue;
      return TunnelStatus(
        enabled: (inbound['enable'] as bool?) ?? true,
        stack: inbound['stack'] as String?,
        device:
            (inbound['interface_name'] as String?) ??
            (inbound['device'] as String?),
      );
    }
    return const TunnelStatus(enabled: false);
  }
}

class _ResolvedCoreApiEndpoint {
  const _ResolvedCoreApiEndpoint({required this.baseUri, required this.secret});

  final Uri baseUri;
  final String? secret;
}

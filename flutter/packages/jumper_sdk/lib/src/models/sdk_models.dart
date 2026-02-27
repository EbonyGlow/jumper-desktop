enum CoreStatus { stopped, starting, running, stopping, error }

enum JumperNetworkMode { tunnel, systemProxy }

enum PluginEvent {
  onStartup,
  onReady,
  onShutdown,
  onCoreStarted,
  onCoreStopped,
  onSubscribe,
}

class CoreState {
  const CoreState({
    required this.status,
    this.pid,
    this.message,
    this.runtimeMode,
    this.networkMode,
  });

  final CoreStatus status;
  final int? pid;
  final String? message;
  final String? runtimeMode;
  final String? networkMode;

  factory CoreState.fromMap(Map<String, Object?> map) {
    final rawStatus = (map['status'] as String?) ?? 'stopped';
    return CoreState(
      status: CoreStatus.values.firstWhere(
        (value) => value.name == rawStatus,
        orElse: () => CoreStatus.stopped,
      ),
      pid: map['pid'] as int?,
      message: map['message'] as String?,
      runtimeMode: map['runtimeMode'] as String?,
      networkMode: map['networkMode'] as String?,
    );
  }
}

class SdkCapabilitiesConfig {
  const SdkCapabilitiesConfig({
    this.networkMode = JumperNetworkMode.tunnel,
    this.allowSystemProxyCapability = true,
    this.allowTunnelCapability = true,
    this.allowNotifyCapability = true,
    this.allowTrayCapability = true,
  });

  final JumperNetworkMode networkMode;
  final bool allowSystemProxyCapability;
  final bool allowTunnelCapability;
  final bool allowNotifyCapability;
  final bool allowTrayCapability;
}

class CoreEvent {
  const CoreEvent({
    required this.type,
    required this.timestampMs,
    this.payload = const <String, Object?>{},
  });

  final String type;
  final int timestampMs;
  final Map<String, Object?> payload;

  factory CoreEvent.fromMap(Map<String, Object?> map) {
    return CoreEvent(
      type: (map['type'] as String?) ?? 'unknown',
      timestampMs: (map['timestampMs'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      payload: (map['payload'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{},
    );
  }
}

class ValidationResult {
  const ValidationResult({
    required this.isValid,
    this.errors = const <String>[],
  });

  final bool isValid;
  final List<String> errors;
}

class CoreConfigs {
  const CoreConfigs({
    required this.config,
  });

  final Map<String, Object?> config;
}

class ProxiesSnapshot {
  const ProxiesSnapshot({
    required this.groups,
  });

  final Map<String, Object?> groups;
}

class ConnectionsSnapshot {
  const ConnectionsSnapshot({
    required this.connections,
  });

  final List<Map<String, Object?>> connections;
}

class KernelLogEvent {
  const KernelLogEvent({
    required this.level,
    required this.message,
    required this.timestampMs,
  });

  final String level;
  final String message;
  final int timestampMs;
}

class TrafficStatEvent {
  const TrafficStatEvent({
    required this.uploadBytes,
    required this.downloadBytes,
  });

  final int uploadBytes;
  final int downloadBytes;
}

class MemoryStatEvent {
  const MemoryStatEvent({
    required this.rssBytes,
  });

  final int rssBytes;
}

class Profile {
  const Profile({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, Object?> data;
}

class SubscriptionResult {
  const SubscriptionResult({
    required this.id,
    required this.success,
    this.message,
  });

  final String id;
  final bool success;
  final String? message;
}

class ProxyNode {
  const ProxyNode({
    required this.tag,
    required this.type,
  });

  final String tag;
  final String type;
}

class RulesetResult {
  const RulesetResult({
    required this.id,
    required this.success,
    this.message,
  });

  final String id;
  final bool success;
  final String? message;
}

class PluginTriggerResult {
  const PluginTriggerResult({
    required this.success,
    this.message,
  });

  final bool success;
  final String? message;
}

class ScheduledTask {
  const ScheduledTask({
    required this.id,
    required this.cron,
    required this.type,
  });

  final String id;
  final String cron;
  final String type;
}

class TaskRunResult {
  const TaskRunResult({
    required this.success,
    this.message,
  });

  final bool success;
  final String? message;
}

class TaskRunEvent {
  const TaskRunEvent({
    required this.taskId,
    required this.timestampMs,
    required this.status,
  });

  final String taskId;
  final int timestampMs;
  final String status;
}

class SystemProxyStatus {
  const SystemProxyStatus({
    required this.enabled,
    this.host,
    this.port,
  });

  final bool enabled;
  final String? host;
  final int? port;

  factory SystemProxyStatus.fromMap(Map<String, Object?> map) {
    return SystemProxyStatus(
      enabled: (map['enabled'] as bool?) ?? false,
      host: map['host'] as String?,
      port: map['port'] as int?,
    );
  }
}

class TrayStatus {
  const TrayStatus({
    required this.visible,
    this.title,
  });

  final bool visible;
  final String? title;

  factory TrayStatus.fromMap(Map<String, Object?> map) {
    return TrayStatus(
      visible: (map['visible'] as bool?) ?? false,
      title: map['title'] as String?,
    );
  }
}

class TunnelStatus {
  const TunnelStatus({
    required this.enabled,
    this.stack,
    this.device,
  });

  final bool enabled;
  final String? stack;
  final String? device;
}

class PlatformCapabilities {
  const PlatformCapabilities({
    required this.tunnelSupported,
    required this.systemProxySupported,
    required this.notifySupported,
    required this.traySupported,
  });

  final bool tunnelSupported;
  final bool systemProxySupported;
  final bool notifySupported;
  final bool traySupported;

  factory PlatformCapabilities.fromMap(Map<String, Object?> map) {
    return PlatformCapabilities(
      tunnelSupported: (map['tunnelSupported'] as bool?) ?? false,
      systemProxySupported: (map['systemProxySupported'] as bool?) ?? false,
      notifySupported: (map['notifySupported'] as bool?) ?? false,
      traySupported: (map['traySupported'] as bool?) ?? false,
    );
  }
}

class JumperSdkException implements Exception {
  const JumperSdkException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'JumperSdkException($code): $message';
}

class JumperRuntimeLaunchOptions {
  const JumperRuntimeLaunchOptions({
    required this.binaryPath,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
    this.networkMode = JumperNetworkMode.tunnel,
  });

  final String binaryPath;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final JumperNetworkMode networkMode;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'binaryPath': binaryPath,
      'arguments': arguments,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      'environment': environment,
      'networkMode': networkMode.name,
    };
  }
}

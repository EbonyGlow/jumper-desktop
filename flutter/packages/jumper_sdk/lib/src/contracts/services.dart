import '../models/sdk_models.dart';

abstract interface class KernelRuntimeService {
  Future<void> startCore({required String profileId});
  Future<void> stopCore();
  Future<void> restartCore({String? reason});
  Future<CoreState> getState();
  Stream<CoreEvent> watchCoreEvents();
}

abstract interface class ConfigEngine {
  Future<String> generateConfig({required Profile profile});
  Future<Profile> restoreProfile({required String configJson});
  Future<ValidationResult> validateConfig({required String configJson});
  Future<String> migrateConfig({
    required String configJson,
    required int targetSchema,
  });
}

abstract interface class CoreApiClient {
  Future<CoreConfigs> getConfigs();
  Future<void> setConfigs(CoreConfigs configs);
  Future<ProxiesSnapshot> getProxies();
  Future<void> useProxy({required String group, required String proxy});
  Future<ConnectionsSnapshot> getConnections();
  Future<void> closeConnection({required String id});
  Future<void> closeAllConnections();
  Stream<KernelLogEvent> watchLogs();
  Stream<TrafficStatEvent> watchTraffic();
  Stream<MemoryStatEvent> watchMemory();
  Stream<ConnectionsSnapshot> watchConnections();
}

abstract interface class SubscriptionService {
  Future<SubscriptionResult> updateOne(String id);
  Future<List<SubscriptionResult>> updateAll();
  Future<List<ProxyNode>> listNodes(String id);
}

abstract interface class RulesetService {
  Future<RulesetResult> updateOne(String id);
  Future<List<RulesetResult>> updateAll();
  Future<void> clear(String id);
}

abstract interface class PluginRuntime {
  Future<void> loadPlugins();
  Future<void> reloadPlugin(String id);
  Future<PluginTriggerResult> trigger(
    PluginEvent event,
    Map<String, Object?> payload,
  );
}

abstract interface class TaskSchedulerService {
  Future<void> registerTask(ScheduledTask task);
  Future<TaskRunResult> runNow(String taskId);
  Stream<TaskRunEvent> watchTaskEvents();
}

abstract interface class SystemProxyCapability {
  Future<void> enableProxy({required String host, required int port});
  Future<void> disableProxy();
  Future<SystemProxyStatus> status();
}

abstract interface class NotifyCapability {
  Future<bool> requestPermission();
  Future<bool> permissionStatus();
  Future<void> sendNotification({
    required String title,
    required String body,
  });
}

abstract interface class TrayCapability {
  Future<void> showTray({
    required String title,
    String? tooltip,
  });
  Future<void> updateTray({
    required String title,
    String? tooltip,
  });
  Future<void> hideTray();
  Future<TrayStatus> trayStatus();
}

abstract interface class TunnelCapability {
  Future<void> enableTunnel({
    String stack,
    String? device,
  });
  Future<void> disableTunnel();
  Future<void> resetTunnel();
  Future<TunnelStatus> tunnelStatus();
}

abstract interface class CapabilityDiscovery {
  Future<PlatformCapabilities> getCapabilities();
}

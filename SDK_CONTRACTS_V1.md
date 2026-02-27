# SDK Contracts v1 (Must Implement First)

## 1) KernelRuntimeService

```dart
abstract interface class KernelRuntimeService {
  Future<void> startCore({required String profileId});
  Future<void> stopCore();
  Future<void> restartCore({String? reason});
  Future<CoreState> getState();
  Stream<CoreEvent> watchCoreEvents();
}
```

## 2) ConfigEngine

```dart
abstract interface class ConfigEngine {
  Future<String> generateConfig({required Profile profile});
  Future<Profile> restoreProfile({required String configJson});
  Future<ValidationResult> validateConfig({required String configJson});
  Future<String> migrateConfig({required String configJson, required int targetSchema});
}
```

## 3) CoreApiClient

```dart
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
```

## 4) SubscriptionService

```dart
abstract interface class SubscriptionService {
  Future<SubscriptionResult> updateOne(String id);
  Future<List<SubscriptionResult>> updateAll();
  Future<List<ProxyNode>> listNodes(String id);
}
```

## 5) RulesetService

```dart
abstract interface class RulesetService {
  Future<RulesetResult> updateOne(String id);
  Future<List<RulesetResult>> updateAll();
  Future<void> clear(String id);
}
```

## 6) PluginRuntime

```dart
abstract interface class PluginRuntime {
  Future<void> loadPlugins();
  Future<void> reloadPlugin(String id);
  Future<PluginTriggerResult> trigger(PluginEvent event, Map<String, Object?> payload);
}
```

## 7) TaskSchedulerService

```dart
abstract interface class TaskSchedulerService {
  Future<void> registerTask(ScheduledTask task);
  Future<TaskRunResult> runNow(String taskId);
  Stream<TaskRunEvent> watchTaskEvents();
}
```

## 8) SystemProxyCapability (Optional Capability)

```dart
abstract interface class SystemProxyCapability {
  Future<void> enableProxy({required String host, required int port});
  Future<void> disableProxy();
  Future<SystemProxyStatus> status();
}
```

## 8.1) NotifyCapability (Optional Capability)

```dart
abstract interface class NotifyCapability {
  Future<bool> requestPermission();
  Future<bool> permissionStatus();
  Future<void> sendNotification({
    required String title,
    required String body,
  });
}
```

## 8.2) TrayCapability (Optional Capability)

```dart
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
```

## 8.3) TunnelCapability (Optional Capability, Default Network Mode)

```dart
abstract interface class TunnelCapability {
  Future<void> enableTunnel({
    String stack = 'mixed',
    String? device,
  });
  Future<void> disableTunnel();
  Future<void> resetTunnel();
  Future<TunnelStatus> tunnelStatus();
}
```

默认策略约束：

- SDK 默认网络模式为 `tunnel`
- 能力支持“可配置开关”，但默认不自动回退到 system-proxy
- 若调用被禁用能力，应返回显式错误码（如 `SDK-CAPABILITY-*-DISABLED`）

## 9) Error Model（统一）

```dart
class JumperSdkException implements Exception {
  final String code; // e.g. SDK-CORE-001
  final String message;
  final Object? details;
  const JumperSdkException(this.code, this.message, [this.details]);
}
```

## 10) 首批必测场景（不可删）

- start -> logs stream -> stop
- restart 幂等
- core 异常退出后状态恢复
- proxy group 切换
- subscription update
- ruleset update
- config validate fail path
- ws 重连
- API timeout -> 错误码映射
- 并发 start 防重入

## 11) Runtime Distribution（新增）

```dart
Future<Map<String, Object?>> setupRuntime({
  required String version,
  required String platformArch,
  String? basePath,
});

Future<Map<String, Object?>> inspectRuntime({
  required String version,
  required String platformArch,
  String? basePath,
});
```

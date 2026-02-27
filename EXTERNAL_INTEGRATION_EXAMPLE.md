# External Flutter Integration Example

本示例说明外部 Flutter 项目如何以 SDK 方式接入 `jumper_sdk`，不依赖本仓库 UI。

## 1. Add Dependencies

外部项目 `pubspec.yaml` 示例（本地路径模式）：

```yaml
dependencies:
  flutter:
    sdk: flutter
  jumper_sdk:
    path: /Users/sean/Desktop/cyber/jumper-desktop/flutter/packages/jumper_sdk
```

如果改为发布包模式，可替换为私有源或公开源版本号依赖。

## 2. Bootstrap SDK Client

```dart
import 'package:jumper_sdk/jumper_sdk.dart';

Future<JumperSdkClient> buildClient() async {
  final launchOptions = await JumperRuntimeBootstrap.prepareLaunchOptions(
    appBasePath: '/absolute/path/to/app-base',
    config: <String, Object?>{
      'log': <String, Object?>{'level': 'info'},
      // 这里放 sing-box 配置片段
    },
  );

  return JumperSdkClient(
    runtimeLaunchOptions: launchOptions,
    coreApiBaseUri: Uri.parse('http://127.0.0.1:20123'),
  );
}
```

## 3. Runtime Control + Core API

```dart
final sdk = await buildClient();

await sdk.startCore(profileId: 'default');
final state = await sdk.getState();
final proxies = await sdk.getProxies();
await sdk.stopCore();
```

## 4. Optional Capabilities

### 4.1 System Proxy

```dart
await sdk.enableProxy(host: '127.0.0.1', port: 7890);
final proxyStatus = await sdk.status();
await sdk.disableProxy();
```

### 4.2 Notify

```dart
if (await sdk.requestPermission()) {
  await sdk.sendNotification(
    title: 'Jumper',
    body: 'Core started successfully',
  );
}
```

### 4.3 Tray

```dart
await sdk.showTray(title: 'Jumper', tooltip: 'Ready');
await sdk.updateTray(title: 'Jumper*', tooltip: 'Running');
await sdk.hideTray();
```

## 5. Recommended Integration Test

建议外部项目至少保留 1 条端到端链路：

- `startCore -> getProxies -> stopCore`
- 失败路径：传入非法 runtime 参数，验证错误码映射
- 可选能力路径：proxy / notify / tray 各 1 条最小用例

## 6. Production Notes

- Release 模式若启用 macOS sandbox，请确保 runtime 二进制位于应用容器路径中。
- 建议将 runtime 更新统一通过 `run-runtime-update.sh` 的编排逻辑执行（或同等逻辑移植到 CI/CD）。

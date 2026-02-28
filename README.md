# Jumper Desktop Execution Pack

本目录是将 `GUI.for.SingBox` 全功能无 UI 化并封装为 Flutter SDK 的可执行计划包。

## 目标

- 对齐 `GUI.for.SingBox` 现有全部核心功能能力。
- 产出可供外部 Flutter 项目直接依赖的 SDK（含 Go 与 sing-box runtime）。
- 保持跨平台可运行与可回滚发布能力。

## 当前状态（2026-02-26）

- 已完成：M2 全部项、M3-01~M3-06、`M3-GATE` 勾选、严格审计修复与故障注入验证。
- 当前阻塞：无（M3 三平台证据链已闭环）。
- 当前建议：发布前先执行 `./audit-baseline-guard.sh`，并复核最新三平台 artifacts 与验收摘要。

## 目录说明

- `MASTER_PLAN.md`：整体里程碑计划（M1/M2/M3）与硬验收门槛。
- `TASK_BOARD.md`：可勾选任务看板（执行跟踪用）。
- `RELEASE_GUIDE.md`：发布流程、门禁矩阵与回滚策略。
- `RELEASE_DAY_COMMANDS.md`：发布日一页式命令清单。
- `EXTERNAL_INTEGRATION_EXAMPLE.md`：外部 Flutter 项目接入示例。
- `M3_GATE_EVIDENCE.md`：三平台 M3-GATE 证据清单。
- `verify-m3-gate-evidence.sh`：对三平台 artifacts 做一键门禁核对。
- `audit-baseline-guard.sh`：审计基线回退保护脚本（规则扫描）。
- `.fvmrc`：Flutter 版本固定为 `3.41.2`。

## 执行原则

- 不先做 UI；先把能力层（headless core）跑通。
- 所有接口先定义契约，再写实现。
- 每个阶段必须通过验收门槛后再进入下阶段。

## Smoke App 真实运行时模式（macOS）

当前 `sdk_smoke_app` 支持通过 `dart-define` 传入真实 core 启动参数：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop/flutter/apps/sdk_smoke_app
fvm flutter run -d macos \
  --dart-define=JUMPER_CORE_BIN=/absolute/path/to/sing-box \
  --dart-define=JUMPER_CORE_ARGS='run --disable-color -c /absolute/path/to/config.json -D /absolute/path/to/workdir' \
  --dart-define=JUMPER_CORE_WORKDIR=/absolute/path/to/workdir \
  --dart-define=JUMPER_CORE_API_BASE=http://127.0.0.1:20123 \
  --dart-define=JUMPER_CORE_API_SECRET=
```

也支持“自动落盘配置 + 约定路径启动”模式（无需显式传 `JUMPER_CORE_BIN`）：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop/flutter/apps/sdk_smoke_app
fvm flutter run -d macos \
  --dart-define=JUMPER_APP_BASE_PATH=/absolute/path/to/app-base \
  --dart-define=JUMPER_CORE_BASE_PATH=data/sing-box \
  --dart-define=JUMPER_CORE_CONFIG_JSON='{"log":{"level":"info"}}' \
  --dart-define=JUMPER_CORE_API_BASE=http://127.0.0.1:20123
```

说明：
- SDK 会把配置写入 `<APP_BASE>/data/sing-box/config.json`
- 默认启动二进制路径为 `<APP_BASE>/data/sing-box/sing-box`（Windows 为 `sing-box.exe`）

## Runtime Assets 自动化

已在 `engine/runtime-assets` 下提供资产清单与脚本：

- `manifest.json`：当前纳入版本与下载链接
- `checksums.json`：runtime 资产校验值（由脚本生成）
- `fetch-sing-box.sh`：按平台下载并解压 sing-box
- `prepare-runtime-assets.sh`：构建前拉取版本（支持 `latest`）、刷新 manifest、更新并验签 checksums、产出版本锁定文件
- `validate-runtime-chain.sh`：执行 `start -> proxies API -> stop` 验证
- `generate-checksums.sh`：生成/更新资产 SHA256
- `verify-checksums.sh`：按 `checksums.json` 验签
- `backup-runtime-container.sh`：备份当前 runtime 目录
- `rollback-runtime-container.sh`：回滚到指定/最新备份
- `run-runtime-stability-check.sh`：执行长时间稳定性探测（默认 30 分钟）
- `validate-runtime-install.sh`：对目标 runtime 目录执行安装后健康检查
- `run-runtime-update.sh`：执行下载/验签/应用/校验/失败回滚的一键更新

最小开发路径（本地快速验证）：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop
./engine/runtime-assets/prepare-runtime-assets.sh darwin-arm64 latest
./engine/runtime-assets/validate-runtime-chain.sh darwin-arm64 "$(python3 - <<'PY'
import json
from pathlib import Path
print(json.loads(Path('engine/runtime-assets/resolved-runtime-lock.json').read_text())['resolved_version'])
PY
)"
./run-runtime-update.sh darwin-arm64 "$(python3 - <<'PY'
import json
from pathlib import Path
print(json.loads(Path('engine/runtime-assets/resolved-runtime-lock.json').read_text())['resolved_version'])
PY
)" com.example.sdkSmokeApp
```

发布前全量路径（门禁全跑）：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop
./audit-baseline-guard.sh
./run-runtime-release-check.sh darwin-arm64 latest com.example.sdkSmokeApp
./run-runtime-stability-check.sh darwin-arm64 "$(python3 - <<'PY'
import json
from pathlib import Path
print(json.loads(Path('engine/runtime-assets/resolved-runtime-lock.json').read_text())['resolved_version'])
PY
)" 1800 5
```

受信任发布工位（仅在需要更新 checksums 时执行）：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop
./engine/runtime-assets/generate-checksums.sh
./engine/runtime-assets/verify-checksums.sh
```

`validate-runtime-chain.sh` 当前会严格校验：
- 启动日志包含 `sing-box started`
- Clash API `/proxies` 可访问
- 代理组数量 > 0
- 进程可被正常停止

`run-runtime-release-check.sh` 会串行执行：
- 验签 checksums
- 备份 runtime
- 回滚 runtime
- 执行 runtime 链路验证

`run-runtime-stability-check.sh` 默认会：
- 启动 `sing-box` 并持续 30 分钟轮询 `/proxies`
- 每轮记录 HTTP 状态、代理组数量与延迟到 JSONL 日志
- 输出统计摘要（成功/失败次数、平均/最大延迟）
- 任一轮失败会计数，出现失败则判定整轮不通过

`run-runtime-update.sh` 默认会：
- 拉取目标版本 runtime（download）
- 校验目标平台 checksums（verify）
- 备份当前 runtime 目录（backup）
- 以 staging 方式替换 runtime（apply）
- 调用 `validate-runtime-install.sh` 进行启动与 `/proxies` 健康检查（validate）
- 若校验失败自动执行 rollback

说明：`run-runtime-update.sh` 不会生成 checksums；仅消费既有 `checksums.json` 进行验签。

用于本地可重复测试时，可追加第 5 个参数覆盖 runtime 根目录（不会改系统容器路径）：

```bash
./run-runtime-update.sh darwin-arm64 1.12.22 com.example.sdkSmokeApp http://127.0.0.1:20123 /abs/path/to/runtime-root
```

`generate-checksums.sh` / `verify-checksums.sh` 现在默认处理 `manifest.json` 里的全部平台；
如需仅处理单个平台，可传入 `darwin-arm64` 等参数。

支持下载平台：
- `darwin-arm64`
- `darwin-amd64`
- `linux-amd64`
- `linux-arm64`
- `windows-amd64`

## 集成测试说明

- `run-smoke-runtime-e2e.sh`：外部预启动 runtime，SDK 验证 Core API
- `run-smoke-runtime-e2e-drive.sh`：同上（兼容脚本名，现已切换到 `flutter test integration_test/... -d macos`）
- `run-smoke-runtime-e2e-drive-direct.sh`：SDK 在应用进程内启动 runtime（DebugProfile 验收模式）
- 以上脚本都已采用 `flutter test integration_test/... -d macos`，已消除 `integration_test plugin was not detected` 警告
- 权威验收采用双轨：
  - 强通过门槛：`validate-runtime-chain.sh`
  - 集成通过门槛：上述 3 个脚本

### macOS Sandbox 注意事项

- 已为 `sdk_smoke_app` 增加 `com.apple.security.network.client` 与 `com.apple.security.network.server` entitlement。
- `sdk_smoke_app` 在 `DebugProfile` 已关闭 `app-sandbox`（仅调试验收），用于验证 SDK 在应用进程内启动 runtime。
- `Release` 仍保持 sandbox 打开，发布态不要依赖“任意路径执行二进制”。
- SDK 现已在 macOS 插件层增加沙箱路径保护：
  - 错误码：`RUNTIME_PATH_BLOCKED_BY_SANDBOX`
  - 含义：sandbox 打开时，runtime 二进制路径不在 app 容器目录内。

可用验收命令：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop
./run-smoke-runtime-e2e-drive-direct.sh
./run-runtime-setup-test.sh
```

该命令会：
- 先把 runtime 预置到 app 容器目录
- 再由 SDK 在 app 进程内执行 `start -> proxies -> stop`

`run-runtime-setup-test.sh` 会验证：
- SDK 调用平台层 `setupRuntime` 将 runtime 资产分发到 app 容器目录
- 再调用 `inspectRuntime` 校验 binary/config 可用

当前状态：
- `run-smoke-runtime-e2e-drive.sh`：已通过
- `run-smoke-runtime-e2e-drive-direct.sh`：已通过（DebugProfile）
- `run-runtime-setup-test.sh`：已通过（容器内 runtime 分发链路）
- `run-runtime-stability-check.sh`：已通过 30 分钟稳定性验证（`stability-20260226-141210.summary.txt`）
- `run-runtime-update.sh`：已完成 apply 成功路径 + 故障回滚路径实测（override runtime root 模式）

## System Proxy Capability（M3-03）

`jumper_sdk` 已支持可选的系统代理能力（当前先落地 macOS）：

- `enableProxy(host, port)`：启用系统 HTTP/HTTPS/SOCKS 代理
- `disableProxy()`：关闭系统代理
- `status()`：查询当前系统代理状态

示例：

```dart
final sdk = JumperSdkClient();
await sdk.enableProxy(host: '127.0.0.1', port: 7890);
final proxyStatus = await sdk.status();
await sdk.disableProxy();
```

实现说明：
- SDK 通过 `MethodChannel` 下发：
  - `enableSystemProxy`
  - `disableSystemProxy`
  - `getSystemProxyStatus`
- macOS 原生层通过 `/usr/sbin/networksetup` 对可用网络服务执行代理设置。
- 若系统权限或服务状态不满足条件，会返回平台错误（`SYSTEM_PROXY_*_FAILED`）。

## Notify Capability（M3-04）

`jumper_sdk` 已支持可选通知能力（当前先落地 macOS）：

- `requestPermission()`：请求通知权限
- `permissionStatus()`：查询通知权限状态
- `sendNotification(title, body)`：发送本地通知

示例：

```dart
final sdk = JumperSdkClient();
final granted = await sdk.requestPermission();
if (granted) {
  await sdk.sendNotification(
    title: 'Jumper',
    body: 'Core is running',
  );
}
```

实现说明：
- SDK 通过 `MethodChannel` 下发：
  - `requestNotificationPermission`
  - `getNotificationPermissionStatus`
  - `showNotification`
- macOS 原生层通过 `UNUserNotificationCenter` 实现授权与通知投递。
- 若授权请求或通知发送失败，会返回平台错误（`NOTIFY_*_FAILED`）。

## Tray Capability（M3-05）

`jumper_sdk` 已支持可选托盘能力（当前先落地 macOS）：

- `showTray(title, tooltip)`：显示托盘项
- `updateTray(title, tooltip)`：更新托盘文案
- `hideTray()`：隐藏托盘项
- `trayStatus()`：查询托盘当前状态

示例：

```dart
final sdk = JumperSdkClient();
await sdk.showTray(title: 'Jumper', tooltip: 'Runtime ready');
await sdk.updateTray(title: 'Jumper*', tooltip: 'Core running');
final tray = await sdk.trayStatus();
await sdk.hideTray();
```

实现说明：
- SDK 通过 `MethodChannel` 下发：
  - `showTray`
  - `updateTray`
  - `hideTray`
  - `getTrayStatus`
- macOS 原生层通过 `NSStatusBar` / `NSStatusItem` 实现托盘项创建与更新。
- 若参数非法会返回平台错误（`TRAY_INVALID_ARGUMENTS`）。

发布态建议：
- 若保持 sandbox 打开，优先使用“外部预启动 runtime + SDK 走 Core API”模式。
- 若必须由 SDK 启动 runtime，需要将 runtime 资产纳入 app 容器并走容器内路径。

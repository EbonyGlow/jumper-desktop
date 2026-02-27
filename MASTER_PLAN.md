# Master Execution Plan (Actionable)

## 0. 执行范围（必须完成）

- 核心控制：start/stop/restart/state/events。
- 配置体系：profile -> sing-box config 生成、恢复、校验、迁移。
- 运行态观测：logs/traffic/memory/connections（REST + WS）。
- 资源体系：subscriptions/rulesets/plugins/scheduled tasks。
- 系统能力：进程、文件、网络、系统代理、通知、托盘（托盘可做可选能力）。
- 更新体系：core 更新、回滚、校验。

## 1. 项目结构（落地目标）

```text
jumper-desktop/
  engine/
    core-go/                # Go 核心能力（bridge 能力重组）
    runtime-assets/         # sing-box 多平台二进制与校验文件
  flutter/
    packages/
      jumper_sdk/           # 对外 Dart API（业务项目直接依赖）
      jumper_sdk_platform/  # Platform channel/FFI 适配层
    apps/
      sdk_smoke_app/        # 冒烟验证 App（无业务 UI）
```

## 2. 里程碑与硬门槛

## M1（第 1-3 周）：Headless Core 可运行

**目标**
- 从 `GUI.for.SingBox` 抽离无 UI 业务核心，形成可编程服务层。

**交付物**
- `KernelRuntimeService`
- `ConfigEngine`
- `CoreApiClient`
- `SubscriptionService`
- `RulesetService`
- `PluginRuntime`（先保留能力，先不扩展新特性）
- `TaskSchedulerService`

**硬验收门槛（全部满足）**
- 可通过 API 完成 `start -> ws events -> stop`。
- 可完成一次订阅更新与规则集更新。
- 可导出并落盘有效 `config.json`，并通过 sing-box 启动。
- 关键路径回归用例通过率 >= 95%（至少 20 条）。

**风险与预案**
- 风险：`kernelApi` 拆分行为不一致。
- 预案：保留 compatibility adapter（映射旧调用）直到 M2 稳定。

---

## M2（第 4-6 周）：Flutter SDK 接入可用

**目标**
- 让外部 Flutter 项目仅依赖 SDK 即可调用完整能力。

**交付物**
- `jumper_sdk` Dart facade（命令 + stream）
- `jumper_sdk_platform`（平台通道）
- `sdk_smoke_app`（冒烟流程：start/logs/proxies/stop）

**硬验收门槛（全部满足）**
- Flutter 调用可执行核心 10+ API：
  - start/stop/restart/state
  - get/set configs
  - get/use proxies
  - get/close connections
  - subscribe logs/traffic/memory/connections
- 事件流丢包率可观测且连续运行 30 分钟无崩溃。
- 单次异常恢复（核心崩溃后重启）成功。

**风险与预案**
- 风险：跨线程消息顺序与生命周期不同步。
- 预案：引入统一事件序号 + last-seen checkpoint 机制。

---

## M3（第 7-9 周）：发布与可选能力完成

**目标**
- 形成可发布的 SDK + runtime 产物，支持升级与回滚。

**交付物**
- runtime 多平台资产包（os/arch）
- 更新校验与回滚机制
- 可选能力模块：system-proxy、notify、tray、updater
- 发布文档与接入样例

**硬验收门槛（全部满足）**
- 三平台（macOS/Windows/Linux）最少各 1 次全流程通过。
- runtime 资产校验失败可阻断安装。
- 回滚流程可在 5 分钟内恢复可运行状态。

## 3. 工程规范（执行必须遵守）

- 接口先行：所有服务先定义契约文件再写实现。
- 错误码统一：`SDK-<domain>-<code>`，不可直接透传原始异常给上层。
- 能力分层：
  - Core：强制能力
  - Capability：可选能力（proxy/tray/notify/updater）
  - Adapter：平台实现细节
- 每周五固定进行一次回归与风险复盘。

## 4. 完成定义（Definition of Done）

- 文档：接口契约、错误码、接入说明齐全。
- 代码：核心路径有自动化测试，至少覆盖启动/停止/事件流/配置生成。
- 运行：`sdk_smoke_app` 可复现完整链路。
- 发布：有可复用构建命令、版本号、变更记录与回滚说明。

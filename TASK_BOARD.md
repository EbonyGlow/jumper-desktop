# Task Board (Execution Tracker)

## Current Gate Snapshot

- M1：未启动（本轮交付聚焦 M2/M3）。
- M2：已完成并通过。
- M3：`M3-01 ~ M3-06` 与 `M3-GATE` 均已完成。
- 当前发布阻塞：无（M3 证据链已闭环）。

## Phase M1 - Headless Core

- [ ] M1-01 拆分 `KernelRuntimeService`（start/stop/restart/state/events）
- [ ] M1-02 抽离 `ConfigEngine`（generate/restore/validate）
- [ ] M1-03 抽离 `CoreApiClient`（REST + WS）
- [ ] M1-04 抽离 `SubscriptionService`
- [ ] M1-05 抽离 `RulesetService`
- [ ] M1-06 抽离 `PluginRuntime`（保留现能力，不扩展）
- [ ] M1-07 抽离 `TaskSchedulerService`
- [ ] M1-08 建立 compatibility adapter（旧调用映射）
- [ ] M1-09 完成 20 条关键路径回归
- [ ] M1-GATE 通过 M1 硬验收门槛

## Phase M2 - Flutter SDK

- [x] M2-01 创建 `jumper_sdk` package
- [x] M2-02 创建 `jumper_sdk_platform` plugin
- [x] M2-03 定义 Dart API（commands + streams）
- [x] M2-04 完成平台通道桥接（macOS/windows/linux）
- [x] M2-05 创建 `sdk_smoke_app`
- [x] M2-06 打通 start/logs/proxies/stop 冒烟流程
- [x] M2-07 连续 30 分钟稳定性验证（已通过：`iterations=352`、`failure_count=0`）
- [x] M2-GATE 通过 M2 硬验收门槛

## Phase M3 - Release & Optional Capabilities

- [x] M3-01 runtime-assets 多平台打包（含校验文件）
- [x] M3-02 更新机制（download/verify/apply/rollback）
- [x] M3-03 capability: system-proxy
- [x] M3-04 capability: notify
- [x] M3-05 capability: tray
- [x] M3-06 发布文档与外部接入示例
- [x] M3-GATE 通过 M3 硬验收门槛

## Blocking Issues

- [ ] BLOCK-01 macOS 已支持可选真实进程启动 + 配置自动落盘；但默认仍可退回 simulator
- [x] BLOCK-02 `run-smoke-runtime-e2e-drive.sh` / `run-smoke-runtime-e2e-drive-direct.sh` 已切换到 `flutter test integration_test/...`，提示已清理
- [x] BLOCK-03 已补 `setupRuntime/inspectRuntime` 容器内分发流程，并新增 checksums + backup/rollback + release-check 流程

## Notes

- 每天收工前必须更新本看板。
- 未过 Gate 不允许进入下一里程碑。
- M2-07 稳定性验收记录：
  - 预检：`stability-20260226-140841.summary.txt`（180s，36/36 成功）
  - 长稳：`stability-20260226-141210.summary.txt`（1800s，352/352 成功）
- M3-01 多平台资产与校验已落地：
  - 已拉取：`darwin-arm64` / `darwin-amd64` / `linux-amd64` / `linux-arm64` / `windows-amd64`
  - 已通过：`./engine/runtime-assets/generate-checksums.sh` + `./engine/runtime-assets/verify-checksums.sh`（all）
- M3-02 更新机制已落地：
  - 新增：`run-runtime-update.sh`（fetch -> checksum verify -> backup -> apply -> validate -> rollback）
  - 新增：`engine/runtime-assets/validate-runtime-install.sh`（安装后健康检查）
  - 回滚实测：故意使用错误 API 端口触发失败，已自动恢复备份版本（`VERSION` 恢复成功）
- M3-03 system-proxy 能力已落地：
  - SDK：`JumperSdkClient implements SystemProxyCapability`
  - 平台通道：`enableSystemProxy` / `disableSystemProxy` / `getSystemProxyStatus`
  - macOS：基于 `networksetup` 执行系统代理启停与状态查询
- M3-04 notify 能力已落地：
  - SDK：`JumperSdkClient implements NotifyCapability`
  - 平台通道：`requestNotificationPermission` / `getNotificationPermissionStatus` / `showNotification`
  - macOS：基于 `UNUserNotificationCenter` 执行通知授权与本地通知发送
- M3-05 tray 能力已落地：
  - SDK：`JumperSdkClient implements TrayCapability`
  - 平台通道：`showTray` / `updateTray` / `hideTray` / `getTrayStatus`
  - macOS：基于 `NSStatusBar` 创建与更新状态栏托盘项
- M3-06 发布文档与外部示例已落地：
  - 新增：`RELEASE_GUIDE.md`（发布门禁、证据矩阵、回滚策略）
  - 新增：`EXTERNAL_INTEGRATION_EXAMPLE.md`（外部 Flutter 项目接入示例）
- M3-GATE 当前状态：
  - 已满足：runtime 校验失败阻断、回滚能力、macOS/Linux/Windows 全流程证据归档
  - 最新复核：`M3 Gate Runtime Evidence` 与 `SDK Platform Native Evidence` 均已通过
- M3-GATE 自动化补齐（已闭环）：
  - 新增 CI：`.github/workflows/m3-gate-runtime-evidence.yml`（macOS/Linux/Windows 三平台矩阵）
  - 新增清单：`M3_GATE_EVIDENCE.md`（触发方式、artifact 要求、勾选规则）
  - 新增核对脚本：`verify-m3-gate-evidence.sh`（对三平台 artifacts 一键验收）
  - 执行结果：三平台证据已在 CI runner 完成并归档，`M3-GATE` 已勾选
- 收尾输出：
  - 新增 `RELEASE_DAY_COMMANDS.md`（发布日一页式命令手册）
- 严格审计修复：
  - 校验链路去除“先生成再验签”的自签名路径（`run-runtime-release-check.sh` / CI / update）
  - `run-runtime-update.sh` 新增 `ERR` 级自动回滚兜底
  - `validate-runtime-install.sh` 去除 `jq` 强依赖，统一 Python 解析
  - macOS system-proxy 增加启用前快照与禁用时恢复（避免覆盖用户原代理配置）
  - `inspectRuntime` 版本匹配改为严格等值（`VERSION` 缺失不再视为匹配）
  - `setupRuntime` 强制要求 `minimal-config.json` 存在（缺失即失败）
  - `run-runtime-update.sh` 清理逻辑改为覆盖隐藏文件（新增 `clear_directory_contents`）
  - 运行时下载链路增强缓存复用与重试（`fetch-sing-box.sh`），降低外网抖动导致的误报
  - 新增故障注入报告：`FAULT_INJECTION_REPORT.json`（首次安装失败清理 + 已安装失败回滚含隐藏文件）
  - 发布基线锁定：`RELEASE_GUIDE.md` + `RELEASE_DAY_COMMANDS.md` 已加入禁止操作与强约束规则
  - 回退保护：新增 `audit-baseline-guard.sh` + `.github/workflows/audit-baseline-guard.yml`
  - 变更追溯：`RELEASE_GUIDE.md` 已新增 `Audit Fix Log (2026-02-26)` 与 `Strict Round` 记录

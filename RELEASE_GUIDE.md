# Jumper SDK Release Guide

本指南用于将 `jumper-desktop` 当前能力打包为可发布交付，并给出可执行的验收步骤与回滚策略。

## 1. Release Preconditions

- Flutter 固定版本：`3.41.2`（通过 `.fvmrc`）
- 本地依赖检查通过：
  - `flutter/packages/jumper_sdk`
  - `flutter/packages/jumper_sdk_platform`
  - `flutter/apps/sdk_smoke_app`
- runtime 资产已准备（见 `engine/runtime-assets/manifest.json`）

## 2. Standard Release Pipeline

在仓库根目录执行：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop

# 1) 代码质量门禁
cd flutter/packages/jumper_sdk && fvm flutter analyze && fvm flutter test
cd ../jumper_sdk_platform && fvm flutter analyze && fvm flutter test
cd ../../apps/sdk_smoke_app && fvm flutter analyze && fvm flutter test
cd ../../..

# 2) 构建前准备目标架构 runtime（latest + 锁定证据）
./engine/runtime-assets/prepare-runtime-assets.sh darwin-arm64 latest

# 3) macOS runtime 链路（发布前强校验）
./run-runtime-release-check.sh darwin-arm64 latest com.example.sdkSmokeApp

# 4) 稳定性门禁（30分钟）
./run-runtime-stability-check.sh darwin-arm64 "$(python3 - <<'PY'
import json
from pathlib import Path
print(json.loads(Path('engine/runtime-assets/resolved-runtime-lock.json').read_text())['resolved_version'])
PY
)" 1800 5
```

说明：`prepare-runtime-assets.sh` 会在构建前更新目标架构资产并生成 `resolved-runtime-lock.json`。`generate-checksums.sh` 仅用于受信任发布工位的手动维护，不属于消费侧验收流水线。

如需在受信任工位更新 checksums，使用：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop
./engine/runtime-assets/generate-checksums.sh
./engine/runtime-assets/verify-checksums.sh
```

审计强约束：
- 消费侧禁止执行 `generate-checksums.sh`。
- 发布前必须执行 `verify-checksums.sh`，不可跳过。

## 3. Runtime Update/Rollback Validation

更新机制应至少验证一次成功路径和一次失败回滚路径：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop

# 成功路径
./run-runtime-update.sh darwin-arm64 1.12.22 com.example.sdkSmokeApp

# 失败回滚路径（示例：错误 API 端口，触发自动 rollback）
./run-runtime-update.sh darwin-arm64 1.12.22 com.example.sdkSmokeApp http://127.0.0.1:29999
```

## 4. Platform Evidence Matrix (M3-GATE)

M3 硬门槛要求三平台至少各 1 次全流程通过。当前建议按下述矩阵收集证据：

- `macOS`：
  - `run-runtime-release-check.sh` 输出日志
  - `stability-*.summary.txt`（30 分钟）
- `Linux`：
  - CI runner 上执行 runtime 链路脚本并归档日志
- `Windows`：
  - CI runner 上执行 runtime 链路脚本并归档日志

建议将三平台日志统一归档到 release artifacts（例如 `release-evidence/<version>/`）。
可直接复用 `.github/workflows/m3-gate-runtime-evidence.yml` 生成三平台证据。

## 5. Rollback Strategy

- 资产层回滚：`engine/runtime-assets/rollback-runtime-container.sh`
- 更新层回滚：`run-runtime-update.sh` 内置自动回滚
- 发布回滚触发条件：
  - checksum 不通过
  - runtime 健康检查失败
  - 稳定性验证出现失败样本

## 6. Known Residual Risks

- macOS 下 sandbox 打开时，runtime 路径必须位于容器内（错误码：`RUNTIME_PATH_BLOCKED_BY_SANDBOX`）。
- Linux/Windows 全流程门禁依赖对应平台 CI runner，当前无法在单机 macOS 上直接完成最终验收。

## 7. Audit Baseline Lock

以下规则作为发布基线，后续变更需明确评审：

- 不允许恢复“generate + verify”同机串联作为验签路径。
- 不允许绕过 `run-runtime-update.sh` 的原子更新与自动回滚。
- 不允许在代理能力里直接全量 `off` 覆盖用户原配置（必须走快照恢复）。

自动化保护：

- 本地可运行：`./audit-baseline-guard.sh`
- CI 已提供：`.github/workflows/audit-baseline-guard.yml`

## 8. Audit Fix Log (2026-02-26)

本次审计后已完成以下修复并通过回归：

- 去除不安全校验路径：
  - `run-runtime-release-check.sh` 不再执行 `generate-checksums.sh`
  - `run-runtime-update.sh` 不再执行 `generate-checksums.sh`
  - `m3-gate-runtime-evidence.yml` 不再包含 generate 步骤
- 强化更新回滚：
  - `run-runtime-update.sh` 增加 `ERR` 级 trap，apply 后任意异常均会回滚
- 提升跨平台兼容：
  - `validate-runtime-install.sh` 改为 Python 解析 JSON，移除 `jq` 依赖
  - `run-runtime-stability-check.sh` 增加 Windows 可执行名分支（`sing-box.exe`）
- 修正平台能力语义与安全性（macOS）：
  - `setupRuntime/inspectRuntime` 增加 `version` 与 manifest 一致性校验
  - system-proxy 增加快照幂等保护（避免二次启用覆盖用户原始代理配置）

建议发布前执行：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop
./audit-baseline-guard.sh
```

## 9. Audit Fix Log (Strict Round, 2026-02-26)

本轮严格审计新增修复（聚焦一致性与原子性）：

- `inspectRuntime` 版本匹配改为严格等值：
  - 之前：`VERSION` 缺失时仍可能被视为匹配
  - 现在：`versionMatches` 仅在 `runtimeVersion == request.version` 时为 `true`
- `setupRuntime` 配置文件改为强约束：
  - 之前：`minimal-config.json` 缺失时可能被跳过复制
  - 现在：缺失即失败（`SETUP_RUNTIME_FAILED`），阻断不完整安装
- `run-runtime-update.sh` 清理逻辑修复隐藏文件遗漏：
  - 新增 `clear_directory_contents`（Python 实现），确保清理包含隐藏文件
  - 已用于 apply、首次安装失败清理、本地回滚恢复三条路径
- 基线守卫升级：
  - `audit-baseline-guard.sh` 新增规则，锁定上述 3 项修复，防止回归
- 运行时资产拉取增强（降低网络抖动影响）：
  - `fetch-sing-box.sh` 增加本地缓存复用（已存在 binary/archive 时不重复下载）
  - `curl` 增加重试参数（`--retry 3 --retry-all-errors --retry-delay 2`）

本轮额外完成故障注入审计：

- 报告文件：`FAULT_INJECTION_REPORT.json`
- 审计用例：
  - 首次安装模式：在 `validate-runtime-install.sh` 阶段注入失败，确认 runtime 目录被清空且无残留
  - 已安装模式：在 `validate-runtime-install.sh` 阶段注入失败，确认回滚后包含隐藏文件在内的数据完全恢复

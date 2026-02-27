# M3 Gate Evidence Checklist

本清单用于完成 `M3-GATE` 最后一项：三平台全流程证据收集。

## 1) CI Workflow

仓库已提供：

- `.github/workflows/m3-gate-runtime-evidence.yml`

该工作流会在 `macOS / Linux / Windows` 三平台执行：

1. 下载 runtime 资产
2. 生成并校验 checksum
3. 执行 `validate-runtime-chain.sh`
4. 上传证据 artifacts

## 2) Manual Trigger

在 GitHub Actions 页面手动触发：

- Workflow: `M3 Gate Runtime Evidence`
- Trigger: `workflow_dispatch`

## 3) Required Artifacts

每个平台应至少包含：

- `engine/runtime-assets/checksums.json`
- `engine/runtime-assets/<platform_arch>/runtime.log`
- `engine/runtime-assets/<platform_arch>/proxies.json`

预期 artifact 名称：

- `runtime-evidence-darwin-arm64`
- `runtime-evidence-linux-amd64`
- `runtime-evidence-windows-amd64`

## 3.1) One-command Verification

下载三平台 artifacts 并解压到同一个目录后，可执行：

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop
./verify-m3-gate-evidence.sh /absolute/path/to/release-evidence
```

目录结构示例：

```text
release-evidence/
  runtime-evidence-darwin-arm64/
  runtime-evidence-linux-amd64/
  runtime-evidence-windows-amd64/
```

## 4) Gate Decision Rule

满足以下条件即可勾选 `M3-GATE`：

- 三个平台 job 全部成功
- 三个平台 artifacts 均存在且可读取
- `runtime.log` 可看到 startup marker
- `proxies.json` 中代理组数量 > 0

## 5) Closure Record (Filled)

状态：**PASS**

### 5.1 Runtime evidence (M3 Gate Runtime Evidence)

- Workflow：`M3 Gate Runtime Evidence`
- 触发方式：`workflow_dispatch / push`
- 结果：三平台 job 全部通过
  - `darwin-arm64`：通过
  - `linux-amd64`：通过
  - `windows-amd64`：通过
- 产物：已生成并可下载
  - `runtime-evidence-darwin-arm64`
  - `runtime-evidence-linux-amd64`
  - `runtime-evidence-windows-amd64`

### 5.2 Native runtime evidence (SDK Platform Native Evidence)

- Workflow：`SDK Platform Native Evidence`
- 结果：Linux / Windows 均通过
- 关键验收：
  - `native start/stop/restart uses real runtime mode` 通过
  - `getPlatformVersion test` 通过
  - Windows 构建成功并通过 integration tests

### 5.3 Fixes included in this closure

- Windows 插件编译修复：
  - `flutter/packages/jumper_sdk_platform/windows/jumper_sdk_platform_plugin.h`
  - 增加 `#include <flutter/encodable_value.h>` 以支持 `EncodableMap`
- M3 跨平台最小配置补齐：
  - `engine/runtime-assets/linux-amd64/minimal-config.json`
  - `engine/runtime-assets/windows-amd64/minimal-config.json`

### 5.4 Final gate statement

- `M3-GATE` 最后一项（三平台全流程证据）已闭环。
- 证据可通过 GitHub Actions 最新成功运行与 artifacts 复核。

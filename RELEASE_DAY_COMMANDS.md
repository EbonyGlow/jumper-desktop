# Release Day Commands (One Page)

仅保留发布当天需要执行的命令，按顺序执行即可。

## 0) 进入目录

```bash
cd /Users/sean/Desktop/cyber/jumper-desktop
```

## 1) Flutter 代码门禁

```bash
cd flutter/packages/jumper_sdk
fvm flutter analyze && fvm flutter test

cd ../jumper_sdk_platform
fvm flutter analyze && fvm flutter test

cd ../../apps/sdk_smoke_app
fvm flutter analyze && fvm flutter test

cd ../../..
```

## 2) Runtime 资产与校验

```bash
./engine/runtime-assets/generate-checksums.sh
./engine/runtime-assets/verify-checksums.sh
```

> 基线规则：`generate-checksums.sh` 仅允许在受信任发布工位执行；验收机/消费机禁止执行 `generate`，只能执行 `verify`。

## 3) 发布链路复核（macOS）

```bash
./run-runtime-release-check.sh darwin-arm64 1.12.22 com.example.sdkSmokeApp
```

## 4) 长稳验证（30 分钟）

```bash
./run-runtime-stability-check.sh darwin-arm64 1.12.22 1800 5
```

## 5) 三平台 Gate 证据（如当次发布需要）

```bash
# 在 GitHub Actions 触发:
# .github/workflows/m3-gate-runtime-evidence.yml

# 下载 artifacts 后本地核对:
./verify-m3-gate-evidence.sh /absolute/path/to/release-evidence
```

## 6) 失败快速回滚

```bash
# runtime 目录回滚
./engine/runtime-assets/rollback-runtime-container.sh com.example.sdkSmokeApp latest

# 或更新编排自动回滚验证
./run-runtime-update.sh darwin-arm64 1.12.22 com.example.sdkSmokeApp http://127.0.0.1:29999
```

## 7) 禁止操作（审计后强约束）

- 禁止在消费侧把 `generate-checksums.sh` 与 `verify-checksums.sh` 串联执行（会造成自签名校验）。
- 禁止手工跳过 `verify-checksums.sh` 直接发布或更新 runtime。
- 禁止绕过 `run-runtime-update.sh` 的回滚链路直接覆盖 runtime 目录。

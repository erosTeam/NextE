# NextE 本地开发环境

本文件只记录可长期复用的本地构建、签名和工作区规则，不记录具体设备地址、当前分支、临时
worktree、任务队列或某次验证快照。所有易变化事实都必须实时查询。

## 依赖与构建

- 新 worktree、缺少 `oh_modules`、或依赖清单变化后先运行 `ohpm install --all`。
- macOS 使用项目脚本安装本地签名配置并构建：

  ```bash
  bash scripts/setup-local-build-profile.sh
  bash scripts/build_hvigor_signed.sh
  ```

- `build-profile.local.json5` 和签名材料只保存在本地。不要提交、打印或把它们当普通配置复制。
- 真机/模拟器安装使用 signed HAP。unsigned HAP 只用于公开 CI 构建验证，不能覆盖已签名安装。
- `dev.sh` 是 Linux legacy 辅助脚本；macOS 不用它替代官方 DevEco/Hvigor 签名路径。

## 工作区与工具发现

- 每次用 `git status`、`git worktree list` 和当前环境实际路径确认状态；不依赖历史 handoff 的
  分支、worktree、CLI 版本或设备列表。
- 不清理、不复用、不覆盖旧 worktree 或其他任务的 WIP，除非用户明确给出路径和操作授权。
- 全局 CI 门禁由 `scripts/run_ci_preflight.sh` 统一执行，`.github/workflows/build.yml` 必须调用同一
  脚本，避免本地与远端清单漂移。配置或旧日志里出现过某个工具，不等于当前环境已经执行它。

## 设备

- 设备地址和连接状态不写入本文件。按 [AGENTS.md](../../AGENTS.md) 用实时
  `hdc list targets -v` 解析用户给出的设备，再按 [Device lease](../device-lease.md) 获取租约。
- 模拟器可验证普通布局和交互；硬件、性能、账号、权限或真实网络行为需要与问题匹配的真机证据。

## 基础检查

开发过程中可按变更范围选择检查：

```bash
node scripts/test_v1_decorator_inventory_contract.mjs
node scripts/test_version_consistency_contract.mjs
python3 scripts/check_i18n_duplicates.py
git diff --check
```

任何推送前都必须额外运行：

```bash
bash scripts/run_ci_preflight.sh
```

推送后必须检查精确 HEAD 对应的 GitHub Actions 结论；Actions 未成功时不能用本地 Hvigor 或部分门禁
宣布交付完成。用户可见、设备相关和 CI/release 工作仍需要各自指南要求的运行时证据。

## 版本步进与发版

`AppScope/app.json5` 的 `app.versionName` 是唯一的发布版本事实源；`versionCode` 每次发布 +1。
CI 的 release 产物命名与 release 正文都从该文件读取。`oh-package.json5` 的 version 不参与发布
决策，但必须与 versionName 一致，由契约脚本强制。

发版步进在一次提交内全部完成，缺一即视为未完成：

1. `AppScope/app.json5`：versionCode +1，versionName 步进。
2. 根 `oh-package.json5`：version 等于新 versionName。
3. `entry/`、`feature/*`、`shared` 每个模块的 `oh-package.json5`：version 等于新 versionName。
4. 新增 `changelog/vX.Y.Z.md`。

`third_party/*`（reader-kit、reader-enhancement）是跨项目共享库，保持独立版本，不随宿主发版。

推送前必须运行版本契约并要求通过：

```bash
node scripts/test_version_consistency_contract.mjs
```

该契约存在的直接原因：2026-10-15 发版只改了 app.json5，release 产物名和正文全部退回旧版本；
且此前多次发版漏改模块 oh-package，版本号曾长期滞留在 1.3.4。禁止从错误历史归纳发版清单。

发布由 tag 触发：main 推送只构建验证；`git tag vX.Y.Z && git push origin vX.Y.Z` 触发签名构建
与 release。tag 必须指向包含完整版本步进的提交。release 生成后核对产物名
`NextE_X.Y.Z_ohos-release-unsigned.hap` 与正文版本；不一致立即停止并修正版本文件，禁止再打
一个新 tag 掩盖，禁止通过删 tag 重发布修复。

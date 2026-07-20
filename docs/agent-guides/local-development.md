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
- 不假设存在统一的本地 harness。全局 CI 门禁以 `.github/workflows/build.yml` 为准；本地按当前
  变更范围直接运行对应脚本。配置或旧日志里出现过某个工具，不等于当前环境已经执行它。

## 设备

- 设备地址和连接状态不写入本文件。按 [AGENTS.md](../../AGENTS.md) 用实时
  `hdc list targets -v` 解析用户给出的设备，再按 [Device lease](../device-lease.md) 获取租约。
- 模拟器可验证普通布局和交互；硬件、性能、账号、权限或真实网络行为需要与问题匹配的真机证据。

## 基础检查

按变更范围选择，不把所有脚本机械地当作每次必跑：

```bash
node scripts/test_v1_decorator_inventory_contract.mjs
node scripts/test_version_consistency_contract.mjs
python3 scripts/check_i18n_duplicates.py
git diff --check
```

用户可见、设备相关和 CI/release 工作仍需要各自指南要求的运行时证据。

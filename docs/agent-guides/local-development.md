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

先核对远端 Release、tag、已有 prepare 提交和对应变更范围，再确定本次目标版本；不能只对工作区
当前版本机械加一。历史遗漏不代表模块版本可以不更新。

一次发版必须同步核对：

- `AppScope/app.json5` 的 `versionName` 和 `versionCode`；正常升级递增 code，修正发布时保留已分配
  code 的兼容性，不把用户设备的安装版本倒退。
- 根、`entry/`、`feature/*`、`shared/` 的全部 `oh-package.json5`，以及存在时的根 `package.json`。
- 关于页的备用版本文字，以及 `changelog/vX.Y.Z.md`；日志覆盖上一正确 Release 以来的用户可见变化。
- CI 读取的版本、tag、HAP 内 `module.json` 的版本、附件文件名和 Release 正文。

更新日志必须以该项目上一正式发布版本到本次发布版本的最终差异为依据：先比较两个版本的 tag、
源码与用户可见行为，再编写日志。不能把本次会话、提交列表或开发过程当作版本差异。
新增功能按最终能力描述；开发期间对它做过的图标、布局、动画调整及返工合并到该功能中，不冒充
旧版缺陷或独立改进。上一版本已有且最终行为未变的功能、已撤回方案、测试和内部实现细节不写入
面向用户的日志；不得补写没有版本差异证据的效果。分别核对 NextE、NextN 的基线，仓库日志与
Release 正文保持一致。版本基线用于内部核对，不在日志正文增加“相较 vX.Y.Z”等前缀。

宿主包的 version 必须等于 app 的 versionName。`third_party/` 独立共享库保持自身版本；不因宿主
发版改共享库。历史说明、测试样本和依赖版本不能进行全仓字符串替换。

CI 从 `AppScope/app.json5` 读取发布版本。推送前运行 `node scripts/test_version_consistency_contract.mjs`；
该检查还须在 CI 中实际执行。NextE 另外运行 `bash scripts/run_ci_preflight.sh`。

main 推送触发构建；包含完整发布修正的提交通过检查后，再推送匹配的 `vX.Y.Z` tag，触发 Release
模式的 unsigned HAP 构建与发布。核对精确提交的 Actions 结果，下载实际 Release 附件，验证包内
版本、摘要和正文后才算发布完成。

错误 tag、Release 和附件按本次授权范围清理、修正并重新发布。不能因当前工具权限不足就编造
“禁止删除或重发”的项目规则；纠错方式以实际发布状态和用户指令为准。

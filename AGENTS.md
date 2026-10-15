# NextE agent entry

**未经用户明确允许，禁止更改样式；修 bug 也不例外。**

This is the repository entrypoint. Keep durable rules here; put platform, product, device and build
details in the linked guides. The current user request is the only source of scope or authorization.

## 每次开始

- 先读 [始终生效规则](docs/agent-guides/always-loaded-rules.md)，再进行计划、修改、验证、派工或汇报。
- 用户最新明确要求优先；旧计划、摘要、记忆、租约和自动唤醒不产生新任务或授权。
- 查看当前源码、脚本、工作区与新鲜证据；计划、交接、产物和归档文档都不是当前事实。
- 修改已有行为前，用文件名和符号查询 [已拒绝方案](docs/agent-guides/rejected-approaches.md)；匹配的 `REJECTED` 条目禁止恢复，除非用户审阅失败证据后明确重新允许。

## 按工作读取

技能绑定是强制的：下表把每类工作钉死到具体技能与文档。压缩或从摘要恢复后，必须按表重读对应技能，
不得凭摘要里的操作模式跳过技能。

| 工作 | 必读 |
| --- | --- |
| HarmonyOS 源码、构建 | `harmony-mandatory-preflight` 和 `harmony-next` 技能，以及 [平台约束](docs/agent-guides/harmonyos-default.md) |
| 设备、截图、日志、UI 操作 | 另读 `harmony-run-device-diagnostics` 技能和 [设备协议](docs/device-lease.md) |
| 本地构建、签名、依赖 | [本地开发](docs/agent-guides/local-development.md) |
| 产品语义、验收 | [产品规则](docs/agent-guides/product-work.md) |
| 共享 Reader | [共同职责](third_party/reader-kit/README.md#consumer-contract) |
| EH 集成、Cookie、远端写入 | [EH 契约](docs/eh-integration-contract.md) |
| 漫画翻译 | [漫画翻译设计](docs/manga-translation-design.md) |
| 架构、模块边界 | [架构](docs/architecture.md) |
| 规划、计划生命周期 | [路线图](docs/roadmap.md) / [计划生命周期](docs/plans/README.md) |

## Hard stops

### State Management V2

`entry/`, `feature/` and `shared/` use V2 state only. Do not add or restore V1 decorators, adapters,
allowlists, temporary bridges or key-churn refresh workarounds. If a requested change appears to require V1,
stop with source/build evidence and propose a V2 design. For every ArkTS/UI/state change, run:

```bash
node scripts/test_v1_decorator_inventory_contract.mjs
```

The result must be `0 file(s)`.

### Device operations

There is no default device. The user must select a full HDC target or an unambiguous shorthand. Resolve a
shorthand against the current `Connected` output of `hdc list targets -v`; continue only on one match, and
never infer a target from history, artifacts or another task. Before installation, launch, input, screenshot,
layout, foreground inspection or logs, acquire the resolved target's lease with
`scripts/device-lease --device <target> ...`; follow [device lease](docs/device-lease.md).

Every HDC command must run in the host environment outside the sandbox: sandboxed network restrictions make HDC report `Connect server failed`, empty output, or ping timeouts, none of which proves the device is offline. Never report a device as offline or disconnected from a sandboxed failure alone.

### Pushes

Before any push, run `bash scripts/run_ci_preflight.sh` and require success. After pushing, inspect the
Actions run for the exact pushed commit; local builds or partial checks are not CI proof.

## Working boundaries

- Shared Reader changes also follow the common
  [consumer contract](third_party/reader-kit/README.md#consumer-contract).
  Use the current cross-host work order identified by the active task; per-app
  plans and historical receipts must not create a competing Reader queue.

- Preserve unrelated user changes and do not commit, push, tag, merge or clean worktrees unless explicitly asked.
- Keep UI fixes narrow; do not add custom controls or new contracts for ordinary layout, copy or visual taste.
- Do not guess uncertain HarmonyOS APIs or runtime behavior; use `harmony-next` or official Huawei docs.
- The reference projects are `../eros_fe`, `../V2Next` and `../eros_n_ohos`; confirm current NextE behavior first.
- `docs/archive/` and `docs/plans/archive/` are historical evidence only and never create work or authorization.

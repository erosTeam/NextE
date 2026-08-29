# NextE agent entry

This is the repository entrypoint. Keep durable rules here; put platform, product, device and build
details in the linked guides. The current user request is the only source of scope or authorization.

## Before acting

1. Read [always-loaded rules](docs/agent-guides/always-loaded-rules.md).
2. Read the guide for the work: [HarmonyOS](docs/agent-guides/harmonyos-default.md),
   [local development](docs/agent-guides/local-development.md), [product work](docs/agent-guides/product-work.md),
   [architecture](docs/architecture.md), [manga translation](docs/manga-translation-design.md),
   [EH integration](docs/eh-integration-contract.md), or [planning](docs/roadmap.md) /
   [plan lifecycle](docs/plans/README.md).
3. Read the applicable skill before using its workflow. Check current source, scripts, worktree state and
   fresh evidence; do not treat plans, handoffs, artifacts or archived documents as current facts.
4. Before editing an existing behavior, query [rejected approaches](docs/agent-guides/rejected-approaches.md)
   with the affected file and symbol names. A matching `REJECTED` entry must not be reintroduced unless
   the current user explicitly reopens it after reviewing its recorded failure.

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

### Pushes

Before any push, run `bash scripts/run_ci_preflight.sh` and require success. After pushing, inspect the
Actions run for the exact pushed commit; local builds or partial checks are not CI proof.

## Working boundaries

- Preserve unrelated user changes and do not commit, push, tag, merge or clean worktrees unless explicitly asked.
- Keep UI fixes narrow; do not add custom controls or new contracts for ordinary layout, copy or visual taste.
- Do not guess uncertain HarmonyOS APIs or runtime behavior; use `harmony-next` or official Huawei docs.
- The reference projects are `../eros_fe`, `../V2Next` and `../eros_n_ohos`; confirm current NextE behavior first.
- `docs/archive/` and `docs/plans/archive/` are historical evidence only and never create work or authorization.

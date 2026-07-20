# NextE Agent Guidelines

This file is the repository's single agent entrypoint. Keep it short: hard stops live here, and detailed
rules live in one domain guide each.

## Authority And Scope

- The user's latest explicit request defines the active scope. Plans, archived notes, handoffs, test
  artifacts, and device leases never create work or authorization by themselves.
- Within repository documentation, follow this order: `AGENTS.md` → the relevant guide below → current
  source and fresh evidence → active task plan. `docs/archive/` and `docs/plans/archive/` are historical
  evidence only.
- Agents may choose reversible implementation details that preserve the requested result. A choice that
  changes product meaning, data ownership, remote schema, user-visible hierarchy, or another major
  trade-off must be explained and returned to the user for decision before implementation.
- Do not create a second global rule set. Merge durable rules into the relevant guide and archive task-
  specific evidence when its lane is no longer active.

## Hard Stop: State Management V2 Only

State Management V1 is retired in `entry/`, `feature/`, and `shared/`. Do not introduce or restore
`@Component`, `@State`, `@Prop`, `@Link`, `@Watch`, `@StorageLink`, `@StorageProp`, `@Provide`,
`@Consume`, `@ObjectLink`, `@Observed`, `@Track`, `@LocalStorageLink`, or `@LocalStorageProp`.

Use `@ComponentV2`, `@ObservedV2`, `@Trace`, `@Local`, `@Param`, `@Monitor`, and project state holders.
Do not add a V1 adapter, allowlist, temporary bridge, or key-churn refresh workaround. If a change appears
to require V1, stop and return `BLOCKED` with source/build evidence and a V2-only alternative.

For every ArkTS/UI/state change, run `node scripts/test_v1_decorator_inventory_contract.mjs`; it must
report `0 file(s)` before merge or push.

## Hard Stop: Device Selection

Before any device-affecting command, the user or current explicit task must identify the intended device.
A full HDC target or an unambiguous shorthand such as `237`, a device label, or an emulator name is valid.

For shorthand, run `hdc list targets -v` and resolve it only against live `Connected` targets. A numeric
shorthand matches the final IPv4 octet. Continue only when exactly one target matches; otherwise ask.
Never infer a target from old notes, artifacts, another task, or “the only connected device”.

Before installation, launch, input, screenshot/recording, foreground inspection, or other device control,
acquire the lease with the resolved full target: `scripts/device-lease --device <target> ...`. Follow
[Device lease](docs/device-lease.md).

## Required Reading

- Every NextE task: [Always-loaded rules](docs/agent-guides/always-loaded-rules.md).
- ArkTS, ArkUI, NDK, or UI work: [HarmonyOS constraints](docs/agent-guides/harmonyos-default.md).
- Build, signing, worktree, or local-tool work: [Local development](docs/agent-guides/local-development.md).
- Device or emulator work: [Device lease](docs/device-lease.md).
- Product bug or feature work: [Product work](docs/agent-guides/product-work.md).
- Architecture-sensitive work: [Architecture](docs/architecture.md).
- EH protocol, parser, cookie, auth, deep-link, or remote-write work:
  [EH integration contract](docs/eh-integration-contract.md).
- Planning or milestone questions: [Roadmap](docs/roadmap.md) and [Plan lifecycle](docs/plans/README.md).

## Reference Projects

- `../eros_fe` — EH product behavior and UX reference.
- `../V2Next` — HarmonyOS architecture and native-component reference.
- `../eros_n_ohos` — prior art for Flutter-to-HarmonyOS integration pitfalls.

## Unsure? Don't Guess

For uncertain ArkTS/ArkUI/NDK APIs or DevEco/hdc/hilog behavior, use the `harmony-next` skill or official
Huawei documentation before acting.

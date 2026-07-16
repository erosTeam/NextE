# NextE Agent Guidelines

This file contains repo-wide hard stops and routes agents to the relevant guide. The user's latest
explicit request defines the active scope; plans, handoffs, historical evidence, and lease records do
not create work or device authorization by themselves.

## Hard Stop: State Management V2 Only

State Management V1 is retired in `entry/`, `feature/`, and `shared/`. Do not introduce or restore
`@Component`, `@State`, `@Prop`, `@Link`, `@Watch`, `@StorageLink`, `@StorageProp`, `@Provide`,
`@Consume`, `@ObjectLink`, `@Observed`, `@Track`, `@LocalStorageLink`, or `@LocalStorageProp`.

Use `@ComponentV2`, `@ObservedV2`, `@Trace`, `@Local`, `@Param`, `@Monitor`, and project state
holders. Do not add a V1 adapter, allowlist, temporary bridge, or key-churn refresh workaround. If a
change appears to require V1, stop and return `BLOCKED` with source/build evidence and a V2-only
alternative.

For every ArkTS/UI/state change, run
`node scripts/test_v1_decorator_inventory_contract.mjs`; it must report `0 file(s)` before merge/push.

## Device Selection: Explicit Intent, Live Resolution

Before any device-affecting command, the user or current active task plan must identify the intended
device. A full HDC target such as `192.168.50.237:12345` is valid, and so is an unambiguous shorthand
such as `237`, a device label, or an emulator name.

When shorthand is supplied:

1. Run the read-only discovery command `hdc list targets -v`.
2. Resolve the shorthand against the current `Connected` targets. A numeric shorthand such as `237`
   matches the final IPv4 octet, not an arbitrary substring.
3. If exactly one target matches, record and echo the resolved full target, then continue without asking
   the user to repeat it.
4. If zero or multiple targets match, stop and ask for clarification. Never choose a device merely
   because it is the only connected target.

Historical addresses, script defaults, handoffs, artifacts, other tasks, and lease records may not be
used to resolve a current selector. `scripts/device-lease` must receive the resolved full target through
`--device <target>` before installation, launch, input, screenshot/recording, foreground-dependent
inspection, or other device control. See [Device lease](docs/device-lease.md) for the exact sequence.

## Required Reading

- Every NextE task: [Always-loaded rules](docs/agent-guides/always-loaded-rules.md).
- ArkTS/ArkUI/platform work: [HarmonyOS default constraints](docs/agent-guides/harmonyos-default.md).
- Device, emulator, build-environment, or worktree work:
  [Current Mac/Codex handoff](docs/agent-guides/current-mac-codex-handoff.md) and
  [Device lease](docs/device-lease.md).
- Product bug or feature work: [Product bug / feature intake](docs/plans/active/product-bug-intake.md).
- Architecture-sensitive work: [Architecture](docs/architecture.md).
- EH protocol, parser, cookie, auth, or deep-link work:
  [EH integration contract](docs/eh-integration-contract.md).
- Planning or milestone questions: [Roadmap](docs/roadmap.md).

## Reference Projects

- `../eros_fe` — feature and UX reference.
- `../V2Next` — HarmonyOS architecture and standards reference.
- `../eros_n_ohos` — prior art for Flutter-to-OHOS integration pitfalls.

## Unsure? Don't Guess

For uncertain ArkTS/ArkUI/NDK APIs or DevEco/hdc/hilog behavior, use the `harmony-next` skill or
official Huawei documentation before acting.

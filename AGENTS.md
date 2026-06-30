# NextE Agent Guidelines

Index plus hard-stop constraints. Open the relevant guide for the current task.

## Hard Stop: State Management V2 Only

State Management V1 is retired in this project. New development must not introduce or restore V1 component/state decorators in `entry/`, `feature/`, or `shared/` code.

Forbidden: `@Component`, `@State`, `@Prop`, `@Link`, `@Watch`, `@StorageLink`, `@StorageProp`, `@Provide`, `@Consume`, `@ObjectLink`, `@Observed`, `@Track`, `@LocalStorageLink`, `@LocalStorageProp`. Use V2: `@ComponentV2`, `@ObservedV2`, `@Trace`, `@Local`, `@Param`, `@Monitor`, and project state holders.

Do not add a V1 adapter, allowlist, temporary bridge, or key-churn refresh workaround. If a requested change appears to require V1, stop and return `BLOCKED` with source/build/device evidence and a V2-only alternative.

For any ArkTS/UI/state change, `node scripts/test_v1_decorator_inventory_contract.mjs` is a required gate and must report `0 file(s)` before merge/push.

## Always Read First

- [Always-loaded rules](docs/agent-guides/always-loaded-rules.md) — data-flow boundary, gates, UI/product preservation, EH destructive writes, login/cookie security, commits.
- [HarmonyOS default constraints](docs/agent-guides/harmonyos-default.md) — ArkTS/ETS syntax hard stops, official API/resource/i18n/theme requirements, ArkUI animation constraints, EH-porting specifics.
- [Current Mac/Codex handoff](docs/agent-guides/current-mac-codex-handoff.md) — migrated-machine paths, current worktrees, emulator QA targets, and device facts.
- [Product bug / feature intake](docs/plans/active/product-bug-intake.md) — short intake index and writing rules. The user's latest explicit request decides what to do next.

## Project Docs

- [Architecture](docs/architecture.md) — module map, shared subsystems, data flow, state/navigation patterns.
- [EH integration contract](docs/eh-integration-contract.md) — domains, endpoints, cookie/auth model, parser→model list, image dispatch, exhentai gating, deep links.
- [Roadmap](docs/roadmap.md) — M0..M6 milestones, risks, open decisions.
- [Device lease](docs/device-lease.md) — advisory lease for agent-controlled real-device QA; check the current handoff before assuming a target because the migrated Mac now has local emulators.

## Reference Projects

- `../eros_fe` — the Flutter EH client whose **features & UX** NextE ports.
- `../V2Next` — the mature HarmonyOS ArkTS app whose **architecture & standards** NextE mirrors.
- `../eros_n_ohos` — an existing Flutter→OHOS port, useful prior art on EH-on-HarmonyOS pitfalls.

## Unsure? Don't guess

For any uncertain ArkTS/ArkUI/NDK API or DevEco/hdc/hilog task, use the `harmony-next` skill or official Huawei docs to confirm.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

NextE (bundle `com.erosteam.nexte`) is a native **HarmonyOS NEXT** third-party **E-Hentai / ExHentai** client written in **ArkTS/ArkUI**. It browses, searches, reads, downloads, and manages an EH account by parsing EH's web pages and `/api.php` JSON into native models. It ports the features & UX of the Flutter app **eros_fe** onto the engineering architecture & standards of the mature HarmonyOS app **V2Next** (`../V2Next`).

- SDK: `26.0.0` (API 26). DevEco command-line tools.
- Multi-module Hvigor workspace (9 modules). Package manager: `ohpm`.
- This is a HarmonyOS project: **consult the `harmony-next` skill / official docs for any ArkTS/ArkUI/NDK API, DevEco, `hdc`/`uitest`/`hilog` task** rather than guessing API shapes.
- See `docs/architecture.md`, `docs/eh-integration-contract.md`, `docs/roadmap.md`.

## Build / Sign / Install

Current macOS workflow uses the official DevEco/Hvigor build-profile signing path. Do **not** use `dev.sh` on macOS.

```bash
bash scripts/setup-local-build-profile.sh
bash scripts/build_hvigor_signed.sh
```

This installs the ignored local `build-profile.local.json5` into `build-profile.json5` with skip-worktree protection, then runs `hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon` and signs through the build profile.

`dev.sh` is a Linux legacy helper (Chinese help: `bash dev.sh --help`). Its signing material paths/passwords come from `scripts/dev.env` (copy from `scripts/dev.env.sample`, gitignored).

```bash
bash dev.sh                # debug: build + sign + install
bash dev.sh --build-only   # debug: build only → unsigned HAP (the CI green gate)
bash dev.sh --no-build     # re-sign + install last artifact
bash dev.sh --launch       # aa start the app
bash dev.sh --log          # hilog | grep NextE
```

Raw HAP build (what CI runs, no signing — the M0 acceptance gate):

```bash
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

- **Installing to ANY device or emulator: always install the SIGNED hap** (`entry-default-signed.hap` from the signed build above — run `setup-local-build-profile.sh` once so `build-profile.json5` has `signingConfigs`, even in a worktree). The unsigned `entry-default-unsigned.hap` is **build-only** (the CI gate); `hdc install -r` of it over an already-signed install fails silently-ish with `error: install sign info inconsistent`, leaving the OLD build running while your screenshots look stale/wrong. This applies to **emulators too**, not just real devices. Do **not** `hdc uninstall` to clear the mismatch — it wipes the EH login. When verifying on-device, confirm the install printed `install bundle successfully`, not just the trailing `AppMod finish`.

- **Single bundle ID `com.erosteam.nexte`.** Signing reuses V2Next's account-level debug cert (`~/.config/harmony/debug-signing`: `debug.p12`, `ohos-D.cer`); a NextE-specific Provisioning Profile `profiles/com.erosteam.nexte.p7b` must be minted once (debug, account-level cert). Signing files are never committed; on macOS, local signing lives in ignored `build-profile.local.json5` and is installed via `scripts/setup-local-build-profile.sh`; Linux legacy `dev.sh` uses `scripts/dev.env`.

## Tests / Gates

No single test runner. Contract tests are standalone scripts under `scripts/`, run individually.

```bash
node scripts/test_v1_decorator_inventory_contract.mjs   # MANDATORY gate — must report 0 file(s)
node scripts/test_version_consistency_contract.mjs      # modules registered & present
python3 scripts/check_i18n_duplicates.py                # locale key parity + no duplicates
```

**Mandatory gate for any ArkTS/UI/state change**: `test_v1_decorator_inventory_contract.mjs` must report `0 file(s)` before merge/push. When you add a subsystem, add the matching `scripts/test_*_contract.mjs` (parser → its parser contract, etc.) with a real EH HTML fixture.

**Harness workflow** (harness-kit): gates are config-driven in `.harness/config.json` (the v1-decorator/version/i18n contracts above plus layering + doc-links + plan-DoD). Run them via `harness-verify` (or `/harness-kit:verify`); the same set runs as a git pre-commit gate. Non-trivial work plans live in `docs/plans/{active,completed}`.

## Format & Commits

```bash
npx @ohos-rs/oxk format --quote-style single --semicolons as-needed <file.ets>
```

- Commit messages: **English only**, Conventional Commits `type(scope): description`. Add Why/What/Validation for bug fixes, parser/network changes, and write actions. Never include cookies, `ipb_pass_hash`, `igneous`, `sk`, or passwords.
- Don't commit unless explicitly asked.
- Code comments: English, explain *why* (product constraints, platform quirks, state invariants). User-facing strings are i18n resources (base + zh_CN + en_US + ja_JP).

## Architecture

Dependency graph (`feature/* → shared` only; features never cross-import; `entry` orchestrates; `shared` is the zero-dep leaf):

```
entry  ──> shared + home, gallery, search, reader, download, user, settings
home     ──> shared    HomePage (multi-source gallery list), GalleryListViewModel
gallery  ──> shared    GalleryDetailPage, GalleryDetailViewModel
search   ──> shared    GallerySearchPage, SearchViewModel
reader   ──> shared    ReaderPage (own HAR — heaviest), ReaderViewModel
download ──> shared    DownloadQueuePage, DownloadViewModel + background agent
user     ──> shared    FavoritesPage, MyTagsPage
settings ──> shared    SettingsPage + sub-pages
shared   ──> (none)    network · parser · model · state · settings · components · theme · services · utils · constants · cache · storage · diagnostics · i18n
```

Data flow: `EhHttpClient → EhApiService/EhApiPhpService → parsers(regex/DOM) → Eh* models → feature ViewModels → AppStorageV2 state holders → @ComponentV2 pages`. Full detail in `docs/architecture.md`; EH integration in `docs/eh-integration-contract.md`.

- **Network** (`shared/network`): `EhHttpClient` (singleton, retry/backoff, gzip, 302 detection, per-site base URL), `EhApiService` (web pages), `EhApiPhpService` (`/api.php` multiplexed by method), `EhCookieStore`+`EhCookieInterceptor` (manual cookie jar — HarmonyOS has none; force `nw=1`, inject `ipb_*`/`igneous`), per-host token-bucket rate limiter, 509/429 distinct.
- **Parsing** (`shared/parser`): EH HTML/JSON → models via in-house regex/DOM (**no external HTML lib**). One parser per page type. Heavy parses on a TaskPool worker. The most fragile layer — back each with a fixture contract test; the CSS-sprite rating `(80-x)/16` and favcat `(pos-2)/19` are verify-live magic constants.
- **Theme** (`shared/theme/ThemeConstants.ets`): all design tokens. **Never hardcode** sizes/colors/font-sizes — use `ThemeConstants` + `EhSemanticColors`. New colors need dark + light coverage.
- **Settings** (`shared/settings`): preference snapshots/bridges; `SettingsBootstrap.loadAll(context)` restores config in `EntryAbility.onWindowStageCreate` before content loads. `CookieJarSettings` persists the sensitive auth bundle (redacted).

## Navigation

`entry/src/main/ets/pages/Index.ets` is the nav shell. **M0 uses plain `Tabs` + `Navigation`/`NavPathStack`** (4 tabs: Home/Search/Favorites/Me). **M1 upgrades to HDS** (`HdsNavigation`+`HdsTabs` from `@kit.UIDesignKit`, as V2Next — built-in at SDK 26, no extra dep). Routed pages push by name: `connectNavStack().stack.pushPathByName('GalleryDetail', params)`. `EntryAbility` parses `/g/` and `/s/` deep links → `publishPendingEhUrl` → `Index` consumes via `@Monitor`.

## State Management V2 — hard constraint

**State Management V1 is retired. Never introduce or restore V1 decorators** in `entry/`, `feature/`, or `shared/`: `@Component`, `@State`, `@Prop`, `@Link`, `@Watch`, `@StorageLink`, `@StorageProp`, `@Provide`, `@Consume`, `@ObjectLink`, `@Observed` (bare), `@Track`, `@LocalStorageLink`, `@LocalStorageProp`. No V1 adapter, allowlist, temporary bridge, or key-churn refresh hack. If a change appears to need V1, stop and report `BLOCKED` with evidence and a V2-only alternative.

Use V2 only: `@ComponentV2`, `@ObservedV2`, `@Trace`, `@Local`, `@Param`, `@Monitor`, and AppStorageV2 holders. Canonical holder pattern (see `shared/state/NavStackHolder.ets`, `PendingEhUrlState.ets`):

```ts
@ObservedV2
export class SiteModeState {
  @Trace isEx: boolean = false
}
const KEY: string = 'v2:siteMode'
export function connectSiteMode(): SiteModeState {
  return AppStorageV2.connect(SiteModeState, KEY, () => new SiteModeState())!
}
```

Cross-component signals are single-writer command buses (timestamped payload + `@Monitor` reactor). Gate: `node scripts/test_v1_decorator_inventory_contract.mjs` must report `0 file(s)`.

## ArkTS gotchas

ArkTS is a restricted TypeScript dialect; many TS constructs **fail to compile**. No `any`/`unknown`, no destructuring (params/assignment/declaration), no object spread, no index access `obj['x']`, no `for..in`, no `Function.bind/call/apply`, no function expressions/nested functions (use arrow functions), no `this` in standalone/static functions, no `globalThis`, omit `catch` type annotations, no `var`. Object literals need an inferable class/interface target. **Porting eros_fe models: hand-write every field, no destructuring/spread; add `copy()`/`merge()` methods.** Full list: `docs/agent-guides/harmonyos-default.md`. Animations: drive via state changes, `renderGroup(true)` on complex subtrees, don't animate layout props.

## Operating boundaries

- **Destructive writes** (rate, favorite, comment post, vote, tag) are non-idempotent. Default validation is non-destructive: open dialog → capture evidence → cancel. Real submits, when authorized, prefer your own test gallery.
- **UI/product preservation**: don't change colors, typography, spacing, layout, wording, navigation, or interaction model while fixing a bug unless explicitly requested. Remove temporary test scaffolding before finalizing.
- **Login/Cookies**: EH cookies (`ipb_member_id`/`ipb_pass_hash`, ex needs `igneous`) come from in-app WebView login or local `.env.local` — never print, commit, or paste them. Redact via `DiagnosticsRedactor`.

## More detail

`AGENTS.md` indexes the agent guides under `docs/agent-guides/`. Design/roadmap notes are in `docs/`.

# Retained subtab framework contract

Created: 2026-06-17
Completed: 2026-06-17
Status: COMPLETED — framework implemented, verified, pushed.

Completion commits:

- `7a8287b` — split A shared `RetainedSubtabHost` + `TabItem`, Home/Toplist migrated.
- `cb50e47` — split B Favorites favcat migrated to shared host.
- `0e5a6f1` — P0 first-activation first-load regression fixed with shared `ActiveKeyState`.
- `46ac1a5` — Favorites favcat bar names-only presentation.

## Trigger

User identified that the current retained-subtab work is becoming patchwork: state retention, visual index, subtab bar geometry, counts, scrollable favcats, and loading affordances are being added one symptom at a time. Future support for custom subtabs requires a unified framework first.

## Control decision

Freeze Commit 3 Favorites WIP as implementation material, not accepted architecture. Do not continue device QA or commit until this framework contract is satisfied.

Current committed checkpoints:

- `cbb2583` — Home source retained tabs.
- `c2b91fb` — Toplist retained tabs + visual-index-synced bars.

Current uncommitted WIP may contain useful code for Favorites/SubTabBar/loading, but it must be audited against this framework before commit.

## Framework goal

All UI surfaces presented as subtabs must use the same architecture and state semantics. A subtab is not a shared-list filter. A real retained subtab has:

1. stable key list,
2. selected-key bus,
3. visual-index bus,
4. keyed retained page instances,
5. per-key VM/datasource/scroller/cache,
6. unified loading policy,
7. unified selector bar metrics/indicator,
8. title-scroller handoff to the active page,
9. deterministic contracts and device QA.

## Required abstraction boundaries

### 1. Host layer

A retained-subtab host owns:

- `SwiperController`,
- stable ordered tab items/keys,
- one `Scroller` per key,
- visual-index state connector,
- active scroller notification to `Index` / HDS title binding,
- `Swiper` event wiring:
  - `onGestureSwipe`,
  - `onAnimationStart`,
  - `onAnimationEnd`,
  - `onChange`.

The host must not own one shared content VM/datasource for all keys.

### 2. Selection bus

A selected-key state holder owns only semantic selection and shared metadata needed by the bar:

- selected key,
- visible/custom key list if needed,
- display labels/counts/order metadata.

It must not own:

- datasource,
- list rows,
- page cursor,
- content loading state,
- VM instance.

### 3. Visual-index bus

Visual index is a separate high-frequency state holder. It exists only for indicator/highlight interpolation and must not trigger data loads.

Rules:

- selected key changes at semantic switch points,
- visual index changes during gesture/animation,
- selector bars consume visual index,
- content pages do not consume visual index for data loading.

### 4. Page layer

Each subtab key gets its own retained page instance. The page owns:

- `@Local` VM,
- datasource through that VM,
- page cursor/load-more state,
- first-load/empty/error state,
- the key's `Scroller`,
- lazy first load when first active,
- refresh/load-more semantics for that key only.

Switching away/back to an already loaded key must not call shared `setData(new)` or reset the cursor/scroll.

### 5. Selector bar layer

One shared selector bar component must serve Home source, Toplist period, Favorites favcat, and future custom subtabs.

It must support:

- compact non-scrollable tabs,
- scrollable many-key tabs,
- optional count/badge per item,
- V2Next-style sliding indicator driven by visual index,
- consistent vertical metrics: label and indicator are one tight visual unit,
- no per-surface hand-written underline.

The bar must not use inflated height, arbitrary bottom gaps, or divergent per-surface padding.

### 6. Loading policy

Loading state is part of the framework, not per-surface improvisation.

Allowed states:

| Scenario | Required presentation |
|---|---|
| first load for a never-loaded key | content area loading only |
| switch to an already retained key | no full-page loading |
| refresh existing key | list refresh affordance only |
| load more | bottom loading only |
| tab switch gesture/animation | no separate top loading |
| global auth/session blocker | explicit auth/blocker state, not content-loading text |

Forbidden:

- top/title loading followed by middle loading for the same key switch,
- shell-level loading for content page first-load,
- clearing retained content on switch,
- using loading as a substitute for retained state.

### 7. Current surfaces

| Surface | Required model |
|---|---|
| Home source | retained subtab host over source keys |
| Toplist period | retained subtab host over period keys |
| Favorites favcat | retained subtab host over favcat keys |
| Future custom subtabs | same framework, dynamic/custom key list |

## Current WIP audit requirements

Before committing any remaining work, Claude must produce a source audit table:

| Requirement | Home | Toplist | Favorites WIP | Shared framework component | Status |
|---|---|---|---|---|---|
| per-key page/VM/scroller/cache | | | | | |
| selected-key bus only | | | | | |
| visual-index bus | | | | | |
| gesture/animation wiring | | | | | |
| selector bar shared component | | | | | |
| compact vertical metrics | | | | | |
| loading policy unified | | | | | |
| title scroller handoff | | | | | |
| custom-tab-ready key model | | | | | |

## Required implementation order from here

1. Stop Commit 3 device QA/commit.
2. Audit current uncommitted diff against this framework.
3. Extract or document framework primitives first:
   - shared selector bar,
   - visual-index state holder/connectors,
   - retained host/page pattern,
   - loading policy.
4. Extend contracts to cover the framework, not just individual Home/Toplist/Favorites patches.
5. Only then continue Favorites migration.
6. Device QA must verify both current surfaces and loading behavior.

## Required contracts

Extend/create deterministic gates to assert:

- tab-presented surfaces do not use a shared VM + `setData(new)` on switch;
- each retained surface has per-key page/VM/scroller/cache or equivalent;
- selected-key buses do not hold datasource/VM/list rows;
- visual-index bus is separate and wired through gesture/animation callbacks;
- selector bars use one shared component and do not hand-roll underlines;
- selector bar vertical metrics are compact and derived from a single token matching V2Next/HDS;
- first-load/refresh/load-more/switch loading positions are not duplicated or conflicting;
- Favorites/future custom subtabs use the same framework as Home/Toplist.

## Device QA gates

Required before accepting the framework:

- Home source: switch away/back preserves list + scroll; indicator tracks swipe; no duplicate loading.
- Toplist period: switch away/back preserves list + scroll; indicator tracks swipe; no duplicate loading.
- Favorites favcat: switch away/back preserves list + scroll; indicator tracks swipe; no duplicate loading.
- First-load of a never-loaded key: content-area loading only.
- Existing retained key: no full-page loading on switch.

## Stop conditions

- Do not resume P1 list-card-height until framework accepted.
- Do not push.
- Do not delete/untrack current WIP; preserve it as audit material.
- Do not implement future custom tabs yet; design for them.

---

## Source audit (2026-06-17, against this contract) — file-level

Files (committed `cbb2583`/`c2b91fb` for Home/Toplist; Favorites + SubTabBar/metrics uncommitted WIP):
- Hosts: `feature/home/.../pages/HomePage.ets`, `ToplistPage.ets`, `feature/user/.../pages/FavoritesPage.ets`
- Per-key pages: `feature/home/.../components/GallerySourcePage.ets`, `ToplistPeriodPage.ets`, `feature/user/.../components/FavcatPage.ets`
- Buses: `shared/.../state/HomeSourceState.ets` (source+toplistTl + `TabVisualIndexState` + `connectHomeSourceVisualIndex`/`connectToplistVisualIndex` + `SELECTOR_BAR_HEIGHT`), `shared/.../state/FavSelectionState.ets` (selectedFavcat+favList+order+cmd bus + `connectFavcatVisualIndex`)
- Shared bar: `shared/.../components/SubTabBar.ets`; content body: `shared/.../components/GalleryListBody.ets`, scaffold `PullRefreshListScaffold.ets`; Index: `entry/.../pages/Index.ets` (`setHomeActiveScroller`), bars `entry/.../components/{HomeSourceBar,ToplistPeriodBar,FavcatBar}.ets`

| Requirement | Home | Toplist | Favorites WIP | Shared component | Status |
|---|---|---|---|---|---|
| per-key page/VM/scroller/cache | GallerySourcePage owns `@Local GalleryListViewModel` + scroller (HomePage map); cache = in-memory via `cachedCount` (no disk) | ToplistPeriodPage, same | FavcatPage owns `@Local FavoritesViewModel` + scroller, same | per-key pattern DUPLICATED inline 3×; **no shared host** | PARTIAL — works per-surface, host not shared, no disk cache |
| selected-key bus only | `HomeSourceState.source` (@Trace, no datasource) | `HomeSourceState.toplistTl` | `FavSelectionState.selectedFavcat` (+favList counts, order, cmd bus; no datasource) | no generic bus; per-surface holders | PASS semantics / per-surface |
| visual-index bus | `connectHomeSourceVisualIndex`→`TabVisualIndexState` | `connectToplistVisualIndex` | `connectFavcatVisualIndex` | **`TabVisualIndexState` SHARED (1 class, 3 keyed connectors)** | UNIFIED ✓ |
| gesture/animation wiring | HomePage Swiper onGestureSwipe/Start/End/Change | ToplistPage, same | FavoritesPage, same | DUPLICATED inline 3× | PASS / not shared |
| selector bar shared component | HomeSourceBar→SubTabBar | ToplistPeriodBar→SubTabBar | FavcatBar→SubTabBar(scrollable+counts) | **`SubTabBar` SHARED** | UNIFIED ✓ |
| compact vertical metrics | `SELECTOR_BAR_HEIGHT=38` + top-aligned + indicator `h-14` | same | same | single token; bottomBuilder height + topPadding + bar all derive | UNIFIED ✓ (canyon fixed) |
| loading policy unified | GalleryListBody: `PageLoadingState` gated `isLoading && itemCount===0` (content area); lazy `loadOnce` | same (GalleryListBody) | FavcatPage: same gating | consistent but DUPLICATED branches; not a shared policy | PARTIAL — consistent, now contract-locked |
| title scroller handoff | `onScrollerReady`→`Index.setHomeActiveScroller(0)` | →(2) | →(1) | Index side shared; page side DUPLICATED 3× | PARTIAL |
| custom-tab-ready key model | `visibleSources()` hardcoded `['','popular','watched']` | `TOPLIST_PERIODS` const | `favcatKeys()` from `favSel.favList` (semi-dynamic) | **no generic TabItem/key model** | GAP — not custom-ready |

### Verified facts (greps)
- Hosts own **0** `@Local vm` and contain **0** `loadData/setData/reload` (delegated to pages). ✓
- Per-key pages each own **1** `@Local vm`, a `loadedOnce` guard, `@Monitor('isActive')`, and **0** visual-index refs. ✓
- Loading: GalleryListBody + FavcatPage both gate first-load on `isLoading && this.vm.itemCount === 0` (content area); no top+center duplicate. ✓

### Conclusion
Already UNIFIED: visual-index bus, shared SubTabBar, compact metrics. **Patchwork (per-surface, not framework):** (1) the retained-subtab HOST (Swiper + scroller map + gesture wiring + scroller handoff) is reimplemented inline 3×; (2) no generic key/TabItem model → not custom-tab-ready; (3) loading policy consistent but duplicated; (4) per-surface buses. No disk cache (in-memory retention only — acceptable for bounded keys).

## Gates added/modified (this pass)

In `scripts/test_retained_tab_contract.mjs`, a new **RETAINED-SUBTAB FRAMEWORK** section asserts, UNIFORMLY across Home/Toplist/Favorites:
- **FW-1 host**: Swiper over per-key pages; full `onGestureSwipe+onAnimationStart+onAnimationEnd+onChange`; `cachedCount`; host owns NO shared content VM; host has NO `loadData/setData/reload` (no reload-on-switch); host hands the active scroller up (`onScrollerReady`).
- **FW-4 page**: each per-key page owns its OWN `@Local` VM + scroller, `loadedOnce` lazy first-load on `@Monitor('isActive')`, and does NOT consume the visual index (bar-only).
- **FW-5 bar**: all three bars use the shared `SubTabBar` + a `*VisualIndex` bus; none hand-rolls a `Color.Transparent`/`.position` underline.
- **FW-6 loading**: both content bodies gate first-load on `isLoading && itemCount===0` (content-area); no top+center duplicate loading; combined with FW-1 (host never loads on switch) ⇒ retained-key switch shows no full-page loading.
- Plus the **compact-metric** gate (already added): `SELECTOR_BAR_HEIGHT<=40`; bottomBuilder height / list topPadding / indicator baseline all derive from it.

`harness-verify` 17/17 green with the framework section (current code satisfies the framework PROPERTIES). A future gate (after host extraction) will assert all surfaces use the shared `RetainedSubtabHost` + a generic `TabItem`/key model.

## Split decision (requirement 3)

The uncommitted diff mixes framework primitives and Favorites. Recommended split (rewrite the host inline code into a shared primitive):

- **A — shared framework primitives (commit first):**
  - `SubTabBar` (scroll + counts + compact metrics) + `SELECTOR_BAR_HEIGHT=38` + top-align/`h-14` (already WIP).
  - `TabVisualIndexState` + `connectFavcatVisualIndex` (already WIP).
  - NEW `shared/.../components/RetainedSubtabHost.ets` — a `@ComponentV2` host taking a key list + a `@BuilderParam pageBuilder(key, isActive, scroller)` + a visual-index connector; it owns the SwiperController, per-key scroller map, gesture/animation wiring, `onScrollerReady`. **Refactor HomePage + ToplistPage to USE it** (proves the framework; deletes the duplicated inline host).
  - NEW generic `TabItem`/key-list model (custom-tab-ready).
  - Framework + loading + metric contracts.
- **B — Favorites migration (commit after A):** `FavoritesViewModel` (configure/applyOrder), `FavcatPage`, `FavoritesPage`, `FavcatBar` rewritten onto `RetainedSubtabHost` + `SubTabBar` (reuses most of the current WIP; the inline Favorites host is replaced by the shared host).

Rewrite needed: HomePage + ToplistPage inline hosts → shared host; Favorites WIP host → shared host. Reusable as-is: SubTabBar, visual-index, FavcatBar tabs, FavoritesViewModel per-favcat methods, FavcatPage list body.

Next step per the contract order: build the shared `RetainedSubtabHost` + `TabItem` model, refactor Home/Toplist onto it (commit A), extend the contract to assert shared-host usage, device-QA Home/Toplist (retention + no duplicate loading), THEN migrate Favorites (commit B). No commit/push/QA-acceptance until controller approves this split.

## Split A — DONE (commit `7a8287b`, not pushed)

Shared framework extracted + Home/Toplist migrated:
- NEW `shared/.../model/TabItem.ets` (generic key+label+count model) + `shared/.../components/RetainedSubtabHost.ets` (owns SwiperController, per-key Scroller map, cachedCount, visual-index publishing from onGestureSwipe/onAnimationStart/onAnimationEnd, onChange key publication, onScrollerReady; NO content VM; page injected via a GLOBAL `@Builder pageBuilder`).
- `SubTabBar` uses `TabItem` (local `SubTabItem` retired); kept compact metrics (SELECTOR_BAR_HEIGHT=38, top-aligned, indicator h-14), interpolated indicator, scrollable + counts.
- `HomePage` + `ToplistPage` rewritten to USE `RetainedSubtabHost` (inline Swipers deleted). `HomeSourceBar`/`ToplistPeriodBar` use `TabItem`. `connectFavcatVisualIndex` added as a visual-index primitive (consumer is split B).
- `test_retained_tab_contract.mjs` rewritten to assert the framework (shared host owns the mechanics; Home/Toplist use it; per-key page/VM/scroller; selection + visual-index buses; shared SubTabBar; compact metrics; content-area loading). Favorites-surface assertions deferred to split B.
- Gates: retained-subtab framework contract + harness-verify **17/17** (V1 inventory 0) + `dev.sh --build-only` SUCCESSFUL + pre-commit 17/17.
- **Device QA on `192.168.50.197:12345`**: Home renders via the shared host, 默认→热门→默认 preserves list + scroll (`/tmp/h_scrolled.jpeg`, `/tmp/h_back.jpeg`); Toplist renders via the same host (own builder, no `@BuilderParam` crash, `/tmp/host_toplist.jpeg`); compact bars, no canyon, content-area first-load only.

**Split A staged (committed in `7a8287b`):** `shared/.../model/TabItem.ets`, `shared/.../components/RetainedSubtabHost.ets`, `shared/.../components/SubTabBar.ets`, `shared/.../state/HomeSourceState.ets`, `shared/.../state/FavSelectionState.ets` (connectFavcatVisualIndex primitive only), `shared/.../Index.ets`, `feature/home/.../pages/HomePage.ets`, `feature/home/.../pages/ToplistPage.ets`, `entry/.../components/HomeSourceBar.ets`, `entry/.../components/ToplistPeriodBar.ets`, `scripts/test_retained_tab_contract.mjs`.

**Split B left UNCOMMITTED (preserved WIP):** `feature/user/.../components/FavcatPage.ets` (new), `feature/user/.../pages/FavoritesPage.ets`, `feature/user/.../viewmodel/FavoritesViewModel.ets`, `entry/.../components/FavcatBar.ets`, `entry/.../pages/Index.ets` (Favorites onScrollerReady mount), `scripts/test_selector_reload_preserves_content_contract.mjs` (FavcatPage pointer). Split B will migrate these onto `RetainedSubtabHost` + `SubTabBar` and re-add the Favorites-surface contract assertions. D list-card-height stash untouched.

## Split B — DONE + PUSHED (commit `cb50e47`, pushed to origin/main)

Favorites favcat migrated onto the framework:
- `FavoritesPage` rewritten to render the shared `RetainedSubtabHost` over favcat keys ('a' + 0-9) via a GLOBAL `@Builder favcatPageBuilder` (no inline Swiper); login gate + global order menu + openOrderMenu command bus preserved.
- `FavcatPage` owns per-key `@Local FavoritesViewModel` + scroller + lazy first-load; `configure`/`applyOrder` fix one favcat + apply the shared order. `FavSelectionState` stays a pure bus. `FavcatBar` uses the shared `SubTabBar` (scrollable + counts) via `connectFavcatVisualIndex`.
- **favList names/counts regression fixed (durable root cause):** device log proved the parse works (`key=a favListN=10 first=F0`) and the publish reaches the bus, but `SubTabBar`'s ForEach keyed on `tab.key` ALONE — seed and real favcats reuse favIds 0-9, so a seed→real update reused the frozen seed chips and the bar stayed "Favorites N / 0". The key now includes the label + count (string labels join; Resource labels stay stable) so dynamic favcat tabs rebuild — matching the old FavcatBar's `favId:favTitle:totNum` invariant. Contract guards it.
- Contracts: `test_retained_tab_contract.mjs` re-added the Favorites-surface assertions + the SubTabBar dynamic-tab key guard; `selector-reload` points at FavcatPage.
- Gates: retained-tab + selector-reload + harness-verify **17/17** (V1 inventory 0) + `dev.sh --build-only` SUCCESSFUL + pre-commit 17/17.
- **Device QA on `192.168.50.197:12345` (logged in):** Favorites renders via the shared host (no `@BuilderParam` crash); the favcat bar shows the account's REAL custom names + counts (`全部 / F0 470 / 本子 1236 / 漫画 609 / 3D 716`, `/tmp/fb_realnames.jpeg`); scroll 全部 → swipe to another favcat (its own list) → back preserves list + scroll (`/tmp/fb2_scrolled.jpeg`, `/tmp/fb2_back.jpeg`); indicator tracks the gesture; content-area first-load only.

**Retained-subtab framework COMPLETE**: Home source + Toplist period + Favorites favcat all on the shared `RetainedSubtabHost` + `TabItem` + `SubTabBar`. `origin/main` = `cb50e47`. D list-card-height stash still parked (resume next, per the gallery-visual plan). Control-plane docs remain untracked (not pushed).

## P0 first-load regression — FIXED + PUSHED (commit `0e5a6f1`, origin/main)

User report: switching to a never-visited subtab did not auto-load (stayed blank). Reproduced on device (tap 热门 → blank).

Root cause: `RetainedSubtabHost` passed activation as a per-render `isActive` boolean through the `@BuilderParam` pageBuilder, but ForEach (stable keys) + Swiper `cachedCount` does NOT re-run the item builder for cached pages → a cached page's `@Param isActive` never updated → its `@Monitor('isActive')` never fired `loadOnce()`. Only the initially-active page (which loads in `aboutToAppear`) ever loaded; every other key's FIRST activation was missed.

Fix (durable, framework-level): the host shares an `ActiveKeyState` (`@ObservedV2` + `@Trace activeKey`) passed by reference to every page; its `@Trace` propagates to ALL pages — cached included — so updates reliably reach them. The host sets `active.activeKey` on `aboutToAppear` + `@Monitor('selectedKey')` (bar tap) + Swiper `onChange` (swipe settle). Each page (`GallerySourcePage`/`ToplistPeriodPage`/`FavcatPage`) replaces `@Param isActive` with `@Param active: ActiveKeyState`, is active when `active.activeKey === itsKey`, and lazy-loads once via `@Monitor('active.activeKey')`. Retention + loading policy unchanged.

Contract: `test_retained_tab_contract.mjs` now asserts the explicit first-activation signal (host owns `ActiveKeyState`, updates it on every path, passes it not `isActive`; pages monitor `active.activeKey`, no longer take `@Param isActive`).

Gates: retained-tab + selector-reload + harness-verify **17/17** (V1 inventory 0) + `dev.sh --build-only` SUCCESSFUL + pre-commit 17/17.

**Device QA on `192.168.50.197:12345`** — first visit auto-loads on EVERY surface: Home 热门 (`/tmp/fix_tap_popular.jpeg`), Home 订阅 (attempts load → content-area parse error, NOT blank → activation works, `/tmp/fix_watched.jpeg`), Toplist 全部 (`/tmp/fix_tl_all.jpeg`), Favorites 本子 (count 1236, `/tmp/fix_fav_honzi.jpeg`). Loading is content-area only (no top+center duplicate); retained switches preserve list+scroll (proven in split B).

**Orthogonal note (NOT this task):** Home 订阅 (watched) showed "无法解析此页面" — a watched-source parse error, separate from activation. Flag for later triage.

**Queued for later (do NOT start yet):** `docs/plans/active/gallery-auth-cookie-completeness-404-gate.md`.

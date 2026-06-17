# Tab/list state architecture gate

Created: 2026-06-17 02:10 +0800
Completed: 2026-06-17
Status: COMPLETED — retained-tab architecture classified and implemented before resuming list-card-height.

Completion commits:

- `cbb2583` — Home source retained tabs.
- `c2b91fb` — Toplist retained tabs + visual-index-synced bars.
- `7a8287b` — shared retained-subtab framework split A.
- `cb50e47` — Favorites favcat retained tabs split B.
- `0e5a6f1` — first-load activation regression fixed.

## Trigger

User reported that the current “sub tab” behavior appears not to be real sub-tabs: switching a sub tab seems to reload the same middle list container instead of switching to an independent tab/list state. This explains prior regressions where switching labels/favcats cleared/reloaded content.

## Control action already taken

- Interrupted Claude while it was implementing P1 list-card-height.
- Preserved the partial D diff in `stash@{0}`:
  `paused D list-card-height partial before tab-list-state architecture gate 2026-06-17T02:08+0800`
- Working tree restored to clean business-code state except existing untracked control-plane docs.
- Do not resume/apply the list-height stash until this architecture gate is classified.

## Verified source facts

### Main bottom tabs

`entry/src/main/ets/pages/Index.ets` uses real `HdsTabs` + `TabContent` for the primary bottom tabs:

- `HomePage({ scroller: this.homeTabScrollers[0] })`
- `FavoritesPage({ scroller: this.homeTabScrollers[1] })`
- `ToplistPage({ scroller: this.homeTabScrollers[2] })`
- `DownloadQueuePage({ scroller: this.homeTabScrollers[3] })`
- `SettingsPage({ scroller: this.homeTabScrollers[4] })`

Each main tab has an Index-owned `Scroller`; this part is closer to real tab state.

### “Sub tabs” / selector bars are not independent tab pages

The title-bar `bottomBuilder` controls are cached component contents and write shared state / command bridges. They do not instantiate independent sub-tab page trees.

#### Gallery source switcher

`HomePage` owns one `GalleryListViewModel` and one `GalleryListBody`:

- `@Local vm: GalleryListViewModel = new GalleryListViewModel()`
- `build() { GalleryListBody({ vm: this.vm, ... }) }`

`HomeSourceBar` writes `HomeSourceState.source`; `HomePage.onSourceChange()` calls:

- `this.vm.setSource(this.homeSource.source)`

`GalleryListViewModel.setSource()` does:

- `this.source = source`
- `await this.reload()`

`reload()` keeps old rows visible during fetch, but replaces the same datasource:

- `this.dataSource.setData(list.gallerys)`

So the gallery source selector is a single VM/datasource with parameterized reload, not per-source list state.

#### Toplist period switcher

`ToplistPage` also owns one `GalleryListViewModel` + `GalleryListBody`:

- `this.vm.syncSource('toplist', this.homeSource.toplistTl)`
- `GalleryListBody({ vm: this.vm, ... })`

`onPeriodChange()` calls:

- `this.vm.setToplistPeriod(this.homeSource.toplistTl)`

`setToplistPeriod()` updates `toplistTl` then `await this.reload()`, replacing the same datasource.

So the toplist period selector is a single VM/datasource with parameterized reload, not per-period list state.

#### Favorites favcat selector

`FavoritesPage` owns one `FavoritesViewModel`, one datasource, one list scaffold branch:

- `@Local vm: FavoritesViewModel = new FavoritesViewModel()`
- `dataSource: BasicDataSource<EhGallery> = new BasicDataSource<EhGallery>()`

`FavcatBar` is mounted as Index title-bar bottomBuilder and communicates through `FavSelectionState` / command bridge. `FavoritesPage.onFavCommand()` calls:

- `this.vm.selectFavcat(this.favSel.cmdArg)`

`FavoritesViewModel.selectFavcat()` does:

- `this.favcat = favcat`
- `await this.load()`

`load()` replaces the same datasource:

- `this.dataSource.setData(list.gallerys)`

So favcat chips are not independent child tabs; they are selectors over one FavoritesPage VM/datasource.

## Current classification

- Main bottom tabs: partially real tabs (`TabContent` + per-tab scroller + per-page VM).
- Gallery source selector / toplist period selector / favorites favcat selector: verified not real sub-tabs; they are parameter selectors that reload/replace one list datasource.
- Prior “switch clears/reloads” behavior is consistent with this architecture. Current code has mitigations to keep old rows visible during reload, but it does not preserve per-sub-tab datasource, pagination cursor, or scroll offset.

## V2Next reference design — required architecture reference, not optional

User correction: V2Next must be read as the Harmony/HDS state architecture reference. eros_fe defines EH product semantics; V2Next shows the local ArkUI/HDS implementation pattern for real retained sub-tabs.

Verified V2Next evidence:

- `/home/gamer/git/V2Next/feature/feed/src/main/ets/pages/HomePage.ets`
  - `HomePage` uses `Swiper(this.swiperController)` over `ForEach(this.visibleTabs(), ...)`.
  - Each tab mounts a distinct `FeedListPage({ tabKey: tab.key, scroller: this.scrollerForTab(tab.key), ... })` keyed by `tab.key`.
  - `Swiper.cachedCount(1)` keeps adjacent tab pages alive.
  - `feedScrollers: Map<string, Scroller>` provides one scroller per feed tab key.
  - `feedRootRefreshActions: Map<string, () => void>` provides one refresh action per feed tab key.
  - `onFeedTabChanged()` changes swiper index and publishes selected key; it does not reuse one middle list by swapping its query.
- `FeedListPage`
  - Owns `@Local vm: FeedViewModel = new FeedViewModel()` per mounted `FeedListPage` instance.
  - `aboutToAppear()` configures loader/cache by `tabKey`, then calls `vm.loadCachedData()` and `vm.loadData()`.
  - Cache key is per tab: `CacheSettings.loadTopicList(context, `tab:${this.tabKey}`)` / `saveTopicList(..., `tab:${this.tabKey}`, ...)`.
- `/home/gamer/git/V2Next/shared/src/main/ets/state/FeedTabState.ets`
  - `FeedTabState` only carries selected key + visible tab list + visual index bridge.
  - It is a tab selection bus, not the list data holder.
  - High-frequency visual index is isolated in `FeedVisualIndexState`; list scroll lock is isolated in `ListScrollState`.

Implication for NextE:

- The current NextE selector bars (`HomeSourceBar`, `ToplistPeriodBar`, `FavcatBar`) copied the HDS bottomBuilder visual shell but did not copy V2Next's retained page model.
- NextE should not be described as having real sub-tabs merely because the selector bar looks like tabs.
- The V2Next-compatible model is: selection bus in shared state + keyed retained list pages/VMs/scrollers/caches per tab key.
- A one-VM `setSource/selectFavcat/setToplistPeriod -> reload -> dataSource.setData` model is a filter/reload model, not a tab model.

## Unknowns to verify before choosing implementation

- eros_fe intended semantics for these selector bars: whether each source/favcat/period preserves independent scroll/list cache or intentionally reloads one list.
- Whether NextE product target should match eros_fe per-selector state and V2Next retained-tab architecture, or keep one-list reload but explicitly treat controls as filters, not tabs.
- Whether current HDS bottomBuilder setup remounts any child content on title-bar updates despite cached `ComponentContent`.
- Device behavior for scroll-offset preservation when switching source/favcat/period.

## Required read-only gate before any implementation

1. Inspect eros_fe source for:
   - home source tabs / popular / watched state retention,
   - favorites favcat tab behavior,
   - toplist period behavior,
   - scroll/cache preservation model.
2. Inspect NextE source for:
   - `HomeSourceBar`, `ToplistPeriodBar`, `FavcatBar`, `HomeSourceState`, `FavSelectionState`, `GalleryListViewModel`, `FavoritesViewModel`, `GalleryListBody`, `FavoritesPage`.
3. Device QA/log probe:
   - switch Gallery source after scrolling; record whether rows/scroll/cursor are preserved or replaced,
   - switch Favorites favcat after scrolling; same,
   - switch Toplist period after scrolling; same.
4. Produce a classification table:
   - `real tab / parameterized selector / filter` semantics,
   - current state holder(s),
   - datasource lifetime,
   - scroll lifetime,
   - reload behavior,
   - mismatch with eros_fe/product expectation.

## Stop condition

Do not implement list-card-height, fixed/adaptive row height, or additional visual work until this gate states whether list state architecture must be fixed first.

---

## Read-only investigation result (2026-06-17 ~02:20 +0800) — three-way classification + scope

Read-only only. No business code changed. D list-card-height stash untouched (not applied). Sources: two Explore sweeps (eros_fe, NextE) + direct reads of eros_fe `tabhome_controller`/`gallery_item`, NextE `GalleryListViewModel.reload()`/`GalleryListBody`, and V2Next `feature/feed/.../HomePage.ets` + `shared/.../state/FeedTabState.ets`. A device probe was started (scroll front page then switch source) but superseded by the V2Next read per controller instruction; the source-level evidence below is conclusive without it.

### Verified primary evidence

- eros_fe host: `lib/pages/tab/view/home_page_small.dart:12-26` = `CupertinoTabScaffold` over `controller.viewList[index]` (IndexedStack-style keep-alive of each bottom tab). `tabhome_controller.dart:26-32` maps `EHRoutes.gallery: const CustomTabbarList()`, `EHRoutes.favorite: const FavoriteTabTabBarPage()`, `EHRoutes.toplist: const ToplistTab()`.
- eros_fe gallery sub-tabs = custom PROFILES: per-profile `CustomSubListController` tagged by UUID (`custom_tabbar_controller.dart:120-122,296-301`), `PageView` of `SubListView` with `AutomaticKeepAliveClientMixin` + `wantKeepAlive=true` + `ValueKey(uuid)` (`custom_sub_page.dart:27-28,54`). Independent list+scroll+cursor per profile. (Historically front/popular/watched were also separate routes+controllers: `GalleryViewController`/`popular_controller`/`watched_controller`.)
- eros_fe favorites favcat = real sub-tabs: per-favcat `FavoriteSubListController` tagged by `favId` (`favorite_tabbar_controller.dart:44-46`), `PageView` per favcat (`favorite_tabbar_page.dart:130-143`) + keep-alive (`favorite_sub_page.dart`). Independent list+scroll+cursor per favcat.
- eros_fe toplist period = single reloaded list: one `TopListViewController` (`get_init.dart:79`), period switch → `reloadData()` → `resetResultPage()` (`tabview_controller.dart:190-217`), scroll reset. NOT sub-tabs.
- V2Next retained pattern (`feature/feed/.../HomePage.ets`): `Swiper(swiperController)` over `ForEach(visibleTabs(), tab => FeedListPage({ tabKey: tab.key, scroller: scrollerForTab(tab.key) }), tab => tab.key)`; `.cachedCount(1)`; `feedScrollers: Map<string,Scroller>` (one per key); `feedRootRefreshActions: Map<string,()=>void>`; inner `FeedListPage` owns `@Local vm = new FeedViewModel()` per instance + per-tab cache `CacheSettings.loadTopicList(ctx, 'tab:${tabKey}')`. `FeedTabState` = selection bus only (`feedTab` key + `feedTabKeys` list); high-freq visual index isolated in `FeedVisualIndexState`; scroll-lock in `ListScrollState`. Tab switch = `swiperController.changeIndex(i)`, never a shared-list query swap.
- NextE current: `HomePage`/`ToplistPage` each own ONE `@Local vm = new GalleryListViewModel()` + ONE `BasicDataSource`; `FavoritesPage` ONE `FavoritesViewModel` + ONE `BasicDataSource`. Selector bars write shared state (`HomeSourceState.source`/`.toplistTl`, `FavSelectionState` cmd bus) → page `@Monitor` → `vm.setSource/setToplistPeriod/selectFavcat` → `reload()`/`load()` → `dataSource.setData(new)`, cursor reset (`nextGid=''` / `toplistPage=0`). Scroller is one Index-owned `Scroller` per MAIN tab, reused across selector switches (no `scrollTo(0)`), but `setData` replaces all rows under the retained offset and switching back refetches page 0. No per-source/per-favcat page, VM, datasource, scroller, or cache.

### Classification table

| Surface | eros_fe product semantics | V2Next Harmony pattern | NextE current model | Verdict |
| --- | --- | --- | --- | --- |
| Home source (默认/热门/订阅 = front/popular/watched) | Retained: separate controllers/keep-alive sub-tabs, own list+scroll+cursor per source | Retained: Swiper + per-key page/VM/scroller/cache, cachedCount(1) | ONE VM/datasource/scroller; `setSource → reload → setData(new)`, cursor reset | **MISMATCH** — should be retained sub-tabs, is a filter/reload |
| Favorites favcat (全部/0–9) | Retained: per-favcat controller in PageView + keep-alive, own list+scroll+cursor | Retained (same pattern) | ONE VM/datasource/scroller; `selectFavcat → load → setData(new)`, cursor reset | **MISMATCH** — should be retained sub-tabs, is a filter/reload |
| Toplist period (day/month/year/all) | Source project implementation uses a single reloaded list, but this is **not allowed to override NextE's current UI semantics** | V2Next retained-tab pattern applies whenever the UI is presented as tabs | ONE VM/datasource; `setToplistPeriod → reload → setData(new)`, page reset | **MISMATCH under current NextE UI** — it is visually/interaction-wise a subtab, so it must behave as retained subtab |

State holder / datasource / scroll / reload columns: all three NextE surfaces share the same lifetime model — one page-scoped VM, one reused `BasicDataSource` mutated by `setData`, one main-tab `Scroller` reused (offset not reset, content replaced), reload resets the pagination cursor. Only the trigger differs (source string vs toplist tl vs favcat cmd bus).

### Corrected conclusion after user product-semantics ruling

- The "sub tabs reload the same middle container" observation is correct and is the root cause of the earlier clear/reload defects: NextE's source/favcat/toplist-period controls are currently **parameterized filters over one list**, despite being presented as subtab controls.
- The earlier claim that Toplist period should remain a filter was wrong for this product: it incorrectly used eros_fe's internal implementation to override NextE's current UI semantics.
- Product rule from controller/user: **if NextE presents a selector as a subtab, it must provide subtab state semantics** — per-key retained page/VM/datasource/scroller/cache. If we want filter semantics, the UI must stop looking/behaving like tabs; that is not the chosen direction here.
- Therefore all three surfaces are in retained-tab scope: Home source, Favorites favcat, and Toplist period.

### Proposed implementation scope (corrected)

Recommendation: **Option A+ — adopt the V2Next retained-tab pattern for Home source + Favorites favcat + Toplist period.** This matches the current NextE UI semantics and the project's V2Next architecture doctrine.

- Gallery main tab: `HomePage` → a `Swiper` over the source keys; each source mounts its own `GalleryListBody` + `@Local GalleryListViewModel` + per-key `Scroller` + per-key list cache; `HomeSourceState` is a selection bus.
- Favorites main tab: `FavoritesPage` → a `Swiper` over favcat keys; per-favcat VM + scroller + cache; `FavSelectionState` is a selection bus.
- Toplist main tab: `ToplistPage` → a `Swiper` over the period keys; each period mounts its own retained list page/VM/scroller/cache. `HomeSourceState.toplistTl` (or a dedicated toplist state) becomes a selection bus for the selected period, not the datasource holder.
- Removable once retained: the white-screen "keep old rows during reload" mitigation in `GalleryListViewModel.reload()` becomes unnecessary for tab switching (retained tabs never blank); keep refresh semantics separate.
- Guard with deterministic contract: retained-tab per-key page/VM/scroller/cache exists for Home source, Favorites favcat, and Toplist period; selection state is bus-only; no surface presented as tab may use one shared VM with `setData(new)` on switch.
- Interaction hard gate from V2Next: retained subtab UI must keep the visible pill/subtab indicator synchronized with Swiper gesture/animation. Do not only update selected key in `onChange`. Mirror V2Next's pattern: a separate visual-index/interpolation state (like `FeedVisualIndexState`) updated from `onGestureSwipe`, `onAnimationStart`, and `onAnimationEnd`, while selected-key state remains the semantic bus. If the current selector-bar component cannot consume a visual index, add that support before accepting the retained-tab refactor.
- Sequencing: this architecture fix lands before resuming P1 list-card-height. The D stash stays parked.
- Cost/risk: larger multi-surface refactor than the earlier A scope; includes `feature/home` Toplist path as well as `feature/user`, `entry`, and shared state/contracts. V2-only and device-QA-gated.

Alternatives considered: pseudo-cache over one VM, or relabeling controls as filters. Both are rejected for current UI because they preserve the same semantic mismatch the user reported.

STOP — corrected scope is A+; implement remaining retained-tab work only after controller explicitly reissues execution with Toplist included. No business code changed by this correction; D stash untouched.

---

## Option A approved — implementation plan (2026-06-17 ~02:30 +0800)

Controller approved Option A: retained tabs for Home source + Favorites favcat; Toplist period stays a single-list filter. Small commits, contracts before/with code, V2-only inventory 0, device QA proves retention, no push, D stash untouched.

### Reference mechanism (V2Next, to mirror)

- `feature/feed/.../HomePage.ets`: `Swiper(ctrl)` over `ForEach(visibleTabs(), tab => FeedListPage({ tabKey, scroller: scrollerForTab(tab.key) }), tab => tab.key)`; per-key `FeedListPage` owns `@Local vm = new FeedViewModel()`; `feedScrollers: Map<string,Scroller>`; selection bus `FeedTabState` drives `swiperController.changeIndex`; `onChange` publishes the new key back; inner page emits `onScrollerReady(tabKey, scroller)` UP.
- `entry/.../Index.ets` `setHomeTabScroller(index, scroller)`: on the inner page's `onScrollerReady`, swap `homeTabScrollers[index]` and, if it's the active main tab, repoint `titleScroller` so the title auto-hide binds the active sub-tab's scroller.

### Commit 1 — Home source retained tabs (feature/home + entry)

- New `feature/home/.../components/GallerySourcePage.ets` (`@ComponentV2`): `@Param sourceKey`, `@Param scroller`, `@Local vm = new GalleryListViewModel()`. On first-activate it `vm.syncSource(sourceKey, tl)` + `vm.loadData()` (lazy: load when first made active, not eagerly for every cached page — avoids N cold-start fetches). `@Monitor('siteMode.isEx')` reloads its own vm. Renders the existing `GalleryListBody({ vm, scroller })`.
- `HomePage.ets`: replace the single `GalleryListBody(vm)` with a `Swiper(swiperController)` over `visibleSources()` (`['', 'popular']` logged-out, `+ 'watched'` logged-in), `ForEach` keyed by source key → `GallerySourcePage({ sourceKey, scroller: scrollerForTab(key), onActiveScroller })`. `cachedCount(visibleSources.length)` retains all (only 2–3). `@Monitor('homeSource.source')` → `swiperController.changeIndex`; `Swiper.onChange` → `homeSource.source = key`. Login change rebuilds `visibleSources` (keyed ForEach retains '' / 'popular'). Emits the active source's scroller up via `@Event onScrollerReady`.
- `HomeSourceState`: already a pure selection bus (`source` + `toplistTl`, no datasource) — keep; add a doc line only.
- `Index.ets`: Home tab `HomePage({ scroller: homeTabScrollers[0] })` → `HomePage({ onScrollerReady: s => this.setHomeActiveScroller(0, s) })`; add `setHomeActiveScroller` mirroring V2Next `setHomeTabScroller` (swap + repoint `titleScroller` when Home is active).
- Contract `scripts/test_retained_tab_contract.mjs`: Home uses `Swiper` + per-key `GallerySourcePage`; `GallerySourcePage` owns its own `@Local GalleryListViewModel`; `HomeSourceState` has no datasource/dataSource field (bus only); HomePage does NOT hold a single shared `GalleryListViewModel` driving all sources. Register `retained-tab` gate.
- Build + harness (incl. V2-only 0). Device QA: scroll front → switch to popular → back to front → front list + scroll offset preserved (no refetch/blank).

### Commit 2 — Favorites favcat retained tabs (feature/user + entry)

- New `feature/user/.../components/FavcatPage.ets`: `@Param favcatKey`, `@Param scroller`, `@Local vm = new FavoritesViewModel()`; lazy first-load on activate; renders the favorites list body (extract the current `FavoritesPage` list/grid branch into a reusable body or inline).
- `FavoritesPage.ets`: `Swiper` over the fixed favcat keys (`all` + slots `0..9`), keyed; per-favcat `FavcatPage`; `FavSelectionState` reduced to a selection bus (selected key + favList counts for the bar + order); the favcat BAR counts (`favList`) are shared metadata updated by whichever page parsed them; the order toggle + login gating preserved. cachedCount tuned (favcats are bounded; choose retain-all if affordable, else adjacent + documented).
- `Index.ets`: Favorites `onScrollerReady` chain like Home.
- Extend `test_retained_tab_contract.mjs`: favcat per-key page/VM/scroller; `FavSelectionState` is a bus.
- Build + harness + device QA: scroll a favcat → switch favcat → back → list + scroll preserved.

### Toplist period retained tabs — CORRECTED to A+ (was wrongly "no change")

User product-semantics ruling: NextE presents the toplist period as a SUBTAB control, so it owes subtab semantics (per-period retained page/VM/datasource/scroller). eros_fe's internal single-list does NOT override NextE's current UI. So Toplist joins the retained-tab scope.

- New `feature/home/.../components/ToplistPeriodPage.ets`: `@Param periodTl: number`, `@Param isActive`, `@Param scroller`, `@Local vm = new GalleryListViewModel()`; `aboutToAppear` syncs `vm.syncSource('toplist', periodTl)` + lazy first-load on activate; renders `GalleryListBody`. (No site `@Monitor` — toplist.php is e-hentai only.)
- `ToplistPage.ets`: `Swiper` over the period keys (tl `11`/`12`/`13`/`15`, in the bar's order), keyed by `String(tl)` → `ToplistPeriodPage` per period; `cachedCount = periods.length` (4, retain all); `@Monitor('homeSource.toplistTl')` → `changeIndex`; `onChange` → `homeSource.toplistTl = periods[i]`; emit active scroller up. `HomeSourceState.toplistTl` is the period selection bus (no datasource).
- `Index.ets`: Toplist tab `onScrollerReady → setHomeActiveScroller(2, s)`.
- `test_retained_tab_contract.mjs` CORRECTED: ToplistPage IS a `Swiper` of per-period `ToplistPeriodPage` (each owns its own `@Local GalleryListViewModel` + scroller); ToplistPage no longer owns one shared VM. General rule encoded per surface: a tab-presented surface must NOT share one VM and `setData(new)` on switch.

### Corrected commit order (A+)

- Commit 1 — Home source retained tabs — DONE (`cbb2583`).
- Commit 2 (next) — Toplist period retained tabs (mirrors Home's GalleryListViewModel/GalleryListBody path; smaller).
- Commit 3 — Favorites favcat retained tabs (login gating, order toggle, favList counts).

### Cross-cutting gates

- V2-only inventory must stay 0 (Swiper/`@ComponentV2`/`@Local`/`@Monitor`/`@Event` only).
- Each commit: build (`dev.sh --build-only`) + `harness-verify` green + device QA screenshots; focused commit; no push; preserve plan docs; D stash untouched.

Implementation start: Commit 1 (Home).

### Progress log

- 2026-06-17 ~03:00 +0800 — **Commit 2 (Toplist period retained tabs + V2Next visual-index-synced indicators for Home + Toplist) DONE** (not pushed). Scope corrected to A+ (Toplist is a subtab → retained). New `ToplistPeriodPage` (own `@Local GalleryListViewModel` + per-period scroller, lazy first-load); `ToplistPage` = `Swiper` over `TOPLIST_PERIODS=[11,12,13,15]` keyed by `String(tl)`, `cachedCount=4`; old `setToplistPeriod->reload` filter retired. NEW visual-index sync hard gate (user: pill animation must track the swipe): added `TabVisualIndexState` + `connectHomeSourceVisualIndex`/`connectToplistVisualIndex` (separate per-frame bus, like FeedVisualIndexState); new shared `SubTabBar` with a single interpolated sliding indicator (per-tab `onAreaChange` widths + `position` lerp between tab centres); `HomePage` + `ToplistPage` Swipers now publish the visual index from `onGestureSwipe`/`onAnimationStart`/`onAnimationEnd` (not just `onChange`); `HomeSourceBar` + `ToplistPeriodBar` rewritten to drive `SubTabBar` from the visual-index bus (discrete per-tab underline retired). `Index` wires Toplist `onScrollerReady→setHomeActiveScroller(2,…)`. Contract `test_retained_tab_contract.mjs` corrected (Toplist now asserted retained, not filter) + visual-index-sync assertions (Swipers wire gesture/animation; bars consume the bus). Gates: retained-tab + harness-verify **17/17** (V1 inventory 0) + `dev.sh --build-only` SUCCESSFUL. **Device QA on `192.168.50.197:12345`**: HomeSourceBar shows the sliding indicator under the active source; a horizontal gesture swipe default→热门 moved the page AND the indicator/highlight followed (`/tmp/vi_home.jpeg`, `/tmp/vi_swiped.jpeg`). Toplist: indicator under 昨日 default; scrolled 昨日 to 千字笙/大芋泥啵啵/Fanbox (`/tmp/vi_tl_scrolled.jpeg`) → switched 全部 (own all-time list at top, indicator→全部, `/tmp/vi_tl_all.jpeg`) → back to 昨日 returns to the SAME galleries + scroll offset, indicator→昨日 (`/tmp/vi_tl_back.jpeg`). Retention + indicator-follow proven; smooth mid-swipe interpolation is implemented per V2Next + contract-locked (best verified by video). **Next: Commit 3 — Favorites favcat retained tabs (with visual-index sync from the start).**
- 2026-06-17 ~02:38 +0800 — **Commit 1 (Home source retained tabs) DONE** (`cbb2583`, not pushed). New `GallerySourcePage` (own `@Local GalleryListViewModel` + per-source scroller, lazy first-load on activate); `HomePage` = `Swiper` over `visibleSources()` keyed by source key, `cachedCount = source count` (retain all 2–3); `HomeSourceState` confirmed a pure selection bus (no edit needed); `Index` wires `onScrollerReady` → `setHomeActiveScroller` (title auto-hide follows active source). Toplist untouched. New blocking gate `test_retained_tab_contract.mjs` (registered, `retained-tab`). Gates: retained-tab + harness-verify **17/17** (V1 inventory 0) + `dev.sh --build-only` SUCCESSFUL + pre-commit 17/17. **Device QA on `192.168.50.197:12345`**: scrolled 默认 to KIJONIHIME/CHFMY (`/tmp/rt_front_scrolled.jpeg`) → switched 热门 (its own list at top, `/tmp/rt_popular.jpeg`) → back to 默认 returns to the SAME galleries + scroll offset, no refetch/blank (`/tmp/rt_back_front.jpeg`). Retention proven. **Next: Commit 2 — Favorites favcat retained tabs** (more complex: login gating, order toggle, favList counts, fixed favcat keys). D list-card-height stash still untouched.

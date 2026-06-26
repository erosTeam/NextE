# Custom home sub-tabs (eros_fe-style customizable gallery tabs)

Status: in progress. Make the home (画廊) sub-tab row fully user-customizable — each tab is a saved
profile (name + search + categories + list type + advanced search + display mode), modeled on eros_fe
("F1"). Built-in 默认/热门/订阅 become default profiles. Phase 1 (model + persistence + migration)
done and device-smoke-verified; Phases 2-6 in progress.

Reference implementation: eros_fe `lib/models/custom_profile.dart` (`CustomProfile` 13 fields),
`custom_tab_config.dart`, `advance_search.dart`, `pages/tab/controller/group/custom_tabbar_controller.dart`
(defaults + CRUD), `custom_sublist_controller.dart` (profile→request), `network/request.dart` (param map),
`pages/tab/view/tabbar/*` (tab bar / manage / edit UI). NextE grounding: `feature/home` (HomePage,
GallerySourcePage, GalleryListViewModel), `shared` (SubTabBar, RetainedSubtabHost, TabItem,
HomeSourceState, SearchFilterState, ListModeState, EhApiService, SubtabSelectionSettings,
SearchHistorySettings, FavcatListSettings, SettingsBootstrap, AppModalScaffold, GroupedListSection,
ConciseListRow), `entry` (HomeSourceBar, Index routerMap), `feature/search` (SearchFilterSheet).

## Goal & scope

The whole home sub-tab row is user-configured. A tab = a `CustomProfile`:
name + searchText + category mask + listType (`gallery`/`popular`/`watched`/`toplist`/`favorite`) +
advanced-search payload + display mode. Built-in 默认(gallery)/热门(popular)/订阅(watched) seed as
default profiles that are renamable, reorderable, hideable. Users add/edit/delete/reorder custom
profiles. UI quality is first-class (reuse the existing design system, settings sub-page chrome, and
search-filter controls).

## Non-goals (explicit)

- WebDAV / cloud profile sync (NextE has no WebDAV layer).
- eros_fe `aggregateGroups` (聚合分组, merging multiple profiles into one feed).
- The separate eros_fe Quick-Search keyword feature (`quick_search_page.dart`) — a different feature.
- Per-profile column **width** (pinch density stays global per mode); only display **mode** can be
  per-profile, and that is deferred to the last phase.
- Built-in profile **deletion** (built-ins are hide-only, to preserve the login-gated 订阅 invariant).

## Key decisions

1. `RetainedSubtabHost` is **not** modified — the Swiper key becomes `profile.uuid`; each page looks up
   its profile by uuid from the holder (no `@BuilderParam` signature churn).
2. toplist **period** and favorite **favcat** are **pinned inside the profile** (chosen in the editor);
   the home bar stays a single clean sliding-underline row (no secondary in-bar selector).
3. **[user-confirmed]** The editor is a **full routed page** (`TabEditPage`, HdsNavDestination +
   SecondaryListScaffold + GroupedListSection, like the settings sub-pages / password-login page) — NOT
   a half-modal. It still reuses extracted `CategorySelector` + `AdvancedSearchControls` (lifted out of
   `SearchFilterSheet` so the two never diverge), bound to a transient `new SearchFilterState()`.
4. Built-in 默认/热门/订阅 are renamable/reorderable/hideable but **not deletable**.
5. **[user-confirmed]** Per-tab display mode IS in scope (still built last, Phase 6); until then all tabs
   follow global `ListModeState`. The home title-bar layout menu writes the **active profile's**
   displayMode (so the menu always changes what you see).
6. Data model is a **flat** class (no nested AdvanceSearch) mirroring `SearchFilterState`'s flat advanced
   fields, so the editor binds the extracted controls and copies fields 1:1.

## Data model (new, in `shared/src/main/ets/model/`)

`CustomProfile.ets` — flat class. Fields / types / defaults:

| field | type | default | notes |
|---|---|---|---|
| `uuid` | string | `''` | stable identity = Swiper key + selection-bus value |
| `name` | string | `''` | display label (user-editable) |
| `listType` | string | `'gallery'` | one of `gallery`/`popular`/`watched`/`toplist`/`favorite` |
| `searchText` | string | `''` | joined f_search text (eros_fe joins its List with spaces) |
| `selectedCats` | number | `0` | INCLUDE bitmask, SAME semantics as `SearchFilterState.selectedCats` (0 or 1023 = no filter); `fCats()=1023-selectedCats` |
| `advancedEnabled` | boolean | `false` | |
| `minRating` | number | `0` | |
| `pagesFrom` / `pagesTo` | number | `0` | |
| `requireTorrent` | boolean | `false` | |
| `showExpunged` | boolean | `false` | |
| `disableLanguageFilter` | boolean | `false` | |
| `disableUploaderFilter` | boolean | `false` | |
| `disableTagFilter` | boolean | `false` | |
| `favcat` | string | `'a'` | favorite-type pin (`a`=all / `0`-`9`) |
| `toplistTl` | number | `15` | toplist-type pin (11/12/13/15) |
| `displayMode` | string | `'global'` | `global` = follow ListModeState, else a ListMode value |
| `hidden` | boolean | `false` | |
| `builtin` | boolean | `false` | the 3 seeds; not deletable |
| `lastEditTime` | number | `0` | |

Methods (hand-written, ArkTS rules): `copy()`, `fCats()` (mirror `SearchFilterState.fCats`),
`requiresLogin()` (true for `watched`/`favorite`).

- **uuid scheme**: `@ohos.util` `util.generateRandomUUID(true)` (RFC4122 v4) for custom; built-ins use
  STABLE reserved ids `builtin-default` / `builtin-popular` / `builtin-watched` (idempotent seeding +
  login-gating key off known ids). *(verify the exact util import via the harmony-next skill.)*
- **config wrapper** `CustomTabConfig.ets` (optional; may fold into the holder): `profiles: CustomProfile[]`,
  `selectedUuid: string`.
- **serialization** (mirror `FavcatListSettings` snapshot pattern): a flat `CustomProfileSnapshot` whose
  fields equal `CustomProfile`. Serialize → `JSON.stringify(snap[])`. Deserialize → `JSON.parse` →
  `Array.isArray` guard → per-entry `typeof` guards + enum clamping (listType to the 5; toplistTl to
  11/12/13/15; displayMode to allowed; favcat to a|0-9) → build a real `CustomProfile` field-by-field
  (no destructuring/index access). Drop empty-uuid; dedup by uuid; **preserve array order = tab order**.

## Field → request mapping (per listType)

All via the EXISTING `GalleryListQuery`/`FavoritesQuery` + `getGalleryList`/`getFavoritesList` (no
network-layer change for gallery/popular/watched/toplist):

- `gallery` → source `''`; profile drives fCats/search/advanced.
- `popular` → source `'popular'` (bare snapshot; ignores filters per getGalleryList).
- `watched` → source `'watched'` (login-gated; profile drives filters).
- `toplist` → source `'toplist'` + `tl=profile.toplistTl` (E-Hentai host, page-paged, no filters).
- `favorite` → `getFavoritesList` with `favcat=profile.favcat` (NEW VM branch — Phase 5).

Categories: store INCLUDE bitmask (like SearchFilterState), convert with `fCats()` — do NOT store
eros_fe's raw f_cats. EH honors `advsearch` only when ≥1 advanced field set (getGalleryList already gates).

## Persistence + state (new, in `shared/`)

- `state/CustomProfilesState.ets`: `@ObservedV2 class CustomProfilesState { @Trace profiles:
  CustomProfile[] = []; @Trace selectedUuid: string = '' }` + helper `findByUuid()`. Connect
  `AppStorageV2.connect(CustomProfilesState, 'v2:customProfiles', ...)`. A single-writer
  `CustomProfilesBridge` command bus (`publishCreate/publishEdit(uuid)/publishManage`) using the
  timestamped cmdKind/cmdSeq pattern from HomeSourceBridge. **@Trace array writes must REASSIGN**
  (`state.profiles = next`), never mutate in place; any field driving a tab's look folds into the
  SubTabBar ForEach key.
- `settings/CustomProfilesSettings.ets` (single writer, mirror SearchHistorySettings): `restore(ctx)`,
  `add/update/remove/reorder/setHidden/setSelected`, `persist()`. `remove` refuses builtin; on removing
  the selected, fall back to first visible. Register `restore` in `SettingsBootstrap.loadAll` BEFORE
  cache preload; the HOME source restore moves here (favcat/toplist for the OTHER surfaces stay in
  `SubtabSelectionSettings`).
- `constants/StorageKeys.ets`: `HOME_CUSTOM_PROFILES = 'subtab.customProfiles'`,
  `HOME_CUSTOM_PROFILES_SELECTED = 'subtab.customProfilesSelected'`. Keep legacy
  HOME_SOURCE/TOPLIST_TL/FAVORITES_FAVCAT (still drive the Toplist tab + Favorites page).

## Migration + seeding (first run / empty)

Seed the 3 built-ins in order: `builtin-default`(gallery), `builtin-popular`(popular),
`builtin-watched`(watched), names from i18n resolved at seed time → stored as plain strings (renamable
thereafter). Read legacy `HOME_SOURCE` → `selectedUuid` (`''`→default, `popular`→popular, `watched`→
watched; if logged out and watched → default). Persist immediately. Idempotent (stable builtin uuids).

**[user-confirmed]** ALSO pre-seed two starter CUSTOM (deletable, `builtin:false`) example profiles
after the three built-ins: 汉化 (listType `gallery`, searchText `language:chinese`) and 选集 (listType
`gallery`, searchText `other:anthology`), names from i18n. They get generated uuids. Seeding runs only
when the stored profile list is empty, so deleting them later does not re-add them.

## Subtab integration (change points)

- `HomePage.ets`: `visibleSources()` → ordered uuids of non-hidden, login-gated profiles; `selectedKey`
  = clamped `selectedUuid`; onSelect → `setSelected`. Login @Monitor: if logged out while selected
  requiresLogin, select first visible. ADD @Monitor on `CustomProfilesBridge` to open editor / push
  manager (mirror openLayoutMenu).
- `RetainedSubtabHost.ets`: **no changes** (feed it uuid list).
- `GallerySourcePage.ets`: resolve profile by uuid; `vm.configureFromProfile(p)` before first load;
  @Monitor profile edits → reconfigure + reload.
- `GalleryListViewModel.ets`: add `configureFromProfile(p)`; `buildQuery` reads filters from profile for
  gallery/watched; `cacheKey` includes profile uuid (`EhPageCacheService.homeProfileKey(isEx, uuid)`).
- `HomeSourceBar.ets`: map profiles → `TabItem[]` (key=uuid, label=name); `scrollable: true`; long-press
  → `publishEdit`; pinned trailing + chip. SubTabBar gains optional `onLongPress(index)` + optional
  pinned-trailing @BuilderParam (additive; existing look unchanged).
- list-type handling: popular/toplist/watched need no in-bar secondary selector; period/favcat pinned in
  profile. favorite is its own VM branch (Phase 5).

## Display-mode-per-tab (in scope; built in Phase 6) — user-confirmed

Optional `@Param overrideMode` on `GalleryListBody`; GallerySourcePage passes `profile.displayMode`
(`global` → follow ListModeState). Column widths stay global. **Decided:** the home title-bar layout
menu writes the **ACTIVE profile's** displayMode (so the menu always changes what you see); a profile
set to `跟随全局` uses the global default. Until Phase 6 ships, every tab follows global ListModeState
(zero regression).

## UI design

### Surface 1 — entry affordance (no new title-bar icon; HDS maxCount:3 already full)
- (A) Pinned trailing circular **+** chip at the strip's right edge (outside horizontal scroll; left
  linear-gradient fade over scrolling tabs) → push TabManager. `Button(type:Circle)` ~30vp + SymbolGlyph
  `sys.symbol.plus`.
- (B) Long-press any tab (`LongPressGesture{duration:500}`) → `bindContextMenu` Menu: 编辑此标签 /
  管理标签 / 添加标签. Tab row keeps its exact current look.

```
┌ home title bar: [search] [layout] [↑]  (unchanged, maxCount 3) ┐
├ sub-tab strip ────────────────────────────────────────────────┤
│  默认   热门   订阅   工作   双子   …  ▌(scrolls)▐   ( + ) ←pinned │
│  ▔▔▔ sliding underline under active                              │
└─ long-press a tab → [编辑此标签 / 管理标签 / 添加标签] ───────────┘
```

### Surface 2 — Tab Management page (routed `TabManager`, `feature/home/.../pages/TabManagerPage.ets`)
Shell: HdsNavDestination + SecondaryListScaffold + immersiveTitleBar(管理标签) +
`.backgroundColor(sub_background)` (REQUIRED or card invisible). Title-bar `+` → editor (create).

```
┌ ‹  管理标签                                              +  ┐
│ ┌ GroupedListSection ─────────────────────────────────────┐ │
│ │ [▦] 默认            画廊                    [默认]  ◉  ≡  │ │  builtin: hide switch + grip, no delete
│ │ [🔥] 热门           热门                    [默认]  ◉  ≡  │ │
│ │ [🔔] 订阅           订阅 (需登录)           [默认]  ◉  ≡  │ │
│ │ [▦] 工作            画廊·Doujinshi,Manga·高级   ◉  ≡  │ │  custom: swipe-left → 删除
│ │ [♥] 我的收藏        收藏·收藏夹2                 ◉  ≡  │ │
│ └─────────────────────────────────────────────────────────┘ │
│  [ + 添加标签 ]   (brand-colored ConciseListRow)            │
└────────────────────────────────────────────────────────────┘
```
Row: leadingIcon = listType glyph; title=name; subtitle = one-line summary; suffix = hide Toggle + drag
grip. Tap row → editor (edit). Reorder = `List.onMove` *(verify SDK 26 signature; fallback up/down
chevrons)*. Delete = `ListItem().swipeAction` red trash, **custom only**, alert-dialog confirm. Hidden
rows render at 0.4 opacity.

### Surface 3 — Tab Edit (full routed page `TabEditPage`) — user-confirmed
Routed HdsNavDestination `TabEdit` registered in Index routerMap; `feature/home/.../pages/TabEditPage.ets`.
Shell: HdsNavDestination + SecondaryListScaffold + `.titleBar(immersiveTitleBar(新建标签/编辑标签))` +
`.backgroundColor(sub_background)`. Pushed (with the target uuid, or empty for create) from HomePage
long-press menu / pinned-chip and from TabManagerPage row tap / `+`. Title-bar trailing 保存 (checkmark)
validates non-empty name + persists with lastEditTime; back = cancel. Custom profile → a 删除 row at the
bottom; builtin → reduced form (name + display mode + hide only; listType/search/cats fixed). Binds a
transient `new SearchFilterState()`.

```
┌ ‹  编辑标签                                            保存 ┐
│ ┌ 名称 ───────────────────────────────────────────┐       │  TextInput (RADIUS_ROUND), GroupedListSection
│ │  工作                                             │       │
│ └──────────────────────────────────────────────────┘       │
│ ┌ 列表类型  ───────────────────────────  画廊  ▾ ──┐       │  ConciseListRow + checkmark Menu of 5
│ │  (favorite→ 收藏夹 ♥ 我的收藏 ▾ | toplist→ [全部 年 月 昨日]) │  (drives which sections below show)
│ └──────────────────────────────────────────────────┘       │
│ ┌ 分类 ───────────────────────────────────────────┐       │  REUSE extracted CategorySelector grid
│ │  [Doujinshi][Manga][Artist CG]… (5×2 toggles)    │       │  (gallery/watched/favorite only)
│ ├ 搜索词 ─────────────────────────────────────────┤       │  AppSearchField
│ │  language:chinese                                 │       │
│ └──────────────────────────────────────────────────┘       │
│ ┌ 高级搜索 ──────────────────────────────────  ◯/◉┐       │  REUSE extracted AdvancedSearchControls
│ │  (评分段 / 页数范围 / 5 个开关; gallery/watched)  │       │
│ ├ 显示模式 ────────────────────────  跟随全局  ▾ ──┤       │  Phase 6 (hidden/disabled until then)
│ └──────────────────────────────────────────────────┘       │
│ ┌ 删除此标签 (custom only, red) ───────────────────┐       │
│ └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### Reuse & extraction
- Bind a transient `@Local filter: SearchFilterState = new SearchFilterState()` (NOT the global
  singleton); seed from the profile on page enter, read back on 保存.
- EXTRACT `shared/.../components/CategorySelector.ets` + `AdvancedSearchControls.ets` from
  `SearchFilterSheet` (search sheet re-consumes them — guard with before/after screenshots).
- REUSE as-is: AppModalScaffold, GroupedListSection, ConciseListRow, SecondaryListScaffold,
  immersiveTitleBar, TabItem, RetainedSubtabHost, TabSegmentButtonV2, AppSearchField,
  Menu/SettingsCheckedMenuItem, alert-dialog confirm.

## i18n keys (base + en_US + zh_CN + ja_JP; run check_i18n_duplicates.py)
Reuse existing where present (home_source_*, toplist period, view_list/grid). Add: tabs_manage_title,
tabs_edit_title, tabs_create_title, tab_name_label, tab_name_placeholder, tab_list_type,
tab_type_{gallery,popular,watched,toplist,favorite}, tab_category, tab_search_text, tab_advanced,
tab_display_mode, tab_display_follow_global, tab_favcat, tab_action_{edit,manage,add,hide,show},
tab_delete_confirm_title, tab_delete_confirm_message, tab_name_required, tab_builtin_badge,
tabs_empty_hint.

## Risks
1. `List.onMove` drag-reorder unproven in repo — verify SDK 26 signature; fallback up/down chevrons.
2. @Trace array reassign + SubTabBar ForEach key must fold name/hidden (memory: ForEach key must include
   render fields) so rename/hide redraws the bar.
3. Favorite-type paging differs from gid-cursor lists — isolate in its own phase.
4. Cache-key change may orphan warmed caches on upgrade (acceptable; re-warm).
5. Extracting CategorySelector/AdvancedSearchControls risks visually regressing the search sheet — gate
   with before/after screenshots.
6. Per-tab display mode changes the global layout-menu write target — confirm with user.

## Decisions (confirmed with user — no blocking open questions)
1. Built-ins HIDE-ONLY (rename + reorder + hide, NOT delete). ✓
2. Editor = **full routed page** `TabEditPage` (like eros_fe), not a half-modal. ✓
3. First-run seeds = 默认/热门/订阅 **plus** two deletable starter customs 汉化 (`language:chinese`) +
   选集 (`other:anthology`). ✓
4. Per-tab display mode **in scope** (Phase 6); home layout menu writes the ACTIVE profile's mode. ✓
5. period/favcat PINNED in profile (no in-bar secondary selector). ✓
6. NON-GOALS: WebDAV sync, aggregateGroups, Quick-Search — out of scope. ✓
7. searchText stored per-profile (each tab remembers its query). ✓

## Phased implementation (each phase shippable; keep V1 gate 0 + harness-verify green)

### Phase 1 — model + persistence + migration (invisible foundation) ✅ DONE
- [x] Add CustomProfile (+ snapshot), CustomProfilesState, CustomProfilesSettings (CRUD/reorder/persist/
      restore + migration/seeding), StorageKeys keys. (CustomTabConfig folded into the holder; command
      bridge deferred to Phase 3.)
- [x] Wire `CustomProfilesSettings.restore` into SettingsBootstrap before cache preload.
- [x] Add `scripts/test_custom_profiles_contract.mjs` (structural: copy/serialize/parse cover all 20
      fields; clamps; legacy-HOME_SOURCE→selectedUuid migration; builtin seeds; storage keys).
- DoD: app builds + launches identically (bar still shows 默认/热门/订阅, unchanged); seeds persist;
  contract green; v1-decorator gate 0; harness-verify green.

### Phase 2 — read-only dynamic tabs (wire bar/host/VM to profiles) ✅ DONE
- [x] HomePage visibleSources/selectedKey from holder; HomeSourceBar builds TabItem[] from profiles
      (scrollable); selection via CustomProfilesSettings.setSelected; login fallback.
- [x] GallerySourcePage resolves profile by uuid; GalleryListViewModel.configureFromProfile +
      buildQuery/cacheKey (uuid-scoped EhPageCacheService.homeProfileKey) from profile; preload by profile.
- DoD met: device .197 — 5 tabs (默认/热门/订阅/汉化/选集); 默认=front page, 汉化=language:chinese,
  选集=other:anthology load correctly; cache isolated per uuid; state retained on switch; V1 gate 0,
  contract green, signed build green.

### Phase 3 — Tab Management page (view/reorder/hide/delete; no editor yet) ✅ DONE
- [x] TabManagerPage routed ('TabManager') + registered in Index routerMap; pinned + chip on
      HomeSourceBar pushes it directly (no bridge needed — matches AccountPage's pushPathByName).
- [x] Reorder via ForEach.onMove (onMove is on DynamicNode, not List); hide via Toggle (setHidden moves
      selection off a hidden selected tab); delete via swipeAction red-trash (custom-only) + confirm dialog.
- DoD met: device .197 — manage page shows 5 cards (type icons + 默认 badge on builtins + search summary
  + visibility toggle); hiding 选集 drops it from the bar and re-shows on un-hide; swipe-deleting 汉化
  (confirm) removes it; builtins have no swipe. V1 gate 0, contract green, signed build green.

### Phase 4 — Tab Editor (create/edit — the headline feature) ✅ DONE
- [x] Extracted CategorySelector + AdvancedSearchControls into shared/components; SearchFilterSheet
      re-consumes them (device-verified the filter sheet is visually unchanged).
- [x] Built routed TabEditPage (name / list-type Menu / favcat or toplist-period conditional / category /
      search / advanced / delete) bound to a transient SearchFilterState; pushed from TabManager + (create)
      and TabManager row tap (edit, uuid param via onReady); 保存 validates name + persists; built-ins
      reduce to name-only.
- DoD met: device .197 — created "TestDJ" (gallery + Manga soloed) → appears in bar + manager + loads a
  distinct list; re-opening it in the editor seeds name + Manga-selected correctly (persist round-trip);
  search filter sheet unchanged after the extraction. V1 gate 0, i18n parity, contract, signed build green.

### Phase 5 — favorite list-type fetch ✅ DONE
- [x] GalleryListViewModel favorite branch: getFavoritesList + favorites page/from paging (ported from
      FavoritesViewModel) honoring the profile favcat pin; cacheKey stays the per-uuid homeProfileKey.
- [x] Bonus: GallerySourcePage @Monitor(profiles) reconfigures + reloads the retained VM when THIS page's
      profile is edited (lastEditTime bump) — a live type/category/favcat edit takes effect without a restart.
- DoD met: device .197 — a favorite-type TestDJ loaded the user's favorites (f:<favcat> labels visible);
  editing it favorite→gallery live-reloaded into a gallery list with no restart. V1 gate 0, build green.

### Phase 6 — per-tab display mode (last, optional polish)
- [ ] GalleryListBody overrideMode @Param; GallerySourcePage passes profile.displayMode; editor 显示模式
      row enabled; resolve layout-menu write-target (recommend active profile).
- DoD: switching tabs can change renderer per profile; 跟随全局 works; no column-width regression;
  gate 0; harness-verify green.

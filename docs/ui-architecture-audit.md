<!-- Generated 2026-06-15 by an exhaustive read-only multi-agent audit (9 agents, 233 source reads)
grounded in eros_fe source (/home/gamer/git/eros_fe = the SPEC) + V2Next patterns (/home/gamer/git/V2Next
= native HOW) vs NextE current. 73 findings, 65 proactively found (not user-raised). This is the durable
record of WHY the breadth-first work produced wide-but-shallow UI/architecture, and the depth-first
sequence to fix it. Companion to docs/parity-driver.md. Every claim cites file:line. -->

# NextE UI/Architecture Problem Report — measured against eros_fe (spec) + V2Next (native HOW)

Cross-lens dedup note: several lenses independently flagged the same three diseases (search-as-tab, controls-in-list, tag-coloring-by-namespace). I merge duplicates and cite the strongest evidence from each.

---

## TIER 0 — FOUNDATIONAL (fix these before anything else)

### F1. The nav shell never adopted V2Next's `bottomBuilder` — every fixed control bar is jammed into the scroll list (ROOT CAUSE of a whole bug class)
- **eros_fe truth**: fixed sub-bars live at nav-bar level, above the body — favcat strip is a pinned/floating `SliverPersistentHeader` (`favorite_tabbar_page.dart:98-100`), source/period selectors are nav chrome, never list content.
- **NextE current**: `Index.ets` `titleBarOpts` (`Index.ets:114-136`) only ever sets `title` / `stackBuilderComponent`; grep for `bottomBuilder` across the repo returns **zero hits**. So `HomePage.SourceBar`, the toplist `PeriodChip` row, and `FavoritesPage.FavHeader` are injected as the first `ListItem/GridItem` (`HomePage.ets:90-92,130-132`; `FavoritesPage.ets:154-158`).
- **Fix**: Port V2Next's `content['bottomBuilder'] = { builderComponent: cc, height, showType: BottomBuilderShowType.DIRECTLY_SHOW }` (`V2Next Index.ets:1356-1361`), keyed on `currentTab`, hosting a `ComponentContent` cached **once** in `aboutToAppear` (`V2Next Index.ets:227-233`; NextE already does this for the search field at `Index.ets:45,117-123` — reuse that muscle). Pin via `.bindToScrollable([scroller])` + `.dynamicHideTitleBar({ hideBottomBuilder:false, mode:HideMode.SCROLL_UP })` (`V2Next Index.ets:650-661`). This single piece fixes F1a–F1d below at once.

  - **F1a (high)** SourceBar scrolls away → can't switch source when scrolled down (`HomePage.ets:130-132`).
  - **F1b (high)** Switching source/period/favcat zeroes `itemCount` then trips the `itemCount===0 && isLoading` branch (`GalleryListViewModel.ets:147-148`; `HomePage.ets:61`; `FavoritesViewModel.ets:160-165`; `FavoritesPage.ets:83`) → `PageLoadingState()` unmounts the very control just tapped. eros_fe shows the spinner in-body via `SliverFillRemaining` (`toplist_page.dart:215-225`) and never unmounts the chrome. Fix: scope the spinner to the body, don't zero `itemCount` before new data lands.
  - **F1c (high)** Favcat bar (`FavoritesPage.ets:236-291`) neither pinned nor preserved; eros_fe pins it in a floating header and swaps only the `PageView` body (`favorite_tabbar_page.dart:130-143`).
  - **F1d (medium)** Toplist period chips (`HomePage.ets:189-197`) should be a title-bar action that opens an HDS picker with the active period reflected in the title (`toplist_page.dart:54,98-112`), not an always-visible inline row.

### F2. SEARCH is a bottom tab — eros_fe has NO search tab (search is an app-bar icon that pushes a route)
- **eros_fe truth**: search is never in `kDefTabMap`/`kTabNameList`; it's a `CupertinoIcons.search` nav-bar action → `NavigatorUtil.goSearchPage()` pushing `EHRoutes.search` (`custom_tabbar_page.dart:219-229`; `routes.dart:61`), and the Favorites tab has its own search icon for search-within-favcat (`favorite_tabbar_page.dart:202-210`).
- **NextE current**: `GallerySearchPage` is the 2nd bottom tab (`Index.ets:166-167`, `tab_search`) and the whole title bar becomes a persistent search field on `currentTab===1` (`Index.ets:114-136`). This is the proximate cause Toplist and Download lost their tab slots.
- **Fix**: Remove the Search tab. Add a magnifier to the Home title-bar trailing that `pushPathByName('Search', …)`, plus a search icon on Favorites; cross-page "search for X" (`Index.ets:66-81`) should push the route, not switch tab index. Use V2Next's title-bar-action + pushed-page idiom.

### F3. Bottom-nav DESTINATION SET is wrong on every count, and Download is fully unreachable
- **eros_fe truth**: default phone bottom nav = **Gallery / Favorite / Toplist / Download / Setting** (History optional/off), user-reorderable + persisted + WebDAV-synced (`tabhome_controller.dart:69-92,119-132,146-204`).
- **NextE current**: hard-coded **Home / Search / Favorites / Me** (`Index.ets:159-174`), no config holder, no persistence. Toplist demoted to a Home chip; **Download is dead UI** — registered at `Index.ets:144` but a repo-wide grep finds **zero** `pushPathByName('Download')` callers and no Settings/Me row; **History** has a model (`ViewedGallery`, `ViewedHistorySettings.ets`) but no page and no entry point anywhere.
- **Fix**: Re-shape the tab set to eros_fe's default; introduce a `TabConfig`-equivalent AppStorageV2 holder (enabled set + order, Setting always last) driving `HdsTabs`. Add the per-list **leading overflow menu** (`buildLeadingCustomPopupMenu`, `default_tabview_controller.dart:323-374`) so any destination not pinned stays reachable — this is eros_fe's safety net that prevents orphaning. At minimum, give Download and History a reachable entry today.

### F4. List-card tag colors are FABRICATED by namespace — eros_fe colors each chip by the per-tag hex EH already emitted in the markup
- **eros_fe truth**: each chip is painted from the tag's OWN parsed hex — `style` attr `#hex` matches: 1st→`color`, 4th→`backgrondColor` (`gallery_list_parser.dart:176-192`), rendered verbatim by `TagItem` with a flat grey fallback (`gallery_item.dart:543-563,595-600`). The namespace→pastel map exists but is **not** used on the list card. These colors carry the logged-in user's MyTags styling.
- **NextE current**: parser captures only `title="ns:tag"` and throws away `style` (`EhGalleryListParser.ets:169-181`); `SimpleTag.color/backgroundColor` are declared (`SimpleTag.ets:11-12`) but never populated; `GalleryCard.ets:55-58` tints every chip with `EhConstants.tagNamespaceColor(t.namespace)` (`EhConstants.ets:151-168`). 100% of the coloring is invented.
- **Fix**: In the parser, also capture each `<div class="gt">` `style` and regex `#([0-9a-f]{6})` (match[0]→color, match[3]→backgroundColor); populate `SimpleTag`. In `GalleryCard.ets` render the parsed hex with a single neutral fallback (`BG_SUB`/`font_secondary`) and **delete** the `tagNamespaceColor` branch.

### F5. No global MyTags/usertag store → the HIDE filter is entirely missing and detail coloring is inverted
- **eros_fe truth**: one app-wide `TagController` (`get_init.dart:92`) holds every tag's color/bg/watch/hide, loaded ~5s after launch (`tag_controller.dart:14-25`) and enriched from every list fetch (`addAllSimpleTag`). `needHide` (`tag_controller.dart:39-57`) drives `removeWhere` after every search/popular/toplist fetch (`fetch_list.dart:86-97,166-172`). Detail chips are colored per-tag by MyTags color + vote (green/red) with a plain namespace label (`gallery_widget.dart:479-495`).
- **NextE current**: `getMyTags` is called only from `MyTagsPage.load` (`MyTagsPage.ets:37`) and discarded on pop — no startup load, no holder, no accessor. There is **no hide filter anywhere** in the list pipeline (grep finds nothing). `GalleryTagsCard.ets:27-37` colors the **namespace header** and leaves members grey — the exact inverse of eros_fe; vote-state coloring absent.
- **Fix**: Add a shared `@ObservedV2`/`@Trace` AppStorageV2 usertag store under `shared/state` (canonical `NavStackHolder.ets` pattern). Load on login/startup from `getMyTags`, enrich from each list parse. Expose `getColor(ns,tag)` / `isHidden(ns,tag)`. Then F4, the detail-color inversion, the hide filter (drop galleries whose `simpleTag ∈ hide`, honoring the `disableCustomFilterTags` 3-way split), and watched flagging all become possible. This is the foundation under F4 + the next two.

### F6. SETTINGS is a 3-row stub — eros_fe's 8 settings sub-pages are entirely absent
- **eros_fe truth**: Settings is a grouped list of 8 routed pages — EH / Layout / Read / Download / Search / Advanced / Security / About (`setting_controller.dart:110-141`; `routes.dart:12-22`).
- **NextE current**: `SettingsPage.ets:93-121` has only Site toggle, View-density cycle, and an About row that is trailing text `NextE v1.0.0` (no page); `Index.ets:139-157` registers none of the sub-pages.
- **Fix**: Build the tree as `HdsNavDestination` pages using V2Next's `SecondaryListScaffold + GroupedListSection + ConciseListRow` (already used in `SettingsPage.AccountSection`). Register each in `routerMap`.

---

## TIER 1 — HIGH

### H1. DETAIL has no GalleryActions row (Rate / Download / Torrent / Archiver / Similar)
- eros_fe: 5-button action bar under the header (`slivers.dart:21-99`, placed by `gallery_page.dart:287`). NextE: only a 3-text-link `relationsRow()` (`GalleryDetailPage.ets:270-306`); torrent is non-interactive text. Fix: add the action card above Tags; Download shows task progress like `DownloadGalleryButton`.

### H2. DETAIL header has no Favorite button
- eros_fe: `[GalleryFavButton, ReadButton]` row beside the cover (`header_sliver.dart:73-83`). NextE: only READ (`GalleryHeaderCard.ets:74-83`); fav state shown read-only (`GalleryInfoBar.ets:88-100`). Fix: add a Fav button left of READ → favcat picker sheet.

### H3. READER has no top bar (Back / counter / Share / menu→settings)
- eros_fe: `ViewTopBar` frosted bar with all four (`view_widget.dart:913-1047`). NextE: `.hideTitleBar(true)` (`ReaderPage.ets:102`) + only bottom chrome (`:302-369`) — no back, no share, no settings. Fix: add a frosted top bar; structure after V2Next `ImagePreviewPage.ets:408-575` (sibling overlay buttons over the gesture layer). *(user_mentioned)*

### H4. READER bottom bar missing Save / Double-page / Auto-read / Thumbnail-strip
- eros_fe: `ControllerButtonBar` (`view_widget.dart:1155-1368`) + thumbnail scrubber (`:1371`). NextE: only counter + mode toggle + slider (`ReaderPage.ets:302-369`). Fix: extend the bottom bar; thumbnail strip jumps on tap.

### H5. ReaderSettingsPage is built and route-registered but UNREACHABLE
- eros_fe: opened from reader `…` menu (`view_widget.dart:996-1015`) and Settings "Read" row. NextE: `ReaderSettings` registered (`Index.ets:154-155`) but no `pushPathByName('ReaderSettings')` anywhere; no Read row, no reader menu. Fix: add both entry points (the route is already wired).

### H6. SEARCH title-bar actions almost entirely missing
- eros_fe: jump-to-top, jump-to-page, image-search, filter, plus in-field quick-search list / add-to-quick-search / URL-jump (`search_page.dart:721-865,917-999`; routes `24,62`). NextE: only a body Filter chip + recent history; bare-URL jump only (`GallerySearchPage.ets:102-112,231-251`). Fix: add per-tab title-bar trailing actions; image-search + quick-search as new routes/pages.

### H7. Toplist demoted from a tab to a Home chip
- eros_fe: first-class tab with its own page, nav title = active period, action-sheet period picker (`toplist_page.dart:54,98-112`). NextE: source chip #3 + inline period row (`HomePage.ets:181,189-197`). Fix: give Toplist its own destination; period via title-bar action. (Overlaps F1d/F3.)

### H8. NAV SHELL collapses 6 configurable tabs → 4 fixed; Toplist/Download/History dropped as tabs
- Consolidated under F3. Critically History has *no* entry point at all today.

### Hand-rolled-chip cluster (HR) — stop hand-rolling, port V2Next `FilterChip`
V2Next's canonical selectable chip is `FilterChip` → native ArkUI `Chip` (`V2Next shared/.../FilterChip.ets:18-31`), used in `DiscoverPage.ets:155-159`. NextE re-implements it as styled `Text` **six** times:
- **HR1 (high)** Home SourceChip/PeriodChip (`HomePage.ets:203-247`) — period sub-tab should be `TabSegmentButtonV2` (`BlockedListsTabsSegment.ets`).
- **HR2 (high)** Favorites FavChip + sort-order toggle (`FavoritesPage.ets:293-323,269-287`).
- **HR3 (high)** Search filter category/rating chips + FilterTrigger (`SearchFilterSheet.ets:160-175`; `GallerySearchPage.ets:231-251`).
- **HR4 (medium)** MyTags tag-SET bar (`MyTagsPage.ets:121-160`) → `TabSegmentButtonV2`. Keep the per-tag colored `TagChip` (`:184-204`) — that's legitimate EH-domain rendering.
- **Fix**: port `FilterChip` (and `TabSegmentButtonV2` pattern) into `shared`, export from `shared/Index.ets`, replace all six.

### H9. Search filter sheet bypasses HDS modal chrome
- V2Next always pairs `.bindSheet()` with `AppModalScaffold` (HDS nav + `titleMode(MODAL)` + native close + safe-area + keyboard padding) — `AppModalScaffold.ets:20-65`. NextE's only sheet is raw `Scroll{Column}` + hand-rolled Reset/Apply capsules (`SearchFilterSheet.ets:32-158`); NextE has **no** `AppModalScaffold` at all. Fix: port it, wrap the sheet content; template = `NetworkProxySettingsPage.ProfileEditorSheet`.

---

## TIER 2 — MEDIUM

- **M1. 'Me' tab is Settings mislabeled** — eros_fe's last tab is the Setting cog (`tabhome_controller.dart:130`); NextE labels it 'Me' with a person concept (`Index.ets:171-173`, `string.json:32-33`). Fix: rename to Settings + gear glyph.
- **M2. Source-switching placed wrong** — eros_fe uses a nav-bar leading menu + a user-PROFILES `LinkScrollBar` (`custom_tabbar_page.dart:354-392`); NextE invents a 4-chip SourceBar conflating 4 endpoints (`HomePage.ets:175-201`). The entire custom-profiles subsystem (presets, add/edit/delete, reorder, persistence, WebDAV) is missing. Fix: implement profiles model + leading overflow.
- **M3. DETAIL InfoBar not tappable** — eros_fe opens a full Gallery-Info copy-able page (`header_sliver.dart:184-191`, `gallery_info_page.dart`); NextE's `GalleryInfoBar.ets:28-121` is inert, no `GalleryInfo` route. Fix: make tappable → push ported info page.
- **M4. FAVORITES missing order-direction nuance / jump-to-page / jump-to-top / favcat-selection page** — eros_fe `favorite_tabbar_page.dart:190-273,379-399`. NextE `FavoritesPage.ets` lacks all of these. Fix: add title-bar jump actions + `selFavorite` page.
- **M5. HISTORY destination absent from IA** — consolidated under F3 (model exists, no page/entry).
- **M6. Tab set not user-configurable** — consolidated under F3.
- **M7. Per-list leading overflow menu missing** — consolidated under F3 (it's the reachability mechanism).
- **M8. Detail-page tag coloring inverted + vote-color missing** — consolidated under F5.
- **M9. Watched-tag flagging unimplemented** — `EhUsertag.watch` parsed, never affects render (`MyTagsPage.ets:19-20` even promises a ring). Depends on F5.
- **M10. Reader chrome hand-rolled vs ImagePreviewPage overlay** — `ReaderPage.ets:302-369` bespoke; mode toggle is another Text chip. Fix under task #19, structure after `ImagePreviewPage.ets`. *(user_mentioned)*
- **M11. Card: cover not flush-left** — eros_fe pads right-only + left-only rounded clip, full-bleed cover (`gallery_item.dart:93,362-374`); NextE wraps the whole card in uniform 12px padding + all-corner 4px thumbnail (`GalleryCard.ets:151`; `EhThumbnail.ets:26`). Fix: right/top/bottom padding only, left-only corner clip.
- **M12. Card: cover too small + fixed pixel box** — eros_fe ≈ shortestSide/3 × 204 (`gallery_item.dart:233-241`); NextE frozen 108×152 (`GalleryCard.ets:9-10`). Fix: width from viewport short side, fill card height.
- **M13. Card: no fixed-height mode** — eros_fe default fixed 204px uniform card (`ehsetting_service.dart:179`); NextE variable `minHeight:152` (`GalleryCard.ets:147`). This is the root of the "cards feel 小气" complaint. Fix: adopt fixed-height ≈204, title capped to (5 − tagLine) lines, bounded multi-row tag grid.
- **M14. Tag chip font 10 vs eros_fe 12** (`GalleryCard.ets:49` vs `gallery_item.dart:549`); a `FONT_SIZE_CAPTION=12` token exists unused.
- **M15. Category badge font 10 vs eros_fe 14** (`GalleryCard.ets:85-90` vs `gallery_item.dart:511-525`).
- **M16. Rating stars 14px + 0.5 snap + extra numeric text** — eros_fe 16px continuous, no numeric (`gallery_item.dart:478-494`); NextE `Rating().stepSize(0.5).height(14)` + `.toFixed(2)` (`GalleryCard.ets:76-82`).
- **M17. Uploader/favNote line misplaced** — eros_fe shows it directly under title (`gallery_item.dart:124-134`); NextE jams it into the bottom meta row (`GalleryCard.ets:96-121`).

---

## TIER 3 — LOW / COSMETIC

- **L1. SETTINGS thinness / single Setting-root decision** — grow toward eros_fe's tree (consolidated under F6).
- **L2. SAFE-MODE IA branch absent** — eros_fe collapses to Gallery+Setting under `isSafeMode` (`tabhome_controller.dart:112-117`); NextE has no such gate. Follow-on after the configurable shell.
- **L3. Tablet master-detail layout absent** — eros_fe `TabHomeLarge` two-pane split (`home_page_large.dart:18-60`); NextE phone-only. Roadmap (project test device is a foldable) — don't attempt before phone IA is right.
- **L4. Home title-bar jump-to-page / jump-to-top / tap-title-to-top missing** — eros_fe action cluster (`custom_tabbar_page.dart:232-259`); NextE Home has no title-bar actions.
- **L5. DETAIL Chapter section missing** — eros_fe grid between Tags and Comments (`gallery_page.dart:289,338-364`).
- **L6. AllThumbnails forward-only** — no jump-to-page / back-to-first / previous-page / tap-title (`all_thumbnails_page.dart:36-104`); NextE `GalleryAllThumbnailsPage.ets` forward-only (`:49-55`).
- **L7. Comments page read-only** — no composer/vote/reply/title action (deferred to write-ops; `GalleryCommentsPage.ets:14`).
- **L8. DETAIL no Add-Tag action** — eros_fe nav tags button → addTag page (`gallery_page.dart:189-198`).
- **L9. DETAIL no Share action** — eros_fe builds `/g/<gid>/<token>` → share (`gallery_page.dart:199-214`).
- **L10. DownloadQueuePage on plain `NavDestination` + non-i18n title** — the only NextE page not on `HdsNavDestination` (`DownloadQueuePage.ets:11-26`). Fix at M4.
- **L11. Search history chips inlined, not extracted** — V2Next factored `SearchHistoryStrip` (`SearchPageComponents.ets:66-123`); NextE inlines `SearchHistoryView` (`GallerySearchPage.ets:156-229`). Widget choice (Text) is correct; only reuse differs.
- **L12. tl ordering / listViewTagLimit / per-chip maxWidth:120 / panorama-icon-vs-'P'-suffix / favcat-heart-row-position / postTime 10px-and-split-row** — small card fidelity gaps: `GalleryCard.ets:12,46` (hard 8-tag cap vs eros_fe default unlimited `item_base.dart:136-142`); `:63-65` (per-chip 120px ellipsis eros_fe never does); `:122-129` ('P' suffix + no panorama icon vs `gallery_item.dart:411-435`); `:99-107` (heart in wrong meta row vs `gallery_item.dart:165-171`); `:130-138` (postTime 10px + split from category vs paired final row `gallery_item.dart:183-197`).
- **L13. Tag-translate toggle not honored at card render** — eros_fe gates on `isTagTranslate` at render (`gallery_item.dart:592-594`); NextE `SimpleTag.display()` unconditionally prefers `translat` (`SimpleTag.ets:21-23`).

---

## PROACTIVELY FOUND (user never mentioned these)

Every item below has `user_mentioned=false`. The handful the user *did* raise are noted at the end so the boundary is clear.

**Navigation / IA (none of this was named):**
- F2 Search wrongly a bottom tab; eros_fe has no Search tab.
- F3 Whole bottom-nav destination set wrong; Toplist demoted; **Download is dead UI with zero callers**; History has no surface at all.
- H7/H8 Toplist demoted to a chip; nav shell collapses 6 configurable tabs to 4 fixed.
- M1 'Me' tab is mislabeled Settings.
- M2 Custom-PROFILES subsystem (LinkScrollBar of saved searches) entirely missing; source-chips invented.
- M5/M6/M7 History absent; tab set not configurable; per-list leading overflow menu missing.
- L2 Safe-mode IA branch absent. L3 Tablet master-detail absent. L4 Home jump-to-page/top cluster missing.

**The "fixed control bar as a scrolling list row" disease (F1 + children):**
- F1 The shell never uses `bottomBuilder` — the structural root cause.
- F1a SourceBar scrolls away. F1b the blank-spinner branch destroys the control you just tapped. F1c favcat bar neither pinned nor preserved. F1d toplist period should be a title-bar picker.
- The `ComponentContent`-cached-once requirement (else ~400 rebuilds/s churn, per V2Next's load-bearing comment) — a trap NextE would walk into when adding bars.

**Tag coloring / usertag store (F4, F5 + children):**
- F4 List-card tag colors 100% fabricated by namespace; the real per-tag hex is parsed-then-discarded.
- F5 No global MyTags store; **the entire hide filter is missing** (hidden galleries always show); detail coloring is the exact inverse of eros_fe; vote-state green/red coloring absent.
- M9 Watched-tag flagging inert. L13 tag-translate toggle ignored at render.

**Detail page (none named):**
- H1 No GalleryActions row. H2 No Favorite button in header. M3 InfoBar not tappable / no GalleryInfo page. L5 No Chapter section. L8 No Add-Tag. L9 No Share.

**Reader (only the top-bar redo was on the user's radar via task #19):**
- H4 Save / Double-page / Auto-read / Thumbnail-strip all missing. H5 ReaderSettingsPage unreachable (dead route).

**Search / Favorites / Settings (none named):**
- H6 Almost all search title-bar actions missing (image-search, quick-search, jump-to-page/top). M4 Favorites jump actions + favcat-selection page missing. F6 Settings is a 3-row stub vs 8 sub-pages. L6 AllThumbnails forward-only. L7 Comments read-only. L10 DownloadQueuePage on plain NavDestination + non-i18n title. L11 history-strip not extracted.

**Hand-rolled chips (user named the symptom only at the Home SourceBar / reader-toggle level; the breadth is new):**
- HR2 Favorites FavChip + sort toggle. HR3 Search category/rating chips + FilterTrigger. HR4 MyTags tag-set bar. H9 Search sheet bypasses `AppModalScaffold` (which NextE doesn't even have).

**Card fidelity (none named — this is the concrete content behind the "cards feel 小气" feeling):**
- M11 cover not flush-left. M12 cover too small/frozen. M13 no fixed-height mode (the actual root of "小气"). M14 tag font 10. M15 category badge 10. M16 stars 14px+snap+extra number. M17 uploader line misplaced. L12 the six small card gaps.

**The four items the user DID mention** (for honesty): F1a/F1b/F1d/F1c (the control-bar-in-list problem, raised across the source/period/favcat bars), H3 (reader top bar), M10 (reader chrome redo, task #19), and F4/F5's list-card color fabrication (raised for the list card and the hide filter). Everything else above is net-new from this audit.

---

## RECOMMENDED DEPTH-FIRST SEQUENCE

**Fix this ONE foundation first: the `Index.ets` nav shell + `bottomBuilder` plumbing (F1).** Grounded reasoning: it is the literal root cause cited independently by three lenses, and it unblocks the most surface area per unit work. Concretely, in order:

1. **`entry/src/main/ets/pages/Index.ets` — shell** *(do this first, it's the keystone)*
   - 1a. Port V2Next's `bottomBuilder` slot: per-tab branch in `titleBarOpts`, each bar a `ComponentContent` cached once in `aboutToAppear` (copy the search-field discipline at `Index.ets:45,117-123`), pinned via `.bindToScrollable` + `.dynamicHideTitleBar({hideBottomBuilder:false})`. (F1)
   - 1b. Remove the Search tab; add a Home title-bar search icon that pushes `'Search'`. (F2)
   - 1c. Re-shape the tab set toward eros_fe's default and add a `TabConfig` AppStorageV2 holder + leading overflow menu so Download/History/Toplist are reachable. (F3)
   - This single page change makes the SourceBar, toplist period, and favcat bar pinned/scroll-immune/reload-survivable, kills the blank-spinner-unmounts-the-control bug, and restores the missing destinations — F1a–F1d, F2, F3, H7, H8 all land here.

2. **`shared/state` usertag store + `shared/parser/EhGalleryListParser.ets` + `GalleryCard.ets`/`GalleryTagsCard.ets`** — the second foundation (F5 → F4 → detail-color inversion → hide filter → watched). Do the store first; the three render fixes and the list hide filter all depend on it.

3. **`shared/components/FilterChip.ets` + `AppModalScaffold.ets`** — port both from V2Next once, then sweep all six hand-rolled chip sites (HR1–HR4) and the search sheet (H9). Cheap, high consistency payoff, and it makes the now-pinned control bars in step 1 use native chips.

4. **`feature/gallery` detail page** — GalleryActions row (H1), header Favorite button (H2), tappable InfoBar → GalleryInfo page (M3), then Share/Add-Tag/Chapter (L5/L8/L9).

5. **`feature/reader`** — top bar + bottom-bar controls + wire ReaderSettings entry points (H3/H4/H5/M10), structured after V2Next `ImagePreviewPage`.

6. **`feature/settings`** — build the 8 sub-page tree (F6) so Downloads/History/Read finally have homes.

7. **Card fidelity pass** (M11–M17, L12, L13) — last, because it's pure visual tuning and the layout discipline (fixed-height ≈204, flush-left cover) is best done once the card isn't also hosting a control bar.

8. **`feature/search` / `feature/user` deep-nav actions** (H6/M4/L6) and the remaining lows.

Do **not** start with the card cosmetics or the chip sweep even though they're easy — the shell (step 1) changes where control bars live and the usertag store (step 2) changes how cards color, so doing those first avoids reworking `GalleryCard`/`HomePage`/`FavoritesPage` twice.

Relevant root paths: `/home/gamer/git/NextE/entry/src/main/ets/pages/Index.ets`, `/home/gamer/git/NextE/feature/home/src/main/ets/pages/HomePage.ets`, `/home/gamer/git/NextE/feature/user/src/main/ets/pages/FavoritesPage.ets`, `/home/gamer/git/NextE/shared/src/main/ets/parser/EhGalleryListParser.ets`, `/home/gamer/git/NextE/shared/src/main/ets/components/GalleryCard.ets`, `/home/gamer/git/NextE/feature/gallery/src/main/ets/components/GalleryTagsCard.ets`; V2Next templates: `/home/gamer/git/V2Next/entry/src/main/ets/pages/Index.ets` (bottomBuilder), `/home/gamer/git/V2Next/shared/src/main/ets/components/FilterChip.ets`, `/home/gamer/git/V2Next/shared/src/main/ets/components/AppModalScaffold.ets`, `/home/gamer/git/V2Next/entry/src/main/ets/components/BlockedListsTabsSegment.ets`, `/home/gamer/git/V2Next/entry/src/main/ets/pages/ImagePreviewPage.ets`.
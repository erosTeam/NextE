# NextE vs eros_fe — feature-depth gap backlog

Source: 7-agent audit `wd0bzkmte` (2026-06-14). The user's verdict: the **already-built** features are
too shallow vs eros_fe ("勉强有个样" / "残缺版本"). eros_fe is the feature-depth + architecture reference
(WHAT data/fields/interactions exist, how structured) — **NOT a pixel copy**; NextE uses native HDS/ArkUI.

**Scope rule (user):** deepen the EXISTING (mostly read) features first. **Defer** write-ops (rating,
fav add/remove, comment post, tag edit) and big new subsystems (download, tag-translation DB, full
uconfig/EhSettings sync, Isar/Hive persistence, global-controller rewrite) — those come later.

Close block by block, each device-verified on 192.168.50.237. Order = visibility × bounded-ness.

## A. Gallery list item enrichment (every list row — highest visibility)
- [x] **favcat heart** — colored `SymbolGlyph(heart_fill)` tinted per favcat slot (eros_fe `_FavcatIcon`).
  Home/search rows resolve the slot from the posted-div border-color; favorites rows carry only the
  favcat NAME (`favTitle`), so `FavoritesViewModel.resolveFavcatSlots` maps favTitle→slot against the
  selector bar. **Gotcha:** EH omits the *active* favcat from the bar on a filtered page → `mergeFavList`
  accumulates the full set from the 全部 load. **Gotcha:** `♥` (U+2665) renders red-emoji and ignores
  `fontColor`; must use SymbolGlyph. Device-verified per-slot: 高分→green #008800, 漫画→orange #ffaa00.
- [x] **rating numeric** next to the stars (eros_fe `_buildRating`); uses `ratingFallBack` (parsed sprite
  value, the community rating) as the display rating, not `rating` (personal vote).
- [x] **favNote** display (parse `favNote` from the row; show in place of uploader when set). (`gallery_item.dart:125`)
- [x] **category color badge** (from real eros_fe device compare): `EhConstants.categoryColor(name)` maps each
  category to eros_fe's `catColor` palette (11 colors, light+dark in app.color); list/grid/simple cards + the
  detail info bar now render the category as a colored badge (white text) instead of plain blue text. Device-
  verified on EX (Western green / Artist CG amber / Misc pink).
- [x] **EX cover fix** `EhConstants.cdnThumb()`: ExHentai thumbnails come from `s.exhentai.org` (auth-gated +
  DNS-blackholed on some networks → blank covers); ehgt.org mirrors the identical `/w/...` path publicly, so
  rewrite the host. Device-verified: 里站 covers that were blank now load. (The blank covers were never a NextE
  bug — confirmed via real-device compare; eros_fe's Android shows them because that network resolves the host.)
- [x] **language / translated badge** — parser derives the 2-letter code (`translated`, chinese→ZH) from
  the `language:<name>` tag via `EhConstants.iso936`. Compact list: grey code before the page count.
  Grid: dark corner-pill on the cover (category-colored styling deferred to the shared category-color map,
  which Block B needs). Device-verified ZH on both. (`gallery_item_flow.dart:75`)
- [~] **expunged** indicator (muted/strikethrough posted time) — DEFERRED: detection is fragile DOM-structural
  (posted-div has child elements) and NO fixture has an expunged gallery to verify against. Needs a real
  expunged-gallery fixture before implementing (else it's blind guessing). (`gallery_list_parser.dart:247`)
- [x] **simpleList** variant — `GallerySimpleCard` (shared): compact fixed-height (72×102 cover) divider row,
  title · uploader · rating+numeric+heart+lang · category+time. Wired into Home/Search/Favorites via the
  existing non-GRID branch (listSpace 0); the settings view toggle is now a 3-way cycle List→Compact→Grid.
  i18n `view_simple` (4 locales). Device-verified cycle + render.
- [ ] **waterfall** variant (image-centric) — `ListMode.WATERFALL`. (lower priority; not in the user's A list)
- [~] long-press context menu (add/remove fav, delete history) — WRITE/history, defer.

## B. Gallery detail page (most feature-dense, most visibly shallow)
- [x] **tag namespace coloring** (UI parity from eros_fe compare): `EhConstants.tagNamespaceColor(ns)` maps each
  tag namespace to eros_fe's `tagColorTagType` pastel palette (10 namespaces, light+dark in app.color);
  `GalleryTagsCard` tints each chip's background by its group's namespace (primary text on the pastel), instead
  of the flat blue-text chips. Device-verified on 里站 (language tags pink-tinted, sample #CAB1BE). (List-row
  tags stay neutral — the list parser strips the namespace; only the detail's grouped tags carry it.)
- [x] **header detail row**: new `GalleryInfoBar` (3 rows: rating+ratingCount+category / language·length·
  fileSize / ❤favcount·posted), inserted after the header. Header now shows EN + **JP title separately** +
  uploader (rating/category/meta moved into the info bar, no dup). Parser already had the fields; contract
  test now locks language/fileSize/ratingCount/posted. Device-verified (★4.83(34)·Manga / Japanese·199P·
  103.4MiB / ❤131·2026-06-14). Category-color map still pending (used a plain emphasize color).
- [x] **header whitespace tightening** (eros_fe real-device compare): the header right column was top-aligned
  title + bottom-pinned uploader with a dead `Blank()` gap (the cover drove the height, the 2 sparse text
  rows didn't fill it). eros_fe *brackets* the cover — title/uploader at the top edge, facts at the bottom
  edge. Moved `GalleryInfoBar`'s row 1 (rating + count + category badge) UP into the header's bottom strip
  (`GalleryHeaderCard`), so title/JP/uploader pin to the top and rating+category pin to the bottom, aligned
  with the cover's edges (no floating gap). InfoBar is now 2 rows (language·length·size / ❤favcount·posted),
  no duplication. Device-verified (192.168.50.197): RTC sabita → title+JP+s4sh top, ★5.00(6)+Doujinshi bottom.
- [~] **rich comment rendering**: LINKS done — the comment body Text uses the native `enableDataDetector`
  + `dataDetectorConfig({types:[URL]})` so bare URLs and `<a>`-as-URL links render brand-colored, underlined
  and tappable (eros_fe linkifies URLs too). Device-verified (twitter URL renders blue vs plain text).
  DEFERRED: bold/italic/strike/spoiler/`<img>` — neither real fixture (gdetail_real, gdetail_rich_real) has
  them, so a Span/ImageSpan tree would be unverifiable guessing; revisit when a real rich-comment sample is
  captured. (EH comments are overwhelmingly text + `<br>` + URLs — verified on 2 fixtures.)
- [x] **comment score + uploader styling**: `EhGalleryComment` + `score` (parsed from `c5` "Score +N") +
  `isUploader` (from the `Uploader Comment` marker). Card shows a 楼主 badge before the uploader's name
  (no score) and a green/red score chip (new `score_positive`/`score_negative` colors, dark+light) +
  per-comment dividers. Contract test locks score/isUploader (real fixture: 50 scored, 1 uploader).
  Device-verified. (`c7` vote-detail list still deferred — low value.)
- [x] **all preview pages**: parser adds `parsePageCount` (max `ptt` label = total preview pages); VM tracks
  `previewPageCount`/`loadedPreviewPages` + `loadMorePreviews()` (fetches `?p=loadedPages` via the existing
  `getPreviewImages`, appends); preview grid shows a count header + a "加载更多" button (i18n). Device-verified:
  count 40 → load-more appended the next page (labels reached 81). **BUG FOUND+FIXED via device diag:** the
  preview regex required `<a ...><div title="Page N">` but **ExHentai wraps it in an extra `<div>`**
  (`<a ...><div><div title=...>`), so previews were parsing to **0 on EX** (where the account is) — i.e.
  previews never showed at all on 里站. Made the wrapper `(?:<div[^>]*>)?` optional; EX now parses 40.
  Contract test mirrors the fix + an EX-variant synthetic case. See [[nexte-eh-ex-preview-markup]].
- [x] **torrent count** + **parent link**: parser adds `torrentCount` (from `Torrent Download (N)`) and
  `parentGid`/`parentToken`/`parentUrl` (from the `Parent:` row). A relations row (between info bar and
  Read) shows a tappable 父版本 link (hidden on self-reference) + 种子: N. Device-verified: tapping 父版本
  navigated from gid 3970138 (942P) to its parent revision 3952258 (938P, earlier date). Contract test
  locks both. **Torrent LIST** (name/seeds/peers/size via gallerytorrents.php) still deferred — needs a
  separate fetch + parser. **Newer version** deferred (no fixture has the marker).
- [x] **similar** (search by title): `EhGallery.shortTitle()` (strip [..]/(..)/{..}, take pre-`|`); a 相似
  link in the relations row publishes `SearchActionState.pendingQuery = <token>:title:"<short>"`. Wired the
  previously-reserved cross-page bus: Index `@Monitor(pendingQuery)` closes the detail page + switches to the
  Search tab + seeds the field; `GallerySearchPage` consumes pendingQuery on appear + monitor (handles the
  lazily-mounted tab) and runs the search. Device-verified: 相似 → Search tab ran `title:"…"` → matching result.
- [~] action bar Rate / Download / Archiver / Fav — WRITE/new-subsystem, defer (keep read: similar, torrent list).

## C. Reader (very basic — only horizontal swipe + zoom + counter)
- [x] **page slider** (seek bar) for jump-to-page: chrome now has a counter + `Slider` (1-based, max =
  `totalPages`). Dragging shows the target page; on release `jumpTo(n)` loads every preview page up to it
  (contiguous list → sequential fetches, `jumping` spinner) then moves there. Device-verified: dragged to
  mid → loaded 40→520 pages → jumped to 499/942 (image changed). **Swiper gotcha fixed:** `.index()` is
  *reactive* (sets the current page), so the old `.index(params.index)` re-applied `0` on every rebuild and
  reset the page after a controller `changeIndex`. Bind `.index(vm.currentIndex)` and set that to jump —
  no SwiperController needed. See [[nexte-arkui-swiper-index]].
- [x] **vertical mode + direction switch (LTR/RTL/vertical)**: new `ReadModeState`/`ReadModeSettings`
  (persisted under the reserved `reading.direction` key, restored in SettingsBootstrap). The reader branches
  on mode — horizontal `Swiper` for LTR/RTL (RTL via `.direction(Direction.Rtl)`) vs a continuous vertical
  `List` of full-width `ReaderVerticalImage`s (height from each image's loaded aspect ratio via onComplete;
  `onScrollIndex` drives the counter + lazy-loads more; slider jump does `scrollToIndex`). A chrome toggle
  cycles 左→右 → 右→左 → 竖向 (i18n). Device-verified all three: vertical shows stacked images + counter
  advanced 1→2 on scroll; RTL/LTR restore the Swiper. eros_fe `ViewMode`.
- [~] **thumbnail strip** panel for quick nav — DEFERRED: preview thumbnails use the ehgt.org CDN which is
  unreachable on the test device (blank cells, can't verify), and it overlaps the just-built page slider.
  Revisit if thumbnail loading works in another environment.
- [~] **double-page** mode (oddLeft/evenLeft) — DEFERRED: a landscape/tablet feature; on the portrait test
  device side-by-side pages are tiny and not meaningfully verifiable. Lower severity than Block D/E/F gaps.
- [~] auto-paging, orientation lock, volume-key turn, brightness — settings (medium/low). DEFERRED.

## D. Search
- [x] **search history** (local persist): new `SearchHistoryState`/`SearchHistorySettings` (JSON array under
  `search.history`, dedup move-to-front, cap 20, restored in SettingsBootstrap). Every run (title-bar submit,
  Similar pendingQuery, chip tap) records via `SearchHistorySettings.add`. The empty state shows recent chips
  (tap → seed field + re-run) + a 清除 clear (i18n), falling back to the hint when empty. Device-verified:
  searched "naruto" → relaunch shows the persisted chip → tap re-ran it (3 results) → clear emptied it.
  **Inset fix:** the non-scaffold history view needed the shared top inset (`topAvoidHeight +
  TITLE_BAR_HEIGHT`, no magic number) or it rendered behind the floating search field. [[nexte-page-layout-from-v2next]]
- [x] **more advanced filters**: `SearchFilterState` + `requireTorrent` (f_sto), `showExpunged` (f_sh), and
  `disableDefaultFilters` (the three f_sfl/f_sfu/f_sft grouped as one "disable my default tag/lang/uploader
  filters"). Wired through `GalleryListQuery` → the list URL builder, surfaced as a new 选项 section of switch
  rows in the filter sheet (i18n), cleared on Reset, applied via the existing applySeq path. Toggles render
  (device-verified); param emission node-verified to match eros_fe exactly (f_sto=on / f_sh=on / f_sfl+f_sfu+
  f_sft=on). (min-favorites omitted — not a real EH search param; language is covered by category + the tag
  query.)
- [~] tag autocomplete suggestions — needs the tag-translation DB; defer (or basic prefix match later).
- [~] quick-search saved list — defer.

## E. Favorites
- [x] **fav note** display on rows — DONE in Block A (favNote parsed + shown in place of the uploader).
- [~] **fav order toggle** (favorited-time vs posted-time): built — `FavoritesQuery.order` → `inline_set=fs_f|
  fs_p` URL param, a 收藏时间/发布时间 toggle in the favcat bar (i18n), VM `toggleOrder()` + reload, and the
  eros_fe `FavOrderException`-style **re-load when the response's active order lags the request** (parsed from
  `<option value="f|p" selected>`; `EhHttpClient` already sends `usingCache:false`). UI device-verified (label
  flips, list reloads). **Visible reorder NOT confirmed:** EH returned `fs_f` selected regardless of
  `inline_set=fs_p` for this session (even on a 2nd request) — server-side stickiness, the exact case
  eros_fe wraps; the top favorites also coincide under both sorts. Code matches eros_fe; the block is EH-side.
- [~] add/remove dialog, local favorites — WRITE/new, defer.

## F. My Tags
- [x] **tagset switching** — new `EhMytagSet` model + parse the `change_tagset` `<select>` (id/name/count +
  selected) → `getMyTags(isEx, tagset)` (`?tagset=N`). The page shows a tagset chip bar; tapping reloads that
  set. Device-verified: switched TAG(38)→Artist(82), tags changed to artist-only (affect3d/amam/…). eros_fe two-level.
- [x] richer usertag display: tags now **grouped by namespace** (header + chips per ns), each in its EH color
  with the watched ring / hidden dim already present; per-tag `weight` parsed (`tagweight_N`) onto `EhUsertag`.
  Contract test locks tagsets + selected + weight (real fixture: 38 tags, 3 tagsets).
- [~] tag edit dialogs, add-new-tag, mutation APIs — WRITE, defer.

## G. Models / parsers to deepen (underpins A–F) — done as a byproduct of A–F
- [x] `EhGalleryComment`: + `score` + `isUploader` (B). `vote`/rich-content-elements deferred (rich rendering
  uses the URL data-detector; `c7` votes are low value).
- [x] `EhGallery` detail fields: language, length, ratingCount, postedTime, japaneseTitle, parentUrl all
  surfaced in the B info bar / relations row. (`expunged` field exists but the indicator is deferred — no fixture.)
- [x] `EhUsertag`: + `weight` + `color` (border); `namespace()` for grouping. New `EhMytagSet` model (F).
- [x] favNote parsed in `EhGalleryListParser` (A).
- [~] EhSettings/uconfig, tag-translation DB, history/download persistence, global controllers — DEFER (big).

## H. Home multi-source (eros_fe popular/watched/front-page collapsed onto the Home tab)
- [x] **source switcher** 默认 / 热门 / 订阅 (eros_fe `request.dart` routes: `/` front · `/popular` · `/watched`).
  `GalleryListQuery.source` routes the path in `getGalleryList`; `/popular` is a fixed snapshot so all
  filter/next params are skipped (eros_fe `isPopular` guards). `GalleryListViewModel.source` + `setSource()`
  hard-reload; a horizontal chip bar is the first list/grid row (same placement + style as the favorites
  favcat bar; `TEXT_ON_BRAND`/`BRAND_PRIMARY` selected). 订阅 only shows when logged in, and a logout while
  on it falls back to 默认 (`@Monitor('auth.isLogin')`). i18n `home_source_default/popular/watched` (4 locales).
  **No-dead-end fix:** the empty full-screen state only takes over for the front page; 热门/订阅 fall through
  to the scaffold so the SourceBar stays reachable. Device-verified (192.168.50.197): 默认→热门 swapped to a
  distinct popular list, 热门→订阅 fetched `/watched` (hilog: HTTP 200, redirect 0 — empty feed for this
  account → "没有更多了" with the bar intact), 订阅→默认 reloaded the live front page. Same gltc parser as
  front/popular, so watched parses identically when populated.
- [~] **排行 toplist** (`toplist.php?tl=15|13|12|11&p=N`) — DEFERRED: distinct HTML (ranked rows) needs its own
  parser + page-number (not gid-cursor) paging + a rank display; a separate block, not the shared list parser.
- [~] quick-search / custom profile tabs (eros_fe `CustomTabbarList`) — config subsystem, defer.

---
**Read-completeness milestone (2026-06-14):** A–G's read gaps are closed and device-verified. Remaining
open items are all explicitly-deferred `[~]`: write-ops (rate/fav/comment/tag-edit), big subsystems
(download / tag-translation DB / uconfig sync / persistence), the EH-blocked fav-order reorder, and the
low-value reader polish (thumbnail strip / double-page / auto-page etc.).

**Quality review (2026-06-14, 7-agent workflow + adversarial verify):** 18 confirmed findings — ALL code
quality (no functional regressions, no feature gaps, no shallow read-impls). Fixed: hardcoded colors → new
`text_on_brand` + `fav_heart_default` theme tokens (dark+light) across 11 sites (cards/chips/badges); `'Note: '`
→ i18n `gallery_fav_note`; favOrder `<option selected>` parse → contract test; 46px Read button →
`ThemeConstants.BUTTON_HEIGHT`. Device-regression clean (favorites: tokens transparent, hearts/chips render
identically). Acknowledged-low (left as-is): one-off layout literals (2px gap / 3px pad / 90×36 input / 60px
label / ConciseListRow dims — value-preserving tokens would be soup, changing values would break verified
layouts), category-color map (deferred), ReaderVM contract test (VMs impractical to contract-test), detail
ratingFallBack-from-sprite (the inline `var average_rating` is more accurate).

Each closed item: read eros_fe's exact impl + the real fixture (scripts/fixtures/*_real.html, session at
/tmp/eh_session.json), implement natively, add/extend the contract test, device-verify.

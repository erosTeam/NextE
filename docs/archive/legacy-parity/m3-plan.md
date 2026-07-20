# M3 — Login / ExHentai (里站) / Favorites / My Tags

Durable worklist for the M3 milestone (auth + private data). Source: research workflow `wx293hb1x`.
Each phase device-verified on `192.168.50.237:12345`; new parsers get a `scripts/test_*_contract.mjs`.

## Architecture (4 layers)

EH auth is cookie-based: `ipb_member_id` + `ipb_pass_hash` (table site) + `igneous` (ExHentai only).
HarmonyOS has no cookie jar — `EhCookieStore` (in-memory) is the runtime source of truth, mirrored
to/from Preferences by `CookieJarSettings`, with `AuthState` as the reactive UI mirror.

## Phase 1 — Login foundation ✅ (done, WebView device-verified; full credential login = user)

- `shared/state/AuthState.ets` — `@ObservedV2 { isLogin, hasIgneous, memberId }` + `connectAuth()`.
- `shared/settings/CookieJarSettings.ets` — `parseCookieValue` / `applyFromHeader` / `save` / `restore` /
  `clear` / `syncAuthState`. Single flat bundle serialized as a cookie header. `igneous=mystery` treated
  as unset. Contract test: `scripts/test_cookiejar_contract.mjs` (0 failures).
- `shared/components/EhWebView.ets` — native `Web` (@kit.ArkWeb) wrapper (JS + DOM storage on).
- `entry/pages/EhLoginWebPage.ets` — hosts EhWebView on `FORUMS_LOGIN_URL`; on each `onPageEnd`,
  `saveCookie` → `fetchCookie(e-hentai.org + forums)` → `applyFromHeader`; once both identity cookies
  present → `CookieJarSettings.save` + toast + `stack.pop`. Route `'EhLogin'` in `Index.routerMap`.
- `SettingsBootstrap.loadAll` → `CookieJarSettings.restore` (login survives restart).
- SettingsPage account section: logged-out → "登录账号" row → push EhLogin; logged-in → member id +
  "退出登录" (confirm → `CookieJarSettings.clear`).
- Device-verified: settings account row → login page renders the EH forums login + Cloudflare Turnstile
  interactively. **Pending: user logs in once to confirm cookie capture → AuthState flips to logged-in.**

## ⛔ Blocker: needs a one-time login (real fixtures + live verification)

Phase 2+ (favorites / ex / My Tags) are auth-gated. To build them to the project's standard they need
a logged-in session for BOTH (a) a real favorites.php / mytags HTML fixture to write the parsers against
(the doctrine requires real-fixture contract tests, not guessed structures), and (b) device verification
on 192.168.50.237. The agent has no test account and must never handle the user's password — so the user
must sign in once (我的 → 登录账号, or 收藏 → 登录账号) on the device. After that, the loop builds favorites
→ ex → My Tags against the real session. Done so far without login: FavoritesPage logged-out gate is now
an actionable login prompt (device-verified).

## Phase 2 — Favorites ✅ (done, device-verified with REAL data)

- `Favcat` model + `EhFavcatListParser` (`<div class="fp" onclick="...favcat=N">` → favId from onclick,
  count from divs[0], name from the `class="i" title="..."` swatch). Contract test
  `scripts/test_favcatlist_parser_contract.mjs` passes against the REAL `favorites_real.html` (all 10 favcats).
- `EhApiService.getFavoritesList(FavoritesQuery)` reuses `EhGalleryListParser` for rows (same `itg gltc`)
  + `EhFavcatListParser` for the bar; `GalleryList.favList` carries the cats. `FavoritesViewModel`
  (BasicDataSource + favcat selection + guarded refresh). `FavoritesPage`: logged-out → login prompt;
  logged-in → `PullRefreshListScaffold` + `GalleryCard` with a horizontal favcat chip bar.
- Device-verified after a normal in-app login: favorites loads remote favcat metadata and galleries; tapping a favcat reloads that category.

## Phase 3 — ExHentai (里站) switch ✅ (done, device-verified)

- `SiteModeSettings` (persist `SITE_MODE_EX` + single writer of `SiteModeState`); restored at bootstrap.
- SettingsPage 站点 row is now tappable: 里站→表站 always; 表站→里站 gated on `auth.isLogin && auth.hasIgneous`
  (else a toast). HomePage + FavoritesPage `@Monitor('siteMode.isEx')` reload from the new host
  (`GalleryListViewModel.reload()`).
- Device-verified: switched to 里站 → Home reloaded real ExHentai galleries (igneous works, no sad panda).
  igneous comes from the login flow (the cdp script visits exhentai.org/uconfig.php). NOTE: a dedicated
  in-app `GET exhentai.org/uconfig.php` igneous-fetch (for users who log in via the WebView without it) is
  still a TODO; sad-panda detection heuristic also deferred.

## Phase 4 — My Tags ✅ (done, device-verified)

- `EhMytags` + `EhUsertag` models; `EhMytagsParser` (each tag = `<div id="tagpreview_N" style="…border-color:#X…"
  title="ns:tag">display</div>` + `tagwatch_N`/`taghide_N` `checked` state + inline `apiuid`/`apikey`).
  Contract `scripts/test_mytags_parser_contract.mjs` passes on the REAL fixture (38 tags, 11 watched /
  15 hidden). `EhApiService.getMyTags(isEx)`. `MyTagsPage` (routed off Settings) = chip cloud in each tag's
  real EH color — watched=white ring, hidden=dimmed. v1 read-only.
- Device-verified: Settings → 我的标签 loads the real tags with correct colors + watch/hide states.

---

## Read-features round (post-M3, user chose "读功能续建")

- [x] **Gallery-detail comments** ✅ (done, device-verified). `EhGalleryComment` + `EhCommentParser`
  (c1 block → comment_N body via `c6`, date+author via `c3`; body stripped to plain text). Contract
  `scripts/test_comment_parser_contract.mjs` passes on the real fixture `gdetail_real.html` (51 comments).
  `GalleryDetailResult.comments` (parsed in `getGalleryDetail`) → `GalleryDetailViewModel.comments` →
  `GalleryCommentsCard` on the detail page. Verified on device (author + date + body render).
- [x] **Search advanced filters** ✅ (done, device-verified). `SearchFilterState` (category SHOW bitmask →
  `fCats()` invert to EH exclude-mask, min rating, page range, `applySeq`). `GalleryListQuery` extended with
  `minRating`/`pagesFrom`/`pagesTo`; `getGalleryList` emits `f_cats`/`f_sr`+`f_srdd`/`f_sp`+`f_spf`+`f_spt`.
  `SearchFilterSheet` (category toggle chips + rating segments + page inputs + reset/apply) hosted via the
  search page `bindSheet`, triggered by a 筛选 chip (blue when active); apply bumps `applySeq` →
  `SearchViewModel.reapplyFilters()`. Verified: Manga+4★ filtered to all-Manga 4★+ results.
- [x] **List grid view** ✅ (done, device-verified). `GalleryGridCard` (full-width cover + title + cat/pages)
  + `PullRefreshGridScaffold` (2-col Grid reusing the generic `PullRefresh` + safe-area insets).
  `ListModeSettings` persists `LIST_MODE`; Settings 列表视图 row toggles 列表/网格. Home / Favorites / Search
  render the grid when `ListMode.GRID` (favorites favcat-bar + search filter-trigger are spanning GridItems).
  Verified: toggle → home + favorites render the 2-col grid with the header spanning.

**Read-features round COMPLETE** (comments ✓, search filters ✓, grid view ✓).

## ✅ M3 COMPLETE (2026-06-14)

Login flow → favorites (favcat selector + list) →
里站/ExHentai switch (igneous) → My Tags — all built and **device-verified through the normal local login path**, every
parser backed by a fixture contract test. Deferred (non-blocking, later): in-app
`exhentai.org/uconfig.php` igneous fetch for WebView-only logins, sad-panda error heuristic, mytags/favorites
**edit** (write) ops, favorites add/remove from detail, search advanced filters, gallery comments, grid view.

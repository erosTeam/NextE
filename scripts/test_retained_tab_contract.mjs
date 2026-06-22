#!/usr/bin/env node
/**
 * Contract for the RETAINED-SUBTAB FRAMEWORK (docs/plans/active/retained-subtab-framework-contract.md).
 *
 * Every UI surface presented as subtabs (Home source, Toplist period, Favorites favcat, future custom
 * subtabs) must share ONE retained-subtab architecture — not per-surface inline patches:
 *   - a shared RetainedSubtabHost owns the Swiper, the per-key Scroller map, cachedCount retention, the
 *     visual-index publishing (onGestureSwipe/onAnimationStart/onAnimationEnd), the onChange selected-key
 *     publication, and the active-scroller handoff; it owns NO content VM/datasource;
 *   - each subtab KEY gets its own retained page (own @Local VM + datasource + scroller + lazy first load);
 *   - selection STATE is a bus (no datasource); the visual index is a SEPARATE bus the bar consumes;
 *   - one shared SubTabBar (compact V2Next metrics, optional counts, scrollable) renders every bar;
 *   - loading is content-area first-load only — no top-then-center duplicate, no full-page load on a
 *     retained-key switch.
 *
 * Split A migrates Home + Toplist onto RetainedSubtabHost (proving the framework). Favorites is still its
 * own inline host (split B) and is asserted as retained-but-pre-migration here.
 *
 * Run: node scripts/test_retained_tab_contract.mjs   (exit 1 on any failure)
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    failures++
    console.error(`✗ ${msg}`)
  }
}

const host = read('shared/src/main/ets/components/RetainedSubtabHost.ets')
const tabItem = read('shared/src/main/ets/model/TabItem.ets')
const subTabBar = read('shared/src/main/ets/components/SubTabBar.ets')
const homeState = read('shared/src/main/ets/state/HomeSourceState.ets')
const favState = read('shared/src/main/ets/state/FavSelectionState.ets')
const homePage = read('feature/home/src/main/ets/pages/HomePage.ets')
const toplist = read('feature/home/src/main/ets/pages/ToplistPage.ets')
const sourcePage = read('feature/home/src/main/ets/components/GallerySourcePage.ets')
const periodPage = read('feature/home/src/main/ets/components/ToplistPeriodPage.ets')
const galleryListBody = read('feature/home/src/main/ets/components/GalleryListBody.ets')
const sourceBar = read('entry/src/main/ets/components/HomeSourceBar.ets')
const periodBar = read('entry/src/main/ets/components/ToplistPeriodBar.ets')
const indexShell = read('entry/src/main/ets/pages/Index.ets')
// Favorites surface — migrated onto the framework in SPLIT B.
const favPage = read('feature/user/src/main/ets/pages/FavoritesPage.ets')
const favcatPage = read('feature/user/src/main/ets/components/FavcatPage.ets')
const favcatBar = read('entry/src/main/ets/components/FavcatBar.ets')

// ── 1. Shared host: ALL retained-subtab mechanics live here, ONCE ───────────────────────────────────
ok(/@ComponentV2/.test(host), 'RetainedSubtabHost is @ComponentV2')
ok(/Swiper\(this\.swiperController\)/.test(host), 'host owns the Swiper(swiperController)')
ok(/@BuilderParam\s+pageBuilder/.test(host), 'host renders each key via a @BuilderParam pageBuilder (generic page injection)')
ok(/Map<string,\s*Scroller>/.test(host), 'host owns the per-key Scroller map (retained scroll per key)')
ok(/\.cachedCount\(this\.keys\.length\)/.test(host), 'host retains ALL keys via cachedCount = keys.length')
ok(
  /\.onGestureSwipe\(/.test(host) && /\.onAnimationStart\(/.test(host) && /\.onAnimationEnd\(/.test(host) && /\.onChange\(/.test(host),
  'host wires the FULL Swiper event set (onGestureSwipe + onAnimationStart + onAnimationEnd + onChange)',
)
ok(/onVisualIndex\(/.test(host), 'host publishes the interpolated visual index (bar indicator sync)')
ok(/onSelectKey\(/.test(host), 'host publishes the selected key back to the surface bus on change')
ok(/onScrollerReady/.test(host), 'host hands the active key scroller up (title-scroller handoff)')
ok(!/@Local\s+vm:/.test(host) && !/loadData|setData|\.reload\(/.test(host), 'host owns NO content VM and never loads/replaces data')
ok(/@Local\s+swiperIndex:\s*number\s*=\s*0/.test(host) &&
  /\.index\(this\.swiperIndex\)/.test(host) &&
  !/\.index\(this\.activeIndex\(\)\)/.test(host),
  'host keeps Swiper.index on a local current index so selectedKey target changes cannot declaratively jump past the animation')
ok(/changeIndex\(target,\s*true\)/.test(host) &&
  /\.duration\(ThemeConstants\.ANIM_DURATION\)/.test(host) &&
  /\.curve\(Curve\.EaseOut\)/.test(host),
  'bar taps ask Swiper to animate from the local current index to the selected target with the project animation timing')
// EXPLICIT FIRST-ACTIVATION SIGNAL: the host shares an ActiveKeyState (an @ObservedV2 whose @Trace reaches
// cached pages) and updates active.activeKey on aboutToAppear + selectedKey change + onChange. A per-render
// isActive @Param does NOT update cached pages (ForEach stable keys + cachedCount), so the old isActive
// signal missed an unvisited subtab's first load — this is the durable fix.
ok(/@ObservedV2[\s\S]*?class ActiveKeyState[\s\S]*?@Trace\s+activeKey/.test(host), 'host defines a shared ActiveKeyState (@ObservedV2 @Trace activeKey)')
ok(/@BuilderParam\s+pageBuilder:\s*\(key:\s*string,\s*active:\s*ActiveKeyState/.test(host), 'host passes the SHARED ActiveKeyState to pages (not a per-render isActive boolean)')
ok(/this\.pageBuilder\(key,\s*this\.active,/.test(host) && !/this\.pageBuilder\(key,\s*key === this\.selectedKey/.test(host),
  'host hands pages this.active as the pageBuilder activation signal (not the old per-render boolean isActive)')
ok((host.match(/this\.active\.activeKey\s*=/g) || []).length >= 3, 'host updates active.activeKey on aboutToAppear + selectedKey change + onChange (every activation path)')

// ── 2. Generic TabItem/key model ─────────────────────────────────────────────────────────────────────
ok(/export class TabItem/.test(tabItem), 'a generic TabItem model exists (key + label + count)')
ok(/key:\s*string/.test(tabItem) && /label:\s*ResourceStr/.test(tabItem) && /count:\s*number/.test(tabItem), 'TabItem carries key + label + count')
ok(/selectedColor:\s*string/.test(tabItem) && /constructor\(key: string, label: ResourceStr, count: number = -1, selectedColor: string = ''\)/.test(tabItem),
  'TabItem carries an optional selectedColor for colored subtab surfaces')
ok(/import \{ TabItem \}/.test(subTabBar) && !/class SubTabItem/.test(subTabBar), 'SubTabBar uses the shared TabItem model (no local SubTabItem)')

// ── 3. Home + Toplist USE the shared host (no inline Swiper) ──────────────────────────────────────────
for (const [name, src, page] of [
  ['HomePage', homePage, 'GallerySourcePage'],
  ['ToplistPage', toplist, 'ToplistPeriodPage'],
]) {
  ok(/RetainedSubtabHost\(\{/.test(src), `${name} renders the shared RetainedSubtabHost`)
  ok(!/Swiper\(/.test(src), `${name} has NO inline Swiper (host mechanics are shared, not re-implemented)`)
  ok(new RegExp(`pageBuilder:\\s*\\w*[Pp]ageBuilder`).test(src), `${name} passes a GLOBAL @Builder pageBuilder`)
  ok(new RegExp(`@Builder\\s+function\\s+\\w*[Pp]ageBuilder[\\s\\S]*?${page}\\(`).test(src), `${name}'s page builder renders ${page} (global @Builder, no this)`)
  ok(/keys:/.test(src) && /selectedKey:/.test(src), `${name} feeds the host its keys + selected key (selection bus)`)
  ok(/onSelectKey:/.test(src) && /onVisualIndex:/.test(src) && /onScrollerReady:/.test(src), `${name} wires onSelectKey + onVisualIndex + onScrollerReady to the host`)
  ok(!/@Local\s+vm:\s*GalleryListViewModel/.test(src), `${name} owns NO shared content VM`)
}
ok(/setHomeActiveScroller\(0,/.test(indexShell) && /setHomeActiveScroller\(2,/.test(indexShell), 'Index wires Home + Toplist onScrollerReady → setHomeActiveScroller')

// ── 4. Per-key pages: own VM + scroller, lazy first-load, no visual-index consumption ────────────────
for (const [name, src, vm] of [
  ['GallerySourcePage', sourcePage, 'GalleryListViewModel'],
  ['ToplistPeriodPage', periodPage, 'GalleryListViewModel'],
  ['FavcatPage', favcatPage, 'FavoritesViewModel'],
]) {
  ok(new RegExp(`@Local\\s+vm:\\s*${vm}\\s*=\\s*new ${vm}\\(\\)`).test(src), `${name} owns its OWN @Local ${vm}`)
  ok(/@Param\s+scroller:\s*Scroller/.test(src), `${name} takes its own scroller`)
  // EXPLICIT first-activation trigger via the shared signal — NOT a per-render isActive @Param (which a
  // cached page never receives, so an unvisited subtab never loaded). The page watches active.activeKey.
  ok(/@Param\s+active:\s*ActiveKeyState/.test(src), `${name} receives the shared ActiveKeyState (not a per-render isActive)`)
  ok(/loadedOnce/.test(src) && /@Monitor\('active\.activeKey'\)/.test(src), `${name} lazy-loads once on first activation, triggered by active.activeKey`)
  ok(/this\.active\.activeKey\s*===/.test(src), `${name} is active when active.activeKey === its own key`)
  ok(!/@Param\s+isActive/.test(src), `${name} no longer uses the fragile @Param isActive`)
  ok(!/VisualIndex|visual\.value/.test(src), `${name} does NOT consume the visual index (bar-only)`)
}

// ── 5. Selection buses hold no datasource; visual-index buses are separate ───────────────────────────
ok(/@Trace\s+source:\s*string/.test(homeState) && /@Trace\s+toplistTl:\s*number/.test(homeState), 'HomeSourceState carries source + toplistTl selection keys')
ok(!/dataSource:|BasicDataSource|GalleryListViewModel/.test(homeState), 'HomeSourceState holds NO datasource/VM (selection bus only)')
ok(/@Trace\s+selectedFavcat:\s*string/.test(favState), 'FavSelectionState carries the selected favcat')
ok(!/dataSource:|BasicDataSource|new FavoritesViewModel/.test(favState), 'FavSelectionState holds NO datasource/VM field (selection bus only)')
ok(/class TabVisualIndexState/.test(homeState), 'a separate per-frame TabVisualIndexState holder exists')
ok(/connectHomeSourceVisualIndex/.test(homeState) && /connectToplistVisualIndex/.test(homeState) && /connectFavcatVisualIndex/.test(favState), 'per-surface visual-index connectors exist (source + period + favcat)')

// ── 6. Selector bars: one shared SubTabBar + visual-index; no hand-rolled underline ──────────────────
for (const [name, src, conn] of [
  ['HomeSourceBar', sourceBar, 'connectHomeSourceVisualIndex'],
  ['ToplistPeriodBar', periodBar, 'connectToplistVisualIndex'],
  ['FavcatBar', favcatBar, 'connectFavcatVisualIndex'],
]) {
  ok(/SubTabBar\(/.test(src), `${name} uses the shared SubTabBar`)
  ok(new RegExp(conn).test(src), `${name} drives the indicator from its visual-index bus`)
  ok(!/Color\.Transparent/.test(src) && !/\.position\(/.test(src), `${name} does not hand-roll a discrete/positioned underline`)
  ok(/new TabItem\(/.test(src), `${name} builds its tabs from the shared TabItem model`)
}

// ── 7. SubTabBar capability + compact vertical metrics (single source of truth, no canyon) ───────────
ok(/@Param\s+scrollable:\s*boolean/.test(subTabBar), 'SubTabBar supports a scrollable mode (favcat overflow)')
ok(/\.position\(/.test(subTabBar), 'SubTabBar positions ONE sliding indicator (interpolated), not per-tab underlines')
ok(/@Param\s+visualIndex:\s*number/.test(subTabBar), 'SubTabBar takes the interpolated visualIndex')
ok(/tabAccentColor\(i: number\): ResourceColor[\s\S]*this\.tabs\[i\]\.selectedColor[\s\S]*ThemeConstants\.BRAND_PRIMARY/.test(subTabBar) &&
  /this\.selectedIndex\(\) === index[\s\S]*this\.tabAccentColor\(index\)/.test(subTabBar),
  'SubTabBar selected text can use a per-tab accent color while uncolored surfaces keep brand primary')
ok(/\.fontWeight\(this\.selectedIndex\(\) === index \? FontWeight\.Bold : FontWeight\.Regular\)/.test(subTabBar),
  'SubTabBar selected text uses Bold weight for stronger contrast without changing favcat identity colors')
ok(/indicatorColor\(\): ResourceColor[\s\S]*this\.lerpHexColor\(fromColor, toColor, frac\)/.test(subTabBar) &&
  /\.backgroundColor\(this\.indicatorColor\(\)\)/.test(subTabBar),
  'SubTabBar indicator color interpolates between adjacent tab selectedColor values during swipe')
ok(/aboutToAppear\(\): void[\s\S]*this\.centerSelectedTab\(false,\s*true\)/.test(subTabBar),
  'SubTabBar re-centers the restored selected tab on attach, even when visualIndex did not change')
ok(/pendingCenterIndex/.test(subTabBar) && /pendingCenterSmooth/.test(subTabBar) &&
  /if \(this\.viewportWidth <= 0 \|\| wi <= 0\) \{[\s\S]*this\.pendingCenterIndex = i/.test(subTabBar),
  'SubTabBar defers restored-tab centering until tab width and viewport measurements are available')
ok(/onAreaChange\([\s\S]*this\.viewportWidth = newValue\.width as number[\s\S]*this\.centerSelectedTab\(false,\s*true\)/.test(subTabBar) &&
  /if \(this\.pendingCenterIndex === index\) \{[\s\S]*this\.centerTab\(index,\s*this\.pendingCenterSmooth\)/.test(subTabBar),
  'SubTabBar completes pending restored-tab centering from viewport and tab measurement callbacks')
// The tab ForEach key MUST include the label + count (not just the stable key): dynamic tabs (favcat reuse
// favId 0-9 across a seed→real update) would otherwise reuse frozen seed chips, leaving the bar on
// placeholder "Favorites N / 0" after the parsed favList lands.
ok(/tab\.label[\s\S]{0,40}?tab\.count/.test(subTabBar), 'SubTabBar ForEach key includes tab.label + tab.count so dynamic favcat tabs rebuild on seed→real (no frozen placeholders)')
const barH = Number((/SELECTOR_BAR_HEIGHT:\s*number\s*=\s*(\d+)/.exec(homeState) || [])[1])
ok(Number.isFinite(barH) && barH <= 40, `SELECTOR_BAR_HEIGHT is not inflated (<=40, matches V2Next TAB_BAR_HEIGHT 38); got ${barH}`)
ok(
  /private bottomBuilder\([\s\S]*content:\s*ComponentContent<Object>,[\s\S]*height:\s*number\s*=\s*SELECTOR_BAR_HEIGHT/.test(indexShell) &&
    /'height':\s*height/.test(indexShell) &&
    /this\.bottomBuilder\(this\.sourceBarContent\)/.test(indexShell) &&
    /this\.bottomBuilder\(this\.favcatBarContent\)/.test(indexShell) &&
    /this\.bottomBuilder\(this\.periodBarContent\)/.test(indexShell) &&
    /this\.bottomBuilder\([\s\S]*this\.downloadTypeBarContent,[\s\S]*DOWNLOAD_SELECTOR_BAR_HEIGHT,[\s\S]*\)/.test(indexShell),
  'Index retained-tab bottomBuilders default to SELECTOR_BAR_HEIGHT; download selector is the explicit non-retained exception',
)
ok(
  /topPadding:\s*SELECTOR_BAR_HEIGHT/.test(sourcePage) && /topPadding:\s*SELECTOR_BAR_HEIGHT/.test(periodPage) && /topPadding:\s*SELECTOR_BAR_HEIGHT/.test(favcatPage),
  'retained pages pass list topPadding = SELECTOR_BAR_HEIGHT (matches the bottomBuilder, no double/hardcoded padding)',
)
ok(/SELECTOR_BAR_HEIGHT\s*-\s*\d+/.test(subTabBar), 'SubTabBar indicator baseline derives from SELECTOR_BAR_HEIGHT (V2Next h-14)')

// ── 8. Loading policy (framework): first-load = content-area only; no top+center duplicate ───────────
for (const [name, src] of [['GalleryListBody', galleryListBody], ['FavcatPage', favcatPage]]) {
  // Content-area first-load, scoped to an empty body (itemCount===0) and shown while loading OR not-yet-
  // loaded — the never-loaded gate prevents a terminal empty/no-more flash before the first load lands.
  ok(
    /PageLoadingState\(\)/.test(src) && /this\.vm\.itemCount\s*===\s*0/.test(src) && /this\.vm\.isLoading/.test(src),
    `${name}: first-load loading is content-area, scoped to itemCount===0`,
  )
  ok(!/LoadingProgress\(\)[\s\S]*?PageLoadingState\(\)|PageLoadingState\(\)[\s\S]*?LoadingProgress\(\)/.test(src), `${name}: no top + center duplicate loading for one first-load`)
}

// ── 9. Favorites favcat MIGRATED onto the shared framework (split B) ─────────────────────────────────
ok(/RetainedSubtabHost\(\{/.test(favPage), 'FavoritesPage renders the shared RetainedSubtabHost (no inline Favorites Swiper)')
ok(!/Swiper\(/.test(favPage), 'FavoritesPage has NO inline Swiper (host mechanics are shared)')
ok(/pageBuilder:\s*favcatPageBuilder/.test(favPage), 'FavoritesPage passes a GLOBAL @Builder favcatPageBuilder')
ok(/@Builder\s+function\s+favcatPageBuilder[\s\S]*?FavcatPage\(/.test(favPage), 'favcatPageBuilder is a global @Builder rendering FavcatPage (no this)')
ok(/keys:\s*this\.favcatKeys\(\)/.test(favPage) && /selectedKey:\s*this\.effectiveSelectedFavcat\(\)/.test(favPage), 'FavoritesPage feeds the host favcat keys + an effective selected favcat (selection bus, logged-out local safe)')
ok(/onSelectKey:/.test(favPage) && /onVisualIndex:/.test(favPage) && /onScrollerReady:/.test(favPage), 'FavoritesPage wires onSelectKey + onVisualIndex + onScrollerReady to the host')
ok(!/@Local\s+vm:\s*FavoritesViewModel/.test(favPage), 'FavoritesPage owns NO shared FavoritesViewModel (data lives in FavcatPage)')
ok(/if \(!this\.auth\.isLogin\) \{[\s\S]*return \['l'\]/.test(favPage), 'FavoritesPage maps logged-out Favorites to the local slot instead of blocking the whole tab')
ok(/orderByPosted/.test(favPage) && /OrderMenu/.test(favPage), 'FavoritesPage preserves the global order toggle (writes the orderByPosted bus)')
// FavcatBar specifics: scrollable (many favcats overflow). It shows the synthetic all-favorites count
// as the remote 0-9 aggregate, while keeping per-slot counts out of the compact horizontal bar.
ok(/scrollable:\s*true/.test(favcatBar), 'FavcatBar uses the SubTabBar scrollable mode (favcat overflow)')
ok(/new TabItem\(fc\.favId,\s*fc\.favTitle,\s*-1,\s*EhConstants\.favCatColor\(fc\.favId\)\)/.test(favcatBar),
  'FavcatBar builds tabs from the REAL favcat names (fc.favTitle)')
ok(/EhConstants\.favCatColor\('a'\)/.test(favcatBar) &&
  /EhConstants\.favCatColor\(fc\.favId\)/.test(favcatBar) &&
  /EhConstants\.favCatColor\('l'\)/.test(favcatBar),
  'FavcatBar passes EH favcat identity colors into SubTabBar for selected text + indicator')
ok(/new TabItem\('a',\s*\$r\('app\.string\.favorites_all'\),\s*this\.fav\.remoteTotalCount\(\),\s*EhConstants\.favCatColor\('a'\)\)/.test(favcatBar),
  'FavcatBar shows the synthetic all-favorites aggregate count')
ok(!/new TabItem\(fc\.favId,\s*fc\.favTitle,\s*fc\.totNum\)/.test(favcatBar),
  'FavcatBar keeps per-slot counts out of the compact horizontal bar')
// The parsed counts are still kept in state (not dropped) — FavSelectionState carries the favList with totals.
ok(/@Trace\s+favList:\s*Favcat\[\]/.test(favState), 'parsed favList counts are retained in FavSelectionState (data kept; only the bar presentation hides them)')
// SubTabBar keeps the GENERIC optional count for future surfaces (favcat just doesn't use it).
ok(/if \(tab\.count >= 0\)/.test(subTabBar), 'SubTabBar still supports an optional per-tab count (generic; future surfaces may use it)')
// Index hands the active favcat scroller up too (title-scroller handoff for Favorites).
ok(/setHomeActiveScroller\(1,/.test(indexShell), 'Index wires FavoritesPage.onScrollerReady → setHomeActiveScroller(1, …)')

if (failures === 0) {
  console.log('✓ retained-subtab framework (A+B): shared RetainedSubtabHost + TabItem; Home + Toplist + Favorites all migrated onto it; per-key page/VM/scroller, selection + visual-index buses, shared SubTabBar, compact metrics, content-area loading policy')
  process.exit(0)
}
console.error(`✗ retained-subtab framework contract: ${failures} failure(s)`)
process.exit(1)

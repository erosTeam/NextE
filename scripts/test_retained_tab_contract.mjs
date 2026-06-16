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
// NOTE: the Favorites surface (FavcatPage/FavoritesPage/FavcatBar) migrates onto this framework in
// SPLIT B; its assertions live in split B's contract extension. Split A asserts only the shared
// framework primitives + the Home/Toplist migration that proves them.

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

// ── 2. Generic TabItem/key model ─────────────────────────────────────────────────────────────────────
ok(/export class TabItem/.test(tabItem), 'a generic TabItem model exists (key + label + count)')
ok(/key:\s*string/.test(tabItem) && /label:\s*ResourceStr/.test(tabItem) && /count:\s*number/.test(tabItem), 'TabItem carries key + label + count')
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
]) {
  ok(new RegExp(`@Local\\s+vm:\\s*${vm}\\s*=\\s*new ${vm}\\(\\)`).test(src), `${name} owns its OWN @Local ${vm}`)
  ok(/@Param\s+scroller:\s*Scroller/.test(src), `${name} takes its own scroller`)
  ok(/loadedOnce/.test(src) && /@Monitor\('isActive'\)/.test(src), `${name} lazy-loads once on first activation`)
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
const barH = Number((/SELECTOR_BAR_HEIGHT:\s*number\s*=\s*(\d+)/.exec(homeState) || [])[1])
ok(Number.isFinite(barH) && barH <= 40, `SELECTOR_BAR_HEIGHT is not inflated (<=40, matches V2Next TAB_BAR_HEIGHT 38); got ${barH}`)
ok(/'height':\s*SELECTOR_BAR_HEIGHT/.test(indexShell), 'Index bottomBuilder height = SELECTOR_BAR_HEIGHT (single source of truth)')
ok(
  /topPadding:\s*SELECTOR_BAR_HEIGHT/.test(sourcePage) && /topPadding:\s*SELECTOR_BAR_HEIGHT/.test(periodPage),
  'retained pages pass list topPadding = SELECTOR_BAR_HEIGHT (matches the bottomBuilder, no double/hardcoded padding)',
)
ok(/SELECTOR_BAR_HEIGHT\s*-\s*\d+/.test(subTabBar), 'SubTabBar indicator baseline derives from SELECTOR_BAR_HEIGHT (V2Next h-14)')

// ── 8. Loading policy (framework primitive): first-load = content-area only; no top+center duplicate.
// (FavcatPage's loading is asserted by split B; here the framework body GalleryListBody locks the policy.)
ok(/isLoading\s*&&\s*this\.vm\.itemCount\s*===\s*0/.test(galleryListBody), 'GalleryListBody: first-load loading is content-area, gated on isLoading && itemCount===0')
ok(!/LoadingProgress\(\)[\s\S]*?PageLoadingState\(\)|PageLoadingState\(\)[\s\S]*?LoadingProgress\(\)/.test(galleryListBody), 'GalleryListBody: no top + center duplicate loading for one first-load')

// Favorites favcat migration onto this framework (host + bar + loading) is asserted in SPLIT B.

if (failures === 0) {
  console.log('✓ retained-subtab framework (split A): shared RetainedSubtabHost + TabItem; Home + Toplist migrated onto it; per-key page/VM/scroller, selection + visual-index buses, shared SubTabBar, compact metrics, content-area loading policy (Favorites migration → split B)')
  process.exit(0)
}
console.error(`✗ retained-subtab framework contract: ${failures} failure(s)`)
process.exit(1)

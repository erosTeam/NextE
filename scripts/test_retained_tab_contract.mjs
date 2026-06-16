#!/usr/bin/env node
/**
 * Contract for the retained-tab architecture (tab-list-state-architecture-gate.md, Option A).
 *
 * The user found that the gallery "sub tabs" reloaded one shared middle list instead of switching to
 * independent retained tabs. Product ruling (Option A+): ANY surface NextE presents as a subtab must
 * provide subtab state — Home SOURCE, Toplist PERIOD, and (a later commit) Favorites FAVCAT each become a
 * retained sub-tab with its OWN page + ViewModel + scroller, kept alive by a Swiper; the selector STATE is
 * a pure selection BUS, never the datasource holder. No tab-presented surface may share one VM and call
 * setData(new) on switch (that is the filter/reload model the user rejected).
 *
 * This locks the architecture so it can't silently regress to one-shared-VM-reload:
 *   - HomePage = Swiper over per-source GallerySourcePage keyed by source key (retained), NOT one shared
 *     GalleryListViewModel + GalleryListBody. GallerySourcePage owns its OWN @Local GalleryListViewModel
 *     + per-page scroller (the data lives here). HomeSourceState is a selection bus only.
 *   - ToplistPage = Swiper over per-period ToplistPeriodPage (each owns its OWN @Local GalleryListViewModel
 *     + scroller); the old single-VM setToplistPeriod->reload filter model is retired. HomeSourceState
 *     .toplistTl is the period selection bus.
 *   - Index reports each active sub-tab scroller up (onScrollerReady chain) for title auto-hide.
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

const homePage = read('feature/home/src/main/ets/pages/HomePage.ets')
const sourcePage = read('feature/home/src/main/ets/components/GallerySourcePage.ets')
const homeState = read('shared/src/main/ets/state/HomeSourceState.ets')
const toplist = read('feature/home/src/main/ets/pages/ToplistPage.ets')
const periodPage = read('feature/home/src/main/ets/components/ToplistPeriodPage.ets')
const subTabBar = read('shared/src/main/ets/components/SubTabBar.ets')
const sourceBar = read('entry/src/main/ets/components/HomeSourceBar.ets')
const periodBar = read('entry/src/main/ets/components/ToplistPeriodBar.ets')
const indexShell = read('entry/src/main/ets/pages/Index.ets')

// ── Home source = retained per-source sub-tabs ──────────────────────────────────────────────────────
// 1) HomePage is a Swiper over per-source pages keyed by source key — not one shared list body.
ok(/Swiper\(this\.swiperController\)/.test(homePage), 'HomePage hosts a Swiper (retained sub-tab container)')
ok(/ForEach\([\s\S]*?GallerySourcePage\(/.test(homePage), 'HomePage renders a GallerySourcePage per source via ForEach')
ok(/\(key: string\) => key,/.test(homePage), 'the source ForEach is KEYED by source key (retains instances across login changes)')
ok(/\.cachedCount\(this\.visibleSources\(\)\.length\)/.test(homePage), 'Swiper retains ALL visible sources (cachedCount = source count) → away/back keeps list + scroll')
// HomePage must NOT itself own the single shared list VM anymore (the data moved into the per-source pages).
ok(!/@Local\s+vm:\s*GalleryListViewModel/.test(homePage), 'HomePage no longer owns one shared GalleryListViewModel')
ok(!/GalleryListBody\(/.test(homePage), 'HomePage no longer renders one shared GalleryListBody directly')

// 2) GallerySourcePage owns its own VM + scroller (per-source data + scroll live here).
ok(/@ComponentV2/.test(sourcePage), 'GallerySourcePage is @ComponentV2')
ok(/@Local\s+vm:\s*GalleryListViewModel\s*=\s*new GalleryListViewModel\(\)/.test(sourcePage), 'GallerySourcePage owns its OWN @Local GalleryListViewModel')
ok(/@Param\s+sourceKey:\s*string/.test(sourcePage), 'GallerySourcePage is keyed by @Param sourceKey')
ok(/@Param\s+scroller:\s*Scroller/.test(sourcePage), 'GallerySourcePage takes its own per-source scroller')
ok(/GalleryListBody\(\{\s*vm:\s*this\.vm/.test(sourcePage), 'GallerySourcePage renders the shared GalleryListBody with its own vm')

// 3) HomeSourceState is a pure SELECTION BUS — it must hold no datasource.
ok(/@Trace\s+source:\s*string/.test(homeState), 'HomeSourceState carries the selected source key (@Trace source)')
ok(!/dataSource|BasicDataSource|GalleryListViewModel|EhGallery\[\]/.test(homeState), 'HomeSourceState holds NO datasource/VM — it is a selection bus only')

// 4) Index reports the active source scroller up (onScrollerReady chain) for title auto-hide.
ok(/onScrollerReady:\s*\(scroller: Scroller\)\s*=>/.test(indexShell), 'Index wires HomePage.onScrollerReady (active source scroller reported up)')
ok(/setHomeActiveScroller\(/.test(indexShell), 'Index has setHomeActiveScroller to repoint the title binding to the active sub-tab scroller')
ok(/@Event\s+onScrollerReady\?/.test(homePage), 'HomePage emits onScrollerReady up to Index')

// ── Toplist period = retained per-period sub-tabs (A+ correction) ───────────────────────────────────
// User product ruling: NextE PRESENTS the period as a subtab, so it owes subtab semantics — NOT a filter.
// A tab-presented surface must never share one VM and setData(new) on switch.
ok(/Swiper\(this\.swiperController\)/.test(toplist), 'ToplistPage hosts a Swiper (retained per-period sub-tabs)')
ok(/ForEach\([\s\S]*?ToplistPeriodPage\(/.test(toplist), 'ToplistPage renders a ToplistPeriodPage per period via ForEach')
ok(/\.cachedCount\(TOPLIST_PERIODS\.length\)/.test(toplist), 'Swiper retains ALL periods (cachedCount = period count) → away/back keeps list + scroll')
ok(!/@Local\s+vm:\s*GalleryListViewModel/.test(toplist), 'ToplistPage no longer owns one shared GalleryListViewModel')
ok(!/setToplistPeriod\(/.test(toplist), 'ToplistPage no longer reloads one shared list via setToplistPeriod (filter model retired)')
// ToplistPeriodPage owns its own VM + scroller (per-period data + scroll live here).
ok(/@ComponentV2/.test(periodPage), 'ToplistPeriodPage is @ComponentV2')
ok(/@Local\s+vm:\s*GalleryListViewModel\s*=\s*new GalleryListViewModel\(\)/.test(periodPage), 'ToplistPeriodPage owns its OWN @Local GalleryListViewModel')
ok(/@Param\s+periodTl:\s*number/.test(periodPage), 'ToplistPeriodPage is keyed by @Param periodTl')
ok(/@Param\s+scroller:\s*Scroller/.test(periodPage), 'ToplistPeriodPage takes its own per-period scroller')
// HomeSourceState.toplistTl is the period selection bus (already asserted bus-only above for source).
ok(/@Trace\s+toplistTl:\s*number/.test(homeState), 'HomeSourceState carries the selected period (@Trace toplistTl) as a bus')
// Index reports the active period scroller up too.
ok(/setHomeActiveScroller\(2,/.test(indexShell), 'Index wires ToplistPage.onScrollerReady → setHomeActiveScroller(2, …)')
ok(/@Event\s+onScrollerReady\?/.test(toplist), 'ToplistPage emits onScrollerReady up to Index')

// ── V2Next visual-index SYNC: the selector bar indicator must track the finger/page swipe ───────────
// User: the pill/subtab animation must be synchronized with the Swiper transition. The retained-tab
// Swiper must publish an interpolated visual index from onGestureSwipe + onAnimationStart + onAnimationEnd
// (not just flip the selected key in onChange after the page settles), and the selector bar must consume
// that visual index for its sliding indicator (V2Next FeedVisualIndexState / FeedPills).

// 1) A per-frame visual-index bus exists, SEPARATE from the semantic selection key.
ok(/class TabVisualIndexState/.test(homeState), 'a per-frame TabVisualIndexState holder exists (separate from the selection key)')
ok(/connectHomeSourceVisualIndex/.test(homeState) && /connectToplistVisualIndex/.test(homeState), 'per-surface visual-index connectors exist (home source + toplist period)')

// 2) The shared interpolated-indicator bar consumes a float visual index and positions a sliding indicator.
ok(/@Param\s+visualIndex:\s*number/.test(subTabBar), 'SubTabBar takes an interpolated @Param visualIndex')
ok(/\.position\(/.test(subTabBar), 'SubTabBar positions a single sliding indicator (interpolated), not a per-tab discrete underline')
ok(/onAreaChange/.test(subTabBar), 'SubTabBar measures tab geometry (onAreaChange) so the indicator tracks real tab centers')

// 3) Each retained Swiper publishes the visual index from gesture + animation, not just onChange.
for (const [name, src, connector] of [
  ['HomePage', homePage, 'connectHomeSourceVisualIndex'],
  ['ToplistPage', toplist, 'connectToplistVisualIndex'],
]) {
  ok(new RegExp(connector).test(src), `${name} connects its visual-index bus (${connector})`)
  ok(/\.onGestureSwipe\(/.test(src), `${name} Swiper publishes visual index on .onGestureSwipe (tracks the finger)`)
  ok(/\.onAnimationStart\(/.test(src), `${name} Swiper publishes visual index on .onAnimationStart (tracks the fling)`)
  ok(/\.onAnimationEnd\(/.test(src), `${name} Swiper settles the visual index on .onAnimationEnd`)
}

// 4) Each selector bar consumes the visual index (drives the indicator), not just `key === selected`.
ok(/connectHomeSourceVisualIndex/.test(sourceBar) && /SubTabBar\(/.test(sourceBar), 'HomeSourceBar drives a SubTabBar from the visual-index bus (synced indicator)')
ok(/connectToplistVisualIndex/.test(periodBar) && /SubTabBar\(/.test(periodBar), 'ToplistPeriodBar drives a SubTabBar from the visual-index bus (synced indicator)')

if (failures === 0) {
  console.log('✓ retained-tab contract: Home source + Toplist period are retained per-key sub-tabs (own VM/scroller, bus state) with V2Next visual-index-synced indicators')
  process.exit(0)
}
console.error(`✗ retained-tab contract: ${failures} failure(s)`)
process.exit(1)

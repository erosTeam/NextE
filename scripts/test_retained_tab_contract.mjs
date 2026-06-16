#!/usr/bin/env node
/**
 * Contract for the retained-tab architecture (tab-list-state-architecture-gate.md, Option A).
 *
 * The user found that the gallery "sub tabs" reloaded one shared middle list instead of switching to
 * independent retained tabs. The fix (V2Next FeedListPage/Swiper pattern): each Home SOURCE (and, in a
 * later commit, each Favorites FAVCAT) is a retained sub-tab with its OWN page + ViewModel + scroller,
 * kept alive by a Swiper; the selector STATE is a pure selection BUS, never the datasource holder. The
 * Toplist PERIOD intentionally stays a single-list filter (eros_fe ToplistTab reloads one list).
 *
 * This locks the architecture so it can't silently regress to one-shared-VM-reload:
 *   - HomePage = Swiper over per-source GallerySourcePage keyed by source key (retained), NOT one shared
 *     GalleryListViewModel + GalleryListBody.
 *   - GallerySourcePage owns its OWN @Local GalleryListViewModel + per-page scroller (the data lives here).
 *   - HomeSourceState is a selection bus only (no datasource / BasicDataSource field).
 *   - Index reports the active source's scroller up (onScrollerReady chain) for title auto-hide.
 *   - ToplistPage stays a single GalleryListViewModel with setToplistPeriod -> reload (a filter, NOT a
 *     Swiper of per-period pages).
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

// ── Toplist period stays a single-list FILTER (must NOT become per-period sub-tabs) ─────────────────
ok(/@Local\s+vm:\s*GalleryListViewModel\s*=\s*new GalleryListViewModel\(\)/.test(toplist), 'ToplistPage keeps ONE GalleryListViewModel (single-list filter)')
ok(/setToplistPeriod\(/.test(toplist), 'ToplistPage switches period via setToplistPeriod -> reload (a filter)')
ok(!/Swiper\(/.test(toplist), 'ToplistPage is NOT a Swiper of per-period pages (period stays a filter, per eros_fe)')

if (failures === 0) {
  console.log('✓ retained-tab contract: Home sources are retained per-key sub-tabs (own VM/scroller, bus state); Toplist stays a single-list filter')
  process.exit(0)
}
console.error(`✗ retained-tab contract: ${failures} failure(s)`)
process.exit(1)

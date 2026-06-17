#!/usr/bin/env node
/**
 * Contract: gallery sub-tab / selector / filter reloads must not clear current content before the
 * replacement page arrives. A clear-before-fetch causes the observed white-screen remount: the page
 * branches on `isLoading && itemCount === 0` and shows PageLoadingState.
 *
 * Run: node scripts/test_selector_reload_preserves_content_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
let failures = 0

function text(rel) {
  return readFileSync(join(ROOT, rel), 'utf8')
}

function methodBody(src, methodName) {
  const marker = new RegExp(`^\\s*(?:async\\s+)?${methodName}\\s*\\([^)]*\\)\\s*:?[^\\{]*\\{`, 'm')
  const m = marker.exec(src)
  if (!m) throw new Error(`method not found: ${methodName}`)
  let i = m.index + m[0].length
  let depth = 1
  while (i < src.length && depth > 0) {
    const ch = src[i]
    if (ch === '{') depth++
    else if (ch === '}') depth--
    i++
  }
  return src.slice(m.index, i)
}

function check(cond, msg) {
  if (!cond) {
    failures++
    console.error(`✗ ${msg}`)
  }
}

function forbidClearBeforeFetch(rel, methodName, fetchToken) {
  const body = methodBody(text(rel), methodName)
  const fetchAt = body.indexOf(fetchToken)
  check(fetchAt >= 0, `${rel} ${methodName} must contain ${fetchToken}`)
  const preFetch = fetchAt >= 0 ? body.slice(0, fetchAt) : body
  check(!/\.setData\s*\(\s*\[\s*\]\s*\)/.test(preFetch), `${rel} ${methodName} clears dataSource before fetching`)
  check(!/\bitemCount\s*=\s*0\b/.test(preFetch), `${rel} ${methodName} zeros itemCount before fetching`)
}

function forbidAnyClear(rel, methodName) {
  const body = methodBody(text(rel), methodName)
  check(!/\.setData\s*\(\s*\[\s*\]\s*\)/.test(body), `${rel} ${methodName} clears dataSource`)
  check(!/\bitemCount\s*=\s*0\b/.test(body), `${rel} ${methodName} zeros itemCount`)
}

// Home source / toplist period / site reload: keep stale rows until getGalleryList returns.
forbidClearBeforeFetch(
  'feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets',
  'reload',
  'getGalleryList',
)

// Favorites favcat/order selectors delegate to load(); the selector methods themselves must not blank.
forbidAnyClear('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets', 'toggleOrder')
forbidAnyClear('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets', 'selectFavcat')
forbidClearBeforeFetch(
  'feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets',
  'load',
  'getFavoritesList',
)

// Search submit / filter reapply: keep previous result body until the new query returns.
forbidClearBeforeFetch(
  'feature/search/src/main/ets/viewmodel/SearchViewModel.ets',
  'search',
  'fetchPage',
)

// UI loading branch shows only for an empty body (itemCount === 0) so selector reloads with existing
// rows don't unmount content — the first-load affordance without the white-screen remount.
for (const [rel, component] of [
  ['feature/home/src/main/ets/components/GalleryListBody.ets', 'GalleryListBody'],
  ['feature/user/src/main/ets/components/FavcatPage.ets', 'FavcatPage'],
  ['feature/search/src/main/ets/pages/GallerySearchPage.ets', 'GallerySearchPage'],
]) {
  const src = text(rel)
  check(
    /PageLoadingState\(\)/.test(src) && /itemCount\s*===\s*0/.test(src),
    `${component} must scope PageLoadingState to an empty body (itemCount === 0)`,
  )
}

// A sub-tab SWITCH must not flash terminal empty/no-more copy before its first load. The loading branch
// is gated on "never loaded yet" (not just the transient isLoading, which leaves a mounted-but-not-yet-
// loading frame that used to render CardEmptyState / an empty scaffold), and the paging footer counts a
// page-level load too so a reload that forces hasMore=false up front can't strand a "没有更多了" footer.
for (const [rel, component, neverLoadedToken] of [
  ['feature/home/src/main/ets/components/GalleryListBody.ets', 'GalleryListBody', '!this.vm.loaded'],
  ['feature/user/src/main/ets/components/FavcatPage.ets', 'FavcatPage', '!this.loadedOnce'],
]) {
  const src = text(rel)
  check(
    src.includes(neverLoadedToken),
    `${component} loading branch must render for a never-loaded key (gate on \`${neverLoadedToken}\`, not just isLoading)`,
  )
  check(
    /isLoading:\s*this\.vm\.isLoadingMore\s*\|\|\s*this\.vm\.isLoading/.test(src),
    `${component} paging footer must count the page-level isLoading (no stranded "no more" during a reload)`,
  )
}

{
  const src = text('feature/search/src/main/ets/pages/GallerySearchPage.ets')
  check(
    /isLoading:\s*this\.vm\.isLoadingMore\s*\|\|\s*this\.vm\.isLoading/.test(src),
    'GallerySearchPage paging footer must count page-level search/filter loading (no stranded "no more" during a reload)',
  )
}

// The home/toplist ViewModel carries the loaded flag and flips it once the first load AND a reload finish.
{
  const vm = text('feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets')
  check(/@Trace\s+loaded:\s*boolean\s*=\s*false/.test(vm), 'GalleryListViewModel declares @Trace loaded (default false)')
  check((vm.match(/this\.loaded\s*=\s*true/g) || []).length >= 2, 'GalleryListViewModel sets loaded=true after both loadData and reload')
}

if (failures === 0) {
  console.log('✓ selector reload contract: selector/filter reloads preserve current content until replacement data arrives')
  process.exit(0)
}
console.error(`✗ selector reload contract: ${failures} failure(s)`)
process.exit(1)

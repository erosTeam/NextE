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

// UI branches may show a loading page only for true initial load (itemCount === 0). This keeps the
// first-load affordance while preventing selector reloads with existing rows from unmounting content.
for (const [rel, component] of [
  ['feature/home/src/main/ets/components/GalleryListBody.ets', 'GalleryListBody'],
  // The favorites list body (loading branch) now lives in the retained per-favcat FavcatPage; switching
  // favcat swipes to a retained page (no reload at all), and within a favcat the loading affordance still
  // scopes to itemCount === 0 initial load.
  ['feature/user/src/main/ets/components/FavcatPage.ets', 'FavcatPage'],
  ['feature/search/src/main/ets/pages/GallerySearchPage.ets', 'GallerySearchPage'],
]) {
  const src = text(rel)
  check(
    /isLoading\s*&&\s*this\.vm\.itemCount\s*===\s*0/.test(src) ||
      /this\.vm\.isLoading\s*&&\s*this\.vm\.itemCount\s*===\s*0/.test(src),
    `${component} must scope PageLoadingState to itemCount === 0 initial-load only`,
  )
}

if (failures === 0) {
  console.log('✓ selector reload contract: selector/filter reloads preserve current content until replacement data arrives')
  process.exit(0)
}
console.error(`✗ selector reload contract: ${failures} failure(s)`)
process.exit(1)

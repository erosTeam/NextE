#!/usr/bin/env node
/**
 * Contract test for favorites search (eros_fe favorites f_search, scoped to the current favcat).
 *
 * `buildFavUrl` is copy-equal to EhApiService.getFavoritesList's URL assembly (favcat + f_search +
 * inline_set order + next cursor). It locks that a favorites search reuses favorites.php with
 * f_search alongside the selected favcat — NOT a separate endpoint, and WITHOUT eros_fe's commented-
 * out sn/st/sf scope toggles. Structural greps lock the current architecture: Favorites title action
 * pushes the one shared Search page in favorite scope; GallerySearchPage seeds SearchViewModel favorite
 * scope and uses favorites.php f_search.
 *
 * Run: node scripts/test_favorites_search_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const EH = 'https://e-hentai.org'
const EX = 'https://exhentai.org'
const baseUrl = (isEx) => (isEx ? EX : EH)

// Mirror of fetchFavoritesBody's URL builder. inlineSet is the sort order (fs_f|fs_p) on the first
// fetch, or 'dm_l' on the thumbnail-mode retry. Defaults to q.order to keep the existing assertions.
function buildFavUrl(q, inlineSet) {
  const set = inlineSet === undefined ? q.order : inlineSet
  const base = baseUrl(q.isEx)
  const params = []
  if (q.favcat.length > 0 && q.favcat !== 'a') params.push(`favcat=${q.favcat}`)
  if (q.search.length > 0) params.push(`f_search=${encodeURIComponent(q.search)}`)
  if (set.length > 0) params.push(`inline_set=${set}`)
  if (q.next.length > 0) params.push(`next=${q.next}`)
  const queryStr = params.length > 0 ? `?${params.join('&')}` : ''
  return `${base}/favorites.php${queryStr}`
}
// Mirror of the dm_l retry guard: a thumbnail-mode page (itg gld div, no itg table) needs the retry.
const needsDmLRetry = (body) => body.indexOf('<table class="itg') < 0 && body.indexOf('class="itg gld') >= 0
const q = (over) => ({ isEx: false, favcat: 'a', next: '', search: '', order: '', ...over })

let failures = 0
const eq = (got, want, label) => { if (got !== want) { console.error(`✗ ${label}\n    got:  ${got}\n    want: ${want}`); failures++ } }
const ok = (cond, label) => { if (!cond) { console.error(`✗ ${label}`); failures++ } }

// All-favcat search: f_search only (favcat 'a' is omitted).
eq(buildFavUrl(q({ search: 'naruto' })), 'https://e-hentai.org/favorites.php?f_search=naruto', 'fav all + search')
// Scoped to a favcat: favcat + f_search together (search is WITHIN the selected slot).
eq(buildFavUrl(q({ favcat: '3', search: 'big breasts' })), 'https://e-hentai.org/favorites.php?favcat=3&f_search=big%20breasts', 'fav slot + search')
// Search + order + cursor all combine.
eq(buildFavUrl(q({ favcat: '0', search: 'x', order: 'fs_p', next: '999' })), 'https://e-hentai.org/favorites.php?favcat=0&f_search=x&inline_set=fs_p&next=999', 'fav search + order + next')
// Empty search → no f_search param (clearing restores the full list).
eq(buildFavUrl(q({ favcat: '3' })), 'https://e-hentai.org/favorites.php?favcat=3', 'fav no search')
// EX host honored.
eq(buildFavUrl(q({ isEx: true, search: 'q' })), 'https://exhentai.org/favorites.php?f_search=q', 'fav ex host + search')

// dm_l retry: the second fetch forces inline_set=dm_l (Minimal list mode) preserving favcat/search/next.
eq(buildFavUrl(q({ favcat: '3', search: 'x', next: '9' }), 'dm_l'), 'https://e-hentai.org/favorites.php?favcat=3&f_search=x&inline_set=dm_l&next=9', 'dm_l retry url preserves favcat/search/next')
// Retry guard: only a thumbnail-mode page (itg gld div, no itg table) triggers the retry.
ok(needsDmLRetry('<div class="itg gld"><div class="gl1t">...</div></div>') === true, 'thumbnail layout → retry')
ok(needsDmLRetry('<table class="itg gltc"><tr>...</tr></table>') === false, 'table layout → no retry')
ok(needsDmLRetry('<table class="itg gltm"><tr>...</tr></table>') === false, 'extended-table layout → no retry')
// A genuinely empty favcat (no itg markup at all) must NOT retry forever.
ok(needsDmLRetry('<div class="itg"></div>') === false, 'no thumbnail div → no retry (genuinely empty)')

// Structural wiring
const read = (f) => readFileSync(join(ROOT, f), 'utf8')
const SEARCH_VM = read('feature/search/src/main/ets/viewmodel/SearchViewModel.ets')
const SEARCH_PAGE = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
const PARAMS = read('shared/src/main/ets/state/SearchPageParams.ets')
const INDEX = read('entry/src/main/ets/pages/Index.ets')
const FAV_PAGE = read('feature/user/src/main/ets/pages/FavoritesPage.ets')
ok(PARAMS.includes("searchType: string = ''") && PARAMS.includes("favcat: string = 'a'"), 'SearchPageParams carries favorite scope + favcat')
ok(/private openFavoriteSearch\(\): void \{[\s\S]*connectFavSelection\(\)\.selectedFavcat[\s\S]*pushPathByName\('Search', new SearchPageParams\('favorite', favcat\)\)/.test(INDEX),
  'Index favorites search pushes shared Search page in favorite scope')
ok(/private favoritesMenu\(\): Record<string, Object> \{[\s\S]*sys\.symbol\.magnifyingglass[\s\S]*this\.openFavoriteSearch\(\)/.test(INDEX),
  'Favorites title-bar has native search action')
ok(!FAV_PAGE.includes('AppSearchField') && !FAV_PAGE.includes('setSearch('),
  'FavoritesPage does not embed a bespoke search field')
ok(/seedFavoriteScope\(favcat: string\): void \{[\s\S]*this\.isFavoriteScope = true[\s\S]*this\.favcat = favcat/.test(SEARCH_VM),
  'SearchViewModel can be seeded into favorite scope')
ok(/private buildFavQuery\(next: string\): FavoritesQuery \{[\s\S]*favcat: this\.isFavoriteScope \? this\.favcat : 'a'[\s\S]*search: this\.query/.test(SEARCH_VM),
  'SearchViewModel favorites query sends current query as f_search')
ok(/private effectiveFavoriteScope\(\): boolean \{[\s\S]*SEARCH_SCOPE_FAVORITE/.test(SEARCH_VM),
  'SearchViewModel also honors filter-sheet Favorite scope')
ok(/context\.pathInfo\.param instanceof SearchPageParams[\s\S]*p\.searchType === 'favorite'[\s\S]*this\.vm\.seedFavoriteScope\(p\.favcat\)[\s\S]*this\.vm\.search\(''\)/.test(SEARCH_PAGE),
  'GallerySearchPage consumes favorite route params and browses the favcat')
ok(/private runQuery\(query: string\): void \{[\s\S]*this\.vm\.search\(trimmed\)/.test(SEARCH_PAGE),
  'GallerySearchPage submit path reuses the same SearchViewModel search')
// dm_l thumbnail-mode retry wiring in EhApiService.
const API = read('shared/src/main/ets/network/EhApiService.ets')
ok(API.includes('private async fetchFavoritesBody('), 'API: fetchFavoritesBody helper')
ok(API.includes("body.indexOf('<table class=\"itg') < 0 && body.indexOf('class=\"itg gld') >= 0"), 'API: dm_l retry guard (no table + thumbnail div)')
ok(API.includes('EhConstants.FAV_DISPLAY_LIST'), 'API: retry forces dm_l (FAV_DISPLAY_LIST)')
const CONST = read('shared/src/main/ets/constants/EhConstants.ets')
ok(CONST.includes("FAV_DISPLAY_LIST: string = 'dm_l'"), 'EhConstants: FAV_DISPLAY_LIST = dm_l')

if (failures > 0) { console.error(`\n✗ favorites search contract: ${failures} failure(s)`); process.exit(1) }
console.log('✓ favorites search contract: favcat-scoped f_search URL + dm_l retry + shared Search favorite-scope locked')

#!/usr/bin/env node
/**
 * Contract for Favorites deep-page loading.
 *
 * Grounding:
 * - eros_fe/lib/network/request.dart applies favorites ListDisplayModeException/FavOrderException
 *   handling inside the shared request path, so first page and later pages get the same guards.
 * - eros_fe/lib/pages/tab/controller/favorite/favorite_sublist_controller.dart continues loading from
 *   the server next cursor because Flutter rows are index-keyed.
 * - NextE adapts that to gid-keyed LazyForEach: a partially-overlapped page still appends fresh rows,
 *   but an all-duplicate page is terminal so the list cannot spin on "load more" with no visible rows.
 *
 * Run: node scripts/test_favorites_loadmore_order_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const vm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
const api = read('shared/src/main/ets/network/EhApiService.ets')
const feRequest = read('../eros_fe/lib/network/request.dart')
const feFavSub = read('../eros_fe/lib/pages/tab/controller/favorite/favorite_sublist_controller.dart')

let passed = 0
const ok = (label, cond) => {
  assert.ok(cond, label)
  passed++
}

ok('FE favorites fetch handles list display mode on shared request path',
  /httpResponse\.error is ListDisplayModeException[\s\S]*_params\['inline_set'\] = 'dm_l'/.test(feRequest))
ok('FE favorites fetch handles order correction on shared request path',
  /httpResponse\.error is FavOrderException[\s\S]*_params\['inline_set'\] = _order/.test(feRequest))
ok('FE favorite subpage keeps loading while next cursor exists',
  /next\.isNotEmpty[\s\S]*await loadDataMore\(\)/.test(feFavSub))

ok('EhApiService keeps dm_l retry centralized in getFavoritesList',
  /async getFavoritesList\(query: FavoritesQuery\): Promise<GalleryList> \{[\s\S]*EhConstants\.FAV_DISPLAY_LIST/.test(api))

ok('FavoritesViewModel defines shared page fetch helper',
  /private async fetchPageWithOrderSync\(next: string\): Promise<GalleryList>/.test(vm))
ok('Shared helper fetches FavoritesQuery for the requested cursor',
  /fetchPageWithOrderSync\(next: string\)[\s\S]*getFavoritesList\(this\.buildQuery\(next\)\)/.test(vm))
ok('Shared helper retries the same cursor when returned favOrder lags',
  /if \(list\.favOrder\.length > 0 && list\.favOrder !== this\.favOrder\) \{[\s\S]*getFavoritesList\(this\.buildQuery\(next\)\)/.test(vm))
ok('Initial load uses the same order-sync helper',
  /const list: GalleryList = await this\.fetchPageWithOrderSync\(''\)/.test(vm))
ok('loadMore captures the current cursor before fetching',
  /const cursor: string = this\.nextGid[\s\S]*const list: GalleryList = await this\.fetchPageWithOrderSync\(cursor\)/.test(vm))
ok('loadMore dedupes before append for gid-keyed LazyForEach',
  /const fresh: EhGallery\[\] = this\.dedupeNew\(list\.gallerys\)/.test(vm))
ok('loadMore stops when a page brings no genuinely fresh rows',
  /this\.hasMore = list\.nextGid\.length > 0 && fresh\.length > 0/.test(vm))
ok('loadMore no longer keeps paging solely because the cursor changed',
  !/this\.hasMore = list\.nextGid\.length > 0 && list\.nextGid !== cursor/.test(vm))

console.log(`✓ favorites load-more order contract: ${passed} assertions passed`)

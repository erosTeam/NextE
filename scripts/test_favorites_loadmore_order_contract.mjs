#!/usr/bin/env node
/**
 * Contract for Favorites deep-page loading.
 *
 * Grounding:
 * - eros_fe/lib/network/request.dart applies favorites ListDisplayModeException/FavOrderException
 *   handling inside the shared request path, so first page and later pages get the same guards.
 * - eros_fe/lib/pages/tab/controller/favorite/favorite_sublist_controller.dart loads favorites with
 *   nextPage + last row gid when ptt page numbers are available, falling back to nextGid otherwise.
 * - NextE adapts that to gid-keyed LazyForEach: fresh rows are appended after dedupe, but pagination
 *   continues or stops from EH page/cursor progress, not from dedupe row count.
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
ok('FE favorite subpage sends page plus last gid when nextPage is available',
  /gid: nextPage > -1 \? \(state\?\.lastOrNull\?\.gid \?\? ''\) : nextGid[\s\S]*page: nextPage/.test(feFavSub))

ok('EhApiService keeps dm_l retry centralized in getFavoritesList',
  /async getFavoritesList\(query: FavoritesQuery\): Promise<GalleryList> \{[\s\S]*EhConstants\.FAV_DISPLAY_LIST/.test(api))
ok('EhApiService favorites URL supports page+from before cursor fallback',
  /if \(query\.page >= 0\) \{[\s\S]*params\.push\(`page=\$\{query\.page\}`\)[\s\S]*params\.push\(`from=\$\{encodeURIComponent\(query\.from\)\}`\)[\s\S]*\} else if \(query\.next\.length > 0\) \{[\s\S]*params\.push\(`next=\$\{encodeURIComponent\(query\.next\)\}`\)/.test(api))
ok('EhApiService ordinary favorites fetch carries no inline_set order',
  /let body: string = await this\.fetchFavoritesBody\(base, query, ''\)/.test(api))
ok('EhApiService applies favorite order only as a first-page correction retry',
  /const activeOrder: string = this\.favoriteOrderFromBody\(body\)[\s\S]*if \(firstPage && query\.order\.length > 0 && activeOrder\.length > 0 && activeOrder !== query\.order\) \{[\s\S]*fetchFavoritesBody\(base, query, query\.order\)/.test(api))

ok('FavoritesViewModel defines shared page fetch helper',
  /private async fetchPage\([\s\S]*next: string,[\s\S]*page: number = -1,[\s\S]*from: string = ''/.test(vm))
ok('Shared helper fetches FavoritesQuery for the requested page/cursor only',
  /getFavoritesList\([\s\S]*this\.buildQuery\(next, page, from\)/.test(vm))
ok('FavoritesViewModel no longer duplicates order retry logic',
  !/favOrder !== this\.favOrder/.test(vm))
ok('Initial load uses the same page helper',
  /const list: GalleryList = await this\.fetchPage\(''\)/.test(vm))
ok('FavoritesViewModel declares stale-cursor history',
  /private lastNext: string = ''/.test(vm))
ok('Initial load resets stale request history with page state',
  /this\.nextGid = ''[\s\S]*this\.nextPage = -1[\s\S]*this\.lastNext = ''[\s\S]*this\.hasMore = false/.test(vm))
ok('Initial load treats nextPage or nextGid as forward paging',
  /this\.nextGid = list\.nextGid[\s\S]*this\.nextPage = list\.nextPage[\s\S]*this\.hasMore = this\.hasForwardPage\(list\)/.test(vm))
ok('FavoritesViewModel mirrors FE next getter: nextPage must be > 0 to count as forward page',
  /private hasForwardPage\(list: GalleryList\): boolean \{[\s\S]*return list\.nextPage > 0 \|\| list\.nextGid\.length > 0/.test(vm))
ok('loadMore captures the current page/from or cursor before fetching',
  /const page: number = this\.nextPage[\s\S]*const from: string = page >= 0 \? this\.lastVisibleGid\(\) : ''[\s\S]*const cursor: string = page >= 0 \? from : this\.nextGid[\s\S]*const requestKey: string = page >= 0 \? `page:\$\{page\}:from:\$\{from\}` : `next:\$\{cursor\}`/.test(vm))
ok('loadMore stops empty page/cursor requests before starting a footer fetch',
  /if \(cursor\.length === 0\) \{[\s\S]*this\.hasMore = false[\s\S]*return[\s\S]*\}[\s\S]*if \(requestKey === this\.lastNext && this\.errorMessage\.length === 0\)/.test(vm))
ok('loadMore does not convert visible footer error retries into no-more',
  /if \(requestKey === this\.lastNext && this\.errorMessage\.length === 0\) \{[\s\S]*this\.hasMore = false[\s\S]*return[\s\S]*\}[\s\S]*this\.isLoadingMore = true/.test(vm))
ok('loadMore clears stale footer error before retry fetch',
  /this\.isLoadingMore = true[\s\S]*this\.errorMessage = ''[\s\S]*const myEpoch: number = this\.epoch/.test(vm))
ok('loadMore dedupes before append for gid-keyed LazyForEach',
  /const fresh: EhGallery\[\] = await this\.translateRows\(this\.dedupeNew\(list\.gallerys\)\)/.test(vm))
ok('loadMore records the successfully requested page/cursor only after epoch-valid apply',
  /if \(this\.epoch === myEpoch\) \{[\s\S]*this\.nextGid = list\.nextGid[\s\S]*this\.nextPage = list\.nextPage[\s\S]*this\.lastNext = requestKey[\s\S]*this\.hasMore = this\.didPagingAdvance\(page, cursor, list\)/.test(vm))
ok('didPagingAdvance mirrors FE next getter for page-paged results',
  /if \(requestedPage >= 0\) \{[\s\S]*return list\.nextPage > 0 \|\| list\.nextGid\.length > 0/.test(vm))
ok('loadMore does not stop solely because a page brings no fresh rows',
  !/this\.hasMore = [^\n]*fresh\.length > 0/.test(vm))
ok('loadMore no longer keeps paging solely because the cursor changed',
  !/this\.hasMore = list\.nextGid\.length > 0 && list\.nextGid !== cursor/.test(vm))
{
  const loadMoreStart = vm.indexOf('async loadMore(): Promise<void>')
  const fetchStart = vm.indexOf('const list: GalleryList = await this.fetchPage(', loadMoreStart)
  const beforeFetch = vm.slice(loadMoreStart, fetchStart)
  ok('loadMore keeps the same page/cursor retryable after a failed fetch',
    !/this\.lastNext = requestKey/.test(beforeFetch))
}

console.log(`✓ favorites load-more order contract: ${passed} assertions passed`)

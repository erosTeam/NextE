#!/usr/bin/env node
/**
 * Contract test for the gallery-list paging hygiene in
 *   feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets (loadMore / dedupeNew / hasMore)
 *
 * The model below is copy-equal to that ViewModel's loadMore logic (no network — synthetic pages).
 * It locks the eros_fe tabview_controller.loadDataMore careful checks, adapted for NextE's
 * gid-keyed LazyForEach:
 *   • stale-cursor guard (eros_fe lastNext==next): an unchanged/empty cursor stops paging, no refetch.
 *   • dedup-by-gid before append: EH repeats the boundary row across pages; gid is the LazyForEach
 *     key, so duplicates must be filtered (eros_fe tolerates dupes via index keys — NextE cannot).
 *   • exhausted when a page brings no genuinely-new rows (infinite same-page loop guard).
 *   • failed load-more does not commit lastNext: retry must re-request the same cursor, not flip to
 *     "no more" because the stale-cursor guard sees its own failed attempt.
 *   • 'popular' is a no-paging fixed snapshot: hasMore stays false and loadMore is a no-op.
 *   • epoch/generation guard: a reload/refresh/source-switch during an in-flight loadMore discards
 *     the stale (cross-source/host) page instead of contaminating the new list + corrupting cursor.
 * If the .ets logic changes, mirror it here.
 *
 * Run: node scripts/test_gallery_paging_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// Mirror of GalleryListViewModel paging state + loadMore (pure; `server` supplies parsed pages).
class VM {
  constructor(source = '') {
    this.source = source
    this.rows = [] // dataSource.getAll()
    this.nextGid = ''
    this.lastNext = ''
    this.hasMore = true
    this.epoch = 0
    this.errorMessage = ''
    this.fetches = 0 // count of network calls actually issued
  }
  isPopular() {
    return this.source === 'popular'
  }
  dedupeNew(rows) {
    const seen = new Set(this.rows.map((g) => g.gid))
    const out = []
    for (const g of rows) {
      if (g.gid.length > 0 && !seen.has(g.gid)) {
        seen.add(g.gid)
        out.push(g)
      }
    }
    return out
  }
  load(page) {
    // first-page load (loadData): replace, reset cursor history
    this.rows = page.gallerys.slice()
    this.nextGid = page.nextGid
    this.lastNext = ''
    this.hasMore = !this.isPopular() && page.nextGid.length > 0
  }
  reload(page1, source) {
    // reload()/setSource()/refresh(): bump epoch (void any in-flight loadMore), replace with page1
    this.epoch += 1
    if (source !== undefined) this.source = source
    this.rows = page1.gallerys.slice()
    this.nextGid = page1.nextGid
    this.lastNext = ''
    this.hasMore = !this.isPopular() && page1.nextGid.length > 0
  }
  // `midFlight` simulates the await suspension point: it runs after the fetch but before the result
  // is applied (where a concurrent reload/refresh can land).
  loadMore(server, midFlight) {
    if (this.isLoading || this.isLoadingMore || !this.hasMore || this.isPopular()) return
    const requestedNext = this.nextGid
    if (requestedNext.length === 0 || requestedNext === this.lastNext) {
      this.hasMore = false
      return
    }
    this.isLoadingMore = true
    this.errorMessage = ''
    const myEpoch = this.epoch
    this.fetches += 1
    try {
      const page = server(requestedNext)
      if (midFlight) midFlight()
      if (this.epoch === myEpoch) {
        const fresh = this.dedupeNew(page.gallerys)
        if (fresh.length > 0) this.rows = this.rows.concat(fresh)
        this.nextGid = page.nextGid
        this.lastNext = requestedNext
        this.hasMore = page.nextGid.length > 0 && fresh.length > 0
      }
    } catch (_err) {
      if (this.epoch === myEpoch) {
        this.errorMessage = 'load-more failed'
      }
    }
    this.isLoadingMore = false
  }
}

const g = (gid) => ({ gid })
const page = (gids, nextGid) => ({ gallerys: gids.map(g), nextGid })

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

// 1. normal forward paging: fresh rows appended, cursor advances
{
  const vm = new VM('')
  vm.load(page(['10', '9', '8'], '8'))
  vm.loadMore(() => page(['7', '6', '5'], '5'))
  ok('appends fresh page', vm.rows.map((r) => r.gid).join(',') === '10,9,8,7,6,5')
  ok('cursor advanced', vm.nextGid === '5')
  ok('still has more', vm.hasMore === true)
  ok('one fetch issued', vm.fetches === 1)
}

// 2. dedup: a repeated boundary row (and within-page dupes) is filtered before append
{
  const vm = new VM('')
  vm.load(page(['10', '9', '8'], '8'))
  vm.loadMore(() => page(['8', '7', '7', '6'], '6')) // 8 repeats boundary; 7 duplicated in-page
  ok('dupes dropped', vm.rows.map((r) => r.gid).join(',') === '10,9,8,7,6')
  ok('no duplicate gids', new Set(vm.rows.map((r) => r.gid)).size === vm.rows.length)
}

// 3. stale cursor: nextGid unchanged across pages → next loadMore bails, no refetch
{
  const vm = new VM('')
  vm.load(page(['10', '9'], '9'))
  vm.loadMore(() => page(['8', '7'], '9')) // server returns SAME nextGid '9'
  ok('appended once', vm.rows.length === 4)
  const fetchesAfterFirst = vm.fetches
  vm.loadMore(() => page(['x'], '9')) // cursor '9' === lastNext '9' → must bail
  ok('stale cursor bails (no second fetch)', vm.fetches === fetchesAfterFirst)
  ok('stale cursor marks exhausted', vm.hasMore === false)
}

// 4. failed loadMore keeps the cursor retryable; retry should not become "no more"
{
  const vm = new VM('')
  vm.load(page(['10', '9'], '9'))
  vm.loadMore((cursor) => {
    ok('failed request uses current cursor', cursor === '9')
    throw new Error('boom')
  })
  ok('failed loadMore records error', vm.errorMessage.length > 0)
  ok('failed loadMore keeps hasMore true', vm.hasMore === true)
  ok('failed loadMore keeps next cursor', vm.nextGid === '9')
  ok('failed loadMore does not commit lastNext', vm.lastNext === '')
  ok('failed loadMore releases loading flag', vm.isLoadingMore === false)
  const fetchesAfterFailure = vm.fetches
  vm.loadMore((cursor) => {
    ok('retry reuses same cursor', cursor === '9')
    return page(['8'], '8')
  })
  ok('retry issues a second fetch', vm.fetches === fetchesAfterFailure + 1)
  ok('retry appends fresh row', vm.rows.map((r) => r.gid).join(',') === '10,9,8')
  ok('retry clears stale error', vm.errorMessage === '')
}

// 5. empty cursor stops paging
{
  const vm = new VM('')
  vm.load(page(['10', '9'], '')) // no next cursor
  ok('no cursor → no more after load', vm.hasMore === false)
  vm.loadMore(() => page(['8'], '8'))
  ok('no cursor → loadMore no-op', vm.fetches === 0)
}

// 6. all-duplicate page (server race) → exhausted, no infinite loop
{
  const vm = new VM('')
  vm.load(page(['10', '9', '8'], '8'))
  vm.loadMore(() => page(['10', '9'], '7')) // every row already present, cursor still moves
  ok('no rows added', vm.rows.length === 3)
  ok('exhausted on zero-fresh', vm.hasMore === false)
}

// 7. popular is a no-paging snapshot
{
  const vm = new VM('popular')
  vm.load(page(['10', '9', '8'], '8')) // even if a cursor is present, popular never pages
  ok('popular hasMore false after load', vm.hasMore === false)
  vm.loadMore(() => page(['7'], '7'))
  ok('popular loadMore no-op', vm.fetches === 0 && vm.rows.length === 3)
}

// 8. epoch guard: a source-switch reload during an in-flight loadMore discards the stale page
{
  const vm = new VM('')
  vm.load(page(['10', '9', '8'], '8'))
  // OLD-source loadMore is suspended at its await; mid-flight a source switch reloads a NEW list.
  vm.loadMore(
    () => page(['7', '6'], '5'), // OLD-source page, resolves late
    () => vm.reload(page(['200', '199'], '199'), 'watched'), // concurrent switch
  )
  ok('new list not contaminated by stale page', vm.rows.map((r) => r.gid).join(',') === '200,199')
  ok('cursor belongs to new source', vm.nextGid === '199')
  ok('stale loadMore cleared the in-flight flag', vm.isLoadingMore === false)
  // and the new source can still page forward normally afterward
  vm.loadMore(() => page(['198', '197'], '197'))
  ok('new source pages forward', vm.rows.map((r) => r.gid).join(',') === '200,199,198,197')
}

// 9. structural: the guards exist in the .ets
{
  const src = readFileSync(
    join(ROOT, 'feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets'),
    'utf8',
  )
  const loadMoreMatch = /async loadMore\(\): Promise<void> \{[\s\S]*?\n  \}\n\n  \/\*\* Toplist/.exec(src)
  assert.ok(loadMoreMatch, 'loadMore block located')
  const loadMoreSrc = loadMoreMatch[0]
  const beforeFetch = loadMoreSrc.slice(0, loadMoreSrc.indexOf('EhApiService.getInstance().getGalleryList'))
  ok('has isPopular no-paging guard in loadMore', /!this\.hasMore \|\| this\.isPopular\(\)/.test(src))
  ok('captures requested cursor before fetch', /const requestedNext: string = this\.nextGid/.test(src))
  ok('has stale-cursor guard', /requestedNext === this\.lastNext/.test(src))
  ok('loadMore clears stale error before retry fetch', /this\.isLoadingMore = true[\s\S]*this\.errorMessage = ''[\s\S]*const myEpoch: number = this\.epoch/.test(loadMoreSrc))
  ok('loadMore does not commit lastNext before fetch', !/this\.lastNext =/.test(beforeFetch))
  ok('fetches the captured requested cursor', /this\.buildQuery\(requestedNext\)/.test(src))
  ok('commits lastNext only inside successful epoch apply', /if \(this\.epoch === myEpoch\) \{[\s\S]*this\.lastNext = requestedNext/.test(loadMoreSrc))
  ok('dedupes before append', /this\.dedupeNew\(list\.gallerys\)/.test(src))
  ok('exhausted on no-fresh', /list\.nextGid\.length > 0 && fresh\.length > 0/.test(src))
  ok('captures epoch before fetch', /const myEpoch: number = this\.epoch/.test(src))
  ok('guards mutations on epoch', /if \(this\.epoch === myEpoch\)/.test(src))
  ok('reload bumps epoch', /this\.epoch = this\.epoch \+ 1/.test(src))
  ok('toplist loadMore clears stale error before retry fetch',
    /private async loadMoreToplist\(\): Promise<void> \{[\s\S]*this\.isLoadingMore = true[\s\S]*this\.errorMessage = ''[\s\S]*const myEpoch: number = this\.epoch/.test(src))
}

// 10. cross-cutting: EVERY paged ViewModel carries the SAME two loadMore guards as Home.
// (a) epoch (loadMore-vs-reset) guard — a reset path runs without the isLoadingMore guard, so an
//     in-flight loadMore could contaminate the new list on favcat/query/source switch.
// (b) gid-dedup guard — EH repeats the boundary gallery across cursor pages and the LazyForEach key
//     is gid, so an undeduped append injects a duplicate key (churn/throw) and hasMore based on the
//     raw page length loops forever on an all-duplicate page.
// Both races are identical in all three VMs; fixing only Home would leave Favorites/Search broken.
{
  const pagedVms = [
    'feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets',
    'feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets',
    'feature/search/src/main/ets/viewmodel/SearchViewModel.ets',
  ]
  for (const rel of pagedVms) {
    const src = readFileSync(join(ROOT, rel), 'utf8')
    const name = rel.split('/').pop()
    const loadMore = /async loadMore\(\): Promise<void> \{[\s\S]*?\n  \}\n\n  canLoadMore/.exec(src)?.[0] ?? ''
    ok(`${name}: clears stale footer error before retry fetch`,
      /this\.isLoadingMore = true[\s\S]*this\.errorMessage = ''[\s\S]*const myEpoch: number = this\.epoch/.test(loadMore))
    ok(`${name}: declares epoch token`, /private epoch: number = 0/.test(src))
    ok(`${name}: captures myEpoch in loadMore`, /const myEpoch: number = this\.epoch/.test(src))
    ok(`${name}: discards stale page on epoch mismatch`, /if \(this\.epoch === myEpoch\)/.test(src))
    ok(`${name}: bumps epoch on reset`, /this\.epoch = this\.epoch \+ 1/.test(src))
    ok(`${name}: declares dedupeNew helper`, /private dedupeNew\(rows: EhGallery\[\]\): EhGallery\[\]/.test(src))
    ok(`${name}: dedupes new rows by gid before append`, /this\.dedupeNew\(list\.gallerys\)/.test(src))
    ok(`${name}: exhausted on no-fresh rows`, /list\.nextGid\.length > 0 && fresh\.length > 0/.test(src))
  }
}

console.log(`✓ gallery paging contract: ${passed} assertions passed`)

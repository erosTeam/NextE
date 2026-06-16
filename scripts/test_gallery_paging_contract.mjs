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
    if (this.nextGid.length === 0 || this.nextGid === this.lastNext) {
      this.hasMore = false
      return
    }
    this.isLoadingMore = true
    this.lastNext = this.nextGid
    const myEpoch = this.epoch
    this.fetches += 1
    const page = server(this.nextGid)
    if (midFlight) midFlight()
    if (this.epoch === myEpoch) {
      const fresh = this.dedupeNew(page.gallerys)
      if (fresh.length > 0) this.rows = this.rows.concat(fresh)
      this.nextGid = page.nextGid
      this.hasMore = page.nextGid.length > 0 && fresh.length > 0
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

// 4. empty cursor stops paging
{
  const vm = new VM('')
  vm.load(page(['10', '9'], '')) // no next cursor
  ok('no cursor → no more after load', vm.hasMore === false)
  vm.loadMore(() => page(['8'], '8'))
  ok('no cursor → loadMore no-op', vm.fetches === 0)
}

// 5. all-duplicate page (server race) → exhausted, no infinite loop
{
  const vm = new VM('')
  vm.load(page(['10', '9', '8'], '8'))
  vm.loadMore(() => page(['10', '9'], '7')) // every row already present, cursor still moves
  ok('no rows added', vm.rows.length === 3)
  ok('exhausted on zero-fresh', vm.hasMore === false)
}

// 6. popular is a no-paging snapshot
{
  const vm = new VM('popular')
  vm.load(page(['10', '9', '8'], '8')) // even if a cursor is present, popular never pages
  ok('popular hasMore false after load', vm.hasMore === false)
  vm.loadMore(() => page(['7'], '7'))
  ok('popular loadMore no-op', vm.fetches === 0 && vm.rows.length === 3)
}

// 7. epoch guard: a source-switch reload during an in-flight loadMore discards the stale page
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

// 8. structural: the guards exist in the .ets
{
  const src = readFileSync(
    join(ROOT, 'feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets'),
    'utf8',
  )
  ok('has isPopular no-paging guard in loadMore', /!this\.hasMore \|\| this\.isPopular\(\)/.test(src))
  ok('has stale-cursor guard', /this\.nextGid === this\.lastNext/.test(src))
  ok('dedupes before append', /this\.dedupeNew\(list\.gallerys\)/.test(src))
  ok('exhausted on no-fresh', /list\.nextGid\.length > 0 && fresh\.length > 0/.test(src))
  ok('captures epoch before fetch', /const myEpoch: number = this\.epoch/.test(src))
  ok('guards mutations on epoch', /if \(this\.epoch === myEpoch\)/.test(src))
  ok('reload bumps epoch', /this\.epoch = this\.epoch \+ 1/.test(src))
}

// 9. cross-cutting: EVERY paged ViewModel carries the same epoch (loadMore-vs-reset) guard.
// The race (a reset path that runs without the isLoadingMore guard) is identical in all three;
// fixing only Home would leave Favorites/Search corrupting their lists on favcat/query switch.
{
  const pagedVms = [
    'feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets',
    'feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets',
    'feature/search/src/main/ets/viewmodel/SearchViewModel.ets',
  ]
  for (const rel of pagedVms) {
    const src = readFileSync(join(ROOT, rel), 'utf8')
    const name = rel.split('/').pop()
    ok(`${name}: declares epoch token`, /private epoch: number = 0/.test(src))
    ok(`${name}: captures myEpoch in loadMore`, /const myEpoch: number = this\.epoch/.test(src))
    ok(`${name}: discards stale page on epoch mismatch`, /if \(this\.epoch === myEpoch\)/.test(src))
    ok(`${name}: bumps epoch on reset`, /this\.epoch = this\.epoch \+ 1/.test(src))
  }
}

console.log(`✓ gallery paging contract: ${passed} assertions passed`)

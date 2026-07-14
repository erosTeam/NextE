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
 *   • first-page ownership run: cache restore, HTTP result, deferred translation, cursor/error/loading
 *     writes all belong to the account/site/profile/source snapshot that started the request. A retained
 *     page may force a replacement run while an old one is still in flight.
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
    this.prevGid = ''
    this.lastNext = ''
    this.lastPrev = ''
    this.hasMore = true
    this.epoch = 0
    this.cacheKey = 'eh:member:a:home'
    this.errorMessage = ''
    this.isLoading = false
    this.isLoadingMore = false
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
  capturePagingRun() {
    return { epoch: this.epoch, cacheKey: this.cacheKey, source: this.source }
  }
  isCurrentPagingRun(run) {
    return this.epoch === run.epoch &&
      this.cacheKey === run.cacheKey &&
      this.source === run.source
  }
  load(page) {
    // first-page load (loadData): replace, reset cursor history
    this.rows = page.gallerys.slice()
    this.nextGid = page.nextGid
    this.prevGid = page.prevGid
    this.lastNext = ''
    this.lastPrev = ''
    this.hasMore = !this.isPopular() && page.nextGid.length > 0
  }
  reload(page1, source) {
    // Completed replacement first page: it bumps epoch, owns the footer state, and replaces rows.
    this.epoch += 1
    if (source !== undefined) this.source = source
    this.rows = page1.gallerys.slice()
    this.nextGid = page1.nextGid
    this.prevGid = page1.prevGid
    this.lastNext = ''
    this.lastPrev = ''
    this.isLoadingMore = false
    this.isLoading = false
    this.hasMore = !this.isPopular() && page1.nextGid.length > 0
  }
  beginReplacement(page1, source) {
    // Model an in-flight first-page replacement: old paging must not release this loading flag.
    this.epoch += 1
    if (source !== undefined) this.source = source
    this.rows = page1.gallerys.slice()
    this.nextGid = page1.nextGid
    this.prevGid = page1.prevGid
    this.lastNext = ''
    this.lastPrev = ''
    this.isLoadingMore = false
    this.isLoading = true
    this.hasMore = !this.isPopular() && page1.nextGid.length > 0
  }
  // `midFlight` simulates the network await; `midTranslation` is the later translateRows await.
  loadMore(server, midFlight, midTranslation) {
    if (this.isLoading || this.isLoadingMore || !this.hasMore || this.isPopular()) return
    const requestedNext = this.nextGid
    if (requestedNext.length === 0) {
      this.hasMore = false
      return
    }
    if (requestedNext === this.lastNext && this.errorMessage.length === 0) {
      this.hasMore = false
      return
    }
    this.isLoadingMore = true
    this.errorMessage = ''
    const run = this.capturePagingRun()
    this.fetches += 1
    try {
      const page = server(requestedNext)
      if (midFlight) midFlight()
      if (this.isCurrentPagingRun(run)) {
        const fresh = this.dedupeNew(page.gallerys)
        if (midTranslation) midTranslation()
        if (this.isCurrentPagingRun(run)) {
          if (fresh.length > 0) this.rows = this.rows.concat(fresh)
          this.nextGid = page.nextGid
          this.lastNext = requestedNext
          this.hasMore = page.nextGid.length > 0 && fresh.length > 0
        }
      }
    } catch (_err) {
      if (this.isCurrentPagingRun(run)) {
        this.errorMessage = 'load-more failed'
      }
    }
    if (this.isCurrentPagingRun(run)) this.isLoadingMore = false
  }
  loadPrevious(server, midTranslation, afterPrepend) {
    const requestedPrev = this.prevGid
    this.isLoading = true
    const run = this.capturePagingRun()
    try {
      const page = server(requestedPrev)
      if (this.isCurrentPagingRun(run)) {
        const fresh = this.dedupeNew(page.gallerys)
        if (midTranslation) midTranslation()
        if (this.isCurrentPagingRun(run)) {
          if (fresh.length > 0) {
            this.rows = fresh.concat(this.rows)
            if (afterPrepend) afterPrepend(fresh.length)
          }
          this.prevGid = page.prevGid
          this.lastPrev = requestedPrev
        }
      }
    } finally {
      if (this.isCurrentPagingRun(run)) this.isLoading = false
    }
  }
}

// Minimal mirror of the first-page ownership token. The production VM additionally captures source,
// profile UUID/revision, toplist period, and favcat; these three cases exercise the two crucial guards:
// context-key changes (including CookieStore before AuthState publishes) and epoch ABA protection.
class FirstPageRunVM {
  constructor() {
    this.epoch = 0
    this.cacheKey = 'eh:member:a:home'
    this.profileContentRevision = 'revision-a'
    this.applyToplistHiddenUserTags = false
  }
  beginFirstPageRun() {
    this.epoch += 1
    return {
      epoch: this.epoch,
      cacheKey: this.cacheKey,
      profileContentRevision: this.profileContentRevision,
      applyToplistHiddenUserTags: this.applyToplistHiddenUserTags,
    }
  }
  isCurrentFirstPageRun(run) {
    return this.epoch === run.epoch &&
      this.cacheKey === run.cacheKey &&
      this.profileContentRevision === run.profileContentRevision &&
      this.applyToplistHiddenUserTags === run.applyToplistHiddenUserTags
  }
}

const g = (gid) => ({ gid })
const page = (gids, nextGid, prevGid = '') => ({ gallerys: gids.map(g), nextGid, prevGid })

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

// 9. translateRows adds a second await after the original network/epoch fence. A replacement landing in
// that gap must block every old append/prepend/cursor/callback write, while retaining its own loading flag.
{
  const vm = new VM('')
  vm.load(page(['10', '9'], '9'))
  vm.loadMore(
    () => page(['8', '7'], '7'),
    undefined,
    () => vm.beginReplacement(page(['200', '199'], '199'), 'watched'),
  )
  ok('translation-late append cannot contaminate replacement rows', vm.rows.map((r) => r.gid).join(',') === '200,199')
  ok('translation-late append cannot replace the new cursor', vm.nextGid === '199' && vm.lastNext === '')
  ok('replacement first page owns the footer loading state', vm.isLoadingMore === false)
}
{
  const vm = new VM('')
  vm.load(page(['10', '9'], '9', '11'))
  let prepended = 0
  vm.loadPrevious(
    (cursor) => {
      ok('previous-page request captures its original cursor', cursor === '11')
      return page(['11'], '9', '12')
    },
    () => vm.beginReplacement(page(['200', '199'], '199', '201'), 'watched'),
    (count) => {
      prepended += count
    },
  )
  ok('translation-late prepend cannot contaminate replacement rows', vm.rows.map((r) => r.gid).join(',') === '200,199')
  ok('translation-late prepend cannot replace the new previous cursor', vm.prevGid === '201' && vm.lastPrev === '')
  ok('translation-late prepend cannot trigger stale scroll compensation', prepended === 0)
  ok('old prepend cannot release an in-flight replacement loading state', vm.isLoading === true)
}
{
  const vm = new VM('')
  vm.load(page(['10', '9'], '9'))
  vm.loadMore(
    () => page(['8'], '8'),
    undefined,
    () => {
      vm.cacheKey = 'eh:member:b:home'
    },
  )
  ok('paging run rejects a CookieStore context change before AuthState publishes', vm.rows.map((r) => r.gid).join(',') === '10,9')
  ok('context-change drop keeps old paging cursor uncommitted', vm.nextGid === '9' && vm.lastNext === '')
  ok('context-only mismatch keeps the old footer locked until a replacement owns it', vm.isLoadingMore === true)
  vm.beginReplacement(page(['200', '199'], '199'), 'watched')
  ok('replacement first page takes ownership and releases the stale footer flag', vm.isLoadingMore === false)
}

// 10. first-page ownership: a context switch discards an old response even before the retained-page
// monitor can publish, and an A→B→A switch cannot revive run A due to its epoch token.
{
  const vm = new FirstPageRunVM()
  const runA = vm.beginFirstPageRun()
  vm.cacheKey = 'eh:member:b:home'
  ok('first-page run rejects an account/site cache-key change', vm.isCurrentFirstPageRun(runA) === false)
  const runB = vm.beginFirstPageRun()
  vm.cacheKey = 'eh:member:a:home'
  ok('first-page epoch rejects an ABA account/site switch', vm.isCurrentFirstPageRun(runA) === false)
  ok('replacement first-page run rejects a subsequent context switch', vm.isCurrentFirstPageRun(runB) === false)
  vm.cacheKey = 'eh:member:b:home'
  ok('replacement first-page run accepts its captured context', vm.isCurrentFirstPageRun(runB) === true)
  vm.profileContentRevision = 'revision-b'
  ok('first-page run rejects a live profile-query revision', vm.isCurrentFirstPageRun(runB) === false)
  const runC = vm.beginFirstPageRun()
  vm.applyToplistHiddenUserTags = true
  ok('first-page run rejects a live toplist hidden-tag filter change', vm.isCurrentFirstPageRun(runC) === false)
}

// 11. structural: the guards exist in the .ets
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
  ok('stale-cursor guard does not convert visible footer errors into no-more',
    /if \(requestedNext === this\.lastNext && this\.errorMessage\.length === 0\) \{[\s\S]*this\.hasMore = false/.test(loadMoreSrc))
  ok('loadMore does not commit lastNext before fetch', !/this\.lastNext =/.test(beforeFetch))
  ok('fetches the captured requested cursor', /this\.buildQuery\(requestedNext\)/.test(src))
  ok('commits lastNext only inside successful ownership apply',
    /translateCurrentPagingRows\(list, run\)[\s\S]*if \(fresh === null\)[\s\S]*this\.lastNext = requestedNext/.test(loadMoreSrc))
  ok('dedupes before append', /this\.dedupeNew\(list\.gallerys\)/.test(src))
  ok('exhausted on no-fresh', /list\.nextGid\.length > 0 && fresh\.length > 0/.test(src))
  ok('captures epoch before fetch', /const myEpoch: number = this\.epoch/.test(src))
  ok('guards paging mutations on full list context', /this\.isCurrentPagingRun\(run\)/.test(src))
  ok('reload bumps epoch', /this\.epoch = this\.epoch \+ 1/.test(src))
  ok('declares immutable first-page ownership context',
    /class GalleryFirstPageRun \{[\s\S]*cacheKey: string[\s\S]*profileContentRevision: string/.test(src))
  ok('first-page current check validates epoch, request fields, and live scoped cache key',
    /private isCurrentFirstPageRun\(run: GalleryFirstPageRun\): boolean \{[\s\S]*this\.epoch !== run\.epoch[\s\S]*this\.profileContentRevision\(\) !== run\.profileContentRevision[\s\S]*applyHiddenUserTags !== run\.applyToplistHiddenUserTags[\s\S]*this\.cacheKey\(\) === run\.cacheKey/.test(src))
  ok('cache restore and delayed cache translation retain the initiating run',
    /applyCachedFirstPageIfEmpty\(run: GalleryFirstPageRun\)[\s\S]*loadGalleryList\(this\.context, run\.cacheKey\)[\s\S]*!this\.isCurrentFirstPageRun\(run\)/.test(src) &&
    /translateCachedRowsLater\([\s\S]*run: GalleryFirstPageRun[\s\S]*!this\.isCurrentFirstPageRun\(run\)/.test(src))
  ok('first-page renderer returns an ownership result after cache/translation awaits',
    /private async renderFirstPageRows\([\s\S]*run: GalleryFirstPageRun[\s\S]*\): Promise<boolean>[\s\S]*!this\.isCurrentFirstPageRun\(run\)[\s\S]*return this\.isCurrentFirstPageRun\(run\)/.test(src))
  ok('tag-translation repaint is fenced against a newer first-page run',
    /async reapplyTagTranslation\(\): Promise<void> \{[\s\S]*const renderVersion: number = this\.cacheRenderVersion \+ 1[\s\S]*const renderEpoch: number = this\.epoch[\s\S]*const renderCacheKey: string = this\.cacheKey\(\)[\s\S]*this\.cacheRenderVersion !== renderVersion[\s\S]*this\.epoch !== renderEpoch[\s\S]*this\.cacheKey\(\) !== renderCacheKey/.test(src))
  ok('paging captures the same live account/site/profile request context as first-page work',
    /private captureCurrentListRun\(\): GalleryFirstPageRun \{[\s\S]*this\.cacheKey\(\)[\s\S]*this\.profileContentRevision\(\)[\s\S]*connectToplistFilter\(\)\.applyHiddenUserTags/.test(src) &&
    /private isCurrentPagingRun\(run: GalleryFirstPageRun\): boolean \{[\s\S]*this\.isCurrentFirstPageRun\(run\)/.test(src))
  ok('shared paging translation helper checks context before and after its await',
    /private async translateCurrentPagingRows\([\s\S]*!this\.isCurrentPagingRun\(run\)[\s\S]*await this\.translateRows\(this\.dedupeNew\(list\.gallerys\)\)[\s\S]*return this\.isCurrentPagingRun\(run\) \? fresh : null/.test(src))
  ok('a replacement first page releases the stale footer state before its old paging request returns',
    /private beginFirstPageRun\(\): GalleryFirstPageRun \{[\s\S]*this\.isLoadingMore = false/.test(src))
  const pagingBlocks = [
    ['gallery next page', '  async loadMore()', '  /** Toplist page paging', 'isLoadingMore'],
    ['toplist next page', '  private async loadMoreToplist()', '  /** After a page jump', 'isLoadingMore'],
    ['toplist previous page', '  private async loadPreviousToplist(', '  private canLoadPreviousDateJump', 'isLoading'],
    ['date-jump previous page', '  private async loadPreviousGallery(', '  /** Favorite-type profiles', 'isLoading'],
    ['favorite previous page', '  private async loadPreviousFavorites(', '  /** Favorites page paging', 'isLoading'],
    ['favorite next page', '  private async loadMoreFavorites()', '  canLoadMore()', 'isLoadingMore'],
  ]
  for (const [name, start, end, loadingFlag] of pagingBlocks) {
    const startIndex = src.indexOf(start)
    const endIndex = src.indexOf(end, startIndex)
    assert.ok(startIndex >= 0 && endIndex > startIndex, `${name} paging block located`)
    const block = src.slice(startIndex, endIndex)
    const translationIndex = block.indexOf('await this.translateCurrentPagingRows')
    assert.ok(translationIndex >= 0, `${name} translation await located`)
    const finallyIndex = block.indexOf('finally')
    const finallyBlock = finallyIndex >= 0 ? block.slice(finallyIndex) : ''
    ok(`${name}: captures a non-mutating request context`, /const run: GalleryFirstPageRun = this\.captureCurrentListRun\(\)/.test(block))
    ok(`${name}: routes translation through the ownership-aware helper`, /await this\.translateCurrentPagingRows\(list, run\)/.test(block))
    ok(`${name}: drops a stale translated page before cursor or row publication`, /if \(fresh === null\)/.test(block))
    ok(`${name}: only its full request context releases the loading flag`,
      new RegExp(`if \\(this\\.isCurrentPagingRun\\(run\\)\\) \\{[\\s\\S]*this\\.${loadingFlag} = false`).test(finallyBlock))
  }
  const firstPageBlocks = [
    ['toplist jump', '  async jumpToToplistPage(', '  canJumpToDateAfter'],
    ['date jump', '  async jumpToDateAfter(', '  /** First load'],
    ['first load', '  async loadData()', '  // Whether a fresh first-page'],
    ['reload', '  async reload(force: boolean = false)', '  /** Pull-to-refresh'],
    ['refresh', '  async refresh(', '  /** Append the next page'],
  ]
  for (const [name, start, end] of firstPageBlocks) {
    const startIndex = src.indexOf(start)
    const endIndex = src.indexOf(end, startIndex)
    assert.ok(startIndex >= 0 && endIndex > startIndex, `${name} first-page block located`)
    const block = src.slice(startIndex, endIndex)
    ok(`${name}: starts an ownership run`, /const run: GalleryFirstPageRun = this\.beginFirstPageRun\(\)/.test(block))
    ok(`${name}: drops an old result after await`, /if \(!this\.isCurrentFirstPageRun\(run\)\)/.test(block))
    ok(`${name}: commits rows through the ownership-aware renderer`, /renderFirstPageRows\(list, this\.itemCount === 0, run/.test(block))
    ok(`${name}: only its current run releases the loading state`,
      /finally \{[\s\S]*if \(this\.isCurrentFirstPageRun\(run\)\) \{[\s\S]*this\.isLoading = false/.test(block))
  }
  ok('forced reload supersedes an in-flight first-page request',
    /async reload\(force: boolean = false\): Promise<boolean> \{[\s\S]*if \(this\.isLoading && !force\)/.test(src))
  ok('toplist loadMore clears stale error before retry fetch',
    /private async loadMoreToplist\(\): Promise<void> \{[\s\S]*this\.isLoadingMore = true[\s\S]*this\.errorMessage = ''[\s\S]*const myEpoch: number = this\.epoch/.test(src))
  ok('toplist first-page query omits p=0 like eros_fe',
    /private buildQuery\(next: string, page: number = -1[\s\S]*?\): GalleryListQuery/.test(src))
  ok('toplist stores parsed nextPage after first-page loads and cache restores',
    (src.match(/this\.toplistNextPage = list\.nextPage/g) ?? []).length >= 3 &&
    /this\.toplistNextPage = cached\.nextPage/.test(src))
  ok('toplist first-page hasMore follows parsed ptt nextPage',
    /return list\.nextPage >= 0 && list\.nextPage <= list\.maxPage/.test(src))
  ok('toplist loadMore requests parsed nextPage instead of hand-computing current page + 1',
    /const requestedPage: number = this\.toplistNextPage/.test(src) &&
    /this\.buildQuery\('', requestedPage\)/.test(src) &&
    !/this\.toplistPage \+ 1/.test(src))
  ok('toplist loadMore advances only from the parsed response nextPage',
    /this\.toplistNextPage = list\.nextPage[\s\S]*this\.hasMore = list\.nextPage >= 0 && list\.nextPage <= this\.maxPage/.test(src) &&
    !/this\.hasMore = [^\n]*fresh\.length > 0/.test(/private async loadMoreToplist\(\): Promise<void> \{[\s\S]*?\n  \}\n\n  canLoadMore/.exec(src)?.[0] ?? ''))
  const apiSrc = readFileSync(join(ROOT, 'shared/src/main/ets/network/EhApiService.ets'), 'utf8')
  ok('toplist network request omits page param until a parsed page is requested',
    /const pageParam: string = query\.page >= 0 \? `&p=\$\{query\.page\}` : ''[\s\S]*toplist\.php\?tl=\$\{query\.tl\}\$\{pageParam\}/.test(apiSrc))
  const homeSourceStateSrc = readFileSync(join(ROOT, 'shared/src/main/ets/state/HomeSourceState.ets'), 'utf8')
  const indexSrc = readFileSync(join(ROOT, 'entry/src/main/ets/pages/Index.ets'), 'utf8')
  const sourcePageSrc = readFileSync(join(ROOT, 'feature/home/src/main/ets/components/GallerySourcePage.ets'), 'utf8')
  const toplistPageSrc = readFileSync(join(ROOT, 'feature/home/src/main/ets/components/ToplistPeriodPage.ets'), 'utf8')
  ok('gallery back-to-top has a dedicated first-page command instead of reusing pull refresh',
    /publishJumpGalleryFirstPage\(\)/.test(homeSourceStateSrc) &&
    /private galleryBackToTopMenuItem\(\): Record<string, Object> \{[\s\S]*HomeSourceBridge\.publishJumpGalleryFirstPage\(\)/.test(indexSrc))
  ok('active gallery page owns first-page command handling',
    /this\.homeSource\.cmdKind === 'jumpGalleryFirstPage'[\s\S]*this\.jumpToFirstPage\(\)/.test(sourcePageSrc))
  ok('date-jump mode back-to-top reloads page 1 instead of prepending another prev page',
    /shouldJumpGalleryFirstPage\(\): boolean \{[\s\S]*return this\.afterDateJump/.test(src) &&
    /async jumpGalleryFirstPage\(\): Promise<boolean> \{[\s\S]*await this\.reload\(\)/.test(src) &&
    /this\.vm\.shouldJumpGalleryFirstPage\(\)[\s\S]*this\.vm\.jumpGalleryFirstPage\(\)/.test(sourcePageSrc))
  ok('retained gallery source forces a fresh first page for account/site/profile context changes',
    /@Monitor\('auth\.memberId'\)[\s\S]*this\.vm\.reload\(true\)/.test(sourcePageSrc) &&
    /@Monitor\('siteMode\.isEx'\)[\s\S]*this\.vm\.reload\(true\)/.test(sourcePageSrc) &&
    /source_profile_reload[\s\S]*this\.vm\.reload\(true\)/.test(sourcePageSrc))
  ok('retained toplist period forces a fresh first page for account/site context changes',
    /@Monitor\('auth\.memberId'\)[\s\S]*this\.vm\.reload\(true\)/.test(toplistPageSrc) &&
    /@Monitor\('siteMode\.isEx'\)[\s\S]*this\.vm\.reload\(true\)/.test(toplistPageSrc))
}

// 12. cross-cutting: every paged ViewModel carries the same race guards as Home, while the
// Favorites VM may use FE's page+from pagination instead of only nextGid.
// (a) epoch (loadMore-vs-reset) guard — a reset path runs without the isLoadingMore guard, so an
//     in-flight loadMore could contaminate the new list on favcat/query/source switch.
// (b) gid-dedup guard — EH repeats the boundary gallery across cursor pages and the LazyForEach key
//     is gid, so an undeduped append injects a duplicate key (churn/throw) and hasMore based on the
//     raw page length loops forever on an all-duplicate page.
// Both races are shared across all three VMs; fixing only Home would leave Favorites/Search broken.
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
    ok(`${name}: discards stale page on its ownership boundary`,
      name === 'GalleryListViewModel.ets'
        ? /isCurrentPagingRun\(run\)/.test(src)
        : /if \(this\.epoch === myEpoch\)/.test(src))
    ok(`${name}: bumps epoch on reset`, /this\.epoch = this\.epoch \+ 1/.test(src))
    ok(`${name}: declares dedupeNew helper`, /private dedupeNew\(rows: EhGallery\[\]\): EhGallery\[\]/.test(src))
    ok(`${name}: dedupes new rows by gid before append`, /this\.dedupeNew\(list\.gallerys\)/.test(src))
    ok(`${name}: automatic load-more is disabled while footer error is visible`,
      /canLoadMore\(\): boolean \{[\s\S]*return this\.hasMore && !this\.isLoadingMore && this\.errorMessage\.length === 0/.test(src))
    if (name === 'FavoritesViewModel.ets') {
      ok(`${name}: favorites paging is based on page/cursor progress, not dedupe count`,
        /this\.hasMore = this\.didPagingAdvance\(page, cursor, list\)/.test(src) &&
        !/this\.hasMore = [^\n]*fresh\.length > 0/.test(src))
      ok(`${name}: repeated request guard is bypassed for visible footer error retry`,
        /if \(requestKey === this\.lastNext && this\.errorMessage\.length === 0\) \{[\s\S]*this\.hasMore = false/.test(loadMore))
    } else if (name === 'SearchViewModel.ets') {
      ok(`${name}: declares stale-cursor history`,
        /private lastNext: string = ''/.test(src))
      ok(`${name}: captures requested cursor before fetch`,
        /const requestedNext: string = this\.nextGid/.test(loadMore))
      ok(`${name}: keeps failed cursor retryable`,
        !/this\.lastNext = requestedNext/.test(loadMore.slice(0, loadMore.indexOf('const list: GalleryList'))))
      ok(`${name}: commits lastNext only after successful epoch-valid apply`,
        /if \(this\.epoch === myEpoch\) \{[\s\S]*this\.nextGid = list\.nextGid[\s\S]*this\.lastNext = requestedNext/.test(loadMore))
      ok(`${name}: fetches the captured requested cursor`,
        /this\.fetchPage\(requestedNext\)/.test(loadMore))
      ok(`${name}: repeated cursor guard is bypassed for visible footer error retry`,
        /if \(requestedNext === this\.lastNext && this\.errorMessage\.length === 0\) \{[\s\S]*this\.hasMore = false/.test(loadMore))
      ok(`${name}: exhausted on no-fresh rows`, /list\.nextGid\.length > 0 && fresh\.length > 0/.test(src))
    } else {
      ok(`${name}: repeated cursor guard is bypassed for visible footer error retry`,
        /if \(requestedNext === this\.lastNext && this\.errorMessage\.length === 0\) \{[\s\S]*this\.hasMore = false/.test(loadMore))
      ok(`${name}: exhausted on no-fresh rows`, /list\.nextGid\.length > 0 && fresh\.length > 0/.test(src))
    }
  }
}

console.log(`✓ gallery paging contract: ${passed} assertions passed`)

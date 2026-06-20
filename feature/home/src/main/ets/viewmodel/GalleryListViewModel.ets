import {
  EhApiService,
  EhGallery,
  GalleryList,
  GalleryListQuery,
  BasicDataSource,
  connectSiteMode,
  DiagnosticLogger,
  EhErrorText,
} from 'shared'

/**
 * Drives one gallery-list source (V2Next FeedViewModel pattern). Rows live in a stable
 * LazyForEach `dataSource` (out of @Trace); `itemCount` mirrors its count as @Trace so the
 * page's loading→list branch re-evaluates. Cursor paging uses the parsed `nextGid`.
 */
@ObservedV2
export class GalleryListViewModel {
  // Stable ref; LazyForEach subscribes to its listeners directly, so NOT @Trace.
  dataSource: BasicDataSource<EhGallery> = new BasicDataSource<EhGallery>()
  @Trace itemCount: number = 0
  @Trace isLoading: boolean = false
  @Trace isLoadingMore: boolean = false
  @Trace hasMore: boolean = true
  @Trace errorMessage: string = ''
  // True once this source/key has COMPLETED its first load (success or error). A never-loaded key must
  // render the content-area loading state, never a terminal empty/no-more flash, before that first load —
  // `isLoading` alone leaves a frame where the key is mounted but the load hasn't flipped it true yet.
  @Trace loaded: boolean = false
  // Home source: '' front page / 'popular' / 'watched' (login-only). @Trace so the switcher row re-renders.
  @Trace source: string = ''
  private nextGid: string = ''
  // Last cursor handed to loadMore (eros_fe lastNext): bail if it didn't advance — the parsed page
  // repeated, so refetching would loop the same rows. Reset whenever the list reloads from page 1.
  private lastNext: string = ''
  // Generation token: reload()/setSource()/refresh() bump it so an in-flight loadMore that resumes
  // afterwards discards its (now cross-source/cross-host) result instead of corrupting the new list.
  private epoch: number = 0
  // Toplist (排行) is PAGE-paged (table.ptt), not gid-cursored: toplistTl = period, toplistPage =
  // current 0-based page, maxPage = last page index parsed from the ptt. toplistTl is @Trace so the
  // period selector row reflects the active period (11 all-time / 12 year / 13 month / 15 yesterday).
  @Trace toplistTl: number = 15
  private toplistPage: number = 0
  private maxPage: number = 0

  // EH 'popular' is a single fixed snapshot with no cursor — it never pages (eros_fe popular tab).
  private isPopular(): boolean {
    return this.source === 'popular'
  }

  private isToplist(): boolean {
    return this.source === 'toplist'
  }

  /**
   * Drop rows already in the list (and dupes within the incoming page) before append. EH can repeat
   * the boundary gallery across page boundaries, and the LazyForEach key is gid — duplicate keys
   * would churn/throw. eros_fe tolerates dupes via index keys; a gid-keyed list must filter them.
   */
  private dedupeNew(rows: EhGallery[]): EhGallery[] {
    const seen: Set<string> = new Set<string>()
    this.dataSource.getAll().forEach((g: EhGallery) => seen.add(g.gid))
    const out: EhGallery[] = []
    rows.forEach((g: EhGallery) => {
      if (g.gid.length > 0 && !seen.has(g.gid)) {
        seen.add(g.gid)
        out.push(g)
      }
    })
    return out
  }

  private buildQuery(next: string, page: number = 0): GalleryListQuery {
    return {
      isEx: connectSiteMode().isEx,
      source: this.source,
      next: next,
      tl: this.isToplist() ? this.toplistTl : 0,
      page: page,
      fCats: 0,
      search: '',
      advancedEnabled: true,
      minRating: 0,
      pagesFrom: 0,
      pagesTo: 0,
      requireTorrent: false,
      showExpunged: false,
      disableLanguageFilter: false,
      disableUploaderFilter: false,
      disableTagFilter: false,
    }
  }

  /**
   * Seed source/period from the shared HomeSourceState holder on (re)mount, WITHOUT reloading —
   * loadData() runs right after. The pinned source bar is the single source of truth; this keeps a
   * freshly-constructed VM aligned with a holder that may already have been changed.
   */
  syncSource(source: string, tl: number): void {
    this.source = source
    this.toplistTl = tl
  }

  /** Switch the home source (默认/热门/排行/订阅) and hard-reload from its first page. No-op if unchanged. */
  async setSource(source: string): Promise<void> {
    if (this.source === source) {
      return
    }
    this.source = source
    await this.reload()
  }

  /** Switch the toplist period (tl 11 all-time / 12 year / 13 month / 15 yesterday) and hard-reload
   * from page 0. No-op if unchanged or not on the toplist source. */
  async setToplistPeriod(tl: number): Promise<void> {
    if (!this.isToplist() || this.toplistTl === tl) {
      return
    }
    this.toplistTl = tl
    await this.reload()
  }

  /** First load (skips if already populated). */
  async loadData(): Promise<void> {
    if (this.isLoading || this.itemCount > 0) {
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(this.buildQuery(''))
      this.dataSource.setData(list.gallerys)
      this.itemCount = this.dataSource.totalCount()
      this.nextGid = list.nextGid
      this.maxPage = list.maxPage
      this.toplistPage = 0
      this.hasMore = this.firstPageHasMore(list)
    } catch (err) {
      const e = err as Error
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('home', 'list_load_failed', e.message)
    }
    this.isLoading = false
    this.loaded = true
  }

  // Whether a fresh first-page load has more: toplist pages while page 0 < maxPage; cursor sources
  // page while a next cursor exists (popular never pages).
  private firstPageHasMore(list: GalleryList): boolean {
    if (this.isToplist()) {
      return list.maxPage > 0
    }
    return !this.isPopular() && list.nextGid.length > 0
  }

  /**
   * Reload the first page for a selector/site/period change without blanking the current body first.
   * The pinned selector may update immediately, but the old rows stay visible until the new page lands;
   * this avoids the white-screen remount regression while still invalidating stale loadMore results.
   */
  async reload(): Promise<void> {
    if (this.isLoading) {
      return
    }
    // Invalidate any in-flight loadMore (it runs without the isLoading flag, so it can overlap a
    // site/source switch) and drop the old cursor immediately, but keep old rows rendered until the
    // replacement page succeeds. On failure, loadMore remains disabled instead of mixing sources.
    this.epoch = this.epoch + 1
    this.isLoading = true
    this.errorMessage = ''
    this.nextGid = ''
    this.lastNext = ''
    this.toplistPage = 0
    this.maxPage = 0
    this.hasMore = false
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(this.buildQuery(''))
      this.dataSource.setData(list.gallerys)
      this.itemCount = this.dataSource.totalCount()
      this.nextGid = list.nextGid
      this.maxPage = list.maxPage
      this.toplistPage = 0
      this.hasMore = this.firstPageHasMore(list)
    } catch (err) {
      const e = err as Error
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('home', 'list_reload_failed', e.message)
    }
    this.isLoading = false
    this.loaded = true
  }

  /** Pull-to-refresh: replace from the first page. Guarded + flagged isLoading so a concurrent
   * loadMore (which checks isLoading) can't interleave its appendData with this setData. */
  async refresh(): Promise<void> {
    if (this.isLoading || this.isLoadingMore) {
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    // Refresh replaces from page 1, so the cursor history resets and any in-flight loadMore is void.
    this.lastNext = ''
    this.epoch = this.epoch + 1
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(this.buildQuery(''))
      this.dataSource.setData(list.gallerys)
      this.itemCount = this.dataSource.totalCount()
      this.nextGid = list.nextGid
      this.maxPage = list.maxPage
      this.toplistPage = 0
      this.hasMore = this.firstPageHasMore(list)
    } catch (err) {
      const e = err as Error
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('home', 'list_refresh_failed', e.message)
    }
    this.isLoading = false
  }

  /** Append the next page at the cursor, with eros_fe's stale-cursor + (gid-keyed) dedup guards. */
  async loadMore(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || !this.hasMore || this.isPopular()) {
      return
    }
    if (this.isToplist()) {
      await this.loadMoreToplist()
      return
    }
    // Stale-cursor guard (eros_fe lastNext == next): no cursor, or it didn't advance since the last
    // page → stop instead of refetching the same rows. Marks the list exhausted.
    if (this.nextGid.length === 0 || this.nextGid === this.lastNext) {
      this.hasMore = false
      return
    }
    this.isLoadingMore = true
    this.lastNext = this.nextGid
    const myEpoch: number = this.epoch
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(
        this.buildQuery(this.nextGid),
      )
      // A reload/refresh/source-switch happened while this fetch was in flight → its rows belong to
      // the OLD source/host. Drop them (the new list already replaced everything); only clear the
      // in-flight flag below.
      if (this.epoch === myEpoch) {
        const fresh: EhGallery[] = this.dedupeNew(list.gallerys)
        if (fresh.length > 0) {
          this.dataSource.appendData(fresh)
          this.itemCount = this.dataSource.totalCount()
        }
        this.nextGid = list.nextGid
        // Exhausted when the cursor is empty OR the page brought no genuinely new rows (server race /
        // repeated boundary page) — guards against an infinite same-page loadMore loop.
        this.hasMore = list.nextGid.length > 0 && fresh.length > 0
      }
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('home', 'list_loadmore_failed', e.message)
    }
    this.isLoadingMore = false
  }

  /** Toplist page paging: fetch the next 0-based page (?p=), dedup-append, stop at maxPage. */
  private async loadMoreToplist(): Promise<void> {
    const nextPage: number = this.toplistPage + 1
    if (nextPage > this.maxPage) {
      this.hasMore = false
      return
    }
    this.isLoadingMore = true
    const myEpoch: number = this.epoch
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(
        this.buildQuery('', nextPage),
      )
      if (this.epoch === myEpoch) {
        const fresh: EhGallery[] = this.dedupeNew(list.gallerys)
        if (fresh.length > 0) {
          this.dataSource.appendData(fresh)
          this.itemCount = this.dataSource.totalCount()
        }
        this.toplistPage = nextPage
        this.hasMore = nextPage < this.maxPage && fresh.length > 0
      }
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('home', 'toplist_loadmore_failed', e.message)
    }
    this.isLoadingMore = false
  }

  canLoadMore(): boolean {
    return this.hasMore && !this.isLoadingMore
  }

  applyFavoriteMutation(gid: string, favcat: string, favTitle: string): void {
    if (gid.length === 0 || this.itemCount === 0) {
      return
    }
    const current: EhGallery[] = this.dataSource.getAll()
    let changed: boolean = false
    const nextRows: EhGallery[] = []
    current.forEach((g: EhGallery) => {
      if (g.gid === gid) {
        const next: EhGallery = g.copy()
        next.favcat = favcat
        next.favTitle = favTitle
        nextRows.push(next)
        changed = true
      } else {
        nextRows.push(g)
      }
    })
    if (changed) {
      this.dataSource.setData(nextRows)
      this.itemCount = this.dataSource.totalCount()
    }
  }
}

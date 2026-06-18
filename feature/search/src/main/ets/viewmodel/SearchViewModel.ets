import {
  EhApiService,
  EhGallery,
  GalleryList,
  GalleryListQuery,
  FavoritesQuery,
  EhConstants,
  BasicDataSource,
  connectSiteMode,
  connectSearchFilter,
  SearchFilterState,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_WATCHED,
  DiagnosticLogger,
  EhErrorText,
} from 'shared'

/**
 * Table-site anonymous gallery search (reuses the list endpoint with f_search). Same
 * BasicDataSource + @Trace itemCount pattern as GalleryListViewModel; `hasSearched` gates
 * the initial "type to search" empty state.
 */
@ObservedV2
export class SearchViewModel {
  dataSource: BasicDataSource<EhGallery> = new BasicDataSource<EhGallery>()
  @Trace itemCount: number = 0
  @Trace isLoading: boolean = false
  @Trace isLoadingMore: boolean = false
  @Trace hasMore: boolean = true
  @Trace hasSearched: boolean = false
  @Trace errorMessage: string = ''
  private query: string = ''
  private nextGid: string = ''
  // Generation token: a new search / filter re-apply / refresh bumps it so an in-flight loadMore
  // that resumes afterwards discards its now-stale (old-query) page instead of mixing it in.
  // search() runs without the isLoadingMore guard, so it can overlap a loadMore.
  private epoch: number = 0
  // Favorite scope (eros_fe SearchType.favorite, search_page_controller.dart:240): when set, the page
  // searches favorites.php f_search instead of the gallery list. Seeded from the route param when the
  // favorites title-bar magnifier pushes here; an empty query browses the favcat (favorites.php allows
  // no f_search). The normal gallery path is untouched when this is false.
  @Trace isFavoriteScope: boolean = false
  private favcat: string = 'a'
  private favOrder: string = EhConstants.FAV_ORDER_FAV

  /** Switch this VM into favorites scope (favorites.php f_search). favcat 'a' = all favorites. */
  seedFavoriteScope(favcat: string): void {
    this.isFavoriteScope = true
    this.favcat = favcat.length > 0 ? favcat : 'a'
  }

  private buildFavQuery(next: string): FavoritesQuery {
    return {
      isEx: connectSiteMode().isEx,
      favcat: this.isFavoriteScope ? this.favcat : 'a',
      next: next,
      search: this.query,
      order: this.favOrder,
    }
  }

  private effectiveFavoriteScope(): boolean {
    return this.isFavoriteScope || connectSearchFilter().searchScope === SEARCH_SCOPE_FAVORITE
  }

  // Fetch one page in the active scope: favorites.php (favorite scope) or the gallery list (normal).
  // Both return GalleryList (.gallerys + .nextGid), so all the dataSource/paging plumbing is shared.
  private fetchPage(next: string): Promise<GalleryList> {
    return this.effectiveFavoriteScope()
      ? EhApiService.getInstance().getFavoritesList(this.buildFavQuery(next))
      : EhApiService.getInstance().getGalleryList(this.buildQuery(next))
  }

  private buildQuery(next: string): GalleryListQuery {
    const f: SearchFilterState = connectSearchFilter()
    return {
      isEx: connectSiteMode().isEx,
      source: f.searchScope === SEARCH_SCOPE_WATCHED ? 'watched' : '',
      next: next,
      tl: 0,
      page: 0,
      fCats: f.fCats(),
      search: this.query,
      minRating: f.minRating,
      pagesFrom: f.pagesFrom,
      pagesTo: f.pagesTo,
      requireTorrent: f.requireTorrent,
      showExpunged: f.showExpunged,
      disableLanguageFilter: f.disableLanguageFilter,
      disableUploaderFilter: f.disableUploaderFilter,
      disableTagFilter: f.disableTagFilter,
    }
  }

  /** Re-run the current query with the latest filters (called when the filter sheet applies). */
  async reapplyFilters(): Promise<void> {
    // Re-run when there's a query OR the filters alone can drive a browse (category-only search).
    if (this.query.length > 0 || connectSearchFilter().isActive()) {
      await this.search(this.query)
    }
  }

  async search(query: string): Promise<void> {
    const trimmed: string = query.trim()
    // An empty query is allowed to browse by active advanced filters (category-only browse, a NextE
    // enhancement — EH supports /?f_cats=… without a keyword) OR in favorite scope (favorites.php with
    // no f_search browses the whole favcat, eros_fe parity).
    if (
      this.isLoading ||
      (trimmed.length === 0 && !this.isFavoriteScope && !connectSearchFilter().isActive())
    ) {
      return
    }
    this.query = trimmed
    this.hasSearched = true
    this.isLoading = true
    this.errorMessage = ''
    this.epoch = this.epoch + 1
    // Preserve current results while the new query/filter request is in flight. The search field or
    // filter sheet may change immediately, but the body must not flash to an empty loading page.
    // Disable old paging until the replacement page succeeds.
    this.nextGid = ''
    this.hasMore = false
    try {
      const list: GalleryList = await this.fetchPage('')
      this.dataSource.setData(list.gallerys)
      this.itemCount = this.dataSource.totalCount()
      this.nextGid = list.nextGid
      this.hasMore = list.nextGid.length > 0
    } catch (err) {
      const e = err as Error
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('search', 'search_failed', e.message)
    }
    this.isLoading = false
  }

  /** Re-run the current query from page 1 (pull-to-refresh). Guarded + flagged isLoading so a
   * concurrent loadMore (which checks isLoading) can't interleave its appendData with this setData. */
  async refresh(): Promise<void> {
    // Allow refresh for a filter-only browse too (empty query but active filters), so pull-to-refresh
    // and the error-retry button work there — mirrors the search()/reapplyFilters() guards.
    if (
      (this.query.length === 0 && !this.isFavoriteScope && !connectSearchFilter().isActive()) ||
      this.isLoading ||
      this.isLoadingMore
    ) {
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    this.epoch = this.epoch + 1
    try {
      const list: GalleryList = await this.fetchPage('')
      this.dataSource.setData(list.gallerys)
      this.itemCount = this.dataSource.totalCount()
      this.nextGid = list.nextGid
      this.hasMore = list.nextGid.length > 0
    } catch (err) {
      const e = err as Error
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('search', 'search_refresh_failed', e.message)
    }
    this.isLoading = false
  }

  /**
   * Drop rows already in the list (and intra-page dupes / empty gids) before append. EH repeats the
   * boundary gallery across cursor page boundaries and the LazyForEach key is gid, so a duplicate gid
   * would churn/throw. Mirrors GalleryListViewModel.dedupeNew (the home VM's gid-keyed list guard).
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

  async loadMore(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || !this.hasMore || !this.hasSearched) {
      return
    }
    this.isLoadingMore = true
    const myEpoch: number = this.epoch
    try {
      const list: GalleryList = await this.fetchPage(this.nextGid)
      // A new search / filter re-apply / refresh landed while this fetch was in flight → these rows
      // are for the OLD query. Drop them rather than mixing them into the new results.
      if (this.epoch === myEpoch) {
        const fresh: EhGallery[] = this.dedupeNew(list.gallerys)
        if (fresh.length > 0) {
          this.dataSource.appendData(fresh)
          this.itemCount = this.dataSource.totalCount()
        }
        this.nextGid = list.nextGid
        // Exhausted when the cursor is empty OR the page brought no genuinely-new rows (repeated
        // boundary page) — without this an all-duplicate page keeps hasMore true and loops loadMore.
        this.hasMore = list.nextGid.length > 0 && fresh.length > 0
      }
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('search', 'search_loadmore_failed', e.message)
    }
    this.isLoadingMore = false
  }

  canLoadMore(): boolean {
    return this.hasMore && !this.isLoadingMore
  }
}

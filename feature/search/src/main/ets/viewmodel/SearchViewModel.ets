import {
  EhApiPhpService,
  EhApiService,
  EhGallery,
  EhTagSuggestion,
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

const TAG_SUGGEST_DELAY_MS: number = 450

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
  @Trace suggestionCount: number = 0
  @Trace isSuggesting: boolean = false
  suggestions: EhTagSuggestion[] = []
  private query: string = ''
  private nextGid: string = ''
  // Generation token: a new search / filter re-apply / refresh bumps it so an in-flight loadMore
  // that resumes afterwards discards its now-stale (old-query) page instead of mixing it in.
  // search() runs without the isLoadingMore guard, so it can overlap a loadMore.
  private epoch: number = 0
  private pendingFilterReapply: boolean = false
  private pendingSearchQuery: string = ''
  private suggestTimer: number = -1
  private suggestEpoch: number = 0
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
      advancedEnabled: f.advancedEnabled,
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

  private lastSuggestToken(query: string): string {
    const trimmed: string = query.trim()
    if (trimmed.length === 0 || trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return ''
    }
    const parts: string[] = trimmed.split(/[ ;"]/)
    const token: string = parts.length > 0 ? parts[parts.length - 1].trim() : ''
    if (token.indexOf(':') >= 0 || token.endsWith('$')) {
      return ''
    }
    return token
  }

  scheduleTagSuggest(query: string): void {
    if (this.suggestTimer >= 0) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    const token: string = this.lastSuggestToken(query)
    this.suggestEpoch = this.suggestEpoch + 1
    const myEpoch: number = this.suggestEpoch
    if (token.length === 0) {
      this.clearSuggestions()
      return
    }
    this.isSuggesting = true
    this.suggestTimer = setTimeout(() => {
      this.fetchSuggestions(token, myEpoch)
    }, TAG_SUGGEST_DELAY_MS)
  }

  clearSuggestions(): void {
    if (this.suggestTimer >= 0) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    this.suggestEpoch = this.suggestEpoch + 1
    this.suggestions = []
    this.suggestionCount = 0
    this.isSuggesting = false
  }

  private async fetchSuggestions(token: string, epoch: number): Promise<void> {
    try {
      const rows: EhTagSuggestion[] = await EhApiPhpService.tagSuggest(
        EhConstants.baseUrl(connectSiteMode().isEx),
        token,
      )
      if (this.suggestEpoch === epoch) {
        this.suggestions = rows
        this.suggestionCount = rows.length
      }
    } catch (err) {
      const e = err as Error
      if (this.suggestEpoch === epoch) {
        this.suggestions = []
        this.suggestionCount = 0
      }
      DiagnosticLogger.warn('search', 'tagsuggest_failed', e.message)
    }
    if (this.suggestEpoch === epoch) {
      this.isSuggesting = false
    }
  }

  /** Re-run the current query with the latest filters (called when the filter sheet live-edits). */
  async reapplyFilters(): Promise<void> {
    // Ordinary search does not implicitly browse with an empty query. Favorite scope is the explicit
    // empty-query browse entry (favorites title-bar search), so it remains allowed.
    const canSearch: boolean = this.query.length > 0 || this.isFavoriteScope
    if (!canSearch) {
      this.dataSource.clear()
      this.itemCount = 0
      this.nextGid = ''
      this.hasMore = true
      this.hasSearched = false
      this.errorMessage = ''
      return
    }
    if (this.isLoading) {
      this.pendingFilterReapply = true
      return
    }
    await this.search(this.query)
  }

  async search(query: string): Promise<void> {
    const trimmed: string = query.trim()
    // Empty ordinary search returns to history; only explicit favorite scope browses without f_search.
    if (trimmed.length === 0 && !this.isFavoriteScope) {
      return
    }
    if (this.isLoading) {
      this.pendingSearchQuery = trimmed
      return
    }
    this.clearSuggestions()
    this.query = trimmed
    this.hasSearched = true
    this.isLoading = true
    this.errorMessage = ''
    this.epoch = this.epoch + 1
    const myEpoch: number = this.epoch
    // Preserve current results while the new query/filter request is in flight. The search field or
    // filter sheet may change immediately, but the body must not flash to an empty loading page.
    // Disable old paging until the replacement page succeeds.
    this.nextGid = ''
    this.hasMore = false
    try {
      const list: GalleryList = await this.fetchPage('')
      if (this.epoch === myEpoch) {
        this.dataSource.setData(list.gallerys)
        this.itemCount = this.dataSource.totalCount()
        this.nextGid = list.nextGid
        this.hasMore = list.nextGid.length > 0
      }
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('search', 'search_failed', e.message)
    }
    if (this.epoch === myEpoch) {
      this.isLoading = false
      if (this.pendingSearchQuery.length > 0 && this.pendingSearchQuery !== this.query) {
        const nextQuery: string = this.pendingSearchQuery
        this.pendingSearchQuery = ''
        this.pendingFilterReapply = false
        await this.search(nextQuery)
        return
      }
      this.pendingSearchQuery = ''
      if (this.pendingFilterReapply) {
        this.pendingFilterReapply = false
        await this.reapplyFilters()
      }
    }
  }

  clearSearchState(): void {
    this.epoch = this.epoch + 1
    this.query = ''
    this.nextGid = ''
    this.dataSource.clear()
    this.itemCount = 0
    this.isLoading = false
    this.isLoadingMore = false
    this.hasMore = true
    this.hasSearched = false
    this.errorMessage = ''
    this.pendingFilterReapply = false
    this.pendingSearchQuery = ''
    this.clearSuggestions()
  }

  /** Re-run the current query from page 1 (pull-to-refresh). Guarded + flagged isLoading so a
   * concurrent loadMore (which checks isLoading) can't interleave its appendData with this setData. */
  async refresh(): Promise<void> {
    // Empty ordinary search has no network state to refresh; favorite scope is an explicit browse.
    if (
      (this.query.length === 0 && !this.isFavoriteScope) ||
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

  applyFavoriteMutation(gid: string, favcat: string, favTitle: string): void {
    if (gid.length === 0 || this.itemCount === 0) {
      return
    }
    const current: EhGallery[] = this.dataSource.getAll()
    let changed: boolean = false
    const nextRows: EhGallery[] = []
    current.forEach((g: EhGallery) => {
      if (g.gid === gid) {
        if (this.effectiveFavoriteScope() && favcat.length === 0) {
          changed = true
          return
        }
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
      if (this.effectiveFavoriteScope()) {
        this.hasMore = this.hasMore && this.itemCount > 0
      }
    }
  }
}

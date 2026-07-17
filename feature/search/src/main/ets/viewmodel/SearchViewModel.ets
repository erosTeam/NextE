import {
  EhApiPhpService,
  EhApiService,
  EhGallery,
  EhTagSuggestion,
  TagTranslationService,
  connectTagTranslationSettings,
  GalleryList,
  GalleryListQuery,
  FavoritesQuery,
  Favcat,
  FavcatSlotResolver,
  FavcatSlotResolveResult,
  connectFavSelection,
  EhConstants,
  GalleryCoverPrefetchDataSource,
  connectSiteMode,
  connectSearchFilter,
  SearchFilterState,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_GALLERY,
  SEARCH_SCOPE_WATCHED,
  DiagnosticLogger,
  EhErrorText,
  LocalBlockService,
} from 'shared'
import { common } from '@kit.AbilityKit'

const TAG_SUGGEST_DELAY_MS: number = 450
const LOCAL_TAG_SUGGEST_LIMIT: number = 200

/**
 * Table-site anonymous gallery search (reuses the list endpoint with f_search). Same
 * BasicDataSource + @Trace itemCount pattern as GalleryListViewModel; `hasSearched` gates
 * the initial "type to search" empty state.
 */
@ObservedV2
export class SearchViewModel {
  dataSource: GalleryCoverPrefetchDataSource = new GalleryCoverPrefetchDataSource()
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
  // Last cursor that successfully made it through loadMore. Mirrors GalleryListViewModel's
  // stale-cursor guard so a failed footer retry never poisons the next manual retry.
  private lastNext: string = ''
  // Generation token: a new search / filter re-apply / refresh bumps it so an in-flight loadMore
  // that resumes afterwards discards its now-stale (old-query) page instead of mixing it in.
  // search() runs without the isLoadingMore guard, so it can overlap a loadMore.
  private epoch: number = 0
  // A clear/new search can release the visible loading-more flag before its old request settles. The
  // owner token prevents that old completion from clearing a newer pagination request's flag.
  private loadMoreRun: number = 0
  // Tag translation reads from RDB asynchronously. Each reapply captures a list snapshot so an older
  // translation cannot replace rows that search, paging, filtering, or a later toggle already changed.
  private tagTranslationRun: number = 0
  private pendingFilterReapply: boolean = false
  private pendingSearchQuery: string = ''
  private suggestTimer: number = -1
  private suggestEpoch: number = 0
  // Request target belongs to this Search page session. Route seeding and filter changes both update
  // this one value, so a favorites entry can later switch to gallery/watched without a route override.
  private scope: string = SEARCH_SCOPE_GALLERY
  private favcat: string = 'a'
  private favOrder: string = EhConstants.FAV_ORDER_FAV
  private context: common.UIAbilityContext | null = null

  setContext(context: common.UIAbilityContext): void {
    this.context = context
  }

  isCurrentQuery(query: string): boolean {
    return this.query.length > 0 && this.query === query.trim()
  }

  setScope(scope: string, favcat: string = 'a'): void {
    this.scope = scope
    this.favcat = favcat.length > 0 ? favcat : 'a'
  }

  private buildFavQuery(next: string): FavoritesQuery {
    return {
      isEx: connectSiteMode().isEx,
      favcat: this.favcat,
      next: next,
      prev: '',
      seek: '',
      page: -1,
      from: '',
      search: this.query,
      order: this.favOrder,
    }
  }

  // Fetch one page in the active scope: favorites.php (favorite scope) or the gallery list (normal).
  // Both return GalleryList (.gallerys + .nextGid), so all the dataSource/paging plumbing is shared.
  private fetchPage(next: string): Promise<GalleryList> {
    return this.scope === SEARCH_SCOPE_FAVORITE
      ? EhApiService.getInstance().getFavoritesList(this.buildFavQuery(next))
      : EhApiService.getInstance().getGalleryList(this.buildQuery(next))
  }

  private resolveFavoriteSlots(gallerys: EhGallery[], favcats: Favcat[]): void {
    // Favorites search responses can omit the active slot from the selector metadata. Resolve from
    // response-local metadata first, then fill any remaining title-only rows from the active
    // account's restored snapshot. The late-change monitor still covers metadata arriving later.
    FavcatSlotResolver.applyInPlace(gallerys, favcats)
    FavcatSlotResolver.applyInPlace(gallerys, connectFavSelection().favList)
  }

  private async translateRows(rows: EhGallery[]): Promise<EhGallery[]> {
    if (this.context === null || !connectTagTranslationSettings().enabled) {
      return rows
    }
    return TagTranslationService.translateGalleries(this.context, rows)
  }

  async reapplyTagTranslation(): Promise<void> {
    this.tagTranslationRun = this.tagTranslationRun + 1
    const run: number = this.tagTranslationRun
    const enabled: boolean = connectTagTranslationSettings().enabled
    const sourceRows: EhGallery[] = this.dataSource.getAll()
    const sourceCount: number = sourceRows.length
    const sourceRevision: number = this.dataSource.contentRevision()
    if (sourceCount === 0) {
      return
    }
    const snapshot: EhGallery[] = sourceRows.slice()
    const rows: EhGallery[] = enabled
      ? await this.translateRows(snapshot)
      : TagTranslationService.clearGalleriesTranslations(snapshot)
    if (
      run !== this.tagTranslationRun ||
      enabled !== connectTagTranslationSettings().enabled ||
      this.dataSource.getAll() !== sourceRows ||
      this.dataSource.totalCount() !== sourceCount ||
      this.dataSource.contentRevision() !== sourceRevision
    ) {
      return
    }
    this.dataSource.setData(rows)
    this.itemCount = this.dataSource.totalCount()
  }

  reapplyLocalBlockRules(): void {
    if (this.itemCount === 0) {
      return
    }
    const rows: EhGallery[] = LocalBlockService.filterGalleries(this.dataSource.getAll())
    if (rows.length === this.itemCount) {
      return
    }
    this.dataSource.setData(rows)
    this.itemCount = this.dataSource.totalCount()
  }

  async applyLocalBlockChange(): Promise<void> {
    this.reapplyLocalBlockRules()
    if (this.hasSearched && this.query.length > 0) {
      await this.search(this.query)
    }
  }

  resolveVisibleFavoriteSlotsFrom(favcats: Favcat[]): boolean {
    if (this.itemCount === 0 || favcats.length === 0) {
      return false
    }
    const result: FavcatSlotResolveResult =
      FavcatSlotResolver.resolvedCopies(this.dataSource.getAll(), favcats)
    if (!result.changed) {
      return false
    }
    this.dataSource.setData(result.rows)
    this.itemCount = this.dataSource.totalCount()
    return true
  }

  private buildQuery(next: string): GalleryListQuery {
    const f: SearchFilterState = connectSearchFilter()
    return {
      isEx: connectSiteMode().isEx,
      source: this.scope === SEARCH_SCOPE_WATCHED ? 'watched' : '',
      next: next,
      prev: '',
      seek: '',
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
      applyToplistHiddenUserTags: false,
    }
  }

  private lastSuggestToken(query: string): string {
    const trimmed: string = query.trim()
    if (trimmed.length === 0 || trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return ''
    }
    const parts: string[] = trimmed.split(/[ ;]/)
    const token: string = parts.length > 0 ? parts[parts.length - 1].trim() : ''
    if (token.indexOf('$') >= 0) {
      return ''
    }
    return token
  }

  scheduleTagSuggest(query: string, context: common.UIAbilityContext): void {
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
      this.fetchSuggestions(context, token, myEpoch)
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

  private async fetchSuggestions(context: common.UIAbilityContext, token: string, epoch: number): Promise<void> {
    try {
      let localRows: EhTagSuggestion[] = []
      try {
        if (connectTagTranslationSettings().enabled) {
          localRows = await TagTranslationService.searchSuggestions(context, token, LOCAL_TAG_SUGGEST_LIMIT)
        }
      } catch (localErr) {
        const e = localErr as Error
        DiagnosticLogger.warn('search', 'tag_translation_suggest_failed', e.message)
      }
      if (this.suggestEpoch !== epoch) {
        return
      }
      if (localRows.length > 0) {
        this.suggestions = localRows
        this.suggestionCount = localRows.length
        this.isSuggesting = false
        return
      }
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
    // Search filter live edits only re-run an existing submitted query. Empty favorite scope is still
    // a compose/search entry, not an implicit favcat browse.
    const canSearch: boolean = this.query.length > 0
    if (!canSearch) {
      this.dataSource.clear()
      this.itemCount = 0
      this.nextGid = ''
      this.lastNext = ''
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
    // Empty search returns to history/blank. Filter-only or favorite-only browsing must be explicit.
    if (trimmed.length === 0) {
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
    this.lastNext = ''
    this.hasMore = false
    try {
      const list: GalleryList = await this.fetchPage('')
      this.resolveFavoriteSlots(list.gallerys, list.favList)
      const rows: EhGallery[] = await this.translateRows(list.gallerys)
      if (this.epoch === myEpoch) {
        this.dataSource.setData(rows)
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
    await this.finishCurrentRequest(myEpoch)
  }

  /**
   * Finish only the still-current first-page request. Search and pull-refresh share this drain because
   * either can receive a newer submitted query or filter change while it is awaiting the network.
   */
  private async finishCurrentRequest(myEpoch: number): Promise<void> {
    if (this.epoch !== myEpoch) {
      return
    }
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

  clearSearchState(): void {
    this.epoch = this.epoch + 1
    this.query = ''
    this.nextGid = ''
    this.lastNext = ''
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
    // Empty search has no network state to refresh.
    if (
      this.query.length === 0 ||
      this.isLoading ||
      this.isLoadingMore
    ) {
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    this.epoch = this.epoch + 1
    const myEpoch: number = this.epoch
    this.lastNext = ''
    try {
      const list: GalleryList = await this.fetchPage('')
      this.resolveFavoriteSlots(list.gallerys, list.favList)
      const rows: EhGallery[] = await this.translateRows(list.gallerys)
      if (this.epoch === myEpoch) {
        this.dataSource.setData(rows)
        this.itemCount = this.dataSource.totalCount()
        this.nextGid = list.nextGid
        this.hasMore = list.nextGid.length > 0
      }
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('search', 'search_refresh_failed', e.message)
    }
    await this.finishCurrentRequest(myEpoch)
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
    const requestedNext: string = this.nextGid
    if (requestedNext.length === 0) {
      this.hasMore = false
      return
    }
    if (requestedNext === this.lastNext && this.errorMessage.length === 0) {
      this.hasMore = false
      return
    }
    this.isLoadingMore = true
    this.loadMoreRun = this.loadMoreRun + 1
    const myLoadMoreRun: number = this.loadMoreRun
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    try {
      const list: GalleryList = await this.fetchPage(requestedNext)
      // A new search / filter re-apply / refresh landed while this fetch was in flight → these rows
      // are for the OLD query. Drop them rather than mixing them into the new results.
      if (this.epoch === myEpoch) {
        const fresh: EhGallery[] = await this.translateRows(this.dedupeNew(list.gallerys))
        // Translation can await disk/network work. A newer search, refresh, filter re-apply, or clear
        // may win while it is running, so never append this old cursor page after that boundary.
        if (this.epoch === myEpoch) {
          this.resolveFavoriteSlots(fresh, list.favList)
          if (fresh.length > 0) {
            this.dataSource.appendData(fresh)
            this.itemCount = this.dataSource.totalCount()
          }
          this.nextGid = list.nextGid
          this.lastNext = requestedNext
          // Exhausted when the cursor is empty OR the page brought no genuinely-new rows (repeated
          // boundary page) — without this an all-duplicate page keeps hasMore true and loops loadMore.
          this.hasMore = list.nextGid.length > 0 && fresh.length > 0
        }
      }
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('search', 'search_loadmore_failed', e.message)
    } finally {
      if (this.loadMoreRun === myLoadMoreRun) {
        this.isLoadingMore = false
      }
    }
  }

  canLoadMore(): boolean {
    return this.hasMore && !this.isLoadingMore && this.errorMessage.length === 0
  }

  applyFavoriteMutation(gid: string, favcat: string, favTitle: string): void {
    if (gid.length === 0 || this.itemCount === 0) {
      return
    }
    const current: EhGallery[] = this.dataSource.getAll()
    const favoriteScope: boolean = this.scope === SEARCH_SCOPE_FAVORITE
    let changed: boolean = false
    if (favoriteScope && favcat.length === 0) {
      for (let index: number = current.length - 1; index >= 0; index--) {
        if (current[index].gid === gid && this.dataSource.removeDataAt(index)) {
          changed = true
        }
      }
    } else {
      for (let index: number = 0; index < current.length; index++) {
        const g: EhGallery = current[index]
        if (g.gid !== gid) {
          continue
        }
        const next: EhGallery = g.copy()
        next.favcat = favcat
        next.favTitle = favTitle
        if (this.dataSource.replaceDataAt(index, next)) {
          changed = true
        }
      }
    }
    if (changed) {
      this.itemCount = this.dataSource.totalCount()
      if (favoriteScope) {
        this.hasMore = this.hasMore && this.itemCount > 0
      }
    }
  }

  applyRatingMutation(
    gid: string,
    userRating: number,
    averageRating: number,
    ratingCount: string,
    colorRating: string,
  ): void {
    if (gid.length === 0 || this.itemCount === 0) {
      return
    }
    const current: EhGallery[] = this.dataSource.getAll()
    for (let index: number = 0; index < current.length; index++) {
      const g: EhGallery = current[index]
      if (g.gid === gid) {
        const next: EhGallery = g.copy()
        next.ratingFallBack = userRating
        next.rating = averageRating
        next.ratingCount = ratingCount
        next.colorRating = colorRating
        next.isRated = true
        this.dataSource.replaceDataAt(index, next)
      }
    }
  }
}

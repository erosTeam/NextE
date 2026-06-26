import {
  EhApiService,
  EhGallery,
  GalleryList,
  GalleryListQuery,
  FavoritesQuery,
  Favcat,
  FavcatSlotResolver,
  FavcatSlotResolveResult,
  TagTranslationService,
  connectTagTranslationSettings,
  BasicDataSource,
  connectFavSelection,
  connectSiteMode,
  DiagnosticLogger,
  EhErrorText,
  EhPageCacheService,
  connectToplistFilter,
  LocalBlockService,
  CustomProfile,
  PROFILE_TYPE_POPULAR,
  PROFILE_TYPE_WATCHED,
  PROFILE_TYPE_TOPLIST,
  PROFILE_TYPE_FAVORITE,
} from 'shared'
import { common } from '@kit.AbilityKit'

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
  // Toplist (排行) is PAGE-paged (table.ptt), not gid-cursored: toplistTl = period, toplistNextPage =
  // the next 0-based page parsed from the ptt. FE stores/requests parsed nextPage directly; do not
  // hand-compute currentPage + 1 here. toplistTl is @Trace so the period selector row reflects the
  // active period (11 all-time / 12 year / 13 month / 15 yesterday).
  @Trace toplistTl: number = 15
  private toplistNextPage: number = -1
  private maxPage: number = 0
  private context: common.UIAbilityContext | null = null
  private cacheRenderVersion: number = 0
  // The custom profile driving this page (null on the legacy toplist/favorites surfaces that use
  // syncSource). When set, buildQuery() pulls search/category/advanced from it and cacheKey() scopes
  // by its uuid so two gallery-type profiles with different searches don't share a cache.
  private profile: CustomProfile | null = null
  private profileUuid: string = ''
  // Favorite-type profile pins (listType 'favorite'): the favcat slot + the favorites page cursor.
  // Favorites paging is page+from (or nextGid fallback), distinct from the gid cursor sources.
  private favcat: string = 'a'
  private favNextPage: number = -1

  setContext(context: common.UIAbilityContext): void {
    this.context = context
  }

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

  private buildQuery(next: string, page: number = -1): GalleryListQuery {
    // popular (bare snapshot) and toplist (toplist.php) ignore filters; gallery + watched honour the
    // profile's search/category/advanced. A null profile (legacy surfaces) keeps the old unfiltered query.
    const p: CustomProfile | null = this.profile
    const filtered: boolean = !this.isPopular() && !this.isToplist()
    const useProfile: boolean = p !== null && filtered
    return {
      isEx: connectSiteMode().isEx,
      source: this.source,
      next: next,
      tl: this.isToplist() ? this.toplistTl : 0,
      page: page,
      fCats: useProfile ? p!.fCats() : 0,
      search: useProfile ? p!.searchText : '',
      advancedEnabled: useProfile ? p!.advancedEnabled : false,
      minRating: useProfile ? p!.minRating : 0,
      pagesFrom: useProfile ? p!.pagesFrom : 0,
      pagesTo: useProfile ? p!.pagesTo : 0,
      requireTorrent: useProfile ? p!.requireTorrent : false,
      showExpunged: useProfile ? p!.showExpunged : false,
      disableLanguageFilter: useProfile ? p!.disableLanguageFilter : false,
      disableUploaderFilter: useProfile ? p!.disableUploaderFilter : false,
      disableTagFilter: useProfile ? p!.disableTagFilter : false,
      applyToplistHiddenUserTags: this.isToplist()
        ? connectToplistFilter().applyHiddenUserTags
        : false,
    }
  }

  private cacheKey(): string {
    if (this.profileUuid.length > 0) {
      return EhPageCacheService.homeProfileKey(connectSiteMode().isEx, this.profileUuid)
    }
    return EhPageCacheService.homeListKey(connectSiteMode().isEx, this.source, this.toplistTl)
  }

  /** Map a profile listType to the existing GalleryListQuery.source vocabulary. */
  private static sourceForListType(listType: string): string {
    if (listType === PROFILE_TYPE_POPULAR) {
      return 'popular'
    }
    if (listType === PROFILE_TYPE_WATCHED) {
      return 'watched'
    }
    if (listType === PROFILE_TYPE_TOPLIST) {
      return 'toplist'
    }
    if (listType === PROFILE_TYPE_FAVORITE) {
      return 'favorite'
    }
    return ''
  }

  /**
   * Configure this VM from a custom profile on (re)mount, WITHOUT reloading — loadData() runs right
   * after. Drives source/period + the search/filter payload + the cache key.
   */
  configureFromProfile(p: CustomProfile): void {
    this.profile = p
    this.profileUuid = p.uuid
    this.source = GalleryListViewModel.sourceForListType(p.listType)
    this.toplistTl = p.toplistTl
    this.favcat = p.favcat
  }

  private isFavorite(): boolean {
    return this.source === 'favorite'
  }

  private buildFavQuery(next: string, page: number, from: string): FavoritesQuery {
    return {
      isEx: connectSiteMode().isEx,
      favcat: this.favcat,
      next: next,
      page: page,
      from: from,
      search: this.profile !== null ? this.profile.searchText : '',
      order: '',
    }
  }

  /** First-page fetch for the active source (favorite uses getFavoritesList; everything else getGalleryList). */
  private async fetchFirstPageList(): Promise<GalleryList> {
    if (this.isFavorite()) {
      return EhApiService.getInstance().getFavoritesList(this.buildFavQuery('', -1, ''))
    }
    return EhApiService.getInstance().getGalleryList(this.buildQuery(''))
  }

  private lastVisibleGid(): string {
    const rows: EhGallery[] = this.dataSource.getAll()
    return rows.length > 0 ? rows[rows.length - 1].gid : ''
  }

  private resolveFavoriteSlots(gallerys: EhGallery[]): void {
    FavcatSlotResolver.applyInPlace(gallerys, connectFavSelection().favList)
  }

  private async translateRows(rows: EhGallery[]): Promise<EhGallery[]> {
    if (this.context === null || !connectTagTranslationSettings().enabled) {
      return rows
    }
    return TagTranslationService.translateGalleries(this.context, rows)
  }

  private async applyCachedFirstPageIfEmpty(): Promise<void> {
    if (this.context === null || this.itemCount > 0) {
      return
    }
    let cached: GalleryList | null = EhPageCacheService.takePreloadedGalleryList(this.cacheKey())
    if (cached === null) {
      cached = await EhPageCacheService.loadGalleryList(this.context, this.cacheKey())
    }
    if (cached === null || cached.gallerys.length === 0) {
      return
    }
    const visibleCached: GalleryList = LocalBlockService.filterGalleryList(cached.copy())
    this.resolveFavoriteSlots(visibleCached.gallerys)
    const rows: EhGallery[] = visibleCached.gallerys.map((g: EhGallery) => g.copy())
    this.cacheRenderVersion = this.cacheRenderVersion + 1
    const renderVersion: number = this.cacheRenderVersion
    this.dataSource.setData(rows)
    this.itemCount = this.dataSource.totalCount()
    this.nextGid = cached.nextGid
    this.maxPage = cached.maxPage
    this.toplistNextPage = cached.nextPage
    this.hasMore = this.firstPageHasMore(cached)
    this.loaded = true
    this.translateCachedRowsLater(rows, renderVersion, cached)
  }

  private async translateCachedRowsLater(
    rows: EhGallery[],
    renderVersion: number,
    cacheSnapshot: GalleryList | null = null,
  ): Promise<void> {
    if (this.context === null || !connectTagTranslationSettings().enabled) {
      return
    }
    const translated: EhGallery[] = await this.translateRows(rows)
    if (this.cacheRenderVersion !== renderVersion || this.itemCount === 0) {
      return
    }
    this.dataSource.setData(translated)
    this.itemCount = this.dataSource.totalCount()
    if (cacheSnapshot !== null) {
      const snapshot: GalleryList = cacheSnapshot.copy()
      snapshot.gallerys = translated
      await this.saveFirstPageCache(snapshot)
    }
  }

  private async renderFirstPageRows(list: GalleryList, deferTranslation: boolean): Promise<void> {
    const displayRows: EhGallery[] = list.gallerys.map((g: EhGallery) => g.copy())
    this.cacheRenderVersion = this.cacheRenderVersion + 1
    const renderVersion: number = this.cacheRenderVersion
    if (connectTagTranslationSettings().enabled && !deferTranslation) {
      const translated: EhGallery[] = await this.translateRows(displayRows)
      if (this.cacheRenderVersion !== renderVersion) {
        return
      }
      this.dataSource.setData(translated)
      this.itemCount = this.dataSource.totalCount()
      const snapshot: GalleryList = list.copy()
      snapshot.gallerys = translated
      await this.saveFirstPageCache(snapshot)
      return
    }
    this.dataSource.setData(displayRows)
    this.itemCount = this.dataSource.totalCount()
    if (connectTagTranslationSettings().enabled) {
      this.translateCachedRowsLater(displayRows, renderVersion, list)
    } else {
      await this.saveFirstPageCache(list)
    }
  }

  private async saveFirstPageCache(list: GalleryList): Promise<void> {
    if (this.context === null) {
      return
    }
    await EhPageCacheService.saveGalleryList(this.context, this.cacheKey(), list)
  }

  async reapplyTagTranslation(): Promise<void> {
    if (this.itemCount === 0) {
      return
    }
    const rows: EhGallery[] = connectTagTranslationSettings().enabled
      ? await this.translateRows(this.dataSource.getAll())
      : TagTranslationService.clearGalleriesTranslations(this.dataSource.getAll())
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
    if (this.loaded && !this.isLoading && !this.isLoadingMore) {
      await this.reload()
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
    await this.applyCachedFirstPageIfEmpty()
    this.isLoading = true
    this.errorMessage = ''
    try {
      const list: GalleryList = await this.fetchFirstPageList()
      this.resolveFavoriteSlots(list.gallerys)
      await this.renderFirstPageRows(list, this.itemCount === 0)
      this.nextGid = list.nextGid
      this.maxPage = list.maxPage
      this.toplistNextPage = list.nextPage
      this.favNextPage = list.nextPage
      this.hasMore = this.firstPageHasMore(list)
    } catch (err) {
      const e = err as Error
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('home', 'list_load_failed', e.message)
    }
    this.isLoading = false
    this.loaded = true
  }

  // Whether a fresh first-page load has more: toplist follows parsed ptt nextPage; cursor sources page
  // while a next cursor exists (popular never pages).
  private firstPageHasMore(list: GalleryList): boolean {
    if (this.isToplist()) {
      return list.nextPage >= 0 && list.nextPage <= list.maxPage
    }
    if (this.isFavorite()) {
      return list.nextPage > 0 || list.nextGid.length > 0
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
    this.toplistNextPage = -1
    this.favNextPage = -1
    this.maxPage = 0
    this.hasMore = false
    try {
      const list: GalleryList = await this.fetchFirstPageList()
      this.resolveFavoriteSlots(list.gallerys)
      await this.renderFirstPageRows(list, this.itemCount === 0)
      this.nextGid = list.nextGid
      this.maxPage = list.maxPage
      this.toplistNextPage = list.nextPage
      this.favNextPage = list.nextPage
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
      const list: GalleryList = await this.fetchFirstPageList()
      this.resolveFavoriteSlots(list.gallerys)
      await this.renderFirstPageRows(list, this.itemCount === 0)
      this.nextGid = list.nextGid
      this.maxPage = list.maxPage
      this.toplistNextPage = list.nextPage
      this.favNextPage = list.nextPage
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
    if (this.isFavorite()) {
      await this.loadMoreFavorites()
      return
    }
    // Stale-cursor guard (eros_fe lastNext == next): no cursor, or it didn't advance since the last
    // page → stop instead of refetching the same rows. Marks the list exhausted.
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
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(
        this.buildQuery(requestedNext),
      )
      // A reload/refresh/source-switch happened while this fetch was in flight → its rows belong to
      // the OLD source/host. Drop them (the new list already replaced everything); only clear the
      // in-flight flag below.
      if (this.epoch === myEpoch) {
        this.resolveFavoriteSlots(list.gallerys)
        const fresh: EhGallery[] = await this.translateRows(this.dedupeNew(list.gallerys))
        if (fresh.length > 0) {
          this.dataSource.appendData(fresh)
          this.itemCount = this.dataSource.totalCount()
        }
        this.nextGid = list.nextGid
        this.lastNext = requestedNext
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

  /** Toplist page paging: request the next ptt-parsed 0-based page (?p=), dedup-append, then store the newly parsed next page. */
  private async loadMoreToplist(): Promise<void> {
    const requestedPage: number = this.toplistNextPage
    if (requestedPage < 0 || requestedPage > this.maxPage) {
      this.hasMore = false
      return
    }
    this.isLoadingMore = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(
        this.buildQuery('', requestedPage),
      )
      if (this.epoch === myEpoch) {
        this.resolveFavoriteSlots(list.gallerys)
        const fresh: EhGallery[] = await this.translateRows(this.dedupeNew(list.gallerys))
        if (fresh.length > 0) {
          this.dataSource.appendData(fresh)
          this.itemCount = this.dataSource.totalCount()
        }
        this.maxPage = list.maxPage
        this.toplistNextPage = list.nextPage
        this.hasMore = list.nextPage >= 0 && list.nextPage <= this.maxPage
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

  /** Favorites page paging (favorite-type profiles): page+from forward, nextGid fallback. Ported from
   * the favorites VM — favorites.php pages by page number + last-visible gid, not a pure gid cursor. */
  private async loadMoreFavorites(): Promise<void> {
    const page: number = this.favNextPage
    const from: string = page >= 0 ? this.lastVisibleGid() : ''
    const cursor: string = page >= 0 ? from : this.nextGid
    if (cursor.length === 0) {
      this.hasMore = false
      return
    }
    const requestKey: string = page >= 0 ? `page:${page}:from:${from}` : `next:${cursor}`
    if (requestKey === this.lastNext && this.errorMessage.length === 0) {
      this.hasMore = false
      return
    }
    this.isLoadingMore = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    try {
      const list: GalleryList = await EhApiService.getInstance().getFavoritesList(
        this.buildFavQuery(page >= 0 ? '' : cursor, page, from),
      )
      if (this.epoch === myEpoch) {
        this.resolveFavoriteSlots(list.gallerys)
        const fresh: EhGallery[] = await this.translateRows(this.dedupeNew(list.gallerys))
        if (fresh.length > 0) {
          this.dataSource.appendData(fresh)
          this.itemCount = this.dataSource.totalCount()
        }
        this.nextGid = list.nextGid
        this.favNextPage = list.nextPage
        this.lastNext = requestKey
        this.hasMore =
          page >= 0
            ? list.nextPage > 0 || list.nextGid.length > 0
            : list.nextGid.length > 0 && list.nextGid !== cursor
      }
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('home', 'fav_loadmore_failed', e.message)
    }
    this.isLoadingMore = false
  }

  canLoadMore(): boolean {
    return this.hasMore && !this.isLoadingMore && this.errorMessage.length === 0
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
    let changed: boolean = false
    const nextRows: EhGallery[] = []
    current.forEach((g: EhGallery) => {
      if (g.gid === gid) {
        const next: EhGallery = g.copy()
        next.ratingFallBack = userRating
        next.rating = averageRating
        next.ratingCount = ratingCount
        next.colorRating = colorRating
        next.isRated = true
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

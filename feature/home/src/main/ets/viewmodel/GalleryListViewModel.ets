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
  GalleryCoverPrefetchDataSource,
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
import { UIContext } from '@kit.ArkUI'

/** Immutable ownership token for one Home list request and its account/site/profile context. */
class GalleryFirstPageRun {
  epoch: number
  cacheKey: string
  source: string
  profileUuid: string
  profileContentRevision: string
  toplistTl: number
  applyToplistHiddenUserTags: boolean
  favcat: string

  constructor(
    epoch: number,
    cacheKey: string,
    source: string,
    profileUuid: string,
    profileContentRevision: string,
    toplistTl: number,
    applyToplistHiddenUserTags: boolean,
    favcat: string,
  ) {
    this.epoch = epoch
    this.cacheKey = cacheKey
    this.source = source
    this.profileUuid = profileUuid
    this.profileContentRevision = profileContentRevision
    this.toplistTl = toplistTl
    this.applyToplistHiddenUserTags = applyToplistHiddenUserTags
    this.favcat = favcat
  }
}

/**
 * Drives one gallery-list source (V2Next FeedViewModel pattern). Rows live in a stable
 * LazyForEach `dataSource` (out of @Trace); `itemCount` mirrors its count as @Trace so the
 * page's loading→list branch re-evaluates. Cursor paging uses the parsed `nextGid`.
 */
@ObservedV2
export class GalleryListViewModel {
  private static nextDebugId: number = 1
  private debugId: number = GalleryListViewModel.nextDebugId++
  // Stable ref; LazyForEach subscribes to its listeners directly, so NOT @Trace.
  dataSource: GalleryCoverPrefetchDataSource = new GalleryCoverPrefetchDataSource()
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
  private prevGid: string = ''
  // Last cursor handed to loadMore (eros_fe lastNext): bail if it didn't advance — the parsed page
  // repeated, so refetching would loop the same rows. Reset whenever the list reloads from page 1.
  private lastNext: string = ''
  private lastPrev: string = ''
  // Generation token: reload()/setSource()/refresh() bump it so an in-flight loadMore that resumes
  // afterwards discards its (now cross-source/cross-host) result instead of corrupting the new list.
  private epoch: number = 0
  // Toplist (排行) is PAGE-paged (table.ptt), not gid-cursored: toplistTl = period, toplistNextPage =
  // the next 0-based page parsed from the ptt. FE stores/requests parsed nextPage directly; do not
  // hand-compute currentPage + 1 here. toplistTl is @Trace so the period selector row reflects the
  // active period (11 all-time / 12 year / 13 month / 15 yesterday).
  @Trace toplistTl: number = 15
  private toplistNextPage: number = -1
  private toplistPrevPage: number = -1
  private afterToplistJump: boolean = false
  private afterDateJump: boolean = false
  private currentToplistPage: number = 0
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
  private favPrevPage: number = -1
  private pagingAppendContext: UIContext | null = null
  private pagingAppendBatchSize: number = 0

  debugState(): string {
    return `vm=${this.debugId} source=${this.source} profile=${this.profileUuid} count=${this.itemCount} loaded=${this.loaded} loading=${this.isLoading} loadingMore=${this.isLoadingMore} hasMore=${this.hasMore} epoch=${this.epoch} next=${this.nextGid} prev=${this.prevGid} favNext=${this.favNextPage} favPrev=${this.favPrevPage} toplistNext=${this.toplistNextPage} toplistPrev=${this.toplistPrevPage} toplistCurrent=${this.currentToplistPage} afterToplistJump=${this.afterToplistJump} afterDateJump=${this.afterDateJump}`
  }

  setContext(context: common.UIAbilityContext): void {
    this.context = context
  }

  /** WaterFlow can opt into frame-sized page commits; other renderers keep one atomic page ADD. */
  configurePagingAppend(uiContext: UIContext | null, batchSize: number = 0): void {
    this.dataSource.cancelPendingAppend()
    this.pagingAppendContext = uiContext
    this.pagingAppendBatchSize = uiContext === null ? 0 : Math.max(1, Math.floor(batchSize))
  }

  private profileContentRevision(): string {
    return this.profile !== null ? this.profile.contentRevision() : ''
  }

  private captureCurrentListRun(): GalleryFirstPageRun {
    return new GalleryFirstPageRun(
      this.epoch,
      this.cacheKey(),
      this.source,
      this.profileUuid,
      this.profileContentRevision(),
      this.toplistTl,
      connectToplistFilter().applyHiddenUserTags,
      this.favcat,
    )
  }

  private beginFirstPageRun(): GalleryFirstPageRun {
    this.epoch = this.epoch + 1
    // A replacement first page owns the footer state immediately. Old paging cleanup is request-context
    // gated, so it cannot release a newer page's spinner or unlock an old cursor after translation resumes.
    this.isLoadingMore = false
    // A deferred cache translation must not repaint a newer account/site/profile run while its
    // replacement request is still in flight.
    this.cacheRenderVersion = this.cacheRenderVersion + 1
    return this.captureCurrentListRun()
  }

  private isCurrentFirstPageRun(run: GalleryFirstPageRun): boolean {
    if (
      this.epoch !== run.epoch ||
      this.source !== run.source ||
      this.profileUuid !== run.profileUuid ||
      this.profileContentRevision() !== run.profileContentRevision ||
      this.toplistTl !== run.toplistTl ||
      this.favcat !== run.favcat
    ) {
      return false
    }
    if (this.isToplist() && connectToplistFilter().applyHiddenUserTags !== run.applyToplistHiddenUserTags) {
      return false
    }
    // The key scopes site + member. This direct check covers the window where CookieStore changes before
    // AuthState publishes, so no old account/site response can write into the current list.
    return this.cacheKey() === run.cacheKey
  }

  private isCurrentPagingRun(run: GalleryFirstPageRun): boolean {
    return this.isCurrentFirstPageRun(run)
  }

  /** Resolve personal slots and translate a paging page only while its original request context owns it. */
  private async translateCurrentPagingRows(
    list: GalleryList,
    run: GalleryFirstPageRun,
  ): Promise<EhGallery[] | null> {
    if (!this.isCurrentPagingRun(run)) {
      return null
    }
    this.resolveFavoriteSlots(list.gallerys)
    const fresh: EhGallery[] = await this.translateRows(this.dedupeNew(list.gallerys))
    return this.isCurrentPagingRun(run) ? fresh : null
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

  private buildQuery(next: string, page: number = -1, seek: string = '', prev: string = ''): GalleryListQuery {
    // popular (bare snapshot) and toplist (toplist.php) ignore filters; gallery + watched honour the
    // profile's search/category/advanced. A null profile (legacy surfaces) keeps the old unfiltered query.
    const p: CustomProfile | null = this.profile
    const filtered: boolean = !this.isPopular() && !this.isToplist()
    const useProfile: boolean = p !== null && filtered
    return {
      isEx: connectSiteMode().isEx,
      source: this.source,
      next: next,
      prev: prev,
      seek: seek,
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
      return EhPageCacheService.homeProfileKey(
        connectSiteMode().isEx,
        this.profileUuid,
        this.profileContentRevision(),
      )
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

  private buildFavQuery(next: string, page: number, from: string, seek: string = '', prev: string = ''): FavoritesQuery {
    return {
      isEx: connectSiteMode().isEx,
      favcat: this.favcat,
      next: next,
      prev: prev,
      seek: seek,
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

  private async applyCachedFirstPageIfEmpty(run: GalleryFirstPageRun): Promise<void> {
    if (this.context === null || this.itemCount > 0 || !this.isCurrentFirstPageRun(run)) {
      return
    }
    let cached: GalleryList | null = EhPageCacheService.takePreloadedGalleryList(run.cacheKey)
    if (cached === null) {
      cached = await EhPageCacheService.loadGalleryList(this.context, run.cacheKey)
    }
    if (!this.isCurrentFirstPageRun(run)) {
      return
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
    this.prevGid = cached.prevGid
    this.maxPage = cached.maxPage
    this.toplistNextPage = cached.nextPage
    this.toplistPrevPage = cached.prevPage
    this.favPrevPage = cached.prevPage
    this.currentToplistPage = 0
    this.afterToplistJump = false
    this.afterDateJump = false
    this.hasMore = this.firstPageHasMore(cached)
    this.loaded = true
    this.translateCachedRowsLater(rows, renderVersion, run, cached)
  }

  private async translateCachedRowsLater(
    rows: EhGallery[],
    renderVersion: number,
    run: GalleryFirstPageRun,
    cacheSnapshot: GalleryList | null = null,
  ): Promise<void> {
    if (this.context === null || !connectTagTranslationSettings().enabled) {
      return
    }
    const translated: EhGallery[] = await this.translateRows(rows)
    if (
      this.cacheRenderVersion !== renderVersion ||
      this.itemCount === 0 ||
      !this.isCurrentFirstPageRun(run)
    ) {
      return
    }
    this.dataSource.setData(translated)
    this.itemCount = this.dataSource.totalCount()
    if (cacheSnapshot !== null) {
      const snapshot: GalleryList = cacheSnapshot.copy()
      snapshot.gallerys = translated
      await this.saveFirstPageCache(snapshot, run)
    }
  }

  private async renderFirstPageRows(
    list: GalleryList,
    deferTranslation: boolean,
    run: GalleryFirstPageRun,
    saveCache: boolean = true,
  ): Promise<boolean> {
    if (!this.isCurrentFirstPageRun(run)) {
      return false
    }
    const displayRows: EhGallery[] = list.gallerys.map((g: EhGallery) => g.copy())
    this.cacheRenderVersion = this.cacheRenderVersion + 1
    const renderVersion: number = this.cacheRenderVersion
    DiagnosticLogger.info(
      'home-list-anchor',
      'render_first_page',
      `${this.debugState()} incoming=${list.gallerys.length} oldCount=${this.itemCount} deferTranslation=${deferTranslation}`,
    )
    if (connectTagTranslationSettings().enabled && !deferTranslation) {
      const translated: EhGallery[] = await this.translateRows(displayRows)
      if (this.cacheRenderVersion !== renderVersion || !this.isCurrentFirstPageRun(run)) {
        return false
      }
      this.dataSource.setData(translated)
      this.itemCount = this.dataSource.totalCount()
      if (saveCache) {
        const snapshot: GalleryList = list.copy()
        snapshot.gallerys = translated
        await this.saveFirstPageCache(snapshot, run)
      }
      return this.isCurrentFirstPageRun(run)
    }
    if (!this.isCurrentFirstPageRun(run)) {
      return false
    }
    this.dataSource.setData(displayRows)
    this.itemCount = this.dataSource.totalCount()
    if (connectTagTranslationSettings().enabled) {
      this.translateCachedRowsLater(displayRows, renderVersion, run, saveCache ? list : null)
    } else if (saveCache) {
      await this.saveFirstPageCache(list, run)
    }
    return this.isCurrentFirstPageRun(run)
  }

  private async saveFirstPageCache(list: GalleryList, run: GalleryFirstPageRun): Promise<void> {
    if (this.context === null || !this.isCurrentFirstPageRun(run)) {
      return
    }
    await EhPageCacheService.saveGalleryList(this.context, run.cacheKey, list)
  }

  async reapplyTagTranslation(): Promise<void> {
    if (this.itemCount === 0) {
      return
    }
    // A settings toggle may translate the current rows asynchronously. Give that repaint its own
    // generation so a newer first-page run (or a second toggle) cannot be overwritten on completion.
    const renderVersion: number = this.cacheRenderVersion + 1
    this.cacheRenderVersion = renderVersion
    const renderEpoch: number = this.epoch
    const renderCacheKey: string = this.cacheKey()
    const rows: EhGallery[] = connectTagTranslationSettings().enabled
      ? await this.translateRows(this.dataSource.getAll())
      : TagTranslationService.clearGalleriesTranslations(this.dataSource.getAll())
    if (
      this.cacheRenderVersion !== renderVersion ||
      this.epoch !== renderEpoch ||
      this.cacheKey() !== renderCacheKey
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
    await this.reload(true)
  }

  /** Switch the toplist period (tl 11 all-time / 12 year / 13 month / 15 yesterday) and hard-reload
   * from page 0. No-op if unchanged or not on the toplist source. */
  async setToplistPeriod(tl: number): Promise<void> {
    if (!this.isToplist() || this.toplistTl === tl) {
      return
    }
    this.toplistTl = tl
    await this.reload(true)
  }

  toplistPageCount(): number {
    return this.isToplist() ? this.maxPage + 1 : 0
  }

  currentToplistPageNumber(): number {
    return this.isToplist() ? this.currentToplistPage + 1 : 1
  }

  shouldJumpGalleryFirstPage(): boolean {
    return this.afterDateJump
  }

  async jumpGalleryFirstPage(): Promise<boolean> {
    if (this.isToplist() || this.isLoading || this.isLoadingMore) {
      return false
    }
    DiagnosticLogger.info('home-list-anchor', 'gallery_first_page_enter', this.debugState())
    const committed: boolean = await this.reload()
    DiagnosticLogger.info('home-list-anchor', 'gallery_first_page_done', this.debugState())
    return committed
  }

  async jumpToToplistPage(pageNumber: number): Promise<boolean> {
    const requestedPage: number = pageNumber - 1
    if (
      !this.isToplist() ||
      this.isLoading ||
      this.isLoadingMore ||
      requestedPage < 0 ||
      requestedPage > this.maxPage
    ) {
      return false
    }
    DiagnosticLogger.info('home-list-anchor', 'toplist_jump_enter', `${this.debugState()} requestedPage=${requestedPage}`)
    const run: GalleryFirstPageRun = this.beginFirstPageRun()
    this.isLoading = true
    this.errorMessage = ''
    this.nextGid = ''
    this.prevGid = ''
    this.lastNext = ''
    this.lastPrev = ''
    this.toplistNextPage = -1
    this.toplistPrevPage = -1
    this.favNextPage = -1
    this.favPrevPage = -1
    this.hasMore = false
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(
        this.buildQuery('', requestedPage),
      )
      if (!this.isCurrentFirstPageRun(run)) {
        return false
      }
      this.resolveFavoriteSlots(list.gallerys)
      const rendered: boolean = await this.renderFirstPageRows(list, this.itemCount === 0, run, false)
      if (!rendered || !this.isCurrentFirstPageRun(run)) {
        return false
      }
      this.nextGid = list.nextGid
      this.prevGid = list.prevGid
      this.maxPage = list.maxPage
      this.toplistNextPage = list.nextPage
      this.toplistPrevPage = list.prevPage
      this.currentToplistPage = requestedPage
      this.afterToplistJump = true
      this.afterDateJump = false
      this.hasMore = this.firstPageHasMore(list)
      DiagnosticLogger.info('home-list-anchor', 'toplist_jump_done', `${this.debugState()} requestedPage=${requestedPage}`)
      return true
    } catch (err) {
      const e = err as Error
      if (this.isCurrentFirstPageRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
        DiagnosticLogger.warn('home', 'toplist_jump_failed', `${this.debugState()} requestedPage=${requestedPage} error=${e.message}`)
      }
      return false
    } finally {
      if (this.isCurrentFirstPageRun(run)) {
        this.isLoading = false
        this.loaded = true
      }
    }
  }

  canJumpToDateAfter(): boolean {
    return !this.isPopular() && !this.isToplist() && !this.isLoading && !this.isLoadingMore
  }

  async jumpToDateAfter(seek: string): Promise<boolean> {
    const dateText: string = seek.trim()
    if (!this.canJumpToDateAfter() || dateText.length === 0) {
      return false
    }
    DiagnosticLogger.info('home-list-anchor', 'date_jump_after_enter', `${this.debugState()} seek=${dateText}`)
    const run: GalleryFirstPageRun = this.beginFirstPageRun()
    this.isLoading = true
    this.errorMessage = ''
    this.nextGid = ''
    this.prevGid = ''
    this.lastNext = ''
    this.lastPrev = ''
    this.toplistNextPage = -1
    this.toplistPrevPage = -1
    this.favNextPage = -1
    this.favPrevPage = -1
    this.maxPage = 0
    this.currentToplistPage = 0
    this.afterToplistJump = false
    this.afterDateJump = false
    this.hasMore = false
    try {
      const list: GalleryList = this.isFavorite()
        ? await EhApiService.getInstance().getFavoritesList(this.buildFavQuery('', -1, '', dateText))
        : await EhApiService.getInstance().getGalleryList(this.buildQuery('', -1, dateText))
      if (!this.isCurrentFirstPageRun(run)) {
        return false
      }
      this.resolveFavoriteSlots(list.gallerys)
      const rendered: boolean = await this.renderFirstPageRows(list, this.itemCount === 0, run, false)
      if (!rendered || !this.isCurrentFirstPageRun(run)) {
        return false
      }
      this.nextGid = list.nextGid
      this.prevGid = list.prevGid
      this.maxPage = list.maxPage
      this.toplistNextPage = list.nextPage
      this.toplistPrevPage = list.prevPage
      this.favNextPage = list.nextPage
      this.favPrevPage = list.prevPage
      this.afterDateJump = true
      this.hasMore = this.firstPageHasMore(list)
      DiagnosticLogger.info('home-list-anchor', 'date_jump_after_done', `${this.debugState()} seek=${dateText}`)
      return true
    } catch (err) {
      const e = err as Error
      if (this.isCurrentFirstPageRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
        DiagnosticLogger.warn('home', 'date_jump_after_failed', `${this.debugState()} seek=${dateText} error=${e.message}`)
      }
      return false
    } finally {
      if (this.isCurrentFirstPageRun(run)) {
        this.isLoading = false
        this.loaded = true
      }
    }
  }

  /** First load (skips if already populated). */
  async loadData(): Promise<boolean> {
    DiagnosticLogger.info('home-list-anchor', 'load_data_enter', this.debugState())
    if (this.isLoading || this.itemCount > 0) {
      DiagnosticLogger.info('home-list-anchor', 'load_data_skip', this.debugState())
      return false
    }
    const run: GalleryFirstPageRun = this.beginFirstPageRun()
    await this.applyCachedFirstPageIfEmpty(run)
    if (!this.isCurrentFirstPageRun(run)) {
      return false
    }
    this.isLoading = true
    this.errorMessage = ''
    try {
      const list: GalleryList = await this.fetchFirstPageList()
      if (!this.isCurrentFirstPageRun(run)) {
        return false
      }
      this.resolveFavoriteSlots(list.gallerys)
      const rendered: boolean = await this.renderFirstPageRows(list, this.itemCount === 0, run)
      if (!rendered || !this.isCurrentFirstPageRun(run)) {
        return false
      }
      this.nextGid = list.nextGid
      this.prevGid = list.prevGid
      this.maxPage = list.maxPage
      this.toplistNextPage = list.nextPage
      this.favNextPage = list.nextPage
      this.toplistPrevPage = list.prevPage
      this.favPrevPage = list.prevPage
      this.currentToplistPage = 0
      this.afterToplistJump = false
      this.afterDateJump = false
      this.hasMore = this.firstPageHasMore(list)
      DiagnosticLogger.info('home-list-anchor', 'load_data_done', this.debugState())
      return true
    } catch (err) {
      const e = err as Error
      if (this.isCurrentFirstPageRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
        DiagnosticLogger.warn('home', 'list_load_failed', e.message)
      }
      return false
    } finally {
      if (this.isCurrentFirstPageRun(run)) {
        this.isLoading = false
        this.loaded = true
      }
    }
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
  async reload(force: boolean = false): Promise<boolean> {
    DiagnosticLogger.info('home-list-anchor', 'reload_enter', this.debugState())
    if (this.isLoading && !force) {
      DiagnosticLogger.info('home-list-anchor', 'reload_skip_loading', this.debugState())
      return false
    }
    // Invalidate any in-flight loadMore (it runs without the isLoading flag, so it can overlap a
    // site/source switch) and drop the old cursor immediately, but keep old rows rendered until the
    // replacement page succeeds. On failure, loadMore remains disabled instead of mixing sources.
    const run: GalleryFirstPageRun = this.beginFirstPageRun()
    this.isLoading = true
    this.errorMessage = ''
    this.nextGid = ''
    this.prevGid = ''
    this.lastNext = ''
    this.lastPrev = ''
    this.toplistNextPage = -1
    this.toplistPrevPage = -1
    this.favNextPage = -1
    this.favPrevPage = -1
    this.maxPage = 0
    this.afterToplistJump = false
    this.afterDateJump = false
    this.hasMore = false
    try {
      const list: GalleryList = await this.fetchFirstPageList()
      if (!this.isCurrentFirstPageRun(run)) {
        return false
      }
      this.resolveFavoriteSlots(list.gallerys)
      const rendered: boolean = await this.renderFirstPageRows(list, this.itemCount === 0, run)
      if (!rendered || !this.isCurrentFirstPageRun(run)) {
        return false
      }
      this.nextGid = list.nextGid
      this.prevGid = list.prevGid
      this.maxPage = list.maxPage
      this.toplistNextPage = list.nextPage
      this.toplistPrevPage = list.prevPage
      this.favNextPage = list.nextPage
      this.favPrevPage = list.prevPage
      this.currentToplistPage = 0
      this.hasMore = this.firstPageHasMore(list)
      DiagnosticLogger.info('home-list-anchor', 'reload_done', this.debugState())
      return true
    } catch (err) {
      const e = err as Error
      if (this.isCurrentFirstPageRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
        DiagnosticLogger.warn('home', 'list_reload_failed', e.message)
      }
      return false
    } finally {
      if (this.isCurrentFirstPageRun(run)) {
        this.isLoading = false
        this.loaded = true
      }
    }
  }

  /** Pull-to-refresh: replace from the first page. Guarded + flagged isLoading so a concurrent
   * loadMore (which checks isLoading) can't interleave its appendData with this setData. */
  async refresh(afterPrepend?: (prependedCount: number) => void): Promise<number> {
    DiagnosticLogger.info('home-list-anchor', 'refresh_enter', this.debugState())
    if (this.isLoading || this.isLoadingMore) {
      DiagnosticLogger.info('home-list-anchor', 'refresh_skip_busy', this.debugState())
      return 0
    }
    if (this.isToplist() && this.afterToplistJump && this.toplistPrevPage >= 0) {
      return await this.loadPreviousToplist(afterPrepend)
    }
    if (this.afterDateJump && this.canLoadPreviousDateJump()) {
      return await this.loadPreviousDateJump(afterPrepend)
    }
    this.isLoading = true
    this.errorMessage = ''
    // Refresh replaces from page 1, so the cursor history resets and any in-flight loadMore is void.
    this.lastNext = ''
    this.lastPrev = ''
    const run: GalleryFirstPageRun = this.beginFirstPageRun()
    try {
      const list: GalleryList = await this.fetchFirstPageList()
      if (!this.isCurrentFirstPageRun(run)) {
        return 0
      }
      this.resolveFavoriteSlots(list.gallerys)
      const rendered: boolean = await this.renderFirstPageRows(list, this.itemCount === 0, run)
      if (!rendered || !this.isCurrentFirstPageRun(run)) {
        return 0
      }
      this.nextGid = list.nextGid
      this.prevGid = list.prevGid
      this.maxPage = list.maxPage
      this.toplistNextPage = list.nextPage
      this.toplistPrevPage = list.prevPage
      this.favNextPage = list.nextPage
      this.favPrevPage = list.prevPage
      this.currentToplistPage = 0
      this.afterToplistJump = false
      this.afterDateJump = false
      this.hasMore = this.firstPageHasMore(list)
      DiagnosticLogger.info('home-list-anchor', 'refresh_done', this.debugState())
    } catch (err) {
      const e = err as Error
      if (this.isCurrentFirstPageRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
        DiagnosticLogger.warn('home', 'list_refresh_failed', e.message)
      }
    } finally {
      if (this.isCurrentFirstPageRun(run)) {
        this.isLoading = false
      }
    }
    return 0
  }

  /** Append the next page at the cursor, with eros_fe's stale-cursor + (gid-keyed) dedup guards. */
  async loadMore(): Promise<void> {
    DiagnosticLogger.info('home-list-anchor', 'load_more_enter', this.debugState())
    if (this.isLoading || this.isLoadingMore || !this.hasMore || this.isPopular()) {
      DiagnosticLogger.info('home-list-anchor', 'load_more_skip', this.debugState())
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
      DiagnosticLogger.info('home-list-anchor', 'load_more_empty_cursor', this.debugState())
      return
    }
    if (requestedNext === this.lastNext && this.errorMessage.length === 0) {
      this.hasMore = false
      DiagnosticLogger.info('home-list-anchor', 'load_more_repeated_cursor', this.debugState())
      return
    }
    this.isLoadingMore = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    const run: GalleryFirstPageRun = this.captureCurrentListRun()
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(
        this.buildQuery(requestedNext),
      )
      const fresh: EhGallery[] | null = await this.translateCurrentPagingRows(list, run)
      if (fresh === null) {
        DiagnosticLogger.info(
          'home-list-anchor',
          'load_more_drop_stale',
          `${this.debugState()} requested=${requestedNext} myEpoch=${myEpoch}`,
        )
        return
      }
      if (fresh.length > 0) {
        const committed: boolean = await this.appendCurrentPagingRows(fresh, run)
        if (!committed) {
          DiagnosticLogger.info(
            'home-list-anchor',
            'load_more_append_interrupted',
            `${this.debugState()} requested=${requestedNext} fresh=${fresh.length}`,
          )
          return
        }
      }
      this.nextGid = list.nextGid
      this.lastNext = requestedNext
      // Exhausted when the cursor is empty OR the page brought no genuinely new rows (server race /
      // repeated boundary page) — guards against an infinite same-page loadMore loop.
      this.hasMore = list.nextGid.length > 0 && fresh.length > 0
      DiagnosticLogger.info(
        'home-list-anchor',
        'load_more_done',
        `${this.debugState()} requested=${requestedNext} incoming=${list.gallerys.length} fresh=${fresh.length}`,
      )
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch && this.isCurrentPagingRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('home', 'list_loadmore_failed', e.message)
    } finally {
      if (this.isCurrentPagingRun(run)) {
        this.isLoadingMore = false
      }
    }
  }

  private async appendCurrentPagingRows(
    fresh: EhGallery[],
    run: GalleryFirstPageRun,
  ): Promise<boolean> {
    const uiContext: UIContext | null = this.pagingAppendContext
    const batchSize: number = this.pagingAppendBatchSize
    if (uiContext === null || batchSize <= 0) {
      this.dataSource.appendData(fresh)
      this.itemCount = this.dataSource.totalCount()
      return true
    }
    return this.dataSource.appendDataByFrame(
      fresh,
      batchSize,
      uiContext,
      (): boolean => {
        return this.pagingAppendContext === uiContext && this.isCurrentPagingRun(run)
      },
      (totalCount: number, _committedCount: number): void => {
        this.itemCount = totalCount
      },
    )
  }

  /** Toplist page paging: request the next ptt-parsed 0-based page (?p=), dedup-append, then store the newly parsed next page. */
  private async loadMoreToplist(): Promise<void> {
    DiagnosticLogger.info('home-list-anchor', 'toplist_more_enter', this.debugState())
    const requestedPage: number = this.toplistNextPage
    if (requestedPage < 0 || requestedPage > this.maxPage) {
      this.hasMore = false
      DiagnosticLogger.info('home-list-anchor', 'toplist_more_no_page', this.debugState())
      return
    }
    this.isLoadingMore = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    const run: GalleryFirstPageRun = this.captureCurrentListRun()
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(
        this.buildQuery('', requestedPage),
      )
      const fresh: EhGallery[] | null = await this.translateCurrentPagingRows(list, run)
      if (fresh === null) {
        DiagnosticLogger.info(
          'home-list-anchor',
          'toplist_more_drop_stale',
          `${this.debugState()} requestedPage=${requestedPage} myEpoch=${myEpoch}`,
        )
        return
      }
      if (fresh.length > 0) {
        this.dataSource.appendData(fresh)
        this.itemCount = this.dataSource.totalCount()
      }
      this.maxPage = list.maxPage
      this.toplistNextPage = list.nextPage
      this.hasMore = list.nextPage >= 0 && list.nextPage <= this.maxPage
      DiagnosticLogger.info(
        'home-list-anchor',
        'toplist_more_done',
        `${this.debugState()} requestedPage=${requestedPage} incoming=${list.gallerys.length} fresh=${fresh.length}`,
      )
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch && this.isCurrentPagingRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('home', 'toplist_loadmore_failed', e.message)
    } finally {
      if (this.isCurrentPagingRun(run)) {
        this.isLoadingMore = false
      }
    }
  }

  /** After a page jump, FE treats pull-to-refresh as "load previous page" instead of reloading page 1. */
  private async loadPreviousToplist(afterPrepend?: (prependedCount: number) => void): Promise<number> {
    DiagnosticLogger.info('home-list-anchor', 'toplist_prev_enter', this.debugState())
    const requestedPage: number = this.toplistPrevPage
    if (requestedPage < 0 || requestedPage > this.maxPage) {
      DiagnosticLogger.info('home-list-anchor', 'toplist_prev_no_page', this.debugState())
      return 0
    }
    this.isLoading = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    const run: GalleryFirstPageRun = this.captureCurrentListRun()
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(
        this.buildQuery('', requestedPage),
      )
      const fresh: EhGallery[] | null = await this.translateCurrentPagingRows(list, run)
      if (fresh === null) {
        DiagnosticLogger.info(
          'home-list-anchor',
          'toplist_prev_drop_stale',
          `${this.debugState()} requestedPage=${requestedPage} myEpoch=${myEpoch}`,
        )
        return 0
      }
      if (fresh.length > 0) {
        this.dataSource.prependData(fresh)
        this.itemCount = this.dataSource.totalCount()
        this.currentToplistPage = requestedPage
        if (afterPrepend) {
          afterPrepend(fresh.length)
        }
      }
      this.maxPage = list.maxPage
      this.toplistPrevPage = list.prevPage
      DiagnosticLogger.info(
        'home-list-anchor',
        'toplist_prev_done',
        `${this.debugState()} requestedPage=${requestedPage} incoming=${list.gallerys.length} fresh=${fresh.length}`,
      )
      return fresh.length
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch && this.isCurrentPagingRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('home', 'toplist_loadprev_failed', e.message)
    } finally {
      if (this.isCurrentPagingRun(run)) {
        this.isLoading = false
      }
    }
    return 0
  }

  private canLoadPreviousDateJump(): boolean {
    if (this.isPopular() || this.isToplist()) {
      return false
    }
    if (this.isFavorite()) {
      return this.favPrevPage >= 0 || this.prevGid.length > 0
    }
    return this.prevGid.length > 0
  }

  private async loadPreviousDateJump(afterPrepend?: (prependedCount: number) => void): Promise<number> {
    if (this.isFavorite()) {
      return await this.loadPreviousFavorites(afterPrepend)
    }
    return await this.loadPreviousGallery(afterPrepend)
  }

  /** After a date seek, pull-to-refresh prepends the newer page through EH's prev cursor. */
  private async loadPreviousGallery(afterPrepend?: (prependedCount: number) => void): Promise<number> {
    DiagnosticLogger.info('home-list-anchor', 'date_jump_prev_enter', this.debugState())
    const requestedPrev: string = this.prevGid
    if (requestedPrev.length === 0) {
      DiagnosticLogger.info('home-list-anchor', 'date_jump_prev_no_cursor', this.debugState())
      return 0
    }
    if (requestedPrev === this.lastPrev && this.errorMessage.length === 0) {
      DiagnosticLogger.info('home-list-anchor', 'date_jump_prev_repeated_cursor', this.debugState())
      return 0
    }
    this.isLoading = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    const run: GalleryFirstPageRun = this.captureCurrentListRun()
    try {
      const list: GalleryList = await EhApiService.getInstance().getGalleryList(
        this.buildQuery('', -1, '', requestedPrev),
      )
      const fresh: EhGallery[] | null = await this.translateCurrentPagingRows(list, run)
      if (fresh === null) {
        DiagnosticLogger.info(
          'home-list-anchor',
          'date_jump_prev_drop_stale',
          `${this.debugState()} requested=${requestedPrev} myEpoch=${myEpoch}`,
        )
        return 0
      }
      if (fresh.length > 0) {
        this.dataSource.prependData(fresh)
        this.itemCount = this.dataSource.totalCount()
        if (afterPrepend) {
          afterPrepend(fresh.length)
        }
      }
      this.prevGid = list.prevGid
      this.lastPrev = requestedPrev
      DiagnosticLogger.info(
        'home-list-anchor',
        'date_jump_prev_done',
        `${this.debugState()} requested=${requestedPrev} incoming=${list.gallerys.length} fresh=${fresh.length}`,
      )
      return fresh.length
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch && this.isCurrentPagingRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('home', 'date_jump_loadprev_failed', e.message)
    } finally {
      if (this.isCurrentPagingRun(run)) {
        this.isLoading = false
      }
    }
    return 0
  }

  /** Favorite-type profiles use page/from for previous pages when EH exposes ptt navigation. */
  private async loadPreviousFavorites(afterPrepend?: (prependedCount: number) => void): Promise<number> {
    DiagnosticLogger.info('home-list-anchor', 'fav_prev_enter', this.debugState())
    const requestedPage: number = this.favPrevPage
    const requestedPrev: string = this.prevGid
    if (requestedPage < 0 && requestedPrev.length === 0) {
      DiagnosticLogger.info('home-list-anchor', 'fav_prev_no_cursor', this.debugState())
      return 0
    }
    const requestKey: string = requestedPage >= 0
      ? `page:${requestedPage}:from:${requestedPrev}`
      : `prev:${requestedPrev}`
    if (requestKey === this.lastPrev && this.errorMessage.length === 0) {
      DiagnosticLogger.info('home-list-anchor', 'fav_prev_repeated_cursor', `${this.debugState()} requestKey=${requestKey}`)
      return 0
    }
    this.isLoading = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    const run: GalleryFirstPageRun = this.captureCurrentListRun()
    try {
      const list: GalleryList = await EhApiService.getInstance().getFavoritesList(
        this.buildFavQuery(
          '',
          requestedPage,
          requestedPage >= 0 ? requestedPrev : '',
          '',
          requestedPage >= 0 ? '' : requestedPrev,
        ),
      )
      const fresh: EhGallery[] | null = await this.translateCurrentPagingRows(list, run)
      if (fresh === null) {
        DiagnosticLogger.info(
          'home-list-anchor',
          'fav_prev_drop_stale',
          `${this.debugState()} requestKey=${requestKey} myEpoch=${myEpoch}`,
        )
        return 0
      }
      if (fresh.length > 0) {
        this.dataSource.prependData(fresh)
        this.itemCount = this.dataSource.totalCount()
        if (afterPrepend) {
          afterPrepend(fresh.length)
        }
      }
      this.prevGid = list.prevGid
      this.favPrevPage = list.prevPage
      this.lastPrev = requestKey
      DiagnosticLogger.info(
        'home-list-anchor',
        'fav_prev_done',
        `${this.debugState()} requestKey=${requestKey} incoming=${list.gallerys.length} fresh=${fresh.length}`,
      )
      return fresh.length
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch && this.isCurrentPagingRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('home', 'fav_loadprev_failed', e.message)
    } finally {
      if (this.isCurrentPagingRun(run)) {
        this.isLoading = false
      }
    }
    return 0
  }

  /** Favorites page paging (favorite-type profiles): page+from forward, nextGid fallback. Ported from
   * the favorites VM — favorites.php pages by page number + last-visible gid, not a pure gid cursor. */
  private async loadMoreFavorites(): Promise<void> {
    DiagnosticLogger.info('home-list-anchor', 'fav_more_enter', this.debugState())
    const page: number = this.favNextPage
    const from: string = page >= 0 ? this.lastVisibleGid() : ''
    const cursor: string = page >= 0 ? from : this.nextGid
    if (cursor.length === 0) {
      this.hasMore = false
      DiagnosticLogger.info('home-list-anchor', 'fav_more_empty_cursor', this.debugState())
      return
    }
    const requestKey: string = page >= 0 ? `page:${page}:from:${from}` : `next:${cursor}`
    if (requestKey === this.lastNext && this.errorMessage.length === 0) {
      this.hasMore = false
      DiagnosticLogger.info('home-list-anchor', 'fav_more_repeated_cursor', `${this.debugState()} requestKey=${requestKey}`)
      return
    }
    this.isLoadingMore = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    const run: GalleryFirstPageRun = this.captureCurrentListRun()
    try {
      const list: GalleryList = await EhApiService.getInstance().getFavoritesList(
        this.buildFavQuery(page >= 0 ? '' : cursor, page, from),
      )
      const fresh: EhGallery[] | null = await this.translateCurrentPagingRows(list, run)
      if (fresh === null) {
        DiagnosticLogger.info(
          'home-list-anchor',
          'fav_more_drop_stale',
          `${this.debugState()} requestKey=${requestKey} myEpoch=${myEpoch}`,
        )
        return
      }
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
      DiagnosticLogger.info(
        'home-list-anchor',
        'fav_more_done',
        `${this.debugState()} requestKey=${requestKey} incoming=${list.gallerys.length} fresh=${fresh.length}`,
      )
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch && this.isCurrentPagingRun(run)) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('home', 'fav_loadmore_failed', e.message)
    } finally {
      if (this.isCurrentPagingRun(run)) {
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
    for (let index: number = 0; index < current.length; index++) {
      const g: EhGallery = current[index]
      if (g.gid === gid) {
        const next: EhGallery = g.copy()
        next.favcat = favcat
        next.favTitle = favTitle
        this.dataSource.replaceDataAt(index, next)
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

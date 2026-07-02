import {
  EhApiService,
  EhGallery,
  GalleryList,
  FavoritesQuery,
  BasicDataSource,
  Favcat,
  FavSelectionState,
  FavcatSlotResolver,
  FavcatSlotResolveResult,
  TagTranslationService,
  connectTagTranslationSettings,
  EhConstants,
  connectLocalFav,
  connectSiteMode,
  EhErrorText,
  EhPageCacheService,
  LocalBlockService,
  DiagnosticLogger,
} from 'shared'
import { common } from '@kit.AbilityKit'

/**
 * Drives the favorites page. Same BasicDataSource + @Trace itemCount pattern as the home/search
 * VMs; additionally holds the favcat selector bar (`favList`) and the selected slot (`favcat`,
 * 'a' = all, 'l' = local). Favorites rows reuse EhGalleryListParser (same gltc layout); the favcat
 * bar comes from EhFavcatListParser for remote slots, while local reads the persisted local list.
 */
@ObservedV2
export class FavoritesViewModel {
  dataSource: BasicDataSource<EhGallery> = new BasicDataSource<EhGallery>()
  @Trace itemCount: number = 0
  @Trace isLoading: boolean = false
  @Trace isLoadingMore: boolean = false
  @Trace hasMore: boolean = true
  @Trace errorMessage: string = ''
  @Trace favList: Favcat[] = []
  @Trace favcat: string = 'a'
  // Favorites sort order: fs_f (by favorited time, EH default) / fs_p (by posted time).
  @Trace favOrder: string = EhConstants.FAV_ORDER_FAV
  private nextGid: string = ''
  private prevGid: string = ''
  private nextPage: number = -1
  private prevPage: number = -1
  private maxPage: number = 0
  private lastNext: string = ''
  private lastPrev: string = ''
  private afterJump: boolean = false
  private cacheRenderVersion: number = 0
  // Generation token: every page-1 reset (load via order toggle / favcat switch / refresh) bumps it
  // so an in-flight loadMore that resumes afterwards discards its now-stale (wrong favcat/order)
  // page instead of mixing it into the new list. selectFavcat/toggleOrder run without isLoadingMore.
  private epoch: number = 0
  private context: common.UIAbilityContext | null = null

  setContext(context: common.UIAbilityContext): void {
    this.context = context
  }

  private buildQuery(
    next: string,
    page: number = -1,
    from: string = '',
    seek: string = '',
    prev: string = '',
  ): FavoritesQuery {
    return {
      isEx: connectSiteMode().isEx,
      favcat: this.favcat,
      next: next,
      prev: prev,
      seek: seek,
      page: page,
      from: from,
      // The favorites TAB always browses the full favcat; f_search now lives on the shared adaptive
      // search page (favorite scope), opened from the title-bar magnifier — not in this list.
      search: '',
      order: this.favOrder,
    }
  }

  private cacheKey(): string {
    return EhPageCacheService.favoritesListKey(connectSiteMode().isEx, this.favcat, this.favOrder)
  }

  private isLocalFavcat(): boolean {
    return this.favcat === 'l'
  }

  private async fetchPage(
    next: string,
    page: number = -1,
    from: string = '',
    seek: string = '',
    prev: string = '',
  ): Promise<GalleryList> {
    return await EhApiService.getInstance().getFavoritesList(
      this.buildQuery(next, page, from, seek, prev),
    )
  }

  /** Fix this VM to one favcat + order WITHOUT loading (retained per-favcat page; loadData runs on
   * first activation). The favcat is stable for the page's lifetime, so selectFavcat is not used. */
  configure(favcat: string, orderByPosted: boolean): void {
    this.favcat = favcat
    this.favOrder = orderByPosted ? EhConstants.FAV_ORDER_POSTED : EhConstants.FAV_ORDER_FAV
  }

  /** Apply a new GLOBAL order (favorited-time ↔ posted-time) and reload from page 1; no-op if unchanged.
   * Used by each retained favcat page when the shared order bus toggles. */
  async applyOrder(orderByPosted: boolean): Promise<void> {
    if (this.isLocalFavcat()) {
      return
    }
    const next: string = orderByPosted ? EhConstants.FAV_ORDER_POSTED : EhConstants.FAV_ORDER_FAV
    if (this.favOrder === next) {
      return
    }
    this.favOrder = next
    await this.load()
  }

  /** Toggle favorited-time ↔ posted-time order and reload from page 1. */
  async toggleOrder(): Promise<void> {
    if (this.isLoading || this.isLocalFavcat()) {
      return
    }
    this.favOrder =
      this.favOrder === EhConstants.FAV_ORDER_FAV
        ? EhConstants.FAV_ORDER_POSTED
        : EhConstants.FAV_ORDER_FAV
    await this.load()
  }

  isOrderByPosted(): boolean {
    return this.favOrder === EhConstants.FAV_ORDER_POSTED
  }

  /** Seed selector metadata from the shared restored snapshot before the first network response. */
  seedFavList(favcats: Favcat[]): void {
    if (this.favList.length === 0 && favcats.length > 0) {
      this.mergeFavList(favcats)
    }
  }

  /**
   * Accumulate the favcat selector list across loads. EH OMITS the currently-selected favcat
   * from the bar (the active chip isn't a clickable `fp` element), so a filtered page's favList
   * is missing exactly the slot every row on it belongs to. Overwriting would break favTitle→slot
   * resolution for the active favcat; merging (Map keeps slot insertion order) keeps the full set
   * seen on the first 全部 load. Incoming wins for fresh counts.
   */
  private mergeFavList(incoming: Favcat[]): void {
    if (incoming.length === 0) {
      return
    }
    const byId: Map<string, Favcat> = new Map<string, Favcat>()
    this.favList.forEach((f: Favcat) => byId.set(f.favId, f))
    incoming.forEach((f: Favcat) => {
      const current: Favcat | undefined = byId.get(f.favId)
      byId.set(f.favId, this.mergeFavcatMetadata(current, f))
    })
    const merged: Favcat[] = []
    byId.forEach((f: Favcat) => merged.push(f))
    this.favList = merged
  }

  private mergeFavcatMetadata(current: Favcat | undefined, incoming: Favcat): Favcat {
    if (current === undefined) {
      return incoming
    }
    const currentPlaceholder: boolean = FavSelectionState.isPlaceholderFavcat(current)
    const incomingPlaceholder: boolean = FavSelectionState.isPlaceholderFavcat(incoming)
    if (incomingPlaceholder && !currentPlaceholder) {
      return current
    }
    if (!incomingPlaceholder && currentPlaceholder) {
      return incoming
    }
    if (!incomingPlaceholder) {
      const next: Favcat = new Favcat(incoming.favId, incoming.favTitle, incoming.totNum)
      if (incoming.totNum === 0 && current.totNum > 0 && incoming.favTitle === current.favTitle) {
        next.totNum = current.totNum
      }
      return next
    }
    return current
  }

  /**
   * Favorites rows carry the favcat NAME (favTitle) but no border-color, so the parser can't
   * set the slot. Resolve favTitle → slot against the favcat selector list so GalleryCard can
   * color the heart. Mutates in place; no-op when favList is empty or the row already has a slot.
   */
  private resolveFavcatSlots(gallerys: EhGallery[]): void {
    this.resolveFavcatSlotsFrom(gallerys, this.favList)
  }

  private resolveFavcatSlotsFrom(gallerys: EhGallery[], favcats: Favcat[]): void {
    FavcatSlotResolver.applyInPlace(gallerys, favcats)
  }

  private async translateRows(rows: EhGallery[]): Promise<EhGallery[]> {
    if (this.context === null || !connectTagTranslationSettings().enabled) {
      return rows
    }
    return TagTranslationService.translateGalleries(this.context, rows)
  }

  private async applyCachedFirstPageIfEmpty(): Promise<void> {
    if (this.context === null || this.itemCount > 0 || this.isLocalFavcat()) {
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
    this.mergeFavList(visibleCached.favList)
    this.resolveFavcatSlots(visibleCached.gallerys)
    const rows: EhGallery[] = visibleCached.gallerys.map((g: EhGallery) => g.copy())
    this.cacheRenderVersion = this.cacheRenderVersion + 1
    const renderVersion: number = this.cacheRenderVersion
    this.dataSource.setData(rows)
    this.itemCount = this.dataSource.totalCount()
    this.nextGid = cached.nextGid
    this.prevGid = cached.prevGid
    this.nextPage = cached.nextPage
    this.prevPage = cached.prevPage
    this.maxPage = cached.maxPage
    this.hasMore = this.hasForwardPage(cached)
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

  private async renderFirstPageRows(
    list: GalleryList,
    deferTranslation: boolean,
    saveCache: boolean = true,
  ): Promise<void> {
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
      if (saveCache) {
        const snapshot: GalleryList = list.copy()
        snapshot.gallerys = translated
        await this.saveFirstPageCache(snapshot)
      }
      return
    }
    this.dataSource.setData(displayRows)
    this.itemCount = this.dataSource.totalCount()
    if (connectTagTranslationSettings().enabled && saveCache) {
      this.translateCachedRowsLater(displayRows, renderVersion, list)
    } else if (saveCache) {
      await this.saveFirstPageCache(list)
    }
  }

  private async saveFirstPageCache(list: GalleryList): Promise<void> {
    if (this.context === null || this.isLocalFavcat()) {
      return
    }
    const snapshot: GalleryList = list.copy()
    snapshot.favList = this.favList
    await EhPageCacheService.saveGalleryList(this.context, this.cacheKey(), snapshot)
  }

  private hasForwardPage(list: GalleryList): boolean {
    return list.nextPage > 0 || list.nextGid.length > 0
  }

  private canLoadPreviousAfterJump(): boolean {
    return this.afterJump && !this.isLocalFavcat() && (this.prevPage >= 0 || this.prevGid.length > 0)
  }

  canJumpRemote(): boolean {
    return !this.isLocalFavcat() && !this.isLoading && !this.isLoadingMore
  }

  canJumpToPageNumber(): boolean {
    return this.canJumpRemote() && (this.nextPage >= 0 || this.prevPage >= 0 || this.maxPage > 0)
  }

  shouldJumpFirstPage(): boolean {
    return this.afterJump && !this.isLocalFavcat()
  }

  currentPageNumber(): number {
    if (this.prevPage >= 0) {
      return this.prevPage + 2
    }
    if (this.nextPage >= 0) {
      return this.nextPage
    }
    return 1
  }

  pageCount(): number {
    return this.maxPage > 0 ? this.maxPage + 1 : 0
  }

  private didPagingAdvance(requestedPage: number, requestedCursor: string, list: GalleryList): boolean {
    if (requestedPage >= 0) {
      return list.nextPage > 0 || list.nextGid.length > 0
    }
    return list.nextGid.length > 0 && list.nextGid !== requestedCursor
  }

  private lastVisibleGid(): string {
    const rows: EhGallery[] = this.dataSource.getAll()
    if (rows.length === 0) {
      return ''
    }
    return rows[rows.length - 1].gid
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
    if (!this.isLoading && !this.isLoadingMore) {
      await this.load()
    }
  }

  /**
   * Favorites rows often carry only favTitle, not the numeric slot. If real favcat metadata arrives
   * after the rows were first rendered, re-resolve visible rows and replace the datasource so card
   * heart colors update in the current process instead of requiring an app restart.
   */
  resolveVisibleFavoriteSlotsFrom(favcats: Favcat[]): boolean {
    if (this.isLocalFavcat() || this.itemCount === 0 || favcats.length === 0) {
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

  /** First load / reload of the current favcat from page 1. */
  async load(): Promise<void> {
    if (this.isLoading) {
      return
    }
    // All page-1 reset paths funnel through load() — bump here so any in-flight loadMore is voided.
    // Keep current rows visible until the replacement page succeeds; selector switches must not
    // blank the whole Favorites body. Drop the old cursor immediately so a failed reload cannot
    // continue paging stale favcat/order data afterwards.
    this.epoch = this.epoch + 1
    this.isLoading = true
    this.errorMessage = ''
    this.nextGid = ''
    this.prevGid = ''
    this.nextPage = -1
    this.prevPage = -1
    this.maxPage = 0
    this.lastNext = ''
    this.lastPrev = ''
    this.afterJump = false
    this.hasMore = false
    await this.applyCachedFirstPageIfEmpty()
    if (this.isLocalFavcat()) {
      const localRows: EhGallery[] = connectLocalFav().items
        .filter((g: EhGallery) => !LocalBlockService.isGalleryBlocked(g))
        .map((g: EhGallery) => g.copy())
      this.dataSource.setData(await this.translateRows(localRows))
      this.itemCount = this.dataSource.totalCount()
      this.favList = []
      this.isLoading = false
      DiagnosticLogger.info(
        'favorites',
        'load_local_done',
        `favcat=${this.favcat} rows=${this.itemCount}`,
      )
      return
    }
    try {
      const list: GalleryList = await this.fetchPage('')
      this.mergeFavList(list.favList)
      this.resolveFavcatSlots(list.gallerys)
      await this.renderFirstPageRows(list, this.itemCount === 0)
      this.nextGid = list.nextGid
      this.prevGid = list.prevGid
      this.nextPage = list.nextPage
      this.prevPage = list.prevPage
      this.maxPage = list.maxPage
      this.hasMore = this.hasForwardPage(list)
      DiagnosticLogger.info(
        'favorites',
        'load_done',
        `favcat=${this.favcat} order=${this.favOrder} rows=${list.gallerys.length} visible=${this.itemCount} nextPage=${this.nextPage} prevPage=${this.prevPage} nextHash=${DiagnosticLogger.ownerHash(this.nextGid)} prevHash=${DiagnosticLogger.ownerHash(this.prevGid)} hasMore=${this.hasMore}`,
      )
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn(
        'favorites',
        'load_failed',
        `favcat=${this.favcat} order=${this.favOrder} error=${(err as Error).message}`,
      )
    }
    this.isLoading = false
  }

  /** Switch favcat slot ('a' = all, '0'-'9') and reload. */
  async selectFavcat(favcat: string): Promise<void> {
    if (this.favcat === favcat || this.isLoading) {
      return
    }
    this.favcat = favcat
    await this.load()
  }

  /** Pull-to-refresh: guarded so a concurrent loadMore can't interleave. */
  async refresh(afterPrepend?: (prependedCount: number) => void): Promise<void> {
    if (this.isLoading || this.isLoadingMore) {
      return
    }
    if (this.canLoadPreviousAfterJump()) {
      await this.loadPrevious(afterPrepend)
      return
    }
    await this.load()
  }

  async jumpToPage(pageNumber: number): Promise<boolean> {
    const requestedPage: number = pageNumber - 1
    const pageCount: number = this.pageCount()
    if (!this.canJumpRemote() || requestedPage < 0 || (pageCount > 0 && pageNumber > pageCount)) {
      return false
    }
    DiagnosticLogger.info(
      'favorites',
      'jump_page_enter',
      `favcat=${this.favcat} order=${this.favOrder} requestedPage=${requestedPage}`,
    )
    this.epoch = this.epoch + 1
    this.isLoading = true
    this.errorMessage = ''
    this.nextGid = ''
    this.prevGid = ''
    this.nextPage = -1
    this.prevPage = -1
    this.lastNext = ''
    this.lastPrev = ''
    this.hasMore = false
    try {
      const list: GalleryList = await this.fetchPage('', requestedPage, '')
      this.mergeFavList(list.favList)
      this.resolveFavcatSlots(list.gallerys)
      await this.renderFirstPageRows(list, this.itemCount === 0, false)
      this.nextGid = list.nextGid
      this.prevGid = list.prevGid
      this.nextPage = list.nextPage
      this.prevPage = list.prevPage
      this.maxPage = list.maxPage
      this.afterJump = true
      this.hasMore = this.hasForwardPage(list)
      DiagnosticLogger.info(
        'favorites',
        'jump_page_done',
        `favcat=${this.favcat} order=${this.favOrder} requestedPage=${requestedPage} rows=${list.gallerys.length} visible=${this.itemCount} nextPage=${this.nextPage} prevPage=${this.prevPage} nextHash=${DiagnosticLogger.ownerHash(this.nextGid)} prevHash=${DiagnosticLogger.ownerHash(this.prevGid)}`,
      )
      this.isLoading = false
      return true
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn(
        'favorites',
        'jump_page_failed',
        `favcat=${this.favcat} order=${this.favOrder} requestedPage=${requestedPage} error=${(err as Error).message}`,
      )
    }
    this.isLoading = false
    return false
  }

  async jumpToDateAfter(seek: string): Promise<boolean> {
    const dateText: string = seek.trim()
    if (!this.canJumpRemote() || dateText.length === 0) {
      return false
    }
    DiagnosticLogger.info(
      'favorites',
      'jump_date_after_enter',
      `favcat=${this.favcat} order=${this.favOrder} seek=${dateText}`,
    )
    this.epoch = this.epoch + 1
    this.isLoading = true
    this.errorMessage = ''
    this.nextGid = ''
    this.prevGid = ''
    this.nextPage = -1
    this.prevPage = -1
    this.maxPage = 0
    this.lastNext = ''
    this.lastPrev = ''
    this.hasMore = false
    try {
      const list: GalleryList = await this.fetchPage('', -1, '', dateText)
      this.mergeFavList(list.favList)
      this.resolveFavcatSlots(list.gallerys)
      await this.renderFirstPageRows(list, this.itemCount === 0, false)
      this.nextGid = list.nextGid
      this.prevGid = list.prevGid
      this.nextPage = list.nextPage
      this.prevPage = list.prevPage
      this.maxPage = list.maxPage
      this.afterJump = true
      this.hasMore = this.hasForwardPage(list)
      DiagnosticLogger.info(
        'favorites',
        'jump_date_after_done',
        `favcat=${this.favcat} order=${this.favOrder} seek=${dateText} rows=${list.gallerys.length} visible=${this.itemCount} nextPage=${this.nextPage} prevPage=${this.prevPage} nextHash=${DiagnosticLogger.ownerHash(this.nextGid)} prevHash=${DiagnosticLogger.ownerHash(this.prevGid)}`,
      )
      this.isLoading = false
      return true
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn(
        'favorites',
        'jump_date_after_failed',
        `favcat=${this.favcat} order=${this.favOrder} seek=${dateText} error=${(err as Error).message}`,
      )
    }
    this.isLoading = false
    return false
  }

  async jumpFirstPage(): Promise<boolean> {
    if (this.isLoading || this.isLoadingMore) {
      return false
    }
    DiagnosticLogger.info(
      'favorites',
      'jump_first_page_enter',
      `favcat=${this.favcat} order=${this.favOrder} afterJump=${this.afterJump}`,
    )
    await this.load()
    DiagnosticLogger.info(
      'favorites',
      'jump_first_page_done',
      `favcat=${this.favcat} order=${this.favOrder} visible=${this.itemCount}`,
    )
    return true
  }

  private async loadPrevious(afterPrepend?: (prependedCount: number) => void): Promise<number> {
    const requestedPage: number = this.prevPage
    const requestedPrev: string = this.prevGid
    if (requestedPage < 0 && requestedPrev.length === 0) {
      DiagnosticLogger.info(
        'favorites',
        'loadprev_no_cursor',
        `favcat=${this.favcat} order=${this.favOrder}`,
      )
      return 0
    }
    const requestKey: string = requestedPage >= 0
      ? `page:${requestedPage}:from:${requestedPrev}`
      : `prev:${requestedPrev}`
    if (requestKey === this.lastPrev && this.errorMessage.length === 0) {
      DiagnosticLogger.info(
        'favorites',
        'loadprev_repeated_cursor',
        `favcat=${this.favcat} order=${this.favOrder} requestHash=${DiagnosticLogger.ownerHash(requestKey)}`,
      )
      return 0
    }
    this.isLoading = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    DiagnosticLogger.info(
      'favorites',
      'loadprev_start',
      `favcat=${this.favcat} order=${this.favOrder} requestHash=${DiagnosticLogger.ownerHash(requestKey)} epoch=${myEpoch}`,
    )
    try {
      const list: GalleryList = await this.fetchPage(
        '',
        requestedPage,
        requestedPage >= 0 ? requestedPrev : '',
        '',
        requestedPage >= 0 ? '' : requestedPrev,
      )
      if (this.epoch === myEpoch) {
        this.mergeFavList(list.favList)
        this.resolveFavcatSlots(list.gallerys)
        const fresh: EhGallery[] = await this.translateRows(this.dedupeNew(list.gallerys))
        if (fresh.length > 0) {
          this.dataSource.prependData(fresh)
          this.itemCount = this.dataSource.totalCount()
          if (afterPrepend) {
            afterPrepend(fresh.length)
          }
        }
        this.prevGid = list.prevGid
        this.prevPage = list.prevPage
        this.maxPage = list.maxPage
        this.lastPrev = requestKey
        DiagnosticLogger.info(
          'favorites',
          'loadprev_done',
          `favcat=${this.favcat} order=${this.favOrder} requestHash=${DiagnosticLogger.ownerHash(requestKey)} incoming=${list.gallerys.length} fresh=${fresh.length} total=${this.itemCount} prevPage=${this.prevPage} prevHash=${DiagnosticLogger.ownerHash(this.prevGid)}`,
        )
        this.isLoading = false
        return fresh.length
      }
      DiagnosticLogger.info(
        'favorites',
        'loadprev_stale_drop',
        `favcat=${this.favcat} order=${this.favOrder} requestEpoch=${myEpoch} currentEpoch=${this.epoch}`,
      )
    } catch (err) {
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn(
        'favorites',
        'loadprev_failed',
        `favcat=${this.favcat} order=${this.favOrder} requestHash=${DiagnosticLogger.ownerHash(requestKey)} error=${(err as Error).message}`,
      )
    }
    this.isLoading = false
    return 0
  }

  async loadMore(): Promise<void> {
    if (this.isLocalFavcat() || this.isLoading || this.isLoadingMore || !this.hasMore) {
      return
    }
    const page: number = this.nextPage
    const from: string = page >= 0 ? this.lastVisibleGid() : ''
    const cursor: string = page >= 0 ? from : this.nextGid
    const requestKey: string = page >= 0 ? `page:${page}:from:${from}` : `next:${cursor}`
    if (cursor.length === 0) {
      this.hasMore = false
      DiagnosticLogger.info(
        'favorites',
        'loadmore_no_cursor',
        `favcat=${this.favcat} order=${this.favOrder} page=${page}`,
      )
      return
    }
    if (requestKey === this.lastNext && this.errorMessage.length === 0) {
      this.hasMore = false
      DiagnosticLogger.warn(
        'favorites',
        'loadmore_duplicate_cursor',
        `favcat=${this.favcat} order=${this.favOrder} requestHash=${DiagnosticLogger.ownerHash(requestKey)}`,
      )
      return
    }
    this.isLoadingMore = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
    DiagnosticLogger.info(
      'favorites',
      'loadmore_start',
      `favcat=${this.favcat} order=${this.favOrder} page=${page} cursorHash=${DiagnosticLogger.ownerHash(cursor)} fromHash=${DiagnosticLogger.ownerHash(from)} epoch=${myEpoch}`,
    )
    try {
      const list: GalleryList = await this.fetchPage(
        page >= 0 ? '' : cursor,
        page,
        from,
      )
      // A favcat switch / order toggle / refresh landed while this fetch was in flight → these rows
      // belong to the OLD favcat/order. Drop them rather than mixing them into the new list.
      if (this.epoch === myEpoch) {
        const fresh: EhGallery[] = await this.translateRows(this.dedupeNew(list.gallerys))
        this.resolveFavcatSlots(fresh)
        if (fresh.length > 0) {
          this.dataSource.appendData(fresh)
          this.itemCount = this.dataSource.totalCount()
        }
        this.nextGid = list.nextGid
        this.nextPage = list.nextPage
        this.maxPage = list.maxPage
        this.lastNext = requestKey
        // Do not let dedupe decide pagination. EH/eros_fe continue by page/cursor progress; fresh rows
        // only decide whether there is anything visible to append in this gid-keyed list.
        this.hasMore = this.didPagingAdvance(page, cursor, list)
        DiagnosticLogger.info(
          'favorites',
          'loadmore_done',
          `favcat=${this.favcat} order=${this.favOrder} requestedPage=${page} rawRows=${list.gallerys.length} freshRows=${fresh.length} total=${this.itemCount} nextPage=${this.nextPage} nextHash=${DiagnosticLogger.ownerHash(this.nextGid)} hasMore=${this.hasMore}`,
        )
      } else {
        DiagnosticLogger.warn(
          'favorites',
          'loadmore_stale_drop',
          `favcat=${this.favcat} order=${this.favOrder} requestEpoch=${myEpoch} currentEpoch=${this.epoch}`,
        )
      }
    } catch (err) {
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
        DiagnosticLogger.warn(
          'favorites',
          'loadmore_failed',
          `favcat=${this.favcat} order=${this.favOrder} page=${page} cursorHash=${DiagnosticLogger.ownerHash(cursor)} error=${(err as Error).message}`,
        )
      }
    }
    this.isLoadingMore = false
  }

  canLoadMore(): boolean {
    return this.hasMore && !this.isLoadingMore && this.errorMessage.length === 0
  }

  applyFavoriteMutation(gid: string, favcat: string, favTitle: string): void {
    if (gid.length === 0 || this.itemCount === 0 || this.isLocalFavcat()) {
      return
    }
    const current: EhGallery[] = this.dataSource.getAll()
    let changed: boolean = false
    const nextRows: EhGallery[] = []
    current.forEach((g: EhGallery) => {
      if (g.gid === gid) {
        const stillInCurrentFavcat: boolean =
          favcat.length > 0 && (this.favcat === 'a' || this.favcat === favcat)
        if (!stillInCurrentFavcat) {
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

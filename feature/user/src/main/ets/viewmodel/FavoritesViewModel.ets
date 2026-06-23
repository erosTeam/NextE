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
  private nextPage: number = -1
  private lastNext: string = ''
  // Generation token: every page-1 reset (load via order toggle / favcat switch / refresh) bumps it
  // so an in-flight loadMore that resumes afterwards discards its now-stale (wrong favcat/order)
  // page instead of mixing it into the new list. selectFavcat/toggleOrder run without isLoadingMore.
  private epoch: number = 0
  private context: common.UIAbilityContext | null = null

  setContext(context: common.UIAbilityContext): void {
    this.context = context
  }

  private buildQuery(next: string, page: number = -1, from: string = ''): FavoritesQuery {
    return {
      isEx: connectSiteMode().isEx,
      favcat: this.favcat,
      next: next,
      page: page,
      from: from,
      // The favorites TAB always browses the full favcat; f_search now lives on the shared adaptive
      // search page (favorite scope), opened from the title-bar magnifier — not in this list.
      search: '',
      order: this.favOrder,
    }
  }

  private isLocalFavcat(): boolean {
    return this.favcat === 'l'
  }

  private async fetchPage(
    next: string,
    page: number = -1,
    from: string = '',
  ): Promise<GalleryList> {
    return await EhApiService.getInstance().getFavoritesList(
      this.buildQuery(next, page, from),
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

  private hasForwardPage(list: GalleryList): boolean {
    return list.nextPage > 0 || list.nextGid.length > 0
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
    this.nextPage = -1
    this.lastNext = ''
    this.hasMore = false
    if (this.isLocalFavcat()) {
      const localRows: EhGallery[] = connectLocalFav().items.map((g: EhGallery) => g.copy())
      this.dataSource.setData(await this.translateRows(localRows))
      this.itemCount = this.dataSource.totalCount()
      this.favList = []
      this.isLoading = false
      return
    }
    try {
      const list: GalleryList = await this.fetchPage('')
      this.mergeFavList(list.favList)
      this.resolveFavcatSlots(list.gallerys)
      const rows: EhGallery[] = await this.translateRows(list.gallerys)
      this.dataSource.setData(rows)
      this.itemCount = this.dataSource.totalCount()
      this.nextGid = list.nextGid
      this.nextPage = list.nextPage
      this.hasMore = this.hasForwardPage(list)
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
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
  async refresh(): Promise<void> {
    if (this.isLoading || this.isLoadingMore) {
      return
    }
    await this.load()
  }

  async loadMore(): Promise<void> {
    if (this.isLocalFavcat() || this.isLoading || this.isLoadingMore || !this.hasMore) {
      return
    }
    const page: number = this.nextPage
    const from: string = page >= 0 ? this.lastVisibleGid() : ''
    const cursor: string = page >= 0 ? from : this.nextGid
    const requestKey: string = page >= 0 ? `page:${page}:from:${from}` : `next:${cursor}`
    if (cursor.length === 0 || requestKey === this.lastNext) {
      this.hasMore = false
      return
    }
    this.isLoadingMore = true
    this.errorMessage = ''
    const myEpoch: number = this.epoch
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
        this.lastNext = requestKey
        // Do not let dedupe decide pagination. EH/eros_fe continue by page/cursor progress; fresh rows
        // only decide whether there is anything visible to append in this gid-keyed list.
        this.hasMore = this.didPagingAdvance(page, cursor, list)
      }
    } catch (err) {
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
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

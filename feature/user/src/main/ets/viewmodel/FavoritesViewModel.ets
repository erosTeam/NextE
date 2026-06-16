import {
  EhApiService,
  EhGallery,
  GalleryList,
  FavoritesQuery,
  BasicDataSource,
  Favcat,
  EhConstants,
  connectSiteMode,
  DiagnosticLogger,
} from 'shared'

/**
 * Drives the favorites page. Same BasicDataSource + @Trace itemCount pattern as the home/search
 * VMs; additionally holds the favcat selector bar (`favList`) and the selected slot (`favcat`,
 * 'a' = all). Favorites rows reuse EhGalleryListParser (same gltc layout); the favcat bar comes
 * from EhFavcatListParser. Requires login — the page gates calls on AuthState.isLogin.
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
  // Generation token: every page-1 reset (load via order toggle / favcat switch / refresh) bumps it
  // so an in-flight loadMore that resumes afterwards discards its now-stale (wrong favcat/order)
  // page instead of mixing it into the new list. selectFavcat/toggleOrder run without isLoadingMore.
  private epoch: number = 0

  private buildQuery(next: string): FavoritesQuery {
    return {
      isEx: connectSiteMode().isEx,
      favcat: this.favcat,
      next: next,
      // The favorites TAB always browses the full favcat; f_search now lives on the shared adaptive
      // search page (favorite scope), opened from the title-bar magnifier — not in this list.
      search: '',
      order: this.favOrder,
    }
  }

  /** Toggle favorited-time ↔ posted-time order and reload from page 1. */
  async toggleOrder(): Promise<void> {
    if (this.isLoading) {
      return
    }
    this.favOrder =
      this.favOrder === EhConstants.FAV_ORDER_FAV
        ? EhConstants.FAV_ORDER_POSTED
        : EhConstants.FAV_ORDER_FAV
    this.dataSource.setData([])
    this.itemCount = 0
    this.nextGid = ''
    this.hasMore = true
    await this.load()
  }

  isOrderByPosted(): boolean {
    return this.favOrder === EhConstants.FAV_ORDER_POSTED
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
    incoming.forEach((f: Favcat) => byId.set(f.favId, f))
    const merged: Favcat[] = []
    byId.forEach((f: Favcat) => merged.push(f))
    this.favList = merged
  }

  /**
   * Favorites rows carry the favcat NAME (favTitle) but no border-color, so the parser can't
   * set the slot. Resolve favTitle → slot against the favcat selector list so GalleryCard can
   * color the heart. Mutates in place; no-op when favList is empty or the row already has a slot.
   */
  private resolveFavcatSlots(gallerys: EhGallery[]): void {
    if (this.favList.length === 0) {
      return
    }
    gallerys.forEach((g: EhGallery) => {
      if (g.favcat.length === 0 && g.favTitle.length > 0) {
        const hit: Favcat | undefined = this.favList.find((f: Favcat) => f.favTitle === g.favTitle)
        if (hit !== undefined) {
          g.favcat = hit.favId
        }
      }
    })
  }

  /** First load / reload of the current favcat from page 1. */
  async load(): Promise<void> {
    if (this.isLoading) {
      return
    }
    // All page-1 reset paths funnel through load() — bump here so any in-flight loadMore is voided.
    this.epoch = this.epoch + 1
    this.isLoading = true
    this.errorMessage = ''
    try {
      let list: GalleryList = await EhApiService.getInstance().getFavoritesList(this.buildQuery(''))
      // EH's inline_set sort order is sticky-by-one-load: the first request after a toggle only
      // SETS the preference and returns the old order. If the response order lags what we asked
      // for, re-load once (the preference is now applied) — eros_fe's FavOrderException handling.
      if (list.favOrder.length > 0 && list.favOrder !== this.favOrder) {
        list = await EhApiService.getInstance().getFavoritesList(this.buildQuery(''))
      }
      this.mergeFavList(list.favList)
      this.resolveFavcatSlots(list.gallerys)
      this.dataSource.setData(list.gallerys)
      this.itemCount = this.dataSource.totalCount()
      this.nextGid = list.nextGid
      this.hasMore = list.nextGid.length > 0
    } catch (err) {
      const e = err as Error
      this.errorMessage = e.message
      DiagnosticLogger.warn('favorites', 'load_failed', e.message)
    }
    this.isLoading = false
  }

  /** Switch favcat slot ('a' = all, '0'-'9') and reload. */
  async selectFavcat(favcat: string): Promise<void> {
    if (this.favcat === favcat || this.isLoading) {
      return
    }
    this.favcat = favcat
    this.dataSource.setData([])
    this.itemCount = 0
    this.nextGid = ''
    this.hasMore = true
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
    if (this.isLoading || this.isLoadingMore || !this.hasMore) {
      return
    }
    this.isLoadingMore = true
    const myEpoch: number = this.epoch
    try {
      const list: GalleryList = await EhApiService.getInstance().getFavoritesList(
        this.buildQuery(this.nextGid),
      )
      // A favcat switch / order toggle / refresh landed while this fetch was in flight → these rows
      // belong to the OLD favcat/order. Drop them rather than mixing them into the new list.
      if (this.epoch === myEpoch) {
        this.resolveFavcatSlots(list.gallerys)
        this.dataSource.appendData(list.gallerys)
        this.itemCount = this.dataSource.totalCount()
        this.nextGid = list.nextGid
        this.hasMore = list.nextGid.length > 0 && list.gallerys.length > 0
      }
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch) {
        this.errorMessage = e.message
      }
      DiagnosticLogger.warn('favorites', 'loadmore_failed', e.message)
    }
    this.isLoadingMore = false
  }

  canLoadMore(): boolean {
    return this.hasMore && !this.isLoadingMore
  }
}

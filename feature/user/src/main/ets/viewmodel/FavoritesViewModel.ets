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
  EhErrorText,
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

  private async fetchPageWithOrderSync(next: string): Promise<GalleryList> {
    let list: GalleryList = await EhApiService.getInstance().getFavoritesList(this.buildQuery(next))
    // EH favorites order/display preferences are server-side and can lag by one response after an
    // inline_set change. Keep this guard on every page fetch, not just page 1, so deep paging stays in
    // the selected order after an account/display-mode correction.
    if (list.favOrder.length > 0 && list.favOrder !== this.favOrder) {
      list = await EhApiService.getInstance().getFavoritesList(this.buildQuery(next))
    }
    return list
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
    const next: string = orderByPosted ? EhConstants.FAV_ORDER_POSTED : EhConstants.FAV_ORDER_FAV
    if (this.favOrder === next) {
      return
    }
    this.favOrder = next
    await this.load()
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
    this.hasMore = false
    try {
      const list: GalleryList = await this.fetchPageWithOrderSync('')
      this.mergeFavList(list.favList)
      this.resolveFavcatSlots(list.gallerys)
      this.dataSource.setData(list.gallerys)
      this.itemCount = this.dataSource.totalCount()
      this.nextGid = list.nextGid
      this.hasMore = list.nextGid.length > 0
    } catch (err) {
      const e = err as Error
      this.errorMessage = EhErrorText.forUser(err)
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
    const cursor: string = this.nextGid
    try {
      const list: GalleryList = await this.fetchPageWithOrderSync(cursor)
      // A favcat switch / order toggle / refresh landed while this fetch was in flight → these rows
      // belong to the OLD favcat/order. Drop them rather than mixing them into the new list.
      if (this.epoch === myEpoch) {
        const fresh: EhGallery[] = this.dedupeNew(list.gallerys)
        this.resolveFavcatSlots(fresh)
        if (fresh.length > 0) {
          this.dataSource.appendData(fresh)
          this.itemCount = this.dataSource.totalCount()
        }
        this.nextGid = list.nextGid
        // Continue based on cursor progress, not row count. Some EH pages can overlap already-seen rows;
        // stop only when EH gives no next cursor or repeats the same cursor.
        this.hasMore = list.nextGid.length > 0 && list.nextGid !== cursor
      }
    } catch (err) {
      const e = err as Error
      if (this.epoch === myEpoch) {
        this.errorMessage = EhErrorText.forUser(err)
      }
      DiagnosticLogger.warn('favorites', 'loadmore_failed', e.message)
    }
    this.isLoadingMore = false
  }

  canLoadMore(): boolean {
    return this.hasMore && !this.isLoadingMore
  }
}

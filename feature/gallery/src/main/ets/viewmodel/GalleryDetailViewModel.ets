import {
  EhApiService,
  EhApiPhpService,
  GalleryRatingResult,
  EhConstants,
  EhGallery,
  EhGalleryImage,
  EhGalleryComment,
  GalleryDetailResult,
  connectSiteMode,
  DiagnosticLogger,
  EhErrorText,
  EhCookieStore,
  TagTranslationService,
  connectTagTranslationSettings,
  TagGroup,
  SimpleTag,
  EhPageCacheService,
} from 'shared'
import { common } from '@kit.AbilityKit'

/** Immutable ownership token for one gallery-detail request and its account/site cache scope. */
class GalleryDetailRun {
  epoch: number
  gid: string
  token: string
  isEx: boolean
  memberId: string
  passHash: string
  cacheKey: string

  constructor(
    epoch: number,
    gid: string,
    token: string,
    isEx: boolean,
    memberId: string,
    passHash: string,
    cacheKey: string,
  ) {
    this.epoch = epoch
    this.gid = gid
    this.token = token
    this.isEx = isEx
    this.memberId = memberId
    this.passHash = passHash
    this.cacheKey = cacheKey
  }
}

/**
 * Drives the gallery detail page. Seeded with the list-row gallery (cover + title) so the
 * header paints instantly, then fetches the detail page and merges the richer header +
 * tags + first preview page over it. `images` holds the page-1.. preview entries the
 * reader resolves into full images.
 */
@ObservedV2
export class GalleryDetailViewModel {
  @Trace gallery: EhGallery = new EhGallery()
  @Trace images: EhGalleryImage[] = []
  @Trace comments: EhGalleryComment[] = []
  @Trace loading: boolean = false
  @Trace loaded: boolean = false
  @Trace error: string = ''
  @Trace cachedDetailApplied: boolean = false
  // The detail shows ONLY the first preview page (a peek); previewPageCount drives the "view all"
  // entry → the separate all-thumbnails page owns the rest of the paging (eros_fe firstPageImage).
  @Trace previewPageCount: number = 1
  // Increments only after a real detail/cache result replaces the preview seed. Consumers use this
  // instead of watching individual fields so they never synchronize an intermediate image/page-count pair.
  @Trace previewRevision: number = 0
  private gid: string = ''
  private token: string = ''
  private context: common.UIAbilityContext | null = null
  private detailRenderVersion: number = 0
  private detailEpoch: number = 0
  // Only an applied detail run may write a mutation/translation snapshot back to the cache. A newer
  // account/site replacement invalidates this immediately while old content remains on screen.
  private activeDetailRun: GalleryDetailRun | null = null

  setContext(context: common.UIAbilityContext): void {
    this.context = context
  }

  /** Seed the header from the list row for instant paint. */
  seed(gallery: EhGallery): void {
    this.gallery = gallery
  }

  async load(gid: string, token: string): Promise<void> {
    if (this.loading || this.loaded) {
      return
    }
    const run: GalleryDetailRun = this.beginDetailRun(gid, token)
    this.error = ''
    this.cachedDetailApplied = false
    // Same-process navigation can apply a copied detail snapshot synchronously. This must happen before
    // loading becomes true so a list → detail → back → same-detail open never flashes the empty spinner.
    const memoryDetailApplied: boolean = this.applyRecentDetailIfAvailable(run)
    this.loading = true
    try {
      if (!memoryDetailApplied) {
        await this.applyCachedDetailIfAvailable(run)
      }
      if (!this.isCurrentDetailRun(run)) {
        return
      }
      await this.fetchAndApply(run, false)
      if (this.isCurrentDetailRun(run)) {
        this.loaded = true
      }
    } catch (err) {
      if (!this.isCurrentDetailRun(run)) {
        return
      }
      this.error = EhErrorText.forUser(err)
      const cookieStore: EhCookieStore = EhCookieStore.getInstance()
      DiagnosticLogger.warn(
        'gallery',
        'detail_load_failed',
        `${(err as Error).message} login=${cookieStore.isLogin()} cookies=${cookieStore.nameSummary()}`,
      )
    } finally {
      if (this.isCurrentDetailRun(run)) {
        this.loading = false
      }
    }
  }

  /** Force a replacement after account/site changes without letting an old request own the loading flag. */
  async reloadForContext(): Promise<void> {
    if (this.gid.length === 0 || this.token.length === 0) {
      return
    }
    const run: GalleryDetailRun = this.beginDetailRun(this.gid, this.token)
    this.loading = true
    this.error = ''
    this.cachedDetailApplied = false
    try {
      await this.fetchAndApply(run, true)
      if (this.isCurrentDetailRun(run)) {
        this.loaded = true
      }
    } catch (err) {
      if (!this.isCurrentDetailRun(run)) {
        return
      }
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'detail_context_reload_failed', (err as Error).message)
    } finally {
      if (this.isCurrentDetailRun(run)) {
        this.loading = false
      }
    }
  }

  private beginDetailRun(gid: string, token: string): GalleryDetailRun {
    this.detailEpoch = this.detailEpoch + 1
    // A cache/detail translation that resumes after a replacement must not repaint its former context.
    this.detailRenderVersion = this.detailRenderVersion + 1
    this.gid = gid
    this.token = token
    const isEx: boolean = connectSiteMode().isEx
    const cookieStore: EhCookieStore = EhCookieStore.getInstance()
    const memberId: string = cookieStore.get(EhConstants.COOKIE_MEMBER_ID)
    const passHash: string = cookieStore.get(EhConstants.COOKIE_PASS_HASH)
    return new GalleryDetailRun(
      this.detailEpoch,
      gid,
      token,
      isEx,
      memberId,
      passHash,
      EhPageCacheService.galleryDetailKey(isEx, gid, token),
    )
  }

  private isCurrentDetailRun(run: GalleryDetailRun): boolean {
    if (
      this.detailEpoch !== run.epoch ||
      this.gid !== run.gid ||
      this.token !== run.token ||
      connectSiteMode().isEx !== run.isEx
    ) {
      return false
    }
    const cookieStore: EhCookieStore = EhCookieStore.getInstance()
    return (
      cookieStore.get(EhConstants.COOKIE_MEMBER_ID) === run.memberId &&
      cookieStore.get(EhConstants.COOKIE_PASS_HASH) === run.passHash
    )
  }

  private async applyCachedDetailIfAvailable(run: GalleryDetailRun): Promise<void> {
    if (this.context === null || !this.isCurrentDetailRun(run)) {
      return
    }
    const cached: GalleryDetailResult | null = await EhPageCacheService.loadGalleryDetail(
      this.context,
      run.cacheKey,
    )
    if (cached === null) {
      return
    }
    this.applyCachedDetail(run, cached)
  }

  private applyRecentDetailIfAvailable(run: GalleryDetailRun): boolean {
    if (this.context === null || !this.isCurrentDetailRun(run)) {
      return false
    }
    const cached: GalleryDetailResult | null = EhPageCacheService.getRecentGalleryDetail(run.cacheKey)
    if (cached === null) {
      return false
    }
    return this.applyCachedDetail(run, cached)
  }

  private applyCachedDetail(run: GalleryDetailRun, cached: GalleryDetailResult): boolean {
    if (!this.isCurrentDetailRun(run)) {
      return false
    }
    const merged: EhGallery = this.gallery.merge(cached.gallery)
    this.detailRenderVersion = this.detailRenderVersion + 1
    const renderVersion: number = this.detailRenderVersion
    this.gallery = connectTagTranslationSettings().enabled
      ? merged
      : TagTranslationService.clearGalleryTranslations(merged)
    this.images = cached.images
    // Drop any empty-body comments a previous bad fetch may have cached, so stale blank rows don't show.
    this.comments = cached.comments.filter((c: EhGalleryComment) => c.contentText.length > 0)
    this.previewPageCount = cached.previewPageCount
    this.previewRevision = this.previewRevision + 1
    this.cachedDetailApplied = true
    this.activeDetailRun = run
    this.translateCachedGalleryLater(this.gallery, renderVersion, run)
    return true
  }

  private async translateCachedGalleryLater(
    gallery: EhGallery,
    renderVersion: number,
    run: GalleryDetailRun,
  ): Promise<void> {
    if (this.context === null || !connectTagTranslationSettings().enabled) {
      return
    }
    const translated: EhGallery = await this.translateGallery(gallery)
    if (this.detailRenderVersion !== renderVersion || !this.isCurrentDetailRun(run)) {
      return
    }
    this.gallery = translated
    this.activeDetailRun = run
    await this.saveDetailCache(run)
  }

  private async saveCurrentDetailCache(): Promise<void> {
    const run: GalleryDetailRun | null = this.activeDetailRun
    if (run === null) {
      return
    }
    await this.saveDetailCache(run)
  }

  private async saveDetailCache(run: GalleryDetailRun): Promise<void> {
    if (this.context === null || !this.isCurrentDetailRun(run)) {
      return
    }
    const detail: GalleryDetailResult = new GalleryDetailResult(
      this.gallery,
      this.images,
      this.comments,
      this.previewPageCount,
    )
    await EhPageCacheService.saveGalleryDetail(this.context, run.cacheKey, detail)
  }

  /**
   * Pull-to-refresh for detail: keep the current header/tags/comments/previews rendered while the
   * replacement detail request is in flight, then merge fresh data over the existing gallery.
   */
  async refresh(): Promise<void> {
    if (this.loading || this.gid.length === 0) {
      return
    }
    const run: GalleryDetailRun = this.beginDetailRun(this.gid, this.token)
    this.loading = true
    this.error = ''
    try {
      await this.fetchAndApply(run, true)
      if (this.isCurrentDetailRun(run)) {
        this.loaded = true
        DiagnosticLogger.info(
          'gallery',
          'detail_refresh_ok',
          `gid=${this.gid} images=${this.images.length} comments=${this.comments.length}`,
        )
      }
    } catch (err) {
      if (!this.isCurrentDetailRun(run)) {
        return
      }
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'detail_refresh_failed', (err as Error).message)
      throw new Error(this.error)
    } finally {
      if (this.isCurrentDetailRun(run)) {
        this.loading = false
      }
    }
  }

  private async fetchAndApply(run: GalleryDetailRun, refresh: boolean): Promise<void> {
    if (!this.isCurrentDetailRun(run)) {
      return
    }
    // eros_fe enrich-then-detail order: a sparse seed (URL paste / deep link) carries only gid+token,
    // no fileCount, so fetch the lighter /api.php gdata metadata first to paint a real header (title,
    // cover, fileCount, rating, tags) before the heavier detail page parse lands. A list-row open
    // already seeded fileCount, so this is skipped there — exactly eros_fe's filecount-absent gate.
    if (this.gallery.fileCount.length === 0) {
      await this.enrichFromApi(run)
      if (!this.isCurrentDetailRun(run)) {
        return
      }
    }
    const seedRatingFallBack: number = this.gallery.ratingFallBack
    const seedRatingCount: string = this.gallery.ratingCount
    const seedColorRating: string = this.gallery.colorRating
    const res: GalleryDetailResult = await EhApiService.getInstance().getGalleryDetail(
      run.gid,
      run.token,
      run.isEx,
    )
    if (!this.isCurrentDetailRun(run)) {
      return
    }
    // A valid gallery detail always has preview images. No images AND no comments means the response was
    // not a real detail page (interstitial / IP-throttle / truncated body) — don't overwrite the current
    // header/images/comments with it and, crucially, don't write that garbage to the page cache.
    if (res.images.length === 0 && res.comments.length === 0) {
      DiagnosticLogger.warn(
        'gallery',
        'detail_fetch_empty_skip',
        `gid=${run.gid} no images/comments; treating as a bad response, keeping existing data + cache`,
      )
      return
    }
    const merged: EhGallery = this.gallery.merge(res.gallery)
    if (!refresh) {
      if (seedRatingFallBack > 0 && merged.ratingFallBack <= 0) {
        merged.ratingFallBack = seedRatingFallBack
      }
      if (seedRatingCount.length > 0 && merged.ratingCount.length === 0) {
        merged.ratingCount = seedRatingCount
      }
      if (seedColorRating.length > 0) {
        merged.colorRating = seedColorRating
      }
    }
    this.detailRenderVersion = this.detailRenderVersion + 1
    const renderVersion: number = this.detailRenderVersion
    const translated: EhGallery = await this.translateGallery(merged)
    if (this.detailRenderVersion !== renderVersion || !this.isCurrentDetailRun(run)) {
      return
    }
    this.gallery = translated
    this.images = res.images
    this.comments = res.comments
    this.previewPageCount = res.previewPageCount
    this.previewRevision = this.previewRevision + 1
    this.activeDetailRun = run
    await this.saveDetailCache(run)
  }

  /**
   * eros_fe keeps list/gdata seed rating presentation on first open: detail HTML may have a weaker or
   * differently-derived rating block, while the list row already carries the user's personal rating
   * colour. A pull-to-refresh is the explicit "trust fresh detail" path, so this only applies to the
   * initial non-refresh load.
   */
  private applyNonRefreshSeedRating(
    seedRatingFallBack: number,
    seedRatingCount: string,
    seedColorRating: string,
  ): void {
    if (seedRatingFallBack > 0 && this.gallery.ratingFallBack <= 0) {
      this.gallery.ratingFallBack = seedRatingFallBack
    }
    if (seedRatingCount.length > 0 && this.gallery.ratingCount.length === 0) {
      this.gallery.ratingCount = seedRatingCount
    }
    if (seedColorRating.length > 0) {
      this.gallery.colorRating = seedColorRating
    }
  }

  private async translateGallery(gallery: EhGallery): Promise<EhGallery> {
    if (this.context === null || !connectTagTranslationSettings().enabled) {
      return TagTranslationService.clearGalleryTranslations(gallery)
    }
    return TagTranslationService.translateGalleryTags(this.context, gallery)
  }

  async reapplyTagTranslation(): Promise<void> {
    const run: GalleryDetailRun | null = this.activeDetailRun
    if (run === null || !this.isCurrentDetailRun(run)) {
      return
    }
    this.detailRenderVersion = this.detailRenderVersion + 1
    const renderVersion: number = this.detailRenderVersion
    const source: EhGallery = this.gallery
    const translated: EhGallery = connectTagTranslationSettings().enabled
      ? await this.translateGallery(source)
      : TagTranslationService.clearGalleryTranslations(source)
    if (
      this.detailRenderVersion !== renderVersion ||
      !this.isCurrentDetailRun(run) ||
      this.gallery !== source
    ) {
      return
    }
    this.gallery = translated
    this.activeDetailRun = run
    await this.saveDetailCache(run)
  }

  /** Best-effort gdata metadata enrich for a sparse seed (eros_fe getMoreGalleryInfoOne). Non-fatal:
   * the detail fetch below provides canonical data, so a gdata failure must not block the page. */
  private async enrichFromApi(run: GalleryDetailRun): Promise<void> {
    try {
      const base: string = EhConstants.baseUrl(run.isEx)
      const seed: EhGallery = new EhGallery(run.gid, run.token)
      const list: EhGallery[] = await EhApiPhpService.galleryData(base, [seed])
      if (!this.isCurrentDetailRun(run) || list.length === 0) {
        return
      }
      const merged: EhGallery = this.gallery.merge(list[0])
      this.detailRenderVersion = this.detailRenderVersion + 1
      const renderVersion: number = this.detailRenderVersion
      const translated: EhGallery = await this.translateGallery(merged)
      if (this.detailRenderVersion !== renderVersion || !this.isCurrentDetailRun(run)) {
        return
      }
      this.gallery = translated
    } catch (err) {
      DiagnosticLogger.warn('gallery', 'gdata_enrich_failed', (err as Error).message)
    }
  }

  /** Whether more preview pages exist beyond the first (drives the "view all" entry). */
  hasMorePreviews(): boolean {
    return this.previewPageCount > 1
  }

  /** Apply the known result of an EH favorite write. `merge()` intentionally treats empty fields as
   * "unknown", so delete/move needs an explicit state replacement to clear stale filled hearts. */
  applyRemoteFavoriteState(favcat: string, favTitle: string, favNote: string): void {
    const next: EhGallery = this.gallery.copy()
    next.favcat = favcat
    next.favTitle = favTitle
    next.favNote = favNote
    this.gallery = next
    this.saveCurrentDetailCache()
  }

  applyRatingResult(result: GalleryRatingResult): void {
    const next: EhGallery = this.gallery.copy()
    next.ratingFallBack = result.userRating
    next.rating = result.averageRating
    next.ratingCount = result.ratingCount
    next.colorRating = result.colorRating
    next.isRated = true
    this.gallery = next
    this.saveCurrentDetailCache()
  }

  private cloneComment(c: EhGalleryComment): EhGalleryComment {
    const next: EhGalleryComment = new EhGalleryComment()
    next.commentId = c.commentId
    next.memberId = c.memberId
    next.author = c.author
    next.postedTime = c.postedTime
    next.contentText = c.contentText
    next.contentLinks = c.contentLinks.slice()
    next.contentSpans = c.contentSpans.slice()
    next.score = c.score
    next.vote = c.vote
    next.canEdit = c.canEdit
    next.canVote = c.canVote
    next.scoreDetails = c.scoreDetails.slice()
    next.isUploader = c.isUploader
    next.translationText = c.translationText
    next.translationSpans = c.translationSpans.slice()
    next.translationShown = c.translationShown
    next.translationLoading = c.translationLoading
    next.translationAutoStarted = c.translationAutoStarted
    return next
  }

  applyCommentVote(commentId: string, score: string, vote: number): void {
    for (let i = 0; i < this.comments.length; i++) {
      const c: EhGalleryComment = this.comments[i]
      if (c.commentId === commentId) {
        const comments: EhGalleryComment[] = this.comments.slice()
        const next: EhGalleryComment = this.cloneComment(c)
        next.score = score
        next.vote = vote
        comments[i] = next
        this.comments = comments
        this.saveCurrentDetailCache()
        return
      }
    }
  }

  applyTagVote(namespace: string, tagText: string, vote: number): void {
    const next: EhGallery = this.gallery.copy()
    const groups: TagGroup[] = []
    for (let i = 0; i < next.tagGroups.length; i++) {
      const group: TagGroup = next.tagGroups[i]
      const tags: SimpleTag[] = []
      for (let j = 0; j < group.tags.length; j++) {
        const tag: SimpleTag = group.tags[j].copy()
        if (group.namespace === namespace && tag.text === tagText) {
          tag.vote = vote
        }
        tags.push(tag)
      }
      groups.push(new TagGroup(group.namespace, tags))
    }
    next.tagGroups = groups
    this.gallery = next
    this.saveCurrentDetailCache()
  }

  async rateGallery(stars: number): Promise<GalleryRatingResult> {
    const ratingValue: number = Math.round(stars * 2)
    const result: GalleryRatingResult = await EhApiPhpService.rateGallery(
      EhConstants.baseUrl(connectSiteMode().isEx),
      this.gallery.apikey,
      this.gallery.apiuid,
      this.gallery.gid.length > 0 ? this.gallery.gid : this.gid,
      this.gallery.token.length > 0 ? this.gallery.token : this.token,
      ratingValue,
    )
    this.applyRatingResult(result)
    return result
  }
}

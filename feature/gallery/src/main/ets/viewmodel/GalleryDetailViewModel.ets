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
  TagTranslationService,
  connectTagTranslationSettings,
  TagGroup,
  SimpleTag,
} from 'shared'
import { common } from '@kit.AbilityKit'

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
  // The detail shows ONLY the first preview page (a peek); previewPageCount drives the "view all"
  // entry → the separate all-thumbnails page owns the rest of the paging (eros_fe firstPageImage).
  @Trace previewPageCount: number = 1
  private gid: string = ''
  private token: string = ''
  private context: common.UIAbilityContext | null = null

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
    this.loading = true
    this.error = ''
    this.gid = gid
    this.token = token
    try {
      await this.fetchAndApply(gid, token, false)
      this.loaded = true
    } catch (err) {
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'detail_load_failed', (err as Error).message)
    }
    this.loading = false
  }

  /**
   * Pull-to-refresh for detail: keep the current header/tags/comments/previews rendered while the
   * replacement detail request is in flight, then merge fresh data over the existing gallery.
   */
  async refresh(): Promise<void> {
    if (this.loading || this.gid.length === 0) {
      return
    }
    this.loading = true
    this.error = ''
    try {
      await this.fetchAndApply(this.gid, this.token, true)
      this.loaded = true
      DiagnosticLogger.info(
        'gallery',
        'detail_refresh_ok',
        `gid=${this.gid} images=${this.images.length} comments=${this.comments.length}`,
      )
    } catch (err) {
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'detail_refresh_failed', (err as Error).message)
      throw new Error(this.error)
    } finally {
      this.loading = false
    }
  }

  private async fetchAndApply(gid: string, token: string, refresh: boolean): Promise<void> {
    // eros_fe enrich-then-detail order: a sparse seed (URL paste / deep link) carries only gid+token,
    // no fileCount, so fetch the lighter /api.php gdata metadata first to paint a real header (title,
    // cover, fileCount, rating, tags) before the heavier detail page parse lands. A list-row open
    // already seeded fileCount, so this is skipped there — exactly eros_fe's filecount-absent gate.
    if (this.gallery.fileCount.length === 0) {
      await this.enrichFromApi(gid, token)
    }
    const seedRatingFallBack: number = this.gallery.ratingFallBack
    const seedRatingCount: string = this.gallery.ratingCount
    const seedColorRating: string = this.gallery.colorRating
    const res: GalleryDetailResult = await EhApiService.getInstance().getGalleryDetail(
      gid,
      token,
      connectSiteMode().isEx,
    )
    this.gallery = await this.translateGallery(this.gallery.merge(res.gallery))
    if (!refresh) {
      this.applyNonRefreshSeedRating(seedRatingFallBack, seedRatingCount, seedColorRating)
    }
    this.images = res.images
    this.comments = res.comments
    this.previewPageCount = res.previewPageCount
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
      return gallery
    }
    return TagTranslationService.translateGalleryTags(this.context, gallery)
  }

  async reapplyTagTranslation(): Promise<void> {
    this.gallery = connectTagTranslationSettings().enabled
      ? await this.translateGallery(this.gallery)
      : TagTranslationService.clearGalleryTranslations(this.gallery)
  }

  /** Best-effort gdata metadata enrich for a sparse seed (eros_fe getMoreGalleryInfoOne). Non-fatal:
   * the detail fetch below provides canonical data, so a gdata failure must not block the page. */
  private async enrichFromApi(gid: string, token: string): Promise<void> {
    try {
      const base: string = EhConstants.baseUrl(connectSiteMode().isEx)
      const seed: EhGallery = new EhGallery(gid, token)
      const list: EhGallery[] = await EhApiPhpService.galleryData(base, [seed])
      if (list.length > 0) {
        this.gallery = await this.translateGallery(this.gallery.merge(list[0]))
      }
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
  }

  applyRatingResult(result: GalleryRatingResult): void {
    const next: EhGallery = this.gallery.copy()
    next.ratingFallBack = result.userRating
    next.rating = result.averageRating
    next.ratingCount = result.ratingCount
    next.colorRating = result.colorRating
    next.isRated = true
    this.gallery = next
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

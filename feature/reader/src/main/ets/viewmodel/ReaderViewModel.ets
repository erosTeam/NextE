import {
  EhApiService,
  EhGalleryImage,
  ImageResolveService,
  connectSiteMode,
  DiagnosticLogger,
  EhErrorText,
} from 'shared'

// How many pages ahead to pre-resolve (eros_fe forward preload): warm the next images' URLs so a
// swipe lands on an already-resolved page instead of waiting for its /s/→URL round-trip.
const PRECACHE_AHEAD: number = 2

/**
 * Drives the reader. Loads the gallery's image-page links one preview page (~20) at a time
 * (the /s/ links the reader resolves into full images), extending as the user nears the end
 * or opens past the loaded range. Holds only the page list + current index; each Swiper
 * page component resolves and shows its own full image.
 */
@ObservedV2
export class ReaderViewModel {
  @Trace images: EhGalleryImage[] = []
  @Trace currentIndex: number = 0
  @Trace loadingMore: boolean = false
  @Trace jumping: boolean = false
  @Trace error: string = ''
  fileCount: number = 0

  private gid: string = ''
  private token: string = ''
  private previewPage: number = -1
  private exhausted: boolean = false
  private loadedPreviewPages: number[] = []
  // Image-page links per preview page (~20/40, gallery-fixed), measured from the first loaded page.
  // Enables a far jump/resume to fetch the missing preview pages CONCURRENTLY (the slider drop case)
  // instead of one-by-one round-trips (eros_fe far-seek). 0 until the first page lands.
  private perPage: number = 0

  async init(
    gid: string,
    token: string,
    fileCount: number,
    startIndex: number,
    seedImages: EhGalleryImage[] = [],
    seedLoadedPages: number = 0,
    seedPerPage: number = 0,
  ): Promise<void> {
    this.gid = gid
    this.token = token
    this.fileCount = fileCount
    this.currentIndex = startIndex
    this.images = []
    this.previewPage = -1
    this.exhausted = false
    this.loadedPreviewPages = []
    this.perPage = 0
    const exactSeed: EhGalleryImage | null = this.exactSeedImage(seedImages, seedLoadedPages, startIndex)
    this.applySeed(seedImages, seedLoadedPages, seedPerPage)
    // A resumed far start page (e.g. lastIndex 500) must not crawl preview pages one-by-one — fetch
    // the gap concurrently. ensureLoaded picks the parallel path past the first page.
    await this.ensureLoaded(startIndex + 2)
    if (exactSeed !== null) {
      this.applyExactSeed(startIndex, exactSeed)
    }
    // Clamp a resumed/restored start page that overshoots the gallery's actual length (e.g. the
    // saved lastIndex predates an expunge/shrink, or fewer pages parsed) — mirrors jumpTo's clamp
    // so the Swiper .index() and the progress write-back never go out of range.
    this.currentIndex = this.images.length > 0 ? Math.min(startIndex, this.images.length - 1) : 0
    this.precacheAhead()
  }

  private exactSeedImage(
    seedImages: EhGalleryImage[],
    seedLoadedPages: number,
    startIndex: number,
  ): EhGalleryImage | null {
    if (seedImages.length === 0 || seedLoadedPages > 0 || startIndex < 0) {
      return null
    }
    const seed: EhGalleryImage = seedImages[0]
    if (seed.page !== startIndex + 1 || seed.imageUrl.length === 0) {
      return null
    }
    return seed.copy()
  }

  private applySeed(seedImages: EhGalleryImage[], seedLoadedPages: number, seedPerPage: number): void {
    if (seedImages.length === 0 || seedLoadedPages <= 0) {
      return
    }
    const seeded: EhGalleryImage[] = []
    seedImages.forEach((img: EhGalleryImage) => {
      seeded.push(img.copy())
    })
    this.images = seeded
    this.previewPage = Math.max(0, seedLoadedPages - 1)
    this.perPage = seedPerPage > 0 ? seedPerPage : seedImages.length
    this.loadedPreviewPages = []
    for (let p: number = 0; p < seedLoadedPages; p++) {
      this.loadedPreviewPages.push(p)
    }
    if (this.fileCount > 0 && this.images.length >= this.fileCount) {
      this.exhausted = true
    }
  }

  private applyExactSeed(index: number, seed: EhGalleryImage): void {
    if (index < 0 || index >= this.images.length) {
      return
    }
    const merged: EhGalleryImage = this.images[index].copy()
    if (seed.imgkey.length > 0) {
      merged.imgkey = seed.imgkey
    }
    if (seed.sUrl.length > 0) {
      merged.sUrl = seed.sUrl
    }
    if (seed.imageUrl.length > 0) {
      merged.imageUrl = seed.imageUrl
    }
    if (seed.originImageUrl.length > 0) {
      merged.originImageUrl = seed.originImageUrl
    }
    if (seed.showKey.length > 0) {
      merged.showKey = seed.showKey
    }
    if (seed.reloadKey.length > 0) {
      merged.reloadKey = seed.reloadKey
    }
    const next: EhGalleryImage[] = []
    for (let i: number = 0; i < this.images.length; i++) {
      next.push(i === index ? merged : this.images[i])
    }
    this.images = next
  }

  /**
   * Ensure image-page links are loaded through `index`. The near case (sequential reading) extends one
   * preview page at a time; a FAR target (slider drop / resumed deep page) fetches every missing preview
   * page CONCURRENTLY once perPage is known, so a far jump pipelines its GETs instead of waiting for each
   * round-trip in turn (same request count as the old one-by-one loop — just not serialized).
   */
  private async ensureLoaded(index: number): Promise<void> {
    // Load the first page first so perPage is known (and a near target may already be satisfied).
    if (this.previewPage < 0) {
      await this.loadMore()
    }
    if (this.exhausted || this.hasPreviewAt(index)) {
      return
    }
    // eros_fe first asks the target `ser`'s preview page directly. Do the same before filling gaps, so
    // a later thumbnail/deep image-page start can paint the target immediately instead of waiting for
    // page-1..target preview pages to serialize or visually snapping back to early pages.
    const loadedTarget: boolean = await this.loadPreviewPageForIndex(index)
    if (loadedTarget || this.exhausted) {
      return
    }
    // perPage unknown (single-page gallery or a parse miss) → fall back to the sequential extend.
    if (this.perPage <= 0) {
      await this.ensureSequential(index)
      return
    }
    if (this.loadingMore) {
      return
    }
    this.loadingMore = true
    this.error = ''
    try {
      const from: number = this.previewPage + 1
      // Cap the target preview page by the gallery length so we don't fetch empty tail pages.
      const lastPage: number =
        this.fileCount > 0
          ? Math.ceil(this.fileCount / this.perPage) - 1
          : Math.floor(index / this.perPage)
      const to: number = Math.min(Math.floor(index / this.perPage), lastPage)
      if (to >= from) {
        const reqs: Promise<EhGalleryImage[]>[] = []
        for (let p: number = from; p <= to; p++) {
          reqs.push(
            EhApiService.getInstance().getPreviewImages(
              this.gid,
              this.token,
              connectSiteMode().isEx,
              p,
            ),
          )
        }
        const results: EhGalleryImage[][] = await Promise.all(reqs)
        // Append in page order; a short/empty page marks the gallery end (stop, stay contiguous).
        for (let i: number = 0; i < results.length; i++) {
          const r: EhGalleryImage[] = results[i]
          if (r.length === 0) {
            this.exhausted = true
            break
          }
          this.mergePreviewPage(from + i, r)
          if (this.fileCount > 0 && this.images.length >= this.fileCount) {
            this.exhausted = true
            break
          }
          // fileCount unknown: a short (< perPage) page is the gallery's last one — mark exhausted to
          // match the sequential loop (which would have probed the next page and gotten an empty one).
          if (this.fileCount <= 0 && r.length < this.perPage) {
            this.exhausted = true
            break
          }
        }
      }
    } catch (err) {
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('reader', 'jump_load_failed', (err as Error).message)
    }
    this.loadingMore = false
  }

  /** Sequential fallback (perPage unknown): extend one preview page at a time until past `index`. */
  private async ensureSequential(index: number): Promise<void> {
    while (!this.exhausted && this.images.length <= index) {
      const before: number = this.images.length
      await this.loadMore()
      if (this.images.length === before) {
        break
      }
    }
  }

  async loadMore(): Promise<void> {
    if (this.loadingMore || this.exhausted) {
      return
    }
    this.loadingMore = true
    this.error = ''
    try {
      const next: number = this.previewPage + 1
      const more: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
        this.gid,
        this.token,
        connectSiteMode().isEx,
        next,
      )
      if (more.length === 0) {
        this.exhausted = true
      } else {
        this.mergePreviewPage(next, more)
        // Record the per-preview-page count from the first full page — it's gallery-fixed, so it lets
        // a later far jump compute exactly which preview pages to fetch.
        if (this.perPage === 0) {
          this.perPage = more.length
        }
        if (this.fileCount > 0 && this.images.length >= this.fileCount) {
          this.exhausted = true
        }
      }
    } catch (err) {
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('reader', 'loadmore_failed', (err as Error).message)
    }
    this.loadingMore = false
  }

  hasPreviewAt(index: number): boolean {
    if (index < 0 || index >= this.images.length) {
      return false
    }
    return this.images[index].sUrl.length > 0
  }

  private async loadPreviewPageForIndex(index: number): Promise<boolean> {
    if (this.perPage <= 0 || index < 0 || this.hasPreviewAt(index) || this.loadingMore) {
      return false
    }
    const targetPreviewPage: number = Math.floor(index / this.perPage)
    if (this.isPreviewPageLoaded(targetPreviewPage)) {
      return this.hasPreviewAt(index)
    }
    this.loadingMore = true
    this.error = ''
    try {
      const more: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
        this.gid,
        this.token,
        connectSiteMode().isEx,
        targetPreviewPage,
      )
      if (more.length === 0) {
        this.exhausted = true
      } else {
        this.mergePreviewPage(targetPreviewPage, more)
      }
    } catch (err) {
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('reader', 'target_preview_load_failed', (err as Error).message)
    }
    this.loadingMore = false
    return this.hasPreviewAt(index)
  }

  private mergePreviewPage(previewPage: number, pageImages: EhGalleryImage[]): void {
    if (pageImages.length === 0) {
      return
    }
    const next: EhGalleryImage[] = []
    for (let i: number = 0; i < this.images.length; i++) {
      next.push(this.images[i].copy())
    }
    const startIndex: number = previewPage * (this.perPage > 0 ? this.perPage : pageImages.length)
    const minLength: number = startIndex + pageImages.length
    for (let i: number = next.length; i < minLength; i++) {
      next.push(new EhGalleryImage(i + 1))
    }
    for (let i: number = 0; i < pageImages.length; i++) {
      const img: EhGalleryImage = pageImages[i]
      const targetIndex: number = img.page > 0 ? img.page - 1 : startIndex + i
      for (let j: number = next.length; j <= targetIndex; j++) {
        next.push(new EhGalleryImage(j + 1))
      }
      next[targetIndex] = img.copy()
    }
    this.images = next
    this.markPreviewPageLoaded(previewPage)
    this.advanceContiguousPreviewPage()
  }

  private markPreviewPageLoaded(previewPage: number): void {
    if (this.isPreviewPageLoaded(previewPage)) {
      return
    }
    this.loadedPreviewPages.push(previewPage)
  }

  private isPreviewPageLoaded(previewPage: number): boolean {
    for (let i: number = 0; i < this.loadedPreviewPages.length; i++) {
      if (this.loadedPreviewPages[i] === previewPage) {
        return true
      }
    }
    return false
  }

  private advanceContiguousPreviewPage(): void {
    let next: number = this.previewPage + 1
    while (this.isPreviewPageLoaded(next)) {
      this.previewPage = next
      next++
    }
  }

  onPageChange(index: number): void {
    this.currentIndex = index
    if (!this.exhausted && !this.hasPreviewAt(index)) {
      this.ensureLoaded(index)
    } else if (!this.exhausted && index >= this.images.length - 3) {
      this.loadMore()
    }
    this.precacheAhead()
  }

  /** Vertical (continuous) mode: top item drives the counter; load more as the bottom nears the end. */
  onVerticalScroll(start: number, end: number): void {
    this.currentIndex = start
    if (!this.exhausted && !this.hasPreviewAt(start)) {
      this.ensureLoaded(start)
    } else if (!this.exhausted && end >= this.images.length - 3) {
      this.loadMore()
    }
    this.precacheAhead()
  }

  /**
   * Pre-resolve the next PRECACHE_AHEAD pages' image URLs (eros_fe forward preload), fire-and-forget,
   * so a forward swipe lands on an already-resolved page instead of waiting for its /s/→URL round-trip.
   * resolve() caches the URL onto each image and coalesces with the page component's on-demand resolve,
   * so this never double-fetches. Skips pages already resolved or not yet loaded.
   */
  private precacheAhead(): void {
    const to: number = Math.min(this.currentIndex + PRECACHE_AHEAD, this.images.length - 1)
    for (let i: number = this.currentIndex + 1; i <= to; i++) {
      const img: EhGalleryImage = this.images[i]
      if (img.imageUrl.length === 0 && img.sUrl.length > 0) {
        ImageResolveService.getInstance()
          .resolve(img)
          .then(
            (): void => {},
            (): void => {},
          )
      }
    }
  }

  /** Total pages for the slider: the known file count, else however many are loaded so far. */
  totalPages(): number {
    return this.fileCount > 0 ? this.fileCount : this.images.length
  }

  /**
   * Jump-to-page (slider release). The image list is contiguous, so reaching page N still means the
   * preview pages up to it must be loaded — but ensureLoaded fetches the missing ones concurrently, so
   * a far jump pipelines its GETs behind the `jumping` spinner instead of crawling one at a time.
   * Returns the clamped, now-loaded target index for the SwiperController to move to.
   */
  async jumpTo(index: number): Promise<number> {
    if (index < 0 || this.jumping) {
      return this.currentIndex
    }
    this.jumping = true
    await this.ensureLoaded(index)
    this.jumping = false
    const target: number = Math.min(index, this.images.length - 1)
    this.currentIndex = target >= 0 ? target : 0
    this.precacheAhead()
    return target >= 0 ? target : 0
  }
}

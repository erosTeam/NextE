import {
  BasicDataSource,
  EhApiService,
  EhGalleryImage,
  ImageResolveService,
  DiagnosticLogger,
  EhErrorText,
  EhUrlRouter,
  ImagePageRef,
  connectReadMode,
} from 'shared'
import { ReaderSessionRequest, ReaderSessionRequestGate } from '../model/ReaderSessionRequestGate'

const MAX_READER_SESSION_CACHE: number = 8
const DEFAULT_PRELOAD_PAGES: number = 2
const MAX_PRELOAD_PAGES: number = 5

class ReaderSessionSnapshot {
  key: string = ''
  fileCount: number = 0
  previewPage: number = -1
  exhausted: boolean = false
  perPage: number = 0
  currentIndex: number = 0
  updatedAt: number = 0
  images: EhGalleryImage[] = []
  loadedPreviewPages: number[] = []
  private imageIndexesByPage: Map<number, number> = new Map()

  copy(): ReaderSessionSnapshot {
    const out: ReaderSessionSnapshot = new ReaderSessionSnapshot()
    out.key = this.key
    out.fileCount = this.fileCount
    out.previewPage = this.previewPage
    out.exhausted = this.exhausted
    out.perPage = this.perPage
    out.currentIndex = this.currentIndex
    out.updatedAt = this.updatedAt
    for (let i: number = 0; i < this.images.length; i++) {
      out.replaceImage(this.images[i])
    }
    out.setLoadedPreviewPages(this.loadedPreviewPages)
    return out
  }

  replaceImage(image: EhGalleryImage): void {
    if (image.page <= 0) {
      return
    }
    const copy: EhGalleryImage = image.copy()
    const existingIndex: number | undefined = this.imageIndexesByPage.get(copy.page)
    if (existingIndex === undefined) {
      this.imageIndexesByPage.set(copy.page, this.images.length)
      this.images.push(copy)
      return
    }
    this.images[existingIndex] = copy
  }

  clearImages(): void {
    this.images = []
    this.imageIndexesByPage.clear()
  }

  setLoadedPreviewPages(pages: number[]): void {
    this.loadedPreviewPages = ReaderSessionSnapshot.copyPages(pages)
  }

  private static copyPages(pages: number[]): number[] {
    const out: number[] = []
    for (let i: number = 0; i < pages.length; i++) {
      out.push(pages[i])
    }
    return out
  }
}

/**
 * Drives the reader. Loads the gallery's image-page links one preview page (~20) at a time
 * (the /s/ links the reader resolves into full images), extending as the user nears the end
 * or opens past the loaded range. Holds only the page list + current index; each Swiper
 * page component resolves and shows its own full image.
 */
@ObservedV2
export class ReaderViewModel {
  private static sessionCache: Map<string, ReaderSessionSnapshot> = new Map()
  private sessionRequests: ReaderSessionRequestGate = new ReaderSessionRequestGate()
  pageIndexSource: BasicDataSource<number> = new BasicDataSource<number>()
  @Trace currentIndex: number = 0
  @Trace loadingMore: boolean = false
  @Trace jumping: boolean = false
  @Trace error: string = ''
  fileCount: number = 0

  private gid: string = ''
  private token: string = ''
  private isEx: boolean = false
  private previewPage: number = -1
  private exhausted: boolean = false
  private cacheKey: string = ''
  private loadedPreviewPages: number[] = []
  private previewImagesByIndex: Map<number, EhGalleryImage> = new Map()
  // Image-page links per preview page (~20/40, gallery-fixed), measured from the first loaded page.
  // Enables a far jump/resume to fetch the missing preview pages CONCURRENTLY (the slider drop case)
  // instead of one-by-one round-trips (eros_fe far-seek). 0 until the first page lands.
  private perPage: number = 0
  @Trace previewLoadingIndex: number = -1
  @Trace previewFailedIndex: number = -1
  @Trace previewError: string = ''

  private isKnownLastPreviewPage(previewPage: number, count: number): boolean {
    if (this.fileCount <= 0 || count <= 0) {
      return false
    }
    const pageSize: number = this.perPage > 0 ? this.perPage : count
    return previewPage * pageSize + count >= this.fileCount
  }

  async init(
    gid: string,
    token: string,
    isEx: boolean,
    fileCount: number,
    startIndex: number,
    seedImages: EhGalleryImage[] = [],
    seedLoadedPages: number = 0,
    seedPerPage: number = 0,
    seedPreviewPages: number[] = [],
    seedImagePageUrl: string = '',
  ): Promise<ReaderSessionRequest | null> {
    const request: ReaderSessionRequest = this.sessionRequests.begin(gid, token, isEx)
    this.gid = gid
    this.token = token
    this.isEx = isEx
    this.fileCount = fileCount
    this.currentIndex = startIndex
    this.cacheKey = ReaderViewModel.sessionKey(gid, token, this.isEx)
    this.loadingMore = false
    this.jumping = false
    this.error = ''
    this.previewLoadingIndex = -1
    this.previewFailedIndex = -1
    this.previewError = ''
    // A retained ReaderViewModel can switch to another gallery with the same page count; that is still
    // a structural reset, so force the LazyForEach source to rebuild once at the new gallery boundary.
    this.syncPageIndexSource(true)
    this.previewImagesByIndex.clear()
    this.previewPage = -1
    this.exhausted = false
    this.loadedPreviewPages = []
    this.perPage = 0
    this.applySessionCache(fileCount)
    const exactSeed: EhGalleryImage | null = this.exactSeedImage(seedImages, seedLoadedPages, startIndex)
    this.applySeed(seedImages, seedLoadedPages, seedPerPage, seedPreviewPages)
    const imagePageSeed: EhGalleryImage | null = this.applySeedImagePageUrl(startIndex, seedImagePageUrl)
    if (imagePageSeed !== null) {
      await this.resolveSeedImage(startIndex, imagePageSeed, request)
      if (!this.isSessionCurrent(request)) {
        return null
      }
    }
    // Load the requested page first. The neighbor pages are warmed after the first paint path is ready,
    // so a later thumbnail or /s/ deep-link start cannot be delayed by preloading pages after it.
    await this.ensureLoaded(startIndex, 'init-start', request)
    if (!this.isSessionCurrent(request)) {
      return null
    }
    if (exactSeed !== null) {
      this.applyExactSeed(startIndex, exactSeed)
    }
    // Clamp a resumed/restored start page that overshoots the gallery's actual length (e.g. the
    // saved lastIndex predates an expunge/shrink, or fewer pages parsed) — mirrors jumpTo's clamp
    // so the Swiper .index() and the progress write-back never go out of range.
    const total: number = this.totalPages()
    this.currentIndex = total > 0 ? Math.min(startIndex, total - 1) : 0
    // The visible page component checks the stable disk cache before resolving /s/. Pre-resolving the
    // current page here would race that check and issue avoidable HTML requests on a cold reopen.
    this.precacheFrom(this.currentIndex + 1, request)
    this.warmPreviewAhead(this.currentIndex, request)
    this.publishSessionCache()
    return request
  }

  /** Lets the page discard a retained route's completion after a newer Reader session begins. */
  isSessionCurrent(request: ReaderSessionRequest | null): boolean {
    if (request === null) {
      return false
    }
    return this.sessionRequests.isCurrent(request) &&
      this.gid === request.gid &&
      this.token === request.token &&
      this.isEx === request.isEx &&
      this.cacheKey === ReaderViewModel.sessionKey(request.gid, request.token, request.isEx)
  }

  private currentSessionRequest(): ReaderSessionRequest {
    return this.sessionRequests.current()
  }

  private static sessionKey(gid: string, token: string, isEx: boolean): string {
    return `${isEx ? 'ex' : 'eh'}:${gid}:${token}`
  }

  private applySessionCache(fileCount: number): void {
    if (this.cacheKey.length === 0) {
      return
    }
    const cached: ReaderSessionSnapshot | undefined = ReaderViewModel.sessionCache.get(this.cacheKey)
    if (cached === undefined || cached.images.length === 0) {
      return
    }
    this.previewImagesByIndex.clear()
    for (let i: number = 0; i < cached.images.length; i++) {
      const image: EhGalleryImage = cached.images[i]
      if (image.page > 0 && image.sUrl.length > 0) {
        this.previewImagesByIndex.set(image.page - 1, image.copy())
      }
    }
    this.notifyPreviewMapChanged()
    this.loadedPreviewPages = []
    for (let i: number = 0; i < cached.loadedPreviewPages.length; i++) {
      this.loadedPreviewPages.push(cached.loadedPreviewPages[i])
    }
    this.previewPage = cached.previewPage
    this.exhausted = cached.exhausted
    this.perPage = cached.perPage
    if (fileCount <= 0 && cached.fileCount > 0) {
      this.fileCount = cached.fileCount
    }
    DiagnosticLogger.info(
      'reader',
      'session_cache_hit',
      `key ${this.cacheKey} images ${this.previewImagesByIndex.size} perPage ${this.perPage}`,
    )
  }

  private publishSessionCache(
    changedIndexes: number[] = [],
    refreshLoadedPreviewPages: boolean = false,
  ): void {
    if (this.cacheKey.length === 0 || this.previewImagesByIndex.size === 0) {
      return
    }
    const existingSnapshot: ReaderSessionSnapshot | undefined = ReaderViewModel.sessionCache.get(this.cacheKey)
    const rebuild: boolean = existingSnapshot === undefined || changedIndexes.length === 0
    const snapshot: ReaderSessionSnapshot = existingSnapshot === undefined
      ? new ReaderSessionSnapshot()
      : existingSnapshot
    if (rebuild) {
      snapshot.clearImages()
      this.previewImagesByIndex.forEach((img: EhGalleryImage) => {
        snapshot.replaceImage(img)
      })
    } else {
      for (let i: number = 0; i < changedIndexes.length; i++) {
        const image: EhGalleryImage | undefined = this.previewImagesByIndex.get(changedIndexes[i])
        if (image !== undefined) {
          snapshot.replaceImage(image)
        }
      }
    }
    snapshot.key = this.cacheKey
    snapshot.fileCount = this.fileCount
    snapshot.previewPage = this.previewPage
    snapshot.exhausted = this.exhausted
    snapshot.perPage = this.perPage
    snapshot.currentIndex = this.currentIndex
    snapshot.updatedAt = Date.now()
    if (rebuild || refreshLoadedPreviewPages) {
      snapshot.setLoadedPreviewPages(this.loadedPreviewPages)
    }
    ReaderViewModel.sessionCache.set(this.cacheKey, snapshot)
    ReaderViewModel.trimSessionCache()
  }

  /**
   * Turning pages changes only resumable scalar state. Keep the existing image snapshot intact instead
   * of deep-copying every loaded image on each horizontal turn or vertical scroll callback.
   */
  private updateSessionCacheState(): void {
    if (this.cacheKey.length === 0) {
      return
    }
    const snapshot: ReaderSessionSnapshot | undefined = ReaderViewModel.sessionCache.get(this.cacheKey)
    if (snapshot === undefined) {
      return
    }
    snapshot.fileCount = this.fileCount
    snapshot.previewPage = this.previewPage
    snapshot.exhausted = this.exhausted
    snapshot.perPage = this.perPage
    snapshot.currentIndex = this.currentIndex
    snapshot.updatedAt = Date.now()
    ReaderViewModel.trimSessionCache()
  }

  private notifyImagesChanged(index: number): void {
    this.notifyPreviewMapChanged([index])
  }

  /** The page-index source is stable; readers refresh only rows whose source URL changed. */
  private notifyPreviewMapChanged(changedIndexes: number[] = []): void {
    const reloaded: boolean = this.syncPageIndexSource()
    if (!reloaded) {
      for (let i: number = 0; i < changedIndexes.length; i++) {
        this.pageIndexSource.notifyDataChanged(changedIndexes[i])
      }
    }
  }

  private syncPageIndexSource(force: boolean = false): boolean {
    const total: number = this.totalPages()
    if (!force && this.pageIndexSource.totalCount() === total) {
      return false
    }
    const indexes: number[] = []
    for (let i: number = 0; i < total; i++) {
      indexes.push(i)
    }
    this.pageIndexSource.setData(indexes)
    return true
  }

  private previewMapUpperBound(): number {
    let max: number = 0
    this.previewImagesByIndex.forEach((_img: EhGalleryImage, index: number) => {
      if (index + 1 > max) {
        max = index + 1
      }
    })
    return max
  }

  private static trimSessionCache(): void {
    if (ReaderViewModel.sessionCache.size <= MAX_READER_SESSION_CACHE) {
      return
    }
    let oldestKey: string = ''
    let oldestAt: number = Number.MAX_SAFE_INTEGER
    ReaderViewModel.sessionCache.forEach((snapshot: ReaderSessionSnapshot, key: string) => {
      if (snapshot.updatedAt < oldestAt) {
        oldestAt = snapshot.updatedAt
        oldestKey = key
      }
    })
    if (oldestKey.length > 0) {
      ReaderViewModel.sessionCache.delete(oldestKey)
    }
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

  private applySeed(
    seedImages: EhGalleryImage[],
    seedLoadedPages: number,
    seedPerPage: number,
    seedPreviewPages: number[] = [],
  ): void {
    if (seedImages.length === 0 || seedLoadedPages <= 0) {
      return
    }
    const changedIndexes: number[] = []
    seedImages.forEach((img: EhGalleryImage, order: number) => {
      const targetIndex: number = img.page > 0 ? img.page - 1 : order
      const copy: EhGalleryImage = img.copy()
      copy.page = targetIndex + 1
      this.previewImagesByIndex.set(targetIndex, copy)
      changedIndexes.push(targetIndex)
    })
    this.notifyPreviewMapChanged(changedIndexes)
    this.perPage = seedPerPage > 0 ? seedPerPage : seedImages.length
    this.loadedPreviewPages = []
    if (seedPreviewPages.length > 0) {
      seedPreviewPages.forEach((p: number) => {
        this.markPreviewPageLoaded(p)
      })
    } else {
      for (let p: number = 0; p < seedLoadedPages; p++) {
        this.markPreviewPageLoaded(p)
      }
    }
    this.advanceContiguousPreviewPage()
    if (this.seedCoversWholeGallery()) {
      this.exhausted = true
    }
  }

  private seedCoversWholeGallery(): boolean {
    if (this.fileCount <= 0) {
      return false
    }
    for (let i: number = 0; i < this.fileCount; i++) {
      if (!this.hasPreviewAt(i)) {
        return false
      }
    }
    return true
  }

  private applySeedImagePageUrl(index: number, seedImagePageUrl: string): EhGalleryImage | null {
    if (index < 0 || seedImagePageUrl.length === 0) {
      return null
    }
    const ref: ImagePageRef | null = EhUrlRouter.parseImagePage(seedImagePageUrl)
    if (ref === null) {
      return null
    }
    const existing: EhGalleryImage | undefined = this.previewImagesByIndex.get(index)
    const img: EhGalleryImage = existing !== undefined ? existing.copy() : new EhGalleryImage(index + 1)
    img.page = index + 1
    img.sUrl = seedImagePageUrl
    img.imgkey = ref.imgkey
    this.previewImagesByIndex.set(index, img)
    this.notifyPreviewMapChanged([index])
    return img
  }

  private async resolveSeedImage(
    index: number,
    image: EhGalleryImage,
    request: ReaderSessionRequest,
  ): Promise<void> {
    try {
      await ImageResolveService.getInstance().resolve(image)
      if (!this.isSessionCurrent(request)) {
        return
      }
      this.applyExactSeed(index, image)
    } catch (err) {
      if (this.isSessionCurrent(request)) {
        DiagnosticLogger.warn('reader', 'seed_image_page_resolve_failed', (err as Error).message)
      }
    }
  }

  private applyExactSeed(index: number, seed: EhGalleryImage): void {
    if (index < 0) {
      return
    }
    const existing: EhGalleryImage | undefined = this.previewImagesByIndex.get(index)
    const merged: EhGalleryImage = existing !== undefined ? existing.copy() : new EhGalleryImage(index + 1)
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
    this.previewImagesByIndex.set(index, merged)
    this.notifyPreviewMapChanged([index])
    this.publishSessionCache([index])
  }

  /**
   * Ensure image-page links are loaded through `index`. The near case (sequential reading) extends one
   * preview page at a time; a FAR target (slider drop / resumed deep page) fetches every missing preview
   * page CONCURRENTLY once perPage is known, so a far jump pipelines its GETs instead of waiting for each
   * round-trip in turn (same request count as the old one-by-one loop — just not serialized).
   */
  private async ensureLoaded(
    index: number,
    reason: string,
    request: ReaderSessionRequest,
  ): Promise<void> {
    if (!this.isSessionCurrent(request)) {
      return
    }
    DiagnosticLogger.info(
      'reader',
      'ensure_loaded_begin',
      `reason ${reason} index ${index} current ${this.currentIndex} hasPreview ${this.hasPreviewAt(index)} total ${this.totalPages()} images ${this.previewImagesByIndex.size} previewPage ${this.previewPage} perPage ${this.perPage}`,
    )
    if (this.loadingMore) {
      const completed: boolean = await this.waitForLoadingComplete(request)
      if (!completed || !this.isSessionCurrent(request)) {
        return
      }
    }
    // Load the first page first so perPage is known (and a near target may already be satisfied).
    if (this.previewPage < 0) {
      await this.loadMoreForSession(request)
      if (!this.isSessionCurrent(request)) {
        return
      }
    }
    if (this.loadingMore) {
      const completed: boolean = await this.waitForLoadingComplete(request)
      if (!completed || !this.isSessionCurrent(request)) {
        return
      }
    }
    if (this.exhausted || this.hasPreviewAt(index)) {
      DiagnosticLogger.info('reader', 'ensure_loaded_done', `reason ${reason} index ${index} already-ready exhausted ${this.exhausted}`)
      return
    }
    // eros_fe first asks the target `ser`'s preview page directly. Do the same before filling gaps, so
    // a later thumbnail/deep image-page start can paint the target immediately instead of waiting for
    // page-1..target preview pages to serialize or visually snapping back to early pages.
    const loadedTarget: boolean = await this.loadPreviewPageForIndex(index, request)
    if (!this.isSessionCurrent(request)) {
      return
    }
    if (loadedTarget || this.exhausted) {
      DiagnosticLogger.info('reader', 'ensure_loaded_done', `reason ${reason} index ${index} target-loaded ${loadedTarget} exhausted ${this.exhausted}`)
      return
    }
    // perPage unknown (single-page gallery or a parse miss) → fall back to the sequential extend.
    if (this.perPage <= 0) {
      await this.ensureSequential(index, request)
      if (this.isSessionCurrent(request)) {
        DiagnosticLogger.info('reader', 'ensure_loaded_done', `reason ${reason} index ${index} sequential`)
      }
      return
    }
    if (this.loadingMore) {
      const completed: boolean = await this.waitForLoadingComplete(request)
      if (!completed || !this.isSessionCurrent(request)) {
        return
      }
      if (this.hasPreviewAt(index) || this.exhausted) {
        DiagnosticLogger.info('reader', 'ensure_loaded_done', `reason ${reason} index ${index} after-wait`)
        return
      }
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
              request.gid,
              request.token,
              request.isEx,
              p,
            ),
          )
        }
        const results: EhGalleryImage[][] = await Promise.all(reqs)
        if (!this.isSessionCurrent(request)) {
          return
        }
        // Append in page order; a short/empty page marks the gallery end (stop, stay contiguous).
        for (let i: number = 0; i < results.length; i++) {
          const r: EhGalleryImage[] = results[i]
          if (r.length === 0) {
            this.exhausted = true
            break
          }
          this.mergePreviewPage(from + i, r, request)
          if (this.isKnownLastPreviewPage(from + i, r.length)) {
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
      if (!this.isSessionCurrent(request)) {
        return
      }
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('reader', 'jump_load_failed', (err as Error).message)
    }
    if (!this.isSessionCurrent(request)) {
      return
    }
    this.loadingMore = false
    DiagnosticLogger.info(
      'reader',
      'ensure_loaded_done',
      `reason ${reason} index ${index} hasPreview ${this.hasPreviewAt(index)} previewPage ${this.previewPage} exhausted ${this.exhausted}`,
    )
  }

  /** Sequential fallback (perPage unknown): extend one preview page at a time until past `index`. */
  private async ensureSequential(index: number, request: ReaderSessionRequest): Promise<void> {
    while (!this.exhausted && !this.hasPreviewAt(index)) {
      if (!this.isSessionCurrent(request)) {
        return
      }
      const before: number = this.previewMapUpperBound()
      await this.loadMoreForSession(request)
      if (!this.isSessionCurrent(request)) {
        return
      }
      if (this.previewMapUpperBound() === before) {
        break
      }
    }
  }

  private async waitForLoadingComplete(request: ReaderSessionRequest): Promise<boolean> {
    while (this.loadingMore) {
      if (!this.isSessionCurrent(request)) {
        return false
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout(() => {
          resolve()
        }, 30)
      })
      if (!this.isSessionCurrent(request)) {
        return false
      }
    }
    return this.isSessionCurrent(request)
  }

  async loadMore(): Promise<void> {
    const request: ReaderSessionRequest = this.currentSessionRequest()
    await this.loadMoreForSession(request)
  }

  private async loadMoreForSession(request: ReaderSessionRequest): Promise<void> {
    if (!this.isSessionCurrent(request)) {
      return
    }
    if (this.loadingMore || this.exhausted) {
      return
    }
    this.loadingMore = true
    this.error = ''
    try {
      const next: number = this.previewPage + 1
      const more: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
        request.gid,
        request.token,
        request.isEx,
        next,
      )
      if (!this.isSessionCurrent(request)) {
        return
      }
      if (more.length === 0) {
        this.exhausted = true
      } else {
        this.mergePreviewPage(next, more, request)
        // Record the per-preview-page count from the first full page — it's gallery-fixed, so it lets
        // a later far jump compute exactly which preview pages to fetch.
        if (this.perPage === 0) {
          this.perPage = more.length
        }
        if (this.isKnownLastPreviewPage(next, more.length)) {
          this.exhausted = true
        }
        this.updateSessionCacheState()
      }
    } catch (err) {
      if (!this.isSessionCurrent(request)) {
        return
      }
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('reader', 'loadmore_failed', (err as Error).message)
    }
    if (!this.isSessionCurrent(request)) {
      return
    }
    this.loadingMore = false
  }

  hasPreviewAt(index: number): boolean {
    if (index < 0) {
      return false
    }
    const img: EhGalleryImage | undefined = this.previewImagesByIndex.get(index)
    return img !== undefined && img.sUrl.length > 0
  }

  imageAt(index: number): EhGalleryImage {
    if (index < 0) {
      return new EhGalleryImage(index + 1)
    }
    const img: EhGalleryImage | undefined = this.previewImagesByIndex.get(index)
    if (img === undefined) {
      return new EhGalleryImage(index + 1)
    }
    return img
  }

  warmPreviewForIndex(index: number, reason: string = 'manual-warm'): void {
    const request: ReaderSessionRequest = this.currentSessionRequest()
    if (!this.isSessionCurrent(request)) {
      return
    }
    if (index < 0 || index >= this.totalPages() || this.hasPreviewAt(index)) {
      return
    }
    DiagnosticLogger.info(
      'reader',
      'thumb_warm_request',
      `index ${index} images ${this.previewImagesByIndex.size} perPage ${this.perPage} loaded ${this.hasPreviewAt(index)}`,
    )
    this.ensureLoaded(index, reason, request)
      .then(
        (): void => {},
        (): void => {},
      )
  }

  private async loadPreviewPageForIndex(
    index: number,
    request: ReaderSessionRequest,
  ): Promise<boolean> {
    if (!this.isSessionCurrent(request)) {
      return false
    }
    if (this.loadingMore) {
      const completed: boolean = await this.waitForLoadingComplete(request)
      if (!completed || !this.isSessionCurrent(request)) {
        return false
      }
      if (this.hasPreviewAt(index)) {
        return true
      }
    }
    if (this.perPage <= 0 || index < 0) {
      return false
    }
    const targetPreviewPage: number = Math.floor(index / this.perPage)
    const pageLoaded: boolean = this.isPreviewPageLoaded(targetPreviewPage)
    DiagnosticLogger.info(
      'reader',
      'target_preview_request',
      `index ${index} previewPage ${targetPreviewPage} loaded ${pageLoaded} hasPreview ${this.hasPreviewAt(index)} perPage ${this.perPage}`,
    )
    if (pageLoaded && this.hasPreviewAt(index)) {
      return this.hasPreviewAt(index)
    }
    this.loadingMore = true
    this.previewLoadingIndex = index
    this.previewFailedIndex = -1
    this.previewError = ''
    this.error = ''
    try {
      const more: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
        request.gid,
        request.token,
        request.isEx,
        targetPreviewPage,
      )
      if (!this.isSessionCurrent(request)) {
        return false
      }
      if (more.length === 0) {
        this.exhausted = true
      } else {
        DiagnosticLogger.info(
          'reader',
          'target_preview_result',
          `previewPage ${targetPreviewPage} count ${more.length} first ${more[0].page} firstThumb ${more[0].thumbUrl.length}`,
        )
        this.mergePreviewPage(targetPreviewPage, more, request)
      }
    } catch (err) {
      if (!this.isSessionCurrent(request)) {
        return false
      }
      this.previewFailedIndex = index
      this.previewError = EhErrorText.forUser(err)
      DiagnosticLogger.warn('reader', 'target_preview_load_failed', (err as Error).message)
    }
    if (!this.isSessionCurrent(request)) {
      return false
    }
    this.loadingMore = false
    if (this.previewLoadingIndex === index) {
      this.previewLoadingIndex = -1
    }
    return this.hasPreviewAt(index)
  }

  private mergePreviewPage(
    previewPage: number,
    pageImages: EhGalleryImage[],
    request: ReaderSessionRequest,
  ): void {
    if (!this.isSessionCurrent(request)) {
      return
    }
    if (pageImages.length === 0) {
      return
    }
    const startIndex: number = previewPage * (this.perPage > 0 ? this.perPage : pageImages.length)
    DiagnosticLogger.info(
      'reader',
      'merge_preview_page',
      `previewPage ${previewPage} count ${pageImages.length} start ${startIndex} first ${pageImages[0].page} firstThumb ${pageImages[0].thumbUrl.length}`,
    )
    const changedIndexes: number[] = []
    for (let i: number = 0; i < pageImages.length; i++) {
      const img: EhGalleryImage = pageImages[i]
      const targetIndex: number = img.page > 0 ? img.page - 1 : startIndex + i
      const existing: EhGalleryImage | undefined = this.previewImagesByIndex.get(targetIndex)
      const base: EhGalleryImage = existing !== undefined ? existing : new EhGalleryImage(targetIndex + 1)
      this.previewImagesByIndex.set(targetIndex, this.mergePreviewImage(base, img))
      changedIndexes.push(targetIndex)
    }
    this.notifyPreviewMapChanged(changedIndexes)
    this.markPreviewPageLoaded(previewPage)
    this.advanceContiguousPreviewPage()
    this.previewFailedIndex = -1
    this.previewError = ''
    this.publishSessionCache(changedIndexes, true)
  }

  private mergePreviewImage(existing: EhGalleryImage, incoming: EhGalleryImage): EhGalleryImage {
    const merged: EhGalleryImage = incoming.copy()
    if (merged.sUrl.length === 0 && existing.sUrl.length > 0) {
      merged.sUrl = existing.sUrl
    }
    if (merged.imgkey.length === 0 && existing.imgkey.length > 0) {
      merged.imgkey = existing.imgkey
    }
    if (existing.imageUrl.length > 0) {
      merged.imageUrl = existing.imageUrl
    }
    if (existing.originImageUrl.length > 0) {
      merged.originImageUrl = existing.originImageUrl
    }
    if (existing.showKey.length > 0) {
      merged.showKey = existing.showKey
    }
    if (existing.reloadKey.length > 0) {
      merged.reloadKey = existing.reloadKey
    }
    return merged
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
    const request: ReaderSessionRequest = this.currentSessionRequest()
    if (!this.isSessionCurrent(request)) {
      return
    }
    DiagnosticLogger.info(
      'reader',
      'page_change',
      `index ${index} hasPreview ${this.hasPreviewAt(index)} total ${this.totalPages()} perPage ${this.perPage}`,
    )
    this.currentIndex = index
    this.prepareTargetPage(index, request)
    this.updateSessionCacheState()
  }

  /** Vertical (continuous) mode: top item drives the counter; load more as the bottom nears the end. */
  onVerticalScroll(start: number, end: number): void {
    const request: ReaderSessionRequest = this.currentSessionRequest()
    if (!this.isSessionCurrent(request)) {
      return
    }
    this.currentIndex = start
    if (!this.exhausted && !this.hasPreviewAt(start)) {
      this.prepareTargetPage(start, request)
    } else if (!this.exhausted && end >= this.previewMapUpperBound() - 3) {
      this.loadMoreForSession(request)
      this.precacheAhead(request)
    } else {
      this.precacheAhead(request)
    }
    this.updateSessionCacheState()
  }

  private prepareTargetPage(index: number, request: ReaderSessionRequest): void {
    if (!this.isSessionCurrent(request)) {
      return
    }
    this.ensureLoaded(index, 'page-change', request)
      .then(
        (): void => {
          if (!this.isSessionCurrent(request)) {
            return
          }
          this.precacheFrom(index + 1, request)
          this.warmPreviewAhead(index, request)
        },
        (): void => {},
      )
  }

  private preloadPages(): number {
    const value: number = connectReadMode().preloadPages
    if (!Number.isFinite(value)) {
      return DEFAULT_PRELOAD_PAGES
    }
    if (value < 0) {
      return 0
    }
    if (value > MAX_PRELOAD_PAGES) {
      return MAX_PRELOAD_PAGES
    }
    return Math.round(value)
  }

  /**
   * Pre-resolve the configured next pages' image URLs (eros_fe forward preload), fire-and-forget,
   * so a forward swipe lands on an already-resolved page instead of waiting for its /s/→URL round-trip.
   * resolve() caches the URL onto each image and coalesces with the page component's on-demand resolve,
   * so this never double-fetches. Skips pages already resolved or not yet loaded.
   */
  private precacheAhead(request: ReaderSessionRequest): void {
    if (!this.isSessionCurrent(request)) {
      return
    }
    this.precacheFrom(this.currentIndex + 1, request)
  }

  private precacheFrom(start: number, request: ReaderSessionRequest): void {
    if (!this.isSessionCurrent(request)) {
      return
    }
    const preloadPages: number = this.preloadPages()
    if (preloadPages <= 0) {
      return
    }
    const to: number = Math.min(start + preloadPages - 1, this.totalPages() - 1)
    for (let i: number = start; i <= to; i++) {
      const img: EhGalleryImage = this.imageAt(i)
      if (img.imageUrl.length === 0 && img.sUrl.length > 0) {
        ImageResolveService.getInstance()
          .resolve(img)
          .then(
            (): void => {
              if (!this.isSessionCurrent(request)) {
                return
              }
              this.notifyImagesChanged(i)
              this.publishSessionCache([i])
            },
            (): void => {},
          )
      }
    }
  }

  private warmPreviewAhead(index: number, request: ReaderSessionRequest): void {
    if (!this.isSessionCurrent(request)) {
      return
    }
    const preloadPages: number = this.preloadPages()
    if (preloadPages <= 0) {
      return
    }
    const total: number = this.totalPages()
    const target: number = Math.min(index + preloadPages, total - 1)
    if (target < 0 || target <= index) {
      return
    }
    DiagnosticLogger.info(
      'reader',
      'preview_ahead_request',
      `index ${index} target ${target} total ${total} hasTarget ${this.hasPreviewAt(target)}`,
    )
    this.ensureLoaded(target, 'preview-ahead', request)
      .then(
        (): void => {
          if (!this.isSessionCurrent(request)) {
            return
          }
          this.precacheFrom(index + 1, request)
        },
        (): void => {},
      )
  }

  /**
   * Auto-read uses this to prepare the next target without changing the current page. The timer only
   * turns after the page component reports Image.onComplete, so this is just preview/url warm-up.
   */
  warmForAutoRead(index: number): void {
    const request: ReaderSessionRequest = this.currentSessionRequest()
    if (!this.isSessionCurrent(request)) {
      return
    }
    this.ensureLoaded(index, 'auto-read', request)
      .then(
        (): void => {
          if (!this.isSessionCurrent(request)) {
            return
          }
          this.precacheFrom(index, request)
        },
        (): void => {},
      )
  }

  /** Total pages for the slider: the known file count, else however many are loaded so far. */
  totalPages(): number {
    if (this.fileCount > 0) {
      return this.fileCount
    }
    return this.previewMapUpperBound()
  }

  /**
   * Jump-to-page (slider release). The image list is contiguous, so reaching page N still means the
   * preview pages up to it must be loaded — but ensureLoaded fetches the missing ones concurrently, so
   * a far jump pipelines its GETs behind the `jumping` spinner instead of crawling one at a time.
   * Returns the clamped, now-loaded target index for the SwiperController to move to.
   */
  async jumpTo(index: number): Promise<number> {
    const request: ReaderSessionRequest = this.currentSessionRequest()
    if (!this.isSessionCurrent(request) || index < 0 || this.jumping) {
      return this.currentIndex
    }
    this.jumping = true
    await this.ensureLoaded(index, 'jump', request)
    if (!this.isSessionCurrent(request)) {
      return this.currentIndex
    }
    this.jumping = false
    const total: number = this.totalPages()
    const target: number = total > 0 ? Math.min(index, total - 1) : 0
    this.currentIndex = target >= 0 ? target : 0
    this.precacheFrom(target, request)
    this.updateSessionCacheState()
    return target >= 0 ? target : 0
  }
}

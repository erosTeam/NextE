import {
  EhApiService,
  EhGalleryImage,
  AllThumbnailsParams,
  BasicDataSource,
  DiagnosticLogger,
  EhErrorText,
} from 'shared'
import { AllThumbnailsTailAppend } from '../model/AllThumbnailsTailAppend'

/**
 * Drives the separate all-thumbnails page (eros_fe AllThumbnailsPageController). The detail page only
 * shows the first preview page (a peek); this page is seeded with that first page and can load sparse
 * preview pages directly for page-number jumps. Forward/backward paging follows the current preview
 * page, not just the contiguous first-page range. Rows live in a stable LazyForEach data source (out of
 * @Trace); itemCount mirrors its count as @Trace so the grid re-evaluates.
 */
@ObservedV2
export class AllThumbnailsViewModel {
  dataSource: BasicDataSource<EhGalleryImage> = new BasicDataSource<EhGalleryImage>(
    (image: EhGalleryImage): string => `${image.page}`,
  )
  @Trace itemCount: number = 0
  @Trace loading: boolean = false
  @Trace error: string = ''
  // loadedPages is 0-based count of fetched preview pages; the seed (page index 0) counts as 1.
  private loadedPages: number = 0
  private loadedPreviewPageMarkers: number[] = []
  private totalPages: number = 1
  private gid: string = ''
  private token: string = ''
  private isEx: boolean = false
  private seeded: boolean = false
  private firstPageCount: number = 0
  private currentPreviewPage: number = 0
  // A detail refresh/context switch may replace the first-page seed while a thumbnail-page request is
  // still in flight. Each replacement advances this token so an old response cannot merge itself into
  // the new browsing session.
  private sessionEpoch: number = 0

  seed(p: AllThumbnailsParams): void {
    if (this.seeded) {
      return
    }
    this.replaceSeed(p)
  }

  /**
   * Reconcile a fresh detail-page first preview page with this browsing surface. Normal refreshes keep
   * already loaded sparse pages only when their source and paging shape are unchanged; an account/site
   * replacement must pass false and starts a fresh session.
   */
  syncDetailFirstPage(p: AllThumbnailsParams, preserveSparse: boolean): void {
    const nextTotalPages: number = p.previewPageCount > 0 ? p.previewPageCount : 1
    const nextFirstPageCount: number = p.firstPage.length
    const canPreserve: boolean =
      preserveSparse &&
      this.seeded &&
      this.gid === p.gid &&
      this.token === p.token &&
      this.isEx === p.isEx &&
      this.totalPages === nextTotalPages &&
      this.firstPageCount === nextFirstPageCount &&
      this.hasSameFirstPageShape(p.firstPage)
    if (!canPreserve) {
      this.replaceSeed(p)
      return
    }
    // Cancel an older page request before replacing the canonical first-page images. Extra sparse pages
    // remain valid for this unchanged source, but no old response may append after this refresh.
    this.sessionEpoch = this.sessionEpoch + 1
    this.loading = false
    this.error = ''
    for (let i: number = 0; i < p.firstPage.length; i++) {
      this.dataSource.replaceDataAt(i, p.firstPage[i].copy())
    }
    this.currentPreviewPage = Math.max(0, Math.min(this.totalPages - 1, this.currentPreviewPage))
  }

  /** Drop every URL/page marker from the old account or site before its replacement detail arrives. */
  invalidate(): void {
    this.sessionEpoch = this.sessionEpoch + 1
    this.dataSource.setData([])
    this.itemCount = 0
    this.loading = false
    this.error = ''
    this.loadedPages = 0
    this.loadedPreviewPageMarkers = []
    this.totalPages = 1
    this.gid = ''
    this.token = ''
    this.isEx = false
    this.seeded = false
    this.firstPageCount = 0
    this.currentPreviewPage = 0
  }

  private replaceSeed(p: AllThumbnailsParams): void {
    this.sessionEpoch = this.sessionEpoch + 1
    this.seeded = true
    this.gid = p.gid
    this.token = p.token
    this.isEx = p.isEx
    this.loading = false
    this.error = ''
    this.totalPages = p.previewPageCount > 0 ? p.previewPageCount : 1
    // The detail page owns its canonical first-page preview array. Keep this paging surface on an
    // independent copy so BasicDataSource.appendData() can never grow the detail's inline peek when
    // later preview pages are appended.
    const inputImages: EhGalleryImage[] = p.seedImages.length > 0 ? p.seedImages : p.firstPage
    const seedImages: EhGalleryImage[] = []
    inputImages.forEach((image: EhGalleryImage) => {
      seedImages.push(image.copy())
    })
    this.dataSource.setData(seedImages)
    this.itemCount = this.dataSource.totalCount()
    this.loadedPages = 0
    this.loadedPreviewPageMarkers = []
    p.seedPreviewPages.forEach((previewPage: number) => {
      if (previewPage >= 0 && previewPage < this.totalPages) {
        this.markPreviewPageLoaded(previewPage)
      }
    })
    if (seedImages.length > 0 && this.loadedPreviewPageMarkers.length === 0) {
      this.markPreviewPageLoaded(0)
    }
    this.advanceContiguousLoadedPages()
    this.firstPageCount = p.seedPerPage > 0
      ? p.seedPerPage
      : (p.firstPage.length > 0 ? p.firstPage.length : seedImages.length)
    this.currentPreviewPage = Math.max(0, Math.min(this.totalPages - 1, p.seedCurrentPreviewPage))
  }

  private isCurrentSession(epoch: number): boolean {
    return this.sessionEpoch === epoch
  }

  private hasSameFirstPageShape(fresh: EhGalleryImage[]): boolean {
    if (fresh.length === 0) {
      return false
    }
    const current: EhGalleryImage[] = this.dataSource.getAll()
    if (current.length < fresh.length) {
      return false
    }
    for (let i: number = 0; i < fresh.length; i++) {
      if (current[i].page !== fresh[i].page) {
        return false
      }
    }
    return true
  }

  hasSeeded(): boolean {
    return this.seeded
  }

  hasMore(): boolean {
    return this.nextForwardPreviewPage() >= 0
  }

  /** Load the next preview page next to the current sparse anchor. */
  async loadNext(): Promise<void> {
    if (this.loading || !this.hasMore() || this.gid.length === 0) {
      return
    }
    const epoch: number = this.sessionEpoch
    this.loading = true
    this.error = ''
    try {
      const nextPage: number = this.nextForwardPreviewPage()
      if (nextPage < 0) {
        return
      }
      const more: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
        this.gid,
        this.token,
        this.isEx,
        nextPage,
      )
      if (!this.isCurrentSession(epoch)) {
        return
      }
      this.mergePreviewPage(nextPage, more)
      this.itemCount = this.dataSource.totalCount()
      this.advanceContiguousLoadedPages()
      this.currentPreviewPage = nextPage
    } catch (err) {
      if (!this.isCurrentSession(epoch)) {
        return
      }
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'thumbs_loadnext_failed', (err as Error).message)
    } finally {
      if (this.isCurrentSession(epoch)) {
        this.loading = false
      }
    }
  }

  loadedImages(): EhGalleryImage[] {
    const src: EhGalleryImage[] = this.dataSource.getAll()
    const out: EhGalleryImage[] = []
    src.forEach((img: EhGalleryImage) => {
      out.push(img.copy())
    })
    return out
  }

  loadedPreviewPages(): number {
    return this.loadedPages
  }

  loadedPreviewPageNumbers(): number[] {
    const out: number[] = []
    this.loadedPreviewPageMarkers.forEach((p: number) => {
      out.push(p)
    })
    return out
  }

  seedPerPage(): number {
    return this.firstPageCount
  }

  currentPreviewPageNumber(): number {
    return this.currentPreviewPage
  }

  visibleIndexForImagePage(pageOneBased: number): number {
    const items: EhGalleryImage[] = this.dataSource.getAll()
    for (let i: number = 0; i < items.length; i++) {
      if (items[i].page === pageOneBased) {
        return i
      }
    }
    return -1
  }

  async loadImagePage(pageOneBased: number): Promise<boolean> {
    if (pageOneBased <= 0 || this.firstPageCount <= 0) {
      return false
    }
    const epoch: number = this.sessionEpoch
    const targetPreviewPage: number = Math.floor((pageOneBased - 1) / this.firstPageCount)
    const pages: number[] = this.previewNeighborhood(targetPreviewPage)
    this.loading = true
    this.error = ''
    try {
      for (let i: number = 0; i < pages.length; i++) {
        if (!this.isCurrentSession(epoch)) {
          return false
        }
        const previewPage: number = pages[i]
        if (this.isPreviewPageLoaded(previewPage)) {
          continue
        }
        const pageImages: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
          this.gid,
          this.token,
          this.isEx,
          previewPage,
        )
        if (!this.isCurrentSession(epoch)) {
          return false
        }
        this.mergePreviewPage(previewPage, pageImages)
      }
      if (!this.isCurrentSession(epoch)) {
        return false
      }
      this.itemCount = this.dataSource.totalCount()
      this.advanceContiguousLoadedPages()
      this.currentPreviewPage = targetPreviewPage
      return this.visibleIndexForImagePage(pageOneBased) >= 0
    } catch (err) {
      if (!this.isCurrentSession(epoch)) {
        return false
      }
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'thumbs_loadpage_failed', (err as Error).message)
      return false
    } finally {
      if (this.isCurrentSession(epoch)) {
        this.loading = false
      }
    }
  }

  private previewNeighborhood(targetPreviewPage: number): number[] {
    const pages: number[] = []
    const start: number = Math.max(0, targetPreviewPage - 1)
    const end: number = Math.min(this.totalPages - 1, targetPreviewPage + 1)
    for (let page: number = start; page <= end; page++) {
      pages.push(page)
    }
    return pages
  }

  async loadPreviousPreviewPage(): Promise<number> {
    if (this.loading || this.currentPreviewPage <= 0 || this.firstPageCount <= 0 || this.gid.length === 0) {
      return -1
    }
    const epoch: number = this.sessionEpoch
    const targetPreviewPage: number = this.currentPreviewPage - 1
    if (!this.isPreviewPageLoaded(targetPreviewPage)) {
      this.loading = true
      this.error = ''
      try {
        const pageImages: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
          this.gid,
          this.token,
          this.isEx,
          targetPreviewPage,
        )
        if (!this.isCurrentSession(epoch)) {
          return -1
        }
        this.mergePreviewPage(targetPreviewPage, pageImages)
        this.itemCount = this.dataSource.totalCount()
        this.advanceContiguousLoadedPages()
      } catch (err) {
        if (!this.isCurrentSession(epoch)) {
          return -1
        }
        this.error = EhErrorText.forUser(err)
        DiagnosticLogger.warn('gallery', 'thumbs_loadprevious_failed', (err as Error).message)
        return -1
      } finally {
        if (this.isCurrentSession(epoch)) {
          this.loading = false
        }
      }
    }
    if (!this.isCurrentSession(epoch)) {
      return -1
    }
    this.currentPreviewPage = targetPreviewPage
    return targetPreviewPage * this.firstPageCount + 1
  }

  private mergePreviewPage(previewPage: number, pageImages: EhGalleryImage[]): void {
    if (pageImages.length === 0) {
      return
    }
    if (AllThumbnailsTailAppend.appendIfStrictTail(this.dataSource, pageImages)) {
      this.markPreviewPageLoaded(previewPage)
      return
    }
    const merged: EhGalleryImage[] = []
    this.dataSource.getAll().forEach((img: EhGalleryImage) => {
      merged.push(img.copy())
    })
    pageImages.forEach((img: EhGalleryImage) => {
      let replaced: boolean = false
      for (let i: number = 0; i < merged.length; i++) {
        if (merged[i].page === img.page) {
          merged[i] = img.copy()
          replaced = true
          break
        }
      }
      if (!replaced) {
        merged.push(img.copy())
      }
    })
    merged.sort((a: EhGalleryImage, b: EhGalleryImage): number => a.page - b.page)
    this.dataSource.setData(merged)
    this.markPreviewPageLoaded(previewPage)
  }

  private markPreviewPageLoaded(previewPage: number): void {
    if (this.isPreviewPageLoaded(previewPage)) {
      return
    }
    this.loadedPreviewPageMarkers.push(previewPage)
  }

  private isPreviewPageLoaded(previewPage: number): boolean {
    for (let i: number = 0; i < this.loadedPreviewPageMarkers.length; i++) {
      if (this.loadedPreviewPageMarkers[i] === previewPage) {
        return true
      }
    }
    return false
  }

  private nextForwardPreviewPage(): number {
    let next: number = this.currentPreviewPage + 1
    while (next < this.totalPages && this.isPreviewPageLoaded(next)) {
      next++
    }
    return next < this.totalPages ? next : -1
  }

  private advanceContiguousLoadedPages(): void {
    let next: number = this.loadedPages
    while (this.isPreviewPageLoaded(next)) {
      next++
    }
    this.loadedPages = next
  }
}

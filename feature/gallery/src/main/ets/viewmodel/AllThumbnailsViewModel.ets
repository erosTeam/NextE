import {
  EhApiService,
  EhGalleryImage,
  AllThumbnailsParams,
  BasicDataSource,
  DiagnosticLogger,
  EhErrorText,
} from 'shared'

/**
 * Drives the separate all-thumbnails page (eros_fe AllThumbnailsPageController). The detail page only
 * shows the first preview page (a peek); this page is seeded with that first page and can load sparse
 * preview pages directly for page-number jumps. Forward/backward paging follows the current preview
 * page, not just the contiguous first-page range. Rows live in a stable LazyForEach data source (out of
 * @Trace); itemCount mirrors its count as @Trace so the grid re-evaluates.
 */
@ObservedV2
export class AllThumbnailsViewModel {
  dataSource: BasicDataSource<EhGalleryImage> = new BasicDataSource<EhGalleryImage>()
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

  seed(p: AllThumbnailsParams): void {
    if (this.seeded) {
      return
    }
    this.seeded = true
    this.gid = p.gid
    this.token = p.token
    this.isEx = p.isEx
    this.totalPages = p.previewPageCount > 0 ? p.previewPageCount : 1
    this.dataSource.setData(p.firstPage)
    this.itemCount = this.dataSource.totalCount()
    this.loadedPages = p.firstPage.length > 0 ? 1 : 0
    this.loadedPreviewPageMarkers = []
    if (p.firstPage.length > 0) {
      this.markPreviewPageLoaded(0)
    }
    this.firstPageCount = p.firstPage.length
    this.currentPreviewPage = 0
  }

  hasMore(): boolean {
    return this.nextForwardPreviewPage() >= 0
  }

  /** Load the next preview page next to the current sparse anchor. */
  async loadNext(): Promise<void> {
    if (this.loading || !this.hasMore() || this.gid.length === 0) {
      return
    }
    this.loading = true
    this.error = ''
    try {
      const nextPage: number = this.nextForwardPreviewPage()
      if (nextPage < 0) {
        this.loading = false
        return
      }
      const more: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
        this.gid,
        this.token,
        this.isEx,
        nextPage,
      )
      this.mergePreviewPage(nextPage, more)
      this.itemCount = this.dataSource.totalCount()
      this.advanceContiguousLoadedPages()
      this.currentPreviewPage = nextPage
    } catch (err) {
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'thumbs_loadnext_failed', (err as Error).message)
    }
    this.loading = false
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
    const targetPreviewPage: number = Math.floor((pageOneBased - 1) / this.firstPageCount)
    const pages: number[] = this.previewNeighborhood(targetPreviewPage)
    this.loading = true
    this.error = ''
    try {
      for (let i: number = 0; i < pages.length; i++) {
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
        this.mergePreviewPage(previewPage, pageImages)
      }
      this.itemCount = this.dataSource.totalCount()
      this.advanceContiguousLoadedPages()
      this.currentPreviewPage = targetPreviewPage
    } catch (err) {
      this.error = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'thumbs_loadpage_failed', (err as Error).message)
    }
    this.loading = false
    return this.visibleIndexForImagePage(pageOneBased) >= 0
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
        this.mergePreviewPage(targetPreviewPage, pageImages)
        this.itemCount = this.dataSource.totalCount()
        this.advanceContiguousLoadedPages()
      } catch (err) {
        this.error = EhErrorText.forUser(err)
        DiagnosticLogger.warn('gallery', 'thumbs_loadprevious_failed', (err as Error).message)
        this.loading = false
        return -1
      }
      this.loading = false
    }
    this.currentPreviewPage = targetPreviewPage
    return targetPreviewPage * this.firstPageCount + 1
  }

  private mergePreviewPage(previewPage: number, pageImages: EhGalleryImage[]): void {
    if (pageImages.length === 0) {
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

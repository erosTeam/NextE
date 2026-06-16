import {
  EhApiService,
  EhGalleryImage,
  AllThumbnailsParams,
  BasicDataSource,
  DiagnosticLogger,
} from 'shared'

/**
 * Drives the separate all-thumbnails page (eros_fe AllThumbnailsPageController). The detail page only
 * shows the first preview page (a peek); this page is seeded with that first page and pages the rest
 * forward on demand via getPreviewImages (?p=loadedPages). Rows live in a stable LazyForEach data
 * source (out of @Trace); itemCount mirrors its count as @Trace so the grid re-evaluates.
 */
@ObservedV2
export class AllThumbnailsViewModel {
  dataSource: BasicDataSource<EhGalleryImage> = new BasicDataSource<EhGalleryImage>()
  @Trace itemCount: number = 0
  @Trace loading: boolean = false
  @Trace error: string = ''
  // loadedPages is 0-based count of fetched preview pages; the seed (page index 0) counts as 1.
  private loadedPages: number = 0
  private totalPages: number = 1
  private gid: string = ''
  private token: string = ''
  private isEx: boolean = false
  private seeded: boolean = false

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
  }

  hasMore(): boolean {
    return this.loadedPages < this.totalPages
  }

  /** Append the next preview page (?p = loadedPages, since the seed page = ?p=0). */
  async loadNext(): Promise<void> {
    if (this.loading || !this.hasMore() || this.gid.length === 0) {
      return
    }
    this.loading = true
    this.error = ''
    try {
      const more: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
        this.gid,
        this.token,
        this.isEx,
        this.loadedPages,
      )
      this.dataSource.appendData(more)
      this.itemCount = this.dataSource.totalCount()
      this.loadedPages = this.loadedPages + 1
    } catch (err) {
      const e = err as Error
      this.error = e.message
      DiagnosticLogger.warn('gallery', 'thumbs_loadnext_failed', e.message)
    }
    this.loading = false
  }
}

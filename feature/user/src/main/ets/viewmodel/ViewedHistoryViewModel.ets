import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  BasicDataSource,
  EhGallery,
  ViewedGallery,
  ViewedHistoryCursor,
  ViewedHistoryPage,
  ViewedHistorySettings,
  connectViewedHistory,
} from 'shared'

const HISTORY_PAGE_SIZE: number = 20
const HISTORY_PREFETCH_DISTANCE: number = 3

/** Page-owned cursor list for viewed history; rows never live in global reactive state. */
@ObservedV2
export class ViewedHistoryViewModel {
  dataSource: BasicDataSource<EhGallery> = new BasicDataSource<EhGallery>(
    (gallery: EhGallery): string => `viewed_${gallery.gid.replace(/[^A-Za-z0-9_]/g, '_')}`,
  )
  @Trace itemCount: number = 0
  @Trace isLoading: boolean = false
  @Trace isLoadingMore: boolean = false
  @Trace hasMore: boolean = true
  @Trace errorMessage: string = ''
  @Trace loaded: boolean = false
  private cursor: ViewedHistoryCursor | null = null
  private context: common.UIAbilityContext | null = null
  private epoch: number = 0
  private observedRevision: number = -1
  private removingGids: Set<string> = new Set<string>()

  setContext(context: common.UIAbilityContext): void {
    this.context = context
  }

  async loadInitial(force: boolean = false): Promise<void> {
    if (this.context === null || this.isLoading || (!force && this.loaded)) {
      return
    }
    const run: number = this.epoch + 1
    this.epoch = run
    this.isLoading = true
    this.isLoadingMore = false
    this.hasMore = false
    this.errorMessage = ''
    try {
      const page: ViewedHistoryPage = await ViewedHistorySettings.loadPage(
        this.context,
        HISTORY_PAGE_SIZE,
        null,
      )
      if (run !== this.epoch) {
        return
      }
      const rows: EhGallery[] = this.mapRows(page.items)
      this.dataSource.setData(rows)
      this.itemCount = rows.length
      this.cursor = page.nextCursor
      this.hasMore = page.hasMore
      this.observedRevision = connectViewedHistory().revision
      this.loaded = true
    } catch (error) {
      if (run === this.epoch) {
        this.errorMessage = AppStrings.get('common_load_failed')
        this.loaded = true
      }
    } finally {
      if (run === this.epoch) {
        this.isLoading = false
      }
    }
  }

  async loadMore(): Promise<void> {
    if (
      this.context === null ||
      this.isLoading ||
      this.isLoadingMore ||
      !this.hasMore ||
      this.cursor === null
    ) {
      return
    }
    const run: number = this.epoch
    const cursor: ViewedHistoryCursor = this.cursor
    this.isLoadingMore = true
    this.errorMessage = ''
    try {
      const page: ViewedHistoryPage = await ViewedHistorySettings.loadPage(
        this.context,
        HISTORY_PAGE_SIZE,
        cursor,
      )
      if (run !== this.epoch) {
        return
      }
      const rows: EhGallery[] = this.dedupeRows(this.mapRows(page.items))
      this.dataSource.appendData(rows)
      this.itemCount = this.dataSource.totalCount()
      this.cursor = page.nextCursor
      this.hasMore = page.hasMore
    } catch (error) {
      if (run === this.epoch) {
        this.errorMessage = AppStrings.get('common_load_failed')
      }
    } finally {
      if (run === this.epoch) {
        this.isLoadingMore = false
      }
    }
  }

  loadMoreIfNearTail(index: number): void {
    if (index >= this.itemCount - HISTORY_PREFETCH_DISTANCE) {
      this.loadMore()
    }
  }

  canLoadMore(): boolean {
    return this.hasMore && !this.isLoading && !this.isLoadingMore && this.cursor !== null
  }

  async reloadIfChanged(revision: number): Promise<void> {
    if (!this.loaded || revision !== this.observedRevision) {
      await this.loadInitial(true)
    }
  }

  async remove(gid: string): Promise<boolean> {
    if (this.context === null) {
      return false
    }
    const index: number = this.indexOfGid(gid)
    if (index < 0 || gid.length === 0 || this.removingGids.has(gid)) {
      return false
    }
    this.removingGids.add(gid)
    try {
      const removed: boolean = await ViewedHistorySettings.remove(this.context, gid)
      if (!removed) {
        return false
      }
      const currentIndex: number = this.indexOfGid(gid)
      if (currentIndex >= 0) {
        this.dataSource.removeDataAt(currentIndex)
        this.itemCount = this.dataSource.totalCount()
      }
      this.observedRevision = connectViewedHistory().revision
      if (this.hasMore) {
        this.loadMore()
      }
      return true
    } finally {
      this.removingGids.delete(gid)
    }
  }

  async clear(): Promise<boolean> {
    if (this.context === null) {
      return false
    }
    try {
      await ViewedHistorySettings.clear(this.context)
      this.epoch = this.epoch + 1
      this.dataSource.clear()
      this.itemCount = 0
      this.cursor = null
      this.hasMore = false
      this.errorMessage = ''
      this.loaded = true
      this.observedRevision = connectViewedHistory().revision
      return true
    } catch (error) {
      this.errorMessage = AppStrings.get('common_load_failed')
      return false
    }
  }

  private mapRows(items: ViewedGallery[]): EhGallery[] {
    const out: EhGallery[] = []
    items.forEach((item: ViewedGallery) => out.push(this.toGallery(item)))
    return out
  }

  private toGallery(item: ViewedGallery): EhGallery {
    const gallery: EhGallery = new EhGallery(item.gid, item.token)
    gallery.englishTitle = item.title
    gallery.japaneseTitle = item.titleJp
    gallery.thumbUrl = item.thumbUrl
    gallery.category = item.category
    gallery.uploader = item.uploader
    gallery.rating = item.rating
    gallery.ratingFallBack = item.rating
    gallery.fileCount = item.fileCount
    gallery.postTime = this.formatTime(item.time)
    gallery.lastViewTime = item.time
    return gallery
  }

  private formatTime(time: number): string {
    if (time <= 0) {
      return ''
    }
    const date: Date = new Date(time)
    const month: string = `${date.getMonth() + 1}`.padStart(2, '0')
    const day: string = `${date.getDate()}`.padStart(2, '0')
    const hour: string = `${date.getHours()}`.padStart(2, '0')
    const minute: string = `${date.getMinutes()}`.padStart(2, '0')
    return `${month}-${day} ${hour}:${minute}`
  }

  private dedupeRows(rows: EhGallery[]): EhGallery[] {
    const seen: Set<string> = new Set<string>()
    this.dataSource.getAll().forEach((gallery: EhGallery) => seen.add(gallery.gid))
    const out: EhGallery[] = []
    rows.forEach((gallery: EhGallery) => {
      if (gallery.gid.length > 0 && !seen.has(gallery.gid)) {
        seen.add(gallery.gid)
        out.push(gallery)
      }
    })
    return out
  }

  private indexOfGid(gid: string): number {
    const items: EhGallery[] = this.dataSource.getAll()
    for (let index: number = 0; index < items.length; index++) {
      if (items[index].gid === gid) {
        return index
      }
    }
    return -1
  }
}

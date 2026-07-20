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

/** Stable V2 row state for one history entry while LazyForEach retains its gid key. */
@ObservedV2
export class ViewedHistoryListRow {
  @Trace gallery: EhGallery = new EhGallery()

  constructor(gallery: EhGallery = new EhGallery()) {
    this.gallery = gallery
  }
}

/** One native ListItemGroup day section; its data source stays stable while a cursor page appends. */
export class ViewedHistoryDayGroup {
  key: string = ''
  // Calendar-day identity only. The displayed relative label must be resolved by the page at render
  // time, otherwise a group created before midnight keeps a stale "Today" string forever.
  dayStart: number = 0
  dataSource: BasicDataSource<ViewedHistoryListRow> = new BasicDataSource<ViewedHistoryListRow>(
    (row: ViewedHistoryListRow): string => `viewed_${row.gallery.gid.replace(/[^A-Za-z0-9_]/g, '_')}`,
  )

  constructor(key: string = '', dayStart: number = 0) {
    this.key = key
    this.dayStart = dayStart
  }
}

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
  @Trace dayGroups: ViewedHistoryDayGroup[] = []
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
      this.resetDayGroups(rows)
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
      this.appendDayGroups(rows)
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

  loadMoreIfNearTailGallery(gid: string): void {
    this.loadMoreIfNearTail(this.indexOfGid(gid))
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
        this.removeFromDayGroups(gid)
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
      this.dayGroups = []
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
    gallery.ratingFallBack = item.ratingFallBack > 0 ? item.ratingFallBack : item.rating
    gallery.colorRating = item.colorRating
    gallery.fileCount = item.fileCount
    gallery.translated = item.translated
    gallery.expunged = item.expunged
    gallery.postTime = item.postTime
    gallery.lastViewTime = item.time
    return gallery
  }

  private resetDayGroups(rows: EhGallery[]): void {
    const existingByKey: Map<string, ViewedHistoryDayGroup> = new Map<string, ViewedHistoryDayGroup>()
    const existingRowsByGid: Map<string, ViewedHistoryListRow> = new Map<string, ViewedHistoryListRow>()
    this.dayGroups.forEach((group: ViewedHistoryDayGroup) => {
      existingByKey.set(group.key, group)
      group.dataSource.getAll().forEach((row: ViewedHistoryListRow) => {
        existingRowsByGid.set(row.gallery.gid, row)
      })
    })
    const rowsByKey: Map<string, ViewedHistoryListRow[]> = new Map<string, ViewedHistoryListRow[]>()
    const orderedKeys: string[] = []
    const dayStarts: Map<string, number> = new Map<string, number>()
    rows.forEach((gallery: EhGallery) => {
      const dayStart: number = this.localDayStart(gallery.lastViewTime)
      const key: string = this.dayKey(dayStart)
      let bucket: ViewedHistoryListRow[] | undefined = rowsByKey.get(key)
      if (bucket === undefined) {
        bucket = []
        rowsByKey.set(key, bucket)
        orderedKeys.push(key)
        dayStarts.set(key, dayStart)
      }
      let row: ViewedHistoryListRow | undefined = existingRowsByGid.get(gallery.gid)
      if (row === undefined) {
        row = new ViewedHistoryListRow(gallery)
      } else {
        row.gallery = gallery
      }
      bucket.push(row)
    })
    const groups: ViewedHistoryDayGroup[] = []
    orderedKeys.forEach((key: string) => {
      let group: ViewedHistoryDayGroup | undefined = existingByKey.get(key)
      if (group === undefined) {
        group = new ViewedHistoryDayGroup(key, dayStarts.get(key) ?? 0)
      }
      const groupRows: ViewedHistoryListRow[] = rowsByKey.get(key) ?? []
      group.dataSource.setData(groupRows)
      groups.push(group)
    })
    this.dayGroups = groups
  }

  private appendDayGroups(rows: EhGallery[]): void {
    if (rows.length === 0) {
      return
    }
    const groups: ViewedHistoryDayGroup[] = this.dayGroups.slice()
    const groupCount: number = groups.length
    this.appendRowsToGroups(groups, rows)
    if (groups.length !== groupCount) {
      this.dayGroups = groups
    }
  }

  private appendRowsToGroups(groups: ViewedHistoryDayGroup[], rows: EhGallery[]): void {
    let group: ViewedHistoryDayGroup | undefined = groups.length > 0 ? groups[groups.length - 1] : undefined
    for (let i: number = 0; i < rows.length; i++) {
      const gallery: EhGallery = rows[i]
      const dayStart: number = this.localDayStart(gallery.lastViewTime)
      const key: string = this.dayKey(dayStart)
      if (group === undefined || group.key !== key) {
        group = new ViewedHistoryDayGroup(key, dayStart)
        groups.push(group)
      }
      group.dataSource.appendData([new ViewedHistoryListRow(gallery)])
    }
  }

  private removeFromDayGroups(gid: string): void {
    for (let groupIndex: number = 0; groupIndex < this.dayGroups.length; groupIndex++) {
      const group: ViewedHistoryDayGroup = this.dayGroups[groupIndex]
      const rows: ViewedHistoryListRow[] = group.dataSource.getAll()
      for (let rowIndex: number = 0; rowIndex < rows.length; rowIndex++) {
        if (rows[rowIndex].gallery.gid !== gid) {
          continue
        }
        group.dataSource.removeDataAt(rowIndex)
        if (group.dataSource.totalCount() === 0) {
          const groups: ViewedHistoryDayGroup[] = this.dayGroups.slice()
          groups.splice(groupIndex, 1)
          this.dayGroups = groups
        }
        return
      }
    }
  }

  private dayKey(time: number): string {
    const date: Date = new Date(time)
    const month: string = `${date.getMonth() + 1}`.padStart(2, '0')
    const day: string = `${date.getDate()}`.padStart(2, '0')
    return `${date.getFullYear()}-${month}-${day}`
  }

  private localDayStart(time: number): number {
    const date: Date = new Date(time)
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
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

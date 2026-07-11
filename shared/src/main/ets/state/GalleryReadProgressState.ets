import { AppStorageV2 } from '@kit.ArkUI'
import { ReadColumnMode } from './ReadModeState'

/**
 * One persisted reading-progress record (port of eros_fe GalleryCache's lastIndex+time).
 * `t` is the last-write epoch millis. A local mutation advances it monotonically per gallery so
 * deferred RDB writes can reject an older snapshot that completes after a newer one; the in-memory
 * page index itself still follows last-call-wins. It is also the seam for cross-device newest-wins.
 */
export class ReadProgressEntry {
  g: string = ''
  i: number = 0
  t: number = 0
  c: string = ''

  constructor(g: string = '', i: number = 0, t: number = 0, c: string = '') {
    this.g = g
    this.i = i
    this.t = t
    this.c = c
  }
}

/**
 * Per-gallery reading position (eros_fe `pageState.lastIndex` / GalleryCacheController.gCacheMap).
 *
 * The reader writes the current page here as the user pages (debounced to disk by
 * GalleryReadProgressSettings, the single writer); the gallery detail's READ button reads it back
 * to resume at that page and label itself with the progress. The actual gid→index map is a plain
 * Map (a `@Trace` Map wouldn't observe internal mutations); reactivity rides on `revision`, bumped
 * on every write, which `getIndex` touches so a consumer reading it inside build() re-evaluates.
 */
@ObservedV2
export class GalleryReadProgressState {
  // Bumped on every write so build()-time readers of getIndex() re-render. (Plain Map below is
  // not itself observable — this counter is the reactive surface.)
  @Trace revision: number = 0
  private indexMap: Map<string, number> = new Map()
  private timeMap: Map<string, number> = new Map()
  private columnModeMap: Map<string, string> = new Map()

  /** Saved page index for a gallery (0 when none). Reads `revision` so callers subscribe. */
  getIndex(gid: string): number {
    // Always-false guard whose sole purpose is to read `revision`, establishing the reactive
    // dependency for any build()-scope caller (so returning from the reader updates the label).
    if (this.revision < 0) {
      return 0
    }
    if (gid.length === 0) {
      return 0
    }
    const v: number | undefined = this.indexMap.get(gid)
    return v === undefined ? 0 : v
  }

  getColumnMode(gid: string): string {
    if (this.revision < 0) {
      return ReadColumnMode.ODD_LEFT
    }
    if (gid.length === 0) {
      return ReadColumnMode.ODD_LEFT
    }
    const v: string | undefined = this.columnModeMap.get(gid)
    if (v === ReadColumnMode.EVEN_LEFT || v === ReadColumnMode.ODD_LEFT) {
      return v
    }
    return ReadColumnMode.ODD_LEFT
  }

  /**
   * Update one gallery's progress in memory. The page itself is last-call-wins (matching eros_fe),
   * while `t` advances monotonically for this gid so an older deferred snapshot cannot win on disk.
   * Disk flush is the caller's job.
   */
  setIndex(gid: string, index: number, time: number): void {
    if (gid.length === 0 || index < 0) {
      return
    }
    this.indexMap.set(gid, index)
    this.timeMap.set(gid, this.nextUpdatedAt(gid, time))
    this.revision = this.revision + 1
  }

  setColumnMode(gid: string, columnMode: string, time: number): void {
    if (gid.length === 0 || (columnMode !== ReadColumnMode.ODD_LEFT && columnMode !== ReadColumnMode.EVEN_LEFT)) {
      return
    }
    // A reader can change the pairing before it turns a page. Keep a page-zero record so this
    // per-gallery preference is included in the persistence snapshot rather than being dropped.
    if (!this.indexMap.has(gid)) {
      this.indexMap.set(gid, 0)
    }
    this.columnModeMap.set(gid, columnMode)
    this.timeMap.set(gid, this.nextUpdatedAt(gid, time))
    this.revision = this.revision + 1
  }

  /** Current durable-shaped entry for one gallery, or null when it has never been tracked. */
  getEntry(gid: string): ReadProgressEntry | null {
    // Establish the same build-time dependency as getIndex/getColumnMode for callers that snapshot
    // a freshly-mutated record before deferring it to RDB.
    if (this.revision < 0 || gid.length === 0) {
      return null
    }
    const index: number | undefined = this.indexMap.get(gid)
    if (index === undefined) {
      return null
    }
    const time: number | undefined = this.timeMap.get(gid)
    const columnMode: string | undefined = this.columnModeMap.get(gid)
    return new ReadProgressEntry(
      gid,
      index,
      time === undefined ? 0 : time,
      columnMode === undefined ? '' : columnMode,
    )
  }

  /** Snapshot for persistence. */
  snapshot(): ReadProgressEntry[] {
    const out: ReadProgressEntry[] = []
    this.indexMap.forEach((idx: number, gid: string) => {
      const t: number | undefined = this.timeMap.get(gid)
      const c: string | undefined = this.columnModeMap.get(gid)
      out.push(new ReadProgressEntry(gid, idx, t === undefined ? 0 : t, c === undefined ? '' : c))
    })
    return out
  }

  /** Bulk-replace the in-memory map (restore-from-disk at startup). */
  replaceAll(entries: ReadProgressEntry[]): void {
    this.indexMap.clear()
    this.timeMap.clear()
    this.columnModeMap.clear()
    entries.forEach((e: ReadProgressEntry) => {
      if (e.g.length > 0 && e.i >= 0) {
        this.indexMap.set(e.g, e.i)
        this.timeMap.set(e.g, e.t)
        if (e.c === ReadColumnMode.ODD_LEFT || e.c === ReadColumnMode.EVEN_LEFT) {
          this.columnModeMap.set(e.g, e.c)
        }
      }
    })
    this.revision = this.revision + 1
  }

  /** Merge entries that changed while an async store refresh was in flight. */
  mergeNewest(entries: ReadProgressEntry[]): void {
    let changed: boolean = false
    entries.forEach((entry: ReadProgressEntry) => {
      if (entry.g.length === 0 || entry.i < 0) {
        return
      }
      const currentTime: number | undefined = this.timeMap.get(entry.g)
      if (currentTime !== undefined && currentTime > entry.t) {
        return
      }
      const currentIndex: number | undefined = this.indexMap.get(entry.g)
      const currentColumnMode: string | undefined = this.columnModeMap.get(entry.g)
      const nextColumnMode: string =
        entry.c === ReadColumnMode.ODD_LEFT || entry.c === ReadColumnMode.EVEN_LEFT ? entry.c : ''
      if (
        currentTime === entry.t && currentIndex === entry.i &&
        (currentColumnMode === undefined ? '' : currentColumnMode) === nextColumnMode
      ) {
        return
      }
      this.indexMap.set(entry.g, entry.i)
      this.timeMap.set(entry.g, entry.t)
      if (nextColumnMode.length > 0) {
        this.columnModeMap.set(entry.g, nextColumnMode)
      } else {
        this.columnModeMap.delete(entry.g)
      }
      changed = true
    })
    if (changed) {
      this.revision = this.revision + 1
    }
  }

  private nextUpdatedAt(gid: string, requestedTime: number): number {
    const previous: number | undefined = this.timeMap.get(gid)
    const requested: number = Math.max(0, Math.floor(requestedTime))
    if (previous === undefined || requested > previous) {
      return requested
    }
    return previous + 1
  }
}

const READ_PROGRESS_KEY: string = 'v2:galleryReadProgress'

export function connectGalleryReadProgress(): GalleryReadProgressState {
  return AppStorageV2.connect(
    GalleryReadProgressState,
    READ_PROGRESS_KEY,
    () => new GalleryReadProgressState(),
  )!
}

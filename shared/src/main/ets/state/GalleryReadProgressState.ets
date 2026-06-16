import { AppStorageV2 } from '@kit.ArkUI'

/**
 * One persisted reading-progress record (port of eros_fe GalleryCache's lastIndex+time).
 * `t` is the last-write epoch millis. Locally it's just metadata (writes are last-write-wins);
 * it's the seam for later cross-device sync, which reconciles newest-wins across sources.
 */
export class ReadProgressEntry {
  g: string = ''
  i: number = 0
  t: number = 0

  constructor(g: string = '', i: number = 0, t: number = 0) {
    this.g = g
    this.i = i
    this.t = t
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

  /**
   * Update one gallery's progress in memory. Last write wins (eros_fe's local
   * GalleryCacheController.setIndex overwrites unconditionally — newest-wins is reconciled only at
   * the sync layer, so `t` is recorded but NOT compared here). Disk flush is the caller's job.
   */
  setIndex(gid: string, index: number, time: number): void {
    if (gid.length === 0 || index < 0) {
      return
    }
    this.indexMap.set(gid, index)
    this.timeMap.set(gid, time)
    this.revision = this.revision + 1
  }

  /** Snapshot for persistence. */
  snapshot(): ReadProgressEntry[] {
    const out: ReadProgressEntry[] = []
    this.indexMap.forEach((idx: number, gid: string) => {
      const t: number | undefined = this.timeMap.get(gid)
      out.push(new ReadProgressEntry(gid, idx, t === undefined ? 0 : t))
    })
    return out
  }

  /** Bulk-replace the in-memory map (restore-from-disk at startup). */
  replaceAll(entries: ReadProgressEntry[]): void {
    this.indexMap.clear()
    this.timeMap.clear()
    entries.forEach((e: ReadProgressEntry) => {
      if (e.g.length > 0 && e.i >= 0) {
        this.indexMap.set(e.g, e.i)
        this.timeMap.set(e.g, e.t)
      }
    })
    this.revision = this.revision + 1
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

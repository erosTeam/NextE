import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { CacheStat } from './CacheStat'

const CACHE_DIR_NAME: string = 'image-block-preview'
const MAX_CACHE_FILE_COUNT: number = 128
const MAX_CACHE_BYTES: number = 32 * 1024 * 1024
// A preview crop completes on the settings-card path. Amortize directory scans without allowing
// the bounded cache to drift materially past its 128-file / 32 MiB target.
const PREVIEW_CACHE_MAINTENANCE_WRITE_INTERVAL: number = 8
const PREVIEW_CACHE_MAINTENANCE_BYTES_INTERVAL: number = 2 * 1024 * 1024

class ImageBlockPreviewCacheEntry {
  path: string = ''
  bytes: number = 0
  mtime: number = 0

  constructor(path: string, bytes: number, mtime: number) {
    this.path = path
    this.bytes = bytes
    this.mtime = mtime
  }
}

/**
 * Bounds generated crops used only by image-block settings previews. Eviction never changes a pHash
 * decision: a missing crop is rebuilt from the rule source when that settings card appears again.
 */
export class ImageBlockPreviewCacheService {
  private static pruneChain: Promise<void> = Promise.resolve()
  private static maintenanceWritesSincePrune: number = -1
  private static maintenanceBytesSincePrune: number = 0

  static filePath(context: common.UIAbilityContext, fileName: string): string {
    const dir: string = ImageBlockPreviewCacheService.cacheDir(context)
    ImageBlockPreviewCacheService.ensureDir(dir)
    return `${dir}/${fileName}`
  }

  static touch(path: string): void {
    try {
      fileIo.utimes(path, Date.now())
    } catch (_error) {}
  }

  static async stat(context: common.UIAbilityContext): Promise<CacheStat> {
    const out: CacheStat = new CacheStat()
    const entries: ImageBlockPreviewCacheEntry[] = ImageBlockPreviewCacheService.entries(context, false)
    out.count = entries.length
    for (let i: number = 0; i < entries.length; i++) {
      out.bytes += entries[i].bytes
    }
    return out
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    const dir: string = ImageBlockPreviewCacheService.cacheDir(context)
    try {
      if (!fileIo.accessSync(dir)) {
        return
      }
      const names: string[] = fileIo.listFileSync(dir)
      for (let i: number = 0; i < names.length; i++) {
        ImageBlockPreviewCacheService.removeIfExists(`${dir}/${names[i]}`)
      }
    } catch (error) {
      DiagnosticLogger.warn('image-cache', 'image_block_preview_clear_failed', (error as Error).message)
    } finally {
      ImageBlockPreviewCacheService.resetMaintenanceCadence()
    }
  }

  /**
   * Keep generated source-preview cards responsive by avoiding a full cache scan after every crop.
   * Explicit startup maintenance retains eager `pruneToLimit()` semantics and partial-file cleanup.
   */
  static async pruneAfterStore(
    context: common.UIAbilityContext,
    protectedPath: string,
    storedBytes: number,
  ): Promise<void> {
    const addedBytes: number = storedBytes > 0 ? storedBytes : 0
    const maintenanceDue: boolean =
      ImageBlockPreviewCacheService.maintenanceWritesSincePrune < 0 ||
      ImageBlockPreviewCacheService.maintenanceWritesSincePrune >=
        PREVIEW_CACHE_MAINTENANCE_WRITE_INTERVAL - 1 ||
      ImageBlockPreviewCacheService.maintenanceBytesSincePrune + addedBytes >=
        PREVIEW_CACHE_MAINTENANCE_BYTES_INTERVAL
    if (!maintenanceDue) {
      ImageBlockPreviewCacheService.maintenanceWritesSincePrune =
        ImageBlockPreviewCacheService.maintenanceWritesSincePrune + 1
      ImageBlockPreviewCacheService.maintenanceBytesSincePrune =
        ImageBlockPreviewCacheService.maintenanceBytesSincePrune + addedBytes
      return
    }

    // Move the cadence forward before awaiting the shared chain so concurrent crop writes preserve
    // their own accounting and can schedule a later maintenance pass.
    ImageBlockPreviewCacheService.maintenanceWritesSincePrune = 0
    ImageBlockPreviewCacheService.maintenanceBytesSincePrune = 0
    try {
      await ImageBlockPreviewCacheService.pruneToLimit(context, false, protectedPath)
    } catch (error) {
      // The crop was already atomically committed. Retry cleanup on the next write instead of hiding it.
      ImageBlockPreviewCacheService.resetMaintenanceCadence()
      DiagnosticLogger.warn('image-cache', 'image_block_preview_maintenance_failed', (error as Error).message)
    }
  }

  static pruneToLimit(
    context: common.UIAbilityContext,
    cleanupPartialFiles: boolean = false,
    protectedPath: string = '',
  ): Promise<void> {
    const next: Promise<void> = ImageBlockPreviewCacheService.pruneChain.then(
      (): Promise<void> =>
        ImageBlockPreviewCacheService.pruneNow(context, cleanupPartialFiles, protectedPath),
      (): Promise<void> =>
        ImageBlockPreviewCacheService.pruneNow(context, cleanupPartialFiles, protectedPath),
    )
    ImageBlockPreviewCacheService.pruneChain = next
    return next
  }

  private static resetMaintenanceCadence(): void {
    ImageBlockPreviewCacheService.maintenanceWritesSincePrune = -1
    ImageBlockPreviewCacheService.maintenanceBytesSincePrune = 0
  }

  private static async pruneNow(
    context: common.UIAbilityContext,
    cleanupPartialFiles: boolean,
    protectedPath: string,
  ): Promise<void> {
    const entries: ImageBlockPreviewCacheEntry[] = ImageBlockPreviewCacheService.entries(context, cleanupPartialFiles)
    if (entries.length === 0) {
      return
    }
    entries.sort((a: ImageBlockPreviewCacheEntry, b: ImageBlockPreviewCacheEntry): number => a.mtime - b.mtime)
    let totalBytes: number = 0
    for (let i: number = 0; i < entries.length; i++) {
      totalBytes += entries[i].bytes
    }
    let remaining: number = entries.length
    let removed: number = 0
    for (let i: number = 0; i < entries.length; i++) {
      if ((totalBytes <= MAX_CACHE_BYTES && remaining <= MAX_CACHE_FILE_COUNT) || remaining <= 1) {
        break
      }
      if (entries[i].path === protectedPath) {
        continue
      }
      ImageBlockPreviewCacheService.removeIfExists(entries[i].path)
      totalBytes -= entries[i].bytes
      remaining--
      removed++
    }
    if (removed > 0) {
      DiagnosticLogger.info(
        'image-cache',
        'image_block_preview_pruned',
        `removed=${removed} remaining=${remaining} bytes=${totalBytes} limit=${MAX_CACHE_BYTES}`,
      )
    }
  }

  private static entries(
    context: common.UIAbilityContext,
    cleanupPartialFiles: boolean,
  ): ImageBlockPreviewCacheEntry[] {
    const out: ImageBlockPreviewCacheEntry[] = []
    const dir: string = ImageBlockPreviewCacheService.cacheDir(context)
    try {
      if (!fileIo.accessSync(dir)) {
        return out
      }
      const names: string[] = fileIo.listFileSync(dir)
      for (let i: number = 0; i < names.length; i++) {
        const name: string = names[i]
        const path: string = `${dir}/${name}`
        if (name.endsWith('.part')) {
          if (cleanupPartialFiles) {
            ImageBlockPreviewCacheService.removeIfExists(path)
          }
          continue
        }
        if (!name.endsWith('.jpg')) {
          continue
        }
        try {
          const stat = fileIo.statSync(path)
          if (stat.size > 0) {
            out.push(new ImageBlockPreviewCacheEntry(path, stat.size, stat.mtime))
          } else {
            ImageBlockPreviewCacheService.removeIfExists(path)
          }
        } catch (_error) {}
      }
    } catch (error) {
      DiagnosticLogger.warn('image-cache', 'image_block_preview_scan_failed', (error as Error).message)
    }
    return out
  }

  private static cacheDir(context: common.UIAbilityContext): string {
    return `${context.cacheDir}/${CACHE_DIR_NAME}`
  }

  private static ensureDir(dir: string): void {
    try {
      fileIo.mkdirSync(dir, true)
    } catch (error) {
      if (!fileIo.accessSync(dir)) {
        throw error as Error
      }
    }
  }

  private static removeIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_error) {}
  }
}

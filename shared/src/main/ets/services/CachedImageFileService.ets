import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhHttpClient } from '../network/EhHttpClient'
import { CacheStat } from './CacheStat'

export interface CachedImageProgress {
  loaded: number
  total: number
}

export interface CachedImageFileResult {
  filePath: string
  displayUri: string
  bytes: number
  fromCache: boolean
}

const CACHE_DIR_NAME: string = 'reader-image-cache'
const DEFAULT_IMAGE_EXTENSION: string = 'jpg'
const READER_IMAGE_CONNECT_TIMEOUT_MS: number = 6000
const READER_IMAGE_NO_PROGRESS_TIMEOUT_MS: number = 10000
const MAX_CACHE_FILE_COUNT: number = 256
const MAX_CACHE_BYTES: number = 64 * 1024 * 1024

class CachedImageFileCacheEntry {
  path: string = ''
  bytes: number = 0
  mtime: number = 0

  constructor(path: string, bytes: number, mtime: number) {
    this.path = path
    this.bytes = bytes
    this.mtime = mtime
  }
}

export class CachedImageFileService {
  private static inFlight: Map<string, Promise<CachedImageFileResult>> = new Map<
    string,
    Promise<CachedImageFileResult>
  >()
  private static pruneChain: Promise<void> = Promise.resolve()

  static cached(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
  ): CachedImageFileResult | null {
    if (url.length === 0) {
      return null
    }
    const localPath: string = CachedImageFileService.localFilePath(url)
    if (localPath.length > 0) {
      const localBytes: number = CachedImageFileService.fileSize(localPath)
      if (localBytes <= 0) {
        return null
      }
      return {
        filePath: localPath,
        displayUri: CachedImageFileService.displayUri(localPath),
        bytes: localBytes,
        fromCache: true,
      }
    }
    const filePath: string = CachedImageFileService.filePath(context, url, cacheKey)
    const cachedBytes: number = CachedImageFileService.fileSize(filePath)
    if (cachedBytes <= 0) {
      return null
    }
    CachedImageFileService.touch(filePath)
    return {
      filePath,
      displayUri: CachedImageFileService.displayUri(filePath),
      bytes: cachedBytes,
      fromCache: true,
    }
  }

  static async load(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    onProgress: (progress: CachedImageProgress) => void,
  ): Promise<CachedImageFileResult> {
    if (url.length === 0) {
      throw new Error('image URL is empty')
    }
    const cached: CachedImageFileResult | null = CachedImageFileService.cached(
      context,
      url,
      cacheKey,
    )
    if (cached !== null) {
      onProgress({ loaded: cached.bytes, total: cached.bytes })
      DiagnosticLogger.info(
        'image-cache',
        'hit',
        `bytes=${cached.bytes} urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
      )
      return cached
    }
    if (CachedImageFileService.localFilePath(url).length > 0) {
      throw new Error('local image file missing')
    }

    const filePath: string = CachedImageFileService.filePath(context, url, cacheKey)
    const inFlight: Promise<CachedImageFileResult> | undefined =
      CachedImageFileService.inFlight.get(filePath)
    if (inFlight !== undefined) {
      const result: CachedImageFileResult = await inFlight
      onProgress({ loaded: result.bytes, total: result.bytes })
      DiagnosticLogger.info(
        'image-cache',
        'join',
        `bytes=${result.bytes} urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
      )
      return result
    }

    const task: Promise<CachedImageFileResult> = CachedImageFileService.downloadAndStore(
      context,
      url,
      cacheKey,
      onProgress,
    )
    CachedImageFileService.inFlight.set(filePath, task)
    try {
      return await task
    } finally {
      CachedImageFileService.inFlight.delete(filePath)
    }
  }

  private static async downloadAndStore(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    onProgress: (progress: CachedImageProgress) => void,
  ): Promise<CachedImageFileResult> {
    const filePath: string = CachedImageFileService.filePath(context, url, cacheKey)
    const tmpPath: string = `${filePath}.part`
    CachedImageFileService.removeIfExists(tmpPath)
    let lastLoggedPercent: number = -20
    let loggedUnknownTotal: boolean = false
    try {
      const bytes: number = await EhHttpClient.getInstance().downloadBinaryToFileInStream(
        url,
        tmpPath,
        (loaded: number, total: number) => {
          if (total <= 0) {
            if (!loggedUnknownTotal) {
              loggedUnknownTotal = true
              DiagnosticLogger.info(
                'image-cache',
                'stream_progress',
                `loaded=${loaded} total=${total} percent=? urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
              )
            }
            onProgress({ loaded, total })
            return
          }
          const percent: number = Math.floor(Math.max(0, Math.min(100, loaded * 100 / total)))
          if (percent > lastLoggedPercent && (percent >= 100 || percent - lastLoggedPercent >= 20)) {
            lastLoggedPercent = percent
            DiagnosticLogger.info(
              'image-cache',
              'stream_progress',
              `loaded=${loaded} total=${total} percent=${percent} urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
            )
          }
          onProgress({ loaded, total })
        },
        READER_IMAGE_CONNECT_TIMEOUT_MS,
        READER_IMAGE_NO_PROGRESS_TIMEOUT_MS,
      )
      CachedImageFileService.removeIfExists(filePath)
      fileIo.renameSync(tmpPath, filePath)
      const finalBytes: number = bytes > 0 ? bytes : CachedImageFileService.fileSize(filePath)
      if (finalBytes <= 0) {
        CachedImageFileService.removeIfExists(filePath)
        throw new Error('downloaded image file is empty')
      }
      CachedImageFileService.touch(filePath)
      onProgress({ loaded: finalBytes, total: finalBytes })
      DiagnosticLogger.info(
        'image-cache',
        'stored',
        `bytes=${finalBytes} urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
      )
      await CachedImageFileService.pruneToLimit(context)
      return {
        filePath,
        displayUri: CachedImageFileService.displayUri(filePath),
        bytes: finalBytes,
        fromCache: false,
      }
    } catch (error) {
      CachedImageFileService.removeIfExists(tmpPath)
      throw error as Error
    }
  }

  static remove(context: common.UIAbilityContext, url: string, cacheKey: string): void {
    const filePath: string = CachedImageFileService.filePath(context, url, cacheKey)
    CachedImageFileService.removeIfExists(filePath)
    CachedImageFileService.removeIfExists(`${filePath}.part`)
  }

  // File count + total bytes of the ImageBlock thumbnail fallback directory, for the cache page.
  static async stat(context: common.UIAbilityContext): Promise<CacheStat> {
    const out: CacheStat = new CacheStat()
    const entries: CachedImageFileCacheEntry[] = CachedImageFileService.entries(context)
    out.count = entries.length
    for (let i: number = 0; i < entries.length; i++) {
      out.bytes += entries[i].bytes
    }
    return out
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    const dir: string = CachedImageFileService.cacheDir(context)
    try {
      if (!fileIo.accessSync(dir)) {
        return
      }
      const names: string[] = fileIo.listFileSync(dir)
      for (let i: number = 0; i < names.length; i++) {
        CachedImageFileService.removeIfExists(`${dir}/${names[i]}`)
      }
    } catch (error) {
      DiagnosticLogger.warn('image-cache', 'clear_failed', (error as Error).message)
    }
  }

  static pruneToLimit(context: common.UIAbilityContext): Promise<void> {
    const next: Promise<void> = CachedImageFileService.pruneChain.then(
      (): Promise<void> => CachedImageFileService.pruneNow(context),
      (): Promise<void> => CachedImageFileService.pruneNow(context),
    )
    CachedImageFileService.pruneChain = next
    return next
  }

  private static async pruneNow(context: common.UIAbilityContext): Promise<void> {
    const entries: CachedImageFileCacheEntry[] = CachedImageFileService.entries(context)
    if (entries.length === 0) {
      return
    }
    entries.sort((a: CachedImageFileCacheEntry, b: CachedImageFileCacheEntry): number => a.mtime - b.mtime)
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
      CachedImageFileService.removeIfExists(entries[i].path)
      totalBytes -= entries[i].bytes
      remaining--
      removed++
    }
    if (removed > 0) {
      DiagnosticLogger.info(
        'image-cache',
        'fallback_disk_pruned',
        `removed=${removed} remaining=${remaining} bytes=${totalBytes} limit=${MAX_CACHE_BYTES}`,
      )
    }
  }

  private static entries(context: common.UIAbilityContext): CachedImageFileCacheEntry[] {
    const out: CachedImageFileCacheEntry[] = []
    const dir: string = CachedImageFileService.cacheDir(context)
    try {
      if (!fileIo.accessSync(dir)) {
        return out
      }
      const names: string[] = fileIo.listFileSync(dir)
      for (let i: number = 0; i < names.length; i++) {
        const path: string = `${dir}/${names[i]}`
        if (names[i].endsWith('.part')) {
          CachedImageFileService.removeIfExists(path)
          continue
        }
        try {
          const stat = fileIo.statSync(path)
          if (stat.size > 0) {
            out.push(new CachedImageFileCacheEntry(path, stat.size, stat.mtime))
          } else {
            CachedImageFileService.removeIfExists(path)
          }
        } catch (_error) {}
      }
    } catch (error) {
      DiagnosticLogger.warn('image-cache', 'fallback_disk_scan_failed', (error as Error).message)
    }
    return out
  }

  static filePath(context: common.UIAbilityContext, url: string, cacheKey: string): string {
    const dir: string = CachedImageFileService.cacheDir(context)
    CachedImageFileService.ensureDir(dir)
    const key: string = url.length > 0 ? url : cacheKey
    return `${dir}/${CachedImageFileService.hashKey(key)}.${CachedImageFileService.extensionFromUrl(url)}`
  }

  private static cacheDir(context: common.UIAbilityContext): string {
    return `${context.cacheDir}/${CACHE_DIR_NAME}`
  }

  static displayUri(path: string): string {
    if (path.startsWith('file://')) {
      return path
    }
    if (path.startsWith('/')) {
      return `file://${path}`
    }
    return `file:///${path}`
  }

  private static localFilePath(url: string): string {
    if (!url.startsWith('file://')) {
      return ''
    }
    return url.substring('file://'.length)
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

  private static touch(path: string): void {
    try {
      fileIo.utimes(path, Date.now())
    } catch (_error) {}
  }

  private static fileSize(path: string): number {
    try {
      return fileIo.statSync(path).size
    } catch (_err) {
      return 0
    }
  }

  private static removeIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_err) {}
  }

  private static hashKey(value: string): string {
    let hash: number = 5381
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) + hash + value.charCodeAt(i)) >>> 0
    }
    return hash.toString(16)
  }

  private static extensionFromUrl(url: string): string {
    const queryIndex: number = url.indexOf('?')
    const clean: string = queryIndex >= 0 ? url.substring(0, queryIndex) : url
    const slashIndex: number = clean.lastIndexOf('/')
    const fileName: string = slashIndex >= 0 ? clean.substring(slashIndex + 1) : clean
    const dotIndex: number = fileName.lastIndexOf('.')
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return DEFAULT_IMAGE_EXTENSION
    }
    const ext: string = fileName.substring(dotIndex + 1).toLowerCase()
    if (
      ext === 'jpg' ||
      ext === 'jpeg' ||
      ext === 'png' ||
      ext === 'webp' ||
      ext === 'gif' ||
      ext === 'bmp' ||
      ext === 'heif'
    ) {
      return ext
    }
    return DEFAULT_IMAGE_EXTENSION
  }
}

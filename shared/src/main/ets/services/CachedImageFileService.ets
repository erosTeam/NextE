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

export class CachedImageFileService {
  private static inFlight: Map<string, Promise<CachedImageFileResult>> = new Map<
    string,
    Promise<CachedImageFileResult>
  >()

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
    onProgress({ loaded: finalBytes, total: finalBytes })
    DiagnosticLogger.info(
      'image-cache',
      'stored',
      `bytes=${finalBytes} urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
    )
    return {
      filePath,
      displayUri: CachedImageFileService.displayUri(filePath),
      bytes: finalBytes,
      fromCache: false,
    }
  }

  static remove(context: common.UIAbilityContext, url: string, cacheKey: string): void {
    CachedImageFileService.removeIfExists(CachedImageFileService.filePath(context, url, cacheKey))
  }

  // File count + total bytes of the reader image cache directory, for the cache page.
  static async stat(context: common.UIAbilityContext): Promise<CacheStat> {
    const out: CacheStat = new CacheStat()
    const dir: string = `${context.cacheDir}/${CACHE_DIR_NAME}`
    try {
      if (!fileIo.accessSync(dir)) {
        return out
      }
      const names: string[] = fileIo.listFileSync(dir)
      out.count = names.length
      for (let i: number = 0; i < names.length; i++) {
        out.bytes += CachedImageFileService.fileSize(`${dir}/${names[i]}`)
      }
    } catch (error) {
      DiagnosticLogger.warn('image-cache', 'stat_failed', (error as Error).message)
    }
    return out
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    const dir: string = `${context.cacheDir}/${CACHE_DIR_NAME}`
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

  static filePath(context: common.UIAbilityContext, url: string, cacheKey: string): string {
    const dir: string = `${context.cacheDir}/${CACHE_DIR_NAME}`
    CachedImageFileService.ensureDir(dir)
    const key: string = url.length > 0 ? url : cacheKey
    return `${dir}/${CachedImageFileService.hashKey(key)}.${CachedImageFileService.extensionFromUrl(url)}`
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

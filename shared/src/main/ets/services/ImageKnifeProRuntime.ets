import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import {
  CacheStrategy,
  HeaderOptions,
  ImageKnife,
  ImageKnifeOptionV2,
  ImageKnifeRequest,
  Priority,
} from '@ohos/imageknifepro'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhConstants } from '../constants/EhConstants'
import { EhCookieStore } from '../network/EhCookieStore'
import { CacheStat } from './CacheStat'
import { CachedImageFileResult, CachedImageFileService } from './CachedImageFileService'

const IMAGEKNIFE_FILE_CACHE_COUNT: number = 192
const IMAGEKNIFE_FILE_CACHE_BYTES: number = 96 * 1024 * 1024
const IMAGEKNIFE_MEMORY_CACHE_COUNT: number = 128
const IMAGEKNIFE_MEMORY_CACHE_BYTES: number = 32 * 1024 * 1024
const IMAGEKNIFE_MAX_REQUESTS: number = 8
const IMAGEKNIFE_CACHE_DIR: string = 'imageknife-cover-cache'
const IMAGEKNIFE_READER_CONNECT_TIMEOUT_MS: number = 6000
const IMAGEKNIFE_READER_READ_TIMEOUT_MS: number = 60000

export class ImageKnifeProRuntime {
  private static initialized: boolean = false

  static initialize(context: common.UIAbilityContext): void {
    if (ImageKnifeProRuntime.initialized) {
      return
    }
    ImageKnifeProRuntime.initialized = true
    try {
      const imageKnife: ImageKnife = ImageKnife.getInstance()
      imageKnife
        .initFileCache(
          context,
          IMAGEKNIFE_FILE_CACHE_COUNT,
          IMAGEKNIFE_FILE_CACHE_BYTES,
          IMAGEKNIFE_CACHE_DIR,
        )
        .then(() => {
          DiagnosticLogger.info('imageknife', 'file_cache_ready', IMAGEKNIFE_CACHE_DIR)
        })
        .catch((error: Error) => {
          DiagnosticLogger.warn('imageknife', 'file_cache_failed', error.message)
        })
      imageKnife.setCacheLimit(
        CacheStrategy.MEMORY,
        IMAGEKNIFE_MEMORY_CACHE_COUNT,
        IMAGEKNIFE_MEMORY_CACHE_BYTES,
      )
      imageKnife.setMaxRequests(IMAGEKNIFE_MAX_REQUESTS)
      DiagnosticLogger.info('imageknife', 'runtime_initialized', 'cover thumbnail trial')
    } catch (error) {
      DiagnosticLogger.warn('imageknife', 'runtime_initialize_failed', (error as Error).message)
    }
  }

  static clearOnBackground(): void {
    if (!ImageKnifeProRuntime.initialized) {
      return
    }
    try {
      ImageKnife.getInstance().clearOnBackground()
    } catch (error) {
      DiagnosticLogger.warn('imageknife', 'clear_on_background_failed', (error as Error).message)
    }
  }

  static reloadOnForeground(): void {
    if (!ImageKnifeProRuntime.initialized) {
      return
    }
    try {
      ImageKnife.getInstance().reloadOnForeground()
    } catch (error) {
      DiagnosticLogger.warn('imageknife', 'reload_on_foreground_failed', (error as Error).message)
    }
  }

  static stat(): CacheStat {
    const out: CacheStat = new CacheStat()
    try {
      const imageKnife: ImageKnife = ImageKnife.getInstance()
      if (!imageKnife.isFileCacheInit()) {
        return out
      }
      const count: number | undefined = imageKnife.getCurrentCacheNum(CacheStrategy.FILE)
      const bytes: number | undefined = imageKnife.getCurrentCacheSize(CacheStrategy.FILE)
      out.count = ImageKnifeProRuntime.safeMetric(count)
      out.bytes = ImageKnifeProRuntime.safeMetric(bytes)
    } catch (error) {
      DiagnosticLogger.warn('imageknife', 'stat_failed', (error as Error).message)
    }
    return out
  }

  static async clearCache(): Promise<void> {
    try {
      const imageKnife: ImageKnife = ImageKnife.getInstance()
      imageKnife.removeAllMemoryCache()
      if (imageKnife.isFileCacheInit()) {
        await imageKnife.removeAllFileCache()
      }
      DiagnosticLogger.info('imageknife', 'cache_cleared', IMAGEKNIFE_CACHE_DIR)
    } catch (error) {
      DiagnosticLogger.warn('imageknife', 'cache_clear_failed', (error as Error).message)
    }
  }

  static preload(url: string, priority: Priority = Priority.LOW): ImageKnifeRequest | null {
    if (url.length === 0 || !ImageKnifeProRuntime.initialized) {
      return null
    }
    try {
      const option: ImageKnifeOptionV2 = new ImageKnifeOptionV2()
      option.loadSrc = url
      option.headerOption = ImageKnifeProRuntime.defaultHeaders()
      option.writeCacheStrategy = CacheStrategy.DEFAULT
      option.priority = priority
      return ImageKnife.getInstance().preload(option)
    } catch (error) {
      DiagnosticLogger.warn(
        'imageknife',
        'preload_failed',
        `urlHash=${DiagnosticLogger.ownerHash(url)} error=${(error as Error).message}`,
      )
      return null
    }
  }

  static async preloadReaderFile(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    priority: number,
  ): Promise<CachedImageFileResult | null> {
    if (url.length === 0) {
      return null
    }
    if (!ImageKnifeProRuntime.initialized) {
      ImageKnifeProRuntime.initialize(context)
    }
    const startedAt: number = Date.now()
    DiagnosticLogger.info(
      'imageknife',
      'reader_imageknife_preload_start',
      `urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
    )
    try {
      const option: ImageKnifeOptionV2 = new ImageKnifeOptionV2()
      option.loadSrc = url
      option.context = context
      option.headerOption = ImageKnifeProRuntime.readerHeaders()
      option.writeCacheStrategy = CacheStrategy.DEFAULT
      option.priority = ImageKnifeProRuntime.priorityFromNumber(priority)
      option.signature = cacheKey
      option.httpOption = {
        connectTimeout: IMAGEKNIFE_READER_CONNECT_TIMEOUT_MS,
        readTimeout: IMAGEKNIFE_READER_READ_TIMEOUT_MS,
      }
      const filePath: string = await ImageKnife.getInstance().preloadCache(option)
      const bytes: number = ImageKnifeProRuntime.fileSize(filePath)
      if (filePath.length === 0 || bytes <= 0) {
        DiagnosticLogger.warn(
          'imageknife',
          'reader_imageknife_preload_failed',
          `emptyResult=${filePath.length === 0} bytes=${bytes} costMs=${Date.now() - startedAt} urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
        )
        return null
      }
      DiagnosticLogger.info(
        'imageknife',
        'reader_imageknife_preload_done',
        `bytes=${bytes} costMs=${Date.now() - startedAt} pathHash=${DiagnosticLogger.ownerHash(filePath)} urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
      )
      return {
        filePath,
        displayUri: CachedImageFileService.displayUri(filePath),
        bytes,
        fromCache: false,
      }
    } catch (error) {
      DiagnosticLogger.warn(
        'imageknife',
        'reader_imageknife_preload_failed',
        `costMs=${Date.now() - startedAt} urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)} error=${(error as Error).message}`,
      )
      return null
    }
  }

  static removeReaderFile(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
  ): void {
    if (url.length === 0) {
      return
    }
    try {
      const option: ImageKnifeOptionV2 = new ImageKnifeOptionV2()
      option.loadSrc = url
      option.context = context
      option.headerOption = ImageKnifeProRuntime.readerHeaders()
      option.signature = cacheKey
      ImageKnife.getInstance().removeFileCache(option)
      DiagnosticLogger.info(
        'imageknife',
        'reader_imageknife_cache_removed',
        `urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
      )
    } catch (error) {
      DiagnosticLogger.warn(
        'imageknife',
        'reader_imageknife_cache_remove_failed',
        `urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)} error=${(error as Error).message}`,
      )
    }
  }

  static cancelPreload(request: ImageKnifeRequest | null): void {
    if (request === null) {
      return
    }
    try {
      ImageKnife.getInstance().cancel(request)
    } catch (error) {
      DiagnosticLogger.warn('imageknife', 'preload_cancel_failed', (error as Error).message)
    }
  }

  static defaultHeaders(): HeaderOptions[] {
    const headers: HeaderOptions[] = []
    headers.push({ key: 'User-Agent', value: EhConstants.USER_AGENT })
    headers.push({ key: 'Accept', value: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8' })
    headers.push({ key: 'Accept-Language', value: EhConstants.ACCEPT_LANGUAGE })
    return headers
  }

  private static readerHeaders(): HeaderOptions[] {
    const headers: HeaderOptions[] = ImageKnifeProRuntime.defaultHeaders()
    const cookie: string = EhCookieStore.getInstance().header()
    if (cookie.length > 0) {
      headers.push({ key: 'Cookie', value: cookie })
    }
    return headers
  }

  private static priorityFromNumber(priority: number): Priority {
    if (priority === 0) {
      return Priority.HIGH
    }
    if (priority === 2) {
      return Priority.LOW
    }
    return Priority.MEDIUM
  }

  private static fileSize(path: string): number {
    if (path.length === 0) {
      return 0
    }
    try {
      return fileIo.statSync(path).size
    } catch (_err) {
      return 0
    }
  }

  private static safeMetric(value: number | undefined): number {
    if (value === undefined || value <= 0) {
      return 0
    }
    return value
  }
}

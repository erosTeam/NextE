import { common } from '@kit.AbilityKit'
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
import { CacheStat } from './CacheStat'

const IMAGEKNIFE_FILE_CACHE_COUNT: number = 192
const IMAGEKNIFE_FILE_CACHE_BYTES: number = 96 * 1024 * 1024
const IMAGEKNIFE_MEMORY_CACHE_COUNT: number = 128
const IMAGEKNIFE_MEMORY_CACHE_BYTES: number = 32 * 1024 * 1024
const IMAGEKNIFE_MAX_REQUESTS: number = 8
const IMAGEKNIFE_CACHE_DIR: string = 'imageknife-cover-cache'

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

  private static safeMetric(value: number | undefined): number {
    if (value === undefined || value <= 0) {
      return 0
    }
    return value
  }
}

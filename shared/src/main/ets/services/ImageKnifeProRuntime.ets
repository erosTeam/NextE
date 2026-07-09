import { common } from '@kit.AbilityKit'
import { CacheStrategy, ImageKnife } from '@ohos/imageknifepro'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

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
}

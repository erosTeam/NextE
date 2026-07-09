import { common } from '@kit.AbilityKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { CacheStat } from './CacheStat'
import { CachedImageFileResult, CachedImageFileService, CachedImageProgress } from './CachedImageFileService'
import { ImageKnifeProRuntime } from './ImageKnifeProRuntime'
import { EH_IMAGE_PRIORITY_LOW } from './ImagePipelineTypes'

export class ImagePipelineService {
  static initialize(context: common.UIAbilityContext): void {
    ImageKnifeProRuntime.initialize(context)
  }

  static clearOnBackground(): void {
    ImageKnifeProRuntime.clearOnBackground()
  }

  static reloadOnForeground(): void {
    ImageKnifeProRuntime.reloadOnForeground()
  }

  static preloadCover(url: string, priority: number = EH_IMAGE_PRIORITY_LOW): void {
    ImageKnifeProRuntime.preload(url, priority)
  }

  static async preloadReaderFile(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    priority: number,
    onProgress?: (progress: CachedImageProgress) => void,
  ): Promise<CachedImageFileResult | null> {
    return ImageKnifeProRuntime.preloadReaderFile(context, url, cacheKey, priority, onProgress)
  }

  static async loadReaderFile(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    priority: number,
    onProgress?: (progress: CachedImageProgress) => void,
  ): Promise<CachedImageFileResult> {
    const imageKnifeResult: CachedImageFileResult | null =
      await ImagePipelineService.preloadReaderFile(context, url, cacheKey, priority, onProgress)
    if (imageKnifeResult !== null) {
      return imageKnifeResult
    }
    DiagnosticLogger.info(
      'image-pipeline',
      'reader_fallback_legacy',
      `urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
    )
    return CachedImageFileService.load(
      context,
      url,
      cacheKey,
      onProgress !== undefined ? onProgress : (_progress: CachedImageProgress) => {},
    )
  }

  static removeReaderFile(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
  ): void {
    ImageKnifeProRuntime.removeReaderFile(context, url, cacheKey)
    CachedImageFileService.remove(context, url, cacheKey)
  }

  static async preloadImageBlockThumbnailFile(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
  ): Promise<CachedImageFileResult | null> {
    return ImageKnifeProRuntime.preloadImageBlockThumbnailFile(context, url, cacheKey)
  }

  static async stat(context: common.UIAbilityContext): Promise<CacheStat> {
    const out: CacheStat = await CachedImageFileService.stat(context)
    const imageCache: CacheStat = ImageKnifeProRuntime.stat()
    out.count += imageCache.count
    out.bytes += imageCache.bytes
    return out
  }

  static async clearCache(context: common.UIAbilityContext): Promise<void> {
    await CachedImageFileService.clear(context)
    await ImageKnifeProRuntime.clearCache()
  }

  static displayUri(path: string): string {
    return CachedImageFileService.displayUri(path)
  }
}

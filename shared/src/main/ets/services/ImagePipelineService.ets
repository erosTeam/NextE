import { common } from '@kit.AbilityKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { CacheStat } from './CacheStat'
import { CachedImageFileResult, CachedImageFileService, CachedImageProgress } from './CachedImageFileService'
import { ImageBlockPreviewCacheService } from './ImageBlockPreviewCacheService'
import { ImageKnifeProRuntime } from './ImageKnifeProRuntime'
import { EH_IMAGE_PRIORITY_LOW } from './ImagePipelineTypes'
import { ReaderImageFileCacheService } from './ReaderImageFileCacheService'
import { ReaderImageCacheSettings } from '../settings/ReaderImageCacheSettings'

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
    try {
      return await ReaderImageFileCacheService.load(
        context,
        url,
        cacheKey,
        ReaderImageCacheSettings.limitBytes(),
        priority,
        onProgress !== undefined ? onProgress : (_progress: CachedImageProgress) => {},
      )
    } catch (error) {
      DiagnosticLogger.warn(
        'image-pipeline',
        'reader_file_load_failed',
        `cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)} error=${(error as Error).message}`,
      )
      return null
    }
  }

  static async loadReaderFile(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    priority: number,
    onProgress?: (progress: CachedImageProgress) => void,
    forceReload: boolean = false,
  ): Promise<CachedImageFileResult> {
    return ReaderImageFileCacheService.load(
      context,
      url,
      cacheKey,
      ReaderImageCacheSettings.limitBytes(),
      priority,
      onProgress !== undefined ? onProgress : (_progress: CachedImageProgress) => {},
      forceReload,
    )
  }

  static readerFileCacheKey(gid: string, token: string, page: number, original: boolean): string {
    return ReaderImageFileCacheService.cacheKey(gid, token, page, original)
  }

  static cachedReaderFile(
    context: common.UIAbilityContext,
    cacheKey: string,
  ): CachedImageFileResult | null {
    return ReaderImageFileCacheService.cached(context, cacheKey)
  }

  static removeReaderFile(context: common.UIAbilityContext, cacheKey: string): void {
    ReaderImageFileCacheService.remove(context, cacheKey)
  }

  /** Cancel a stale Reader prefetch only while it is still waiting for the low-priority slot. */
  static cancelQueuedReaderFile(context: common.UIAbilityContext, cacheKey: string): boolean {
    return ReaderImageFileCacheService.cancelQueued(context, cacheKey)
  }

  static async pruneReaderFileCache(context: common.UIAbilityContext): Promise<void> {
    await ReaderImageFileCacheService.pruneToLimit(context, ReaderImageCacheSettings.limitBytes())
  }

  static async pruneImageBlockThumbnailFallbackCache(
    context: common.UIAbilityContext,
  ): Promise<void> {
    await CachedImageFileService.pruneToLimit(context)
  }

  static async pruneImageBlockPreviewCache(context: common.UIAbilityContext): Promise<void> {
    await ImageBlockPreviewCacheService.pruneToLimit(context, true)
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
    const readerCache: CacheStat = await ReaderImageFileCacheService.stat(context)
    const imageBlockPreviewCache: CacheStat = await ImageBlockPreviewCacheService.stat(context)
    const imageCache: CacheStat = ImageKnifeProRuntime.stat()
    out.count += readerCache.count
    out.bytes += readerCache.bytes
    out.count += imageBlockPreviewCache.count
    out.bytes += imageBlockPreviewCache.bytes
    out.count += imageCache.count
    out.bytes += imageCache.bytes
    return out
  }

  static async clearCache(context: common.UIAbilityContext): Promise<void> {
    await CachedImageFileService.clear(context)
    await ReaderImageFileCacheService.clear(context)
    await ImageBlockPreviewCacheService.clear(context)
    await ImageKnifeProRuntime.clearCache()
  }

  static displayUri(path: string): string {
    return CachedImageFileService.displayUri(path)
  }
}

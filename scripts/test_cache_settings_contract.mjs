#!/usr/bin/env node
/**
 * Contract for cache-storage service boundaries.
 *
 * Cache-page layout, route registration, strings, and clear-button presentation are verified by review
 * and device paths. This gate protects only the durable stat/clear APIs and aggregate image-cache cleanup.
 */
import fs from 'node:fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
const ok = (name, condition) => {
  if (!condition) {
    throw new Error(name)
  }
}

ok('CacheStat model holds count + bytes',
  /export class CacheStat \{[\s\S]*count: number[\s\S]*bytes: number/.test(read('shared/src/main/ets/services/CacheStat.ets')))

const pageCache = read('shared/src/main/ets/services/EhPageCacheService.ets')
ok('page cache exposes stat() + clearAll()',
  /static async stat\(context: common\.UIAbilityContext\): Promise<CacheStat>/.test(pageCache) &&
    /static async clearAll\(context: common\.UIAbilityContext\): Promise<void>[\s\S]*DELETE FROM eh_page_cache/.test(pageCache))

const imagePipeline = read('shared/src/main/ets/services/ImagePipelineService.ets')
ok('image cache pipeline counts every cache layer',
  /static async stat\(context: common\.UIAbilityContext\): Promise<CacheStat>[\s\S]*CachedImageFileService\.stat[\s\S]*ReaderImageFileCacheService\.stat[\s\S]*ImageBlockPreviewCacheService\.stat[\s\S]*ImageKnifeProRuntime\.stat/.test(imagePipeline))
ok('image cache pipeline clears disk, reader, and memory cache layers together',
  /static async clearCache\(context: common\.UIAbilityContext\): Promise<void>[\s\S]*CachedImageFileService\.clear[\s\S]*ReaderImageFileCacheService\.clear[\s\S]*ImageBlockPreviewCacheService\.clear[\s\S]*ImageKnifeProRuntime\.clearCache/.test(imagePipeline))

const fallbackImageCache = read('shared/src/main/ets/services/CachedImageFileService.ets')
ok('ImageBlock thumbnail fallback cache has an independent bounded LRU disk lifecycle',
  /MAX_CACHE_FILE_COUNT: number = 256/.test(fallbackImageCache) &&
    /MAX_CACHE_BYTES: number = 64 \* 1024 \* 1024/.test(fallbackImageCache) &&
    /static cached\([\s\S]*CachedImageFileService\.touch\(filePath\)/.test(fallbackImageCache) &&
    /private static async downloadAndStore[\s\S]*try \{[\s\S]*await CachedImageFileService\.(?:pruneAfterStore|pruneToLimit)\(context[\s\S]*catch \(error\) \{[\s\S]*removeIfExists\(tmpPath\)/.test(fallbackImageCache) &&
    /static pruneToLimit\(context: common\.UIAbilityContext[\s\S]*pruneChain/.test(fallbackImageCache) &&
    /private static entries\([\s\S]*endsWith\('\.part'\)[\s\S]*removeIfExists\(path\)/.test(fallbackImageCache))

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
ok('startup prunes ImageBlock thumbnail fallback cache independently of Reader cache settings',
  /pruneImageBlockThumbnailFallbackCache\(context\)[\s\S]*fallback_disk_startup_prune_failed/.test(bootstrap) &&
    /static async pruneImageBlockThumbnailFallbackCache[\s\S]*CachedImageFileService\.pruneToLimit\(context\)/.test(imagePipeline))

const imageBlockPreviewCache = read('shared/src/main/ets/services/ImageBlockPreviewCacheService.ets')
ok('ImageBlock settings preview cache has an independent bounded disk lifecycle',
  /MAX_CACHE_FILE_COUNT: number = 128/.test(imageBlockPreviewCache) &&
    /MAX_CACHE_BYTES: number = 32 \* 1024 \* 1024/.test(imageBlockPreviewCache) &&
    /static touch\(path: string\)[\s\S]*fileIo\.utimes/.test(imageBlockPreviewCache) &&
    /static pruneToLimit\([\s\S]*pruneChain/.test(imageBlockPreviewCache) &&
    /name\.endsWith\('\.part'\)[\s\S]*cleanupPartialFiles/.test(imageBlockPreviewCache))
ok('startup prunes ImageBlock settings preview cache and removes stale partial files',
  /pruneImageBlockPreviewCache\(context\)[\s\S]*image_block_preview_startup_prune_failed/.test(bootstrap) &&
    /static async pruneImageBlockPreviewCache[\s\S]*ImageBlockPreviewCacheService\.pruneToLimit\(context, true\)/.test(imagePipeline))

const commentSvc = read('shared/src/main/ets/services/CommentTranslationService.ets')
ok('comment translation cache exposes stat() and clear()',
  /static async stat\(context: common\.UIAbilityContext\): Promise<CacheStat>/.test(commentSvc) &&
    /static async clear\(context: common\.UIAbilityContext\): Promise<void>/.test(commentSvc))

const tagSvc = read('shared/src/main/ets/services/TagTranslationService.ets')
ok('tag translation cache exposes statCache() + clearTranslations()',
  /static async statCache\(context: common\.UIAbilityContext\): Promise<CacheStat>/.test(tagSvc) &&
    /static async clearTranslations\(context: common\.UIAbilityContext\): Promise<void>/.test(tagSvc))

ok('CacheStat is exported from shared', /export \{ CacheStat \}/.test(read('shared/src/main/ets/Index.ets')))

console.log('✓ cache storage contract: aggregate cache stat and clear boundaries locked')

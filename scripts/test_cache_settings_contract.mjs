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
  /static async stat\(context: common\.UIAbilityContext\): Promise<CacheStat>[\s\S]*CachedImageFileService\.stat[\s\S]*ReaderImageFileCacheService\.stat[\s\S]*ImageKnifeProRuntime\.stat/.test(imagePipeline))
ok('image cache pipeline clears disk, reader, and memory cache layers together',
  /static async clearCache\(context: common\.UIAbilityContext\): Promise<void>[\s\S]*CachedImageFileService\.clear[\s\S]*ReaderImageFileCacheService\.clear[\s\S]*ImageKnifeProRuntime\.clearCache/.test(imagePipeline))

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

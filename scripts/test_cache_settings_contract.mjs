#!/usr/bin/env node
/**
 * Contract for the storage/cache settings page.
 *
 * Every cache the app keeps must be countable, sizeable and clearable from one page, plus a clear-all.
 * Run: node scripts/test_cache_settings_contract.mjs
 */
import fs from 'fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

ok('CacheStat model holds count + bytes',
  /export class CacheStat \{[\s\S]*count: number[\s\S]*bytes: number/.test(read('shared/src/main/ets/services/CacheStat.ets')))

const pageCache = read('shared/src/main/ets/services/EhPageCacheService.ets')
ok('page cache exposes stat() + clearAll()',
  /static async stat\(context: common\.UIAbilityContext\): Promise<CacheStat>/.test(pageCache) &&
    /static async clearAll\(context: common\.UIAbilityContext\): Promise<void>[\s\S]*DELETE FROM eh_page_cache/.test(pageCache))

const imgCache = read('shared/src/main/ets/services/CachedImageFileService.ets')
ok('image cache exposes stat() + clear()',
  /static async stat\(context: common\.UIAbilityContext\): Promise<CacheStat>[\s\S]*listFileSync/.test(imgCache) &&
    /static async clear\(context: common\.UIAbilityContext\): Promise<void>[\s\S]*removeIfExists/.test(imgCache))

const commentSvc = read('shared/src/main/ets/services/CommentTranslationService.ets')
ok('comment translation cache exposes stat() and clear()',
  /static async stat\(context: common\.UIAbilityContext\): Promise<CacheStat>/.test(commentSvc) &&
    /static async clear\(context: common\.UIAbilityContext\): Promise<void>/.test(commentSvc))

const tagSvc = read('shared/src/main/ets/services/TagTranslationService.ets')
ok('tag translation cache exposes statCache() + clearTranslations()',
  /static async statCache\(context: common\.UIAbilityContext\): Promise<CacheStat>/.test(tagSvc) &&
    /static async clearTranslations\(context: common\.UIAbilityContext\): Promise<void>/.test(tagSvc))

const page = read('feature/settings/src/main/ets/pages/CacheSettingsPage.ets')
ok('cache page lists all four caches',
  /app\.string\.cache_page/.test(page) &&
    /app\.string\.cache_image/.test(page) &&
    /app\.string\.cache_comment_translation/.test(page) &&
    /app\.string\.cache_tag_translation/.test(page))
ok('cache page confirms before clearing and re-reads stats after',
  /confirmThenClear\(/.test(page) &&
    /showAlertDialog/.test(page) &&
    /this\.refreshAll\(\)/.test(page))
ok('cache page has a clear-all that clears every cache',
  /app\.string\.cache_clear_all/.test(page) &&
    /clearEverything\(\): Promise<void>[\s\S]*EhPageCacheService\.clearAll[\s\S]*CachedImageFileService\.clear[\s\S]*CommentTranslationService\.clear[\s\S]*TagTranslationService\.clearTranslations/.test(page))

ok('CacheStat exported from shared', /export \{ CacheStat \}/.test(read('shared/src/main/ets/Index.ets')))
ok('CacheSettingsPage exported from feature/settings', /export \{ CacheSettingsPage \}/.test(read('feature/settings/src/main/ets/Index.ets')))
ok('CacheSettings route registered in the nav shell',
  /name === 'CacheSettings'[\s\S]*CacheSettingsPage\(\)/.test(read('entry/src/main/ets/pages/Index.ets')))
ok('Settings page has an entry that pushes CacheSettings',
  /app\.string\.settings_cache[\s\S]*pushPathByName\('CacheSettings'/.test(read('feature/settings/src/main/ets/pages/SettingsPage.ets')))

for (const locale of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const s = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of ['settings_cache', 'cache_page', 'cache_image', 'cache_comment_translation',
    'cache_tag_translation', 'cache_clear_all', 'cache_items_unit', 'cache_clear_confirm',
    'cache_clear_all_confirm', 'cache_cleared', 'common_clear']) {
    ok(`${locale} has ${key}`, new RegExp(`"name": "${key}"`).test(s))
  }
}

if (failures === 0) {
  console.log('✓ cache settings contract passed')
  process.exit(0)
}
console.error(`✗ cache settings contract: ${failures} failure(s)`)
process.exit(1)

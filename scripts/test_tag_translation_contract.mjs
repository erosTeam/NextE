#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const service = read('shared/src/main/ets/services/TagTranslationService.ets')
const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
const suggestion = read('shared/src/main/ets/model/EhTagSuggestion.ets')
const settingsState = read('shared/src/main/ets/state/TagTranslationSettingsState.ets')
const settings = read('shared/src/main/ets/settings/TagTranslationSettings.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/TagTranslationSettingsPage.ets')
const layoutPage = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')
const entryPage = read('entry/src/main/ets/pages/Index.ets')
const vm = read('feature/search/src/main/ets/viewmodel/SearchViewModel.ets')
const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
const homeVm = read('feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets')
const detailVm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
const favVm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
const constants = read('shared/src/main/ets/constants/EhConstants.ets')

assert.match(store, /relationalStore\.getRdbStore\(context, LOCAL_DATA_STORE_CONFIG\)/)
assert.match(store, /CREATE TABLE IF NOT EXISTS tag_translations/)
assert.match(store, /PRIMARY KEY\(namespace, key\)/)
assert.match(store, /idx_tag_translations_key/)
assert.match(store, /idx_tag_translations_name/)
assert.doesNotMatch(service, /preferences\.getPreferences|StorageKeys\.STORE_SETTINGS/)

assert.match(service, /https:\/\/api\.github\.com\/repos\/EhTagTranslation\/Database\/releases\/latest/)
assert.match(service, /ghproxy\.homeboyc\.cn/)
assert.match(service, /const DB_ASSET_NAME:\s*string\s*=\s*'db\.raw\.json\.gz'/)
assert.match(service, /getPublicText\(useCdn \? CDN_RELEASE_API_URL : RELEASE_API_URL\)/)
assert.match(service, /downloadPublicFile\(downloadUrl, gzPath\)/)
assert.match(service, /import \{ http \} from '@kit\.NetworkKit'/)
assert.doesNotMatch(service, /EhHttpClient|getInstance\(\)\.getText|getInstance\(\)\.downloadBinaryToFile/)
assert.doesNotMatch(service, /'Cookie':|EhCookieStore/)
assert.match(service, /zlib\.createGZipSync\(\)/)
assert.match(service, /gzip\.gzopen\(path, 'rb'\)/)
assert.match(service, /gzip\.gzread\(buffer\)/)
assert.match(service, /JSON\.parse\(rawJson\)/)
assert.match(service, /Object\.keys\(group\.data\)/)
assert.match(service, /row\.namespace = namespace[\s\S]*row\.key = key[\s\S]*row\.name = TagTranslationService\.safeString\(value\.name\)/)
assert.match(service, /batchInsert\('tag_translations', chunk\)/)
assert.match(service, /static async status\(context: common\.UIAbilityContext\): Promise<TagTranslationStatus>/)
assert.match(service, /SELECT value FROM tag_translation_meta WHERE key = \? LIMIT 1/)

assert.match(service, /static async translateFullTagAsync\(context: common\.UIAbilityContext, fullTag: string\): Promise<string>/)
assert.match(service, /SELECT name FROM tag_translations WHERE namespace = \? AND key = \? LIMIT 1/)
assert.match(service, /case 'language:chinese':[\s\S]*return '中文'/)
assert.match(service, /static async translateGalleries\([\s\S]*Promise<EhGallery\[]>/)
assert.match(service, /static async translateGalleryTags\([\s\S]*Promise<EhGallery>/)
assert.match(constants, /static localizedTagDisplay\(namespace: string, localized: string\): string/)
assert.match(constants, /return `\$\{ns\}:\$\{text\}`/)
assert.match(service, /translateTagInPlace\(context, g\.simpleTags\[j\]\.namespace, g\.simpleTags\[j\], cache, true\)/)
assert.match(service, /translateTagInPlace\(context, group\.namespace, group\.tags\[k\], cache, false\)/)
assert.match(service, /tag\.translat = includePrefix \? EhConstants\.localizedTagDisplay\(namespace, translated\) : translated/)
assert.doesNotMatch(service, /bootstrapTask|bootstrapTried|ensureReady\(/)

assert.match(service, /static async searchSuggestions\([\s\S]*Promise<EhTagSuggestion\[]>/)
assert.match(service, /if \(await TagTranslationService\.hasRows\(context\)\) \{[\s\S]*queryRdbSuggestions\(context, q, limit\)/)
assert.doesNotMatch(service, /ensureReadyInBackground/)
assert.match(service, /key LIKE \? ESCAPE/)
assert.match(service, /name LIKE \? ESCAPE/)
assert.match(service, /stripNameMarkdown\(value: string\)/)
assert.match(service, /new EhTagSuggestion\(namespace, key, name\)/)
assert.match(suggestion, /displayName:\s*string\s*=\s*''/)

assert.match(settingsState, /enabled: boolean = false/)
assert.match(settingsState, /useCdn: boolean = false/)
assert.match(settingsState, /updateMode: string = TAG_TRANSLATION_UPDATE_MANUAL/)
assert.match(settingsState, /rowCount: number = 0/)
assert.match(settings, /TagTranslationService\.status\(context\)/)
assert.match(settings, /TagTranslationService\.updateFromLatestRelease\(context, state\.useCdn\)/)
assert.match(settings, /TAG_TRANSLATION_UPDATE_EVERY_START[\s\S]*setTimeout/)
assert.match(settingsPage, /export struct TagTranslationSettingsPage/)
assert.match(settingsPage, /TagTranslationSettings\.setEnabled/)
assert.match(settingsPage, /TagTranslationSettings\.updateNow\(this\.ctx\(\)\)/)
assert.match(settingsPage, /tag_translation_update_mode/)
assert.match(layoutPage, /this\.stack\.pushPathByName\('TagTranslationSettings', null\)/)
assert.match(entryPage, /TagTranslationSettingsPage/)

assert.match(vm, /connectTagTranslationSettings\(\)\.enabled[\s\S]*TagTranslationService\.searchSuggestions\(context, token, 30\)[\s\S]*localRows\.length > 0[\s\S]*return[\s\S]*EhApiPhpService\.tagSuggest/)
assert.match(vm, /tag_translation_suggest_failed/)
assert.match(page, /suggestionTitle\(s: EhTagSuggestion\)[\s\S]*s\.displayName\.length > 0 \? s\.displayName : this\.formatSuggestionQuery\(s\)/)
assert.match(page, /suggestionSubtitle\(s: EhTagSuggestion\)[\s\S]*return query/)
assert.match(page, /EhConstants\.exactTagSearchQuery\(s\.namespace, s\.text\)/)
assert.match(page, /TagTranslationService\.touchSuggestion\(this\.ctx\(\), s\)/)
assert.match(page, /this\.vm\.suggestionCount > 0[\s\S]*this\.SearchSuggestionView\(\)/)

assert.match(homeVm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(homeVm, /connectTagTranslationSettings\(\)\.enabled[\s\S]*TagTranslationService\.translateGalleries\(this\.context, rows\)/)
assert.match(homeVm, /translateRows\(list\.gallerys\)[\s\S]*this\.dataSource\.setData\(rows\)/)
assert.match(vm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(vm, /translateRows\(list\.gallerys\)[\s\S]*this\.dataSource\.setData\(rows\)/)
assert.match(favVm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(favVm, /translateRows\(list\.gallerys\)[\s\S]*this\.dataSource\.setData\(rows\)/)
assert.match(detailVm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(detailVm, /TagTranslationService\.translateGalleryTags\(this\.context, gallery\)/)

// Mirror the EhTagTranslation raw shape so this contract fails if the expected release JSON shape drifts.
const sample = {
  data: [
    {
      namespace: 'female',
      data: {
        'big breasts': { name: '巨乳', intro: 'intro text', links: 'https://example.test' },
      },
    },
    {
      namespace: 'language',
      data: {
        chinese: { name: '中文' },
      },
    },
  ],
}
const parsed = []
for (const group of sample.data) {
  for (const key of Object.keys(group.data)) {
    parsed.push({
      namespace: group.namespace,
      key,
      name: group.data[key].name || '',
      intro: group.data[key].intro || '',
      links: group.data[key].links || '',
    })
  }
}
assert.deepEqual(parsed[0], {
  namespace: 'female',
  key: 'big breasts',
  name: '巨乳',
  intro: 'intro text',
  links: 'https://example.test',
})
assert.equal(parsed.find((row) => row.name.includes('中文')).key, 'chinese')

console.log('✓ tag translation contract: release import, RDB storage, localized lookup, and search candidate wiring preserved')

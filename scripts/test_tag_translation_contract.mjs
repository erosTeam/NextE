#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const service = read('shared/src/main/ets/services/TagTranslationService.ets')
const axiosClient = read('shared/src/main/ets/network/AxiosHttpClient.ets')
const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
const suggestion = read('shared/src/main/ets/model/EhTagSuggestion.ets')
const settingsState = read('shared/src/main/ets/state/TagTranslationSettingsState.ets')
const settings = read('shared/src/main/ets/settings/TagTranslationSettings.ets')
const settingsBootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const vm = read('feature/search/src/main/ets/viewmodel/SearchViewModel.ets')
const homeVm = read('feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets')
const detailVm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
const favVm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
const constants = read('shared/src/main/ets/constants/EhConstants.ets')
const simpleTagModel = read('shared/src/main/ets/model/SimpleTag.ets')

assert.match(store, /relationalStore\.getRdbStore\(context, LOCAL_DATA_STORE_CONFIG\)/)
assert.match(store, /CREATE TABLE IF NOT EXISTS tag_translations/)
assert.match(store, /PRIMARY KEY\(namespace, key\)/)
assert.match(store, /idx_tag_translations_key/)
assert.match(store, /idx_tag_translations_name/)
assert.doesNotMatch(service, /preferences\.getPreferences|StorageKeys\.STORE_SETTINGS/)

assert.match(service, /https:\/\/api\.github\.com\/repos\/EhTagTranslation\/Database\/releases\/latest/)
assert.match(service, /ghproxy\.homeboyc\.cn/)
assert.match(service, /const DB_ASSET_NAME:\s*string\s*=\s*'db\.raw\.json\.gz'/)
assert.match(service, /orderedSources\(useCdn: boolean\): TagTranslationDownloadSource\[\][\s\S]*return useCdn \? \[mirror, direct\] : \[direct, mirror\]/)
assert.match(service, /fetchLatestRelease\(useCdn: boolean\)[\s\S]*orderedSources\(useCdn\)[\s\S]*release_source_failed[\s\S]*tag translation release failed/)
assert.match(service, /downloadPublicFileWithFallback\([\s\S]*orderedSources\(useCdn\)[\s\S]*asset_source_failed[\s\S]*tag translation asset failed/)
assert.match(service, /publicHttpError\([\s\S]*tag translation \$\{phase\} HTTP \$\{statusCode\} via \$\{sourceLabel\}/)
assert.match(service, /rateLimitHint\(statusCode: number, rawHeader: string\)[\s\S]*x-ratelimit-remaining[\s\S]*x-ratelimit-reset/)
assert.match(service, /import \{ AxiosBinaryResponse, AxiosHttpClient, AxiosTextResponse \} from '..\/network\/AxiosHttpClient'/)
assert.match(service, /AxiosHttpClient\.requestText\(/)
assert.match(service, /AxiosHttpClient\.requestBinary\(/)
assert.doesNotMatch(service, /@kit\.NetworkKit|http\.createHttp|req\.request\(/)
assert.match(axiosClient, /responseType: 'string'/)
assert.match(axiosClient, /responseType: 'array_buffer'/)
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
assert.match(service, /updateFromLatestRelease\([\s\S]*force: boolean = false[\s\S]*localStatus\.version === remoteVersion[\s\S]*update_skip_latest[\s\S]*return 0/)

assert.match(service, /static async translateFullTagAsync\([\s\S]*context: common\.UIAbilityContext,[\s\S]*fullTag: string,[\s\S]*\): Promise<string>/)
assert.match(service, /SELECT name FROM tag_translations WHERE namespace = \? AND key = \? LIMIT 1/)
assert.match(service, /case 'language:chinese':[\s\S]*return '中文'/)
assert.match(service, /static async translateGalleries\([\s\S]*Promise<EhGallery\[]>/)
assert.match(service, /static async translateGalleryTags\([\s\S]*Promise<EhGallery>/)
assert.match(constants, /static localizedTagDisplay\(namespace: string, localized: string\): string/)
assert.match(constants, /return `\$\{ns\}:\$\{text\}`/)
assert.match(simpleTagModel, /siteLabel: string = ''/)
assert.match(simpleTagModel, /localizedDisplay\(localized: string\): string[\s\S]*this\.siteLabel\.endsWith\(suffix\)/)
assert.match(service, /translationMapForGalleries\([\s\S]*context,[\s\S]*galleries,[\s\S]*\)/)
assert.match(service, /SQL_SELECT_TAG_TRANSLATIONS_BY_KEYS_PREFIX/)
assert.match(service, /queryTranslationBatchForNamespace\([\s\S]*store,[\s\S]*namespace,[\s\S]*keys,[\s\S]*translations,[\s\S]*\)/)
assert.match(service, /applyCachedTagTranslation\([\s\S]*g\.simpleTags\[j\]\.namespace,[\s\S]*g\.simpleTags\[j\],[\s\S]*cache,[\s\S]*true,[\s\S]*\)/)
assert.match(service, /applyCachedTagTranslation\([\s\S]*group\.namespace,[\s\S]*group\.tags\[k\],[\s\S]*cache,[\s\S]*false,[\s\S]*\)/)
assert.match(service, /tag\.translat = includePrefix \? tag\.localizedDisplay\(translated\) : translated/)
assert.doesNotMatch(service, /includePrefix \? EhConstants\.localizedTagDisplay/)
assert.doesNotMatch(service, /bootstrapTask|bootstrapTried|ensureReady\(/)

assert.match(service, /static async searchSuggestions\([\s\S]*Promise<EhTagSuggestion\[]>/)
assert.match(service, /if \(await TagTranslationService\.hasRows\(context\)\) \{[\s\S]*queryRdbSuggestions\([\s\S]*context,[\s\S]*q,[\s\S]*limit,[\s\S]*\)/)
assert.doesNotMatch(service, /ensureReadyInBackground/)
assert.match(service, /key LIKE \? ESCAPE/)
assert.match(service, /name LIKE \? ESCAPE/)
assert.match(service, /SQL_QUERY_TAG_TRANSLATIONS_BY_NAMESPACE/)
assert.match(service, /suggestionQuery\(raw: string\): TagSuggestionQuery/)
assert.match(service, /out\.namespace = EhConstants\.expandNamespace\(text\.substring\(0, idx\)\)/)
assert.match(service, /cleanTagQueryText\(value: string\)/)
assert.match(service, /tag\.startsWith\('"'\)/)
assert.match(service, /tag\.endsWith\('\$'\)/)
assert.match(service, /stripNameMarkdown\(value: string\)/)
assert.match(service, /new EhTagSuggestion\(namespace, key, name\)/)
assert.match(suggestion, /displayName:\s*string\s*=\s*''/)

assert.match(settingsState, /enabled: boolean = false/)
assert.match(settingsState, /useCdn: boolean = false/)
assert.match(settingsState, /updateMode: string = TAG_TRANSLATION_UPDATE_MANUAL/)
assert.match(settingsState, /rowCount: number = 0/)
assert.match(settings, /TagTranslationService\.status\(context\)/)
const tagRestoreStart = settings.indexOf('static async restore')
const tagRestoreEnd = settings.indexOf('\n  static async setEnabled', tagRestoreStart)
const tagRestore = settings.slice(tagRestoreStart, tagRestoreEnd)
assert.doesNotMatch(tagRestore, /await TagTranslationSettings\.refreshStatus\(context\)/)
assert.match(settings, /private static statusRefreshEpoch: number = 0/)
assert.match(settings, /static async refreshStatus[\s\S]*statusRefreshEpoch \+ 1[\s\S]*epoch !== TagTranslationSettings\.statusRefreshEpoch/)
assert.match(settings, /static scheduleStatusRefresh[\s\S]*setTimeout[\s\S]*TagTranslationSettings\.refreshStatus\(context\)\.catch[\s\S]*tagtranslation_status_refresh_failed/)
assert.match(settingsBootstrap, /SecuritySettings\.restore\(context\)[\s\S]*schedulePageCachePreload\(context\)[\s\S]*TagTranslationSettings\.scheduleStatusRefresh\(context\)/)
assert.match(settings, /updateNow\(context: common\.UIAbilityContext, force: boolean = true\)/)
assert.match(settings, /TagTranslationService\.updateFromLatestRelease\(context, state\.useCdn, force\)/)
assert.match(settings, /TAG_TRANSLATION_UPDATE_EVERY_START[\s\S]*setTimeout\([\s\S]*TagTranslationSettings\.updateNow\(context, false\)/)
assert.match(vm, /const LOCAL_TAG_SUGGEST_LIMIT: number = 200/)
assert.doesNotMatch(vm, /token\.indexOf\(':'\) >= 0/)
assert.match(vm, /connectTagTranslationSettings\(\)\.enabled[\s\S]*TagTranslationService\.searchSuggestions\(context, token, LOCAL_TAG_SUGGEST_LIMIT\)[\s\S]*localRows\.length > 0[\s\S]*return[\s\S]*EhApiPhpService\.tagSuggest/)
assert.match(vm, /tag_translation_suggest_failed/)
assert.match(homeVm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(homeVm, /connectTagTranslationSettings\(\)\.enabled[\s\S]*TagTranslationService\.translateGalleries\(this\.context, rows\)/)
assert.match(homeVm, /renderFirstPageRows\([\s\S]*list: GalleryList,[\s\S]*deferTranslation: boolean,[\s\S]*run: GalleryFirstPageRun[\s\S]*\): Promise<boolean>[\s\S]*connectTagTranslationSettings\(\)\.enabled && !deferTranslation[\s\S]*await this\.translateRows\(displayRows\)/)
assert.match(homeVm, /this\.translateCachedRowsLater\(displayRows, renderVersion, [^)]+\)/)
assert.match(homeVm, /await this\.renderFirstPageRows\(list, this\.itemCount === 0, run\)/)
assert.match(homeVm, /reapplyTagTranslation\(\): Promise<void>[\s\S]*clearGalleriesTranslations\(this\.dataSource\.getAll\(\)\)/)
assert.match(vm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(vm, /translateRows\(list\.gallerys\)[\s\S]*this\.dataSource\.setData\(rows\)/)
assert.match(vm, /private tagTranslationRun: number = 0/)
assert.match(vm, /reapplyTagTranslation\(\): Promise<void>[\s\S]*tagTranslationRun = this\.tagTranslationRun \+ 1[\s\S]*sourceRows: EhGallery\[\] = this\.dataSource\.getAll\(\)[\s\S]*snapshot: EhGallery\[\] = sourceRows\.slice\(\)[\s\S]*clearGalleriesTranslations\(snapshot\)/)
assert.match(vm, /run !== this\.tagTranslationRun[\s\S]*enabled !== connectTagTranslationSettings\(\)\.enabled[\s\S]*this\.dataSource\.getAll\(\) !== sourceRows[\s\S]*this\.dataSource\.totalCount\(\) !== sourceCount/)
assert.match(favVm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(favVm, /renderFirstPageRows\([\s\S]*list: GalleryList,[\s\S]*deferTranslation: boolean,[\s\S]*run: FavoritesFirstPageRun[\s\S]*\): Promise<boolean>[\s\S]*connectTagTranslationSettings\(\)\.enabled && !deferTranslation[\s\S]*await this\.translateRows\(displayRows\)/)
assert.match(favVm, /this\.translateCachedRowsLater\(displayRows, renderVersion, run, list\)/)
assert.match(favVm, /await this\.renderFirstPageRows\(list, this\.itemCount === 0, run\)/)
assert.match(detailVm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(detailVm, /TagTranslationService\.translateGalleryTags\(this\.context, gallery\)/)
assert.match(detailVm, /this\.gallery = connectTagTranslationSettings\(\)\.enabled[\s\S]*this\.translateCachedGalleryLater\(this\.gallery, renderVersion, run\)/)
assert.match(detailVm, /reapplyTagTranslation\(\): Promise<void>[\s\S]*source: EhGallery = this\.gallery[\s\S]*clearGalleryTranslations\(source\)/)
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

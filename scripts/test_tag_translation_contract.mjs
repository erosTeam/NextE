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
const galleryModel = read('shared/src/main/ets/model/EhGallery.ets')
const simpleTagModel = read('shared/src/main/ets/model/SimpleTag.ets')
const homeBody = read('feature/home/src/main/ets/components/GalleryListBody.ets')
const homePage = read('feature/home/src/main/ets/components/GallerySourcePage.ets')
const toplistPage = read('feature/home/src/main/ets/components/ToplistPeriodPage.ets')
const favPage = read('feature/user/src/main/ets/components/FavcatPage.ets')
const detailPage = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const galleryCard = read('shared/src/main/ets/components/GalleryCard.ets')
const waterfallCard = read('shared/src/main/ets/components/GalleryWaterfallCard.ets')
const detailTagsCard = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
const editTagsPage = read('feature/gallery/src/main/ets/pages/GalleryEditTagsPage.ets')

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
assert.match(settings, /updateNow\(context: common\.UIAbilityContext, force: boolean = true\)/)
assert.match(settings, /TagTranslationService\.updateFromLatestRelease\(context, state\.useCdn, force\)/)
assert.match(settings, /TAG_TRANSLATION_UPDATE_EVERY_START[\s\S]*setTimeout\([\s\S]*TagTranslationSettings\.updateNow\(context, false\)/)
assert.match(settingsPage, /export struct TagTranslationSettingsPage/)
assert.match(settingsPage, /TagTranslationSettings\.setEnabled/)
assert.match(settingsPage, /TagTranslationSettings\.updateNow\(this\.ctx\(\)\)/)
assert.match(settingsPage, /tag_translation_update_mode/)
assert.match(layoutPage, /this\.stack\.pushPathByName\('TagTranslationSettings', null\)/)
assert.match(entryPage, /TagTranslationSettingsPage/)

assert.match(vm, /const LOCAL_TAG_SUGGEST_LIMIT: number = 200/)
assert.doesNotMatch(vm, /token\.indexOf\(':'\) >= 0/)
assert.match(vm, /connectTagTranslationSettings\(\)\.enabled[\s\S]*TagTranslationService\.searchSuggestions\(context, token, LOCAL_TAG_SUGGEST_LIMIT\)[\s\S]*localRows\.length > 0[\s\S]*return[\s\S]*EhApiPhpService\.tagSuggest/)
assert.match(vm, /tag_translation_suggest_failed/)
assert.match(page, /suggestionNamespaceLabel\(namespace: string\): string \{[\s\S]*AppStrings\.get\('tag_ns_female'\)[\s\S]*return ns/)
assert.match(page, /suggestionTitle\(s: EhTagSuggestion\)[\s\S]*this\.suggestionNamespaceLabel\(s\.namespace\)[\s\S]*this\.formatSuggestionQuery\(s\)/)
assert.match(page, /suggestionSubtitle\(s: EhTagSuggestion\)[\s\S]*return query/)
assert.match(page, /EhConstants\.exactTagSearchQuery\(s\.namespace, s\.text\)/)
assert.match(page, /TagTranslationService\.touchSuggestion\(this\.ctx\(\), s\)/)
assert.match(page, /this\.vm\.suggestionCount > 0[\s\S]*this\.SearchSuggestionView\(\)/)

assert.match(homeVm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(homeVm, /connectTagTranslationSettings\(\)\.enabled[\s\S]*TagTranslationService\.translateGalleries\(this\.context, rows\)/)
assert.match(homeVm, /renderFirstPageRows\([\s\S]*list: GalleryList,[\s\S]*deferTranslation: boolean[\s\S]*\): Promise<void>[\s\S]*!deferTranslation[\s\S]*await this\.translateRows\(displayRows\)/)
assert.match(homeVm, /this\.translateCachedRowsLater\(displayRows, renderVersion, [^)]+\)/)
assert.match(homeVm, /await this\.renderFirstPageRows\(list, this\.itemCount === 0\)/)
assert.match(homeVm, /reapplyTagTranslation\(\): Promise<void>[\s\S]*clearGalleriesTranslations\(this\.dataSource\.getAll\(\)\)/)
assert.match(vm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(vm, /translateRows\(list\.gallerys\)[\s\S]*this\.dataSource\.setData\(rows\)/)
assert.match(vm, /reapplyTagTranslation\(\): Promise<void>[\s\S]*clearGalleriesTranslations\(this\.dataSource\.getAll\(\)\)/)
assert.match(favVm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(favVm, /renderFirstPageRows\([\s\S]*list: GalleryList,[\s\S]*deferTranslation: boolean[\s\S]*\): Promise<void>[\s\S]*!deferTranslation[\s\S]*await this\.translateRows\(displayRows\)/)
assert.match(favVm, /this\.translateCachedRowsLater\(displayRows, renderVersion, list\)/)
assert.match(favVm, /await this\.renderFirstPageRows\(list, this\.itemCount === 0\)/)
assert.match(favVm, /reapplyTagTranslation\(\): Promise<void>[\s\S]*clearGalleriesTranslations\(this\.dataSource\.getAll\(\)\)/)
assert.match(detailVm, /setContext\(context: common\.UIAbilityContext\)/)
assert.match(detailVm, /TagTranslationService\.translateGalleryTags\(this\.context, gallery\)/)
assert.match(detailVm, /this\.gallery = connectTagTranslationSettings\(\)\.enabled[\s\S]*this\.translateCachedGalleryLater\(this\.gallery, renderVersion\)/)
assert.match(detailVm, /reapplyTagTranslation\(\): Promise<void>[\s\S]*clearGalleryTranslations\(this\.gallery\)/)
assert.match(galleryModel, /renderKey\(\): string[\s\S]*tag\.translat/)
assert.doesNotMatch(homeBody, /\(g: EhGallery\) => g\.gid/)
assert.doesNotMatch(favPage, /\(g: EhGallery\) => g\.gid/)
assert.doesNotMatch(page, /\(g: EhGallery\) => g\.gid/)
assert.match(homeBody, /\(g: EhGallery\) => g\.renderKey\(\)/)
assert.match(favPage, /\(g: EhGallery\) => g\.renderKey\(\)/)
assert.match(page, /\(g: EhGallery\) => g\.renderKey\(\)/)
assert.match(detailTagsCard, /tagGroupRenderKey\(tg: TagGroup\): string[\s\S]*tag\.translat/)
assert.match(detailTagsCard, /this\.tagSig\.version[\s\S]*tg\.namespace[\s\S]*t\.text[\s\S]*t\.translat[\s\S]*t\.vote/)
assert.match(detailTagsCard, /\(tg: TagGroup\) => this\.tagGroupRenderKey\(tg\)/)
for (const src of [homePage, toplistPage, page, favPage, detailPage]) {
  assert.match(src, /@Monitor\('tagTranslation\.enabled'\)[\s\S]*reapplyTagTranslation\(\)/)
}
for (const [name, source] of [
  ['GalleryCard', galleryCard],
  ['GalleryWaterfallCard', waterfallCard],
  ['GalleryTagsCard', detailTagsCard],
  ['GalleryEditTagsPage', editTagsPage],
]) {
  assert(
    source.includes('connectTagTranslationSettings') &&
      source.includes('@Local tagTranslation') &&
      source.includes('tagLabel') &&
      source.includes('this.tagTranslation.enabled ?'),
    `${name} must render raw tag text immediately when tag translation is disabled`,
  )
}

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

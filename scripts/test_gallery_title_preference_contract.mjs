#!/usr/bin/env node
/**
 * Contract: Gallery detail title can use Japanese title as primary, matching eros_fe
 * `jpnTitleInGalleryPage` without changing global list-card title behavior.
 *
 * FE reference:
 * - eros_fe/lib/pages/setting/layout_setting_page.dart: japanese_title_in_gallery switch.
 * - eros_fe/lib/pages/gallery/controller/gallery_page_state.dart: mainTitle/subTitle swap.
 *
 * Run: node scripts/test_gallery_title_preference_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const feSetting = read('../eros_fe/lib/pages/setting/layout_setting_page.dart')
const feState = read('../eros_fe/lib/pages/gallery/controller/gallery_page_state.dart')
const gallery = read('shared/src/main/ets/model/EhGallery.ets')
const state = read('shared/src/main/ets/state/GalleryTitleState.ets')
const settings = read('shared/src/main/ets/settings/GalleryTitleSettings.ets')
const storage = read('shared/src/main/ets/constants/StorageKeys.ets')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')
const layoutPage = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')
const header = read('feature/gallery/src/main/ets/components/GalleryHeaderCard.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const listCard = read('shared/src/main/ets/components/GalleryCard.ets')

const locales = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok('FE exposes japanese_title_in_gallery as a layout setting',
  /japanese_title_in_gallery[\s\S]*CupertinoSwitch[\s\S]*jpnTitleInGalleryPage/.test(feSetting))
ok('FE swaps detail mainTitle and subTitle from jpnTitleInGalleryPage',
  /String get subTitle[\s\S]*jpnTitleInGalleryPage[\s\S]*englishTitle/.test(feState) &&
  /String get mainTitle[\s\S]*jpnTitleInGalleryPage[\s\S]*japaneseTitle/.test(feState))

ok('EhGallery exposes setting-driven primary and secondary title helpers',
  /displayTitle\(japanesePrimary: boolean\): string \{[\s\S]*this\.japaneseTitle[\s\S]*return this\.title\(\)/.test(gallery) &&
  /secondaryTitle\(japanesePrimary: boolean\): string \{[\s\S]*this\.englishTitle[\s\S]*this\.japaneseTitle/.test(gallery))
ok('GalleryTitleState is V2-only and stores the FE preference',
  /@ObservedV2[\s\S]*class GalleryTitleState[\s\S]*@Trace japaneseTitleInGalleryPage: boolean = false/.test(state) &&
  /AppStorageV2\.connect\(GalleryTitleState, GALLERY_TITLE_KEY/.test(state))
ok('GalleryTitleSettings persists and restores the preference',
  /JAPANESE_TITLE_IN_GALLERY_PAGE/.test(storage) &&
  /store\.getSync\([\s\S]*StorageKeys\.JAPANESE_TITLE_IN_GALLERY_PAGE[\s\S]*false/.test(settings) &&
  /store\.putSync\(StorageKeys\.JAPANESE_TITLE_IN_GALLERY_PAGE, enabled\)/.test(settings))
ok('Settings bootstrap restores gallery title preference before first paint',
  /import \{ GalleryTitleSettings \} from '\.\/GalleryTitleSettings'/.test(bootstrap) &&
  /await GalleryTitleSettings\.restore\(context\)/.test(bootstrap))
ok('Shared barrel exports title state and settings',
  /export \{ GalleryTitleState, connectGalleryTitle \} from '\.\/state\/GalleryTitleState'/.test(sharedIndex) &&
  /export \{ GalleryTitleSettings \} from '\.\/settings\/GalleryTitleSettings'/.test(sharedIndex))

ok('Layout settings page renders the Japanese-title switch row',
  /@Local galleryTitle: GalleryTitleState = connectGalleryTitle\(\)/.test(layoutPage) &&
  /settings_japanese_title_in_gallery[\s\S]*settings_japanese_title_in_gallery_hint[\s\S]*checked: this\.galleryTitle\.japaneseTitleInGalleryPage/.test(layoutPage) &&
  /GalleryTitleSettings\.setJapaneseTitleInGalleryPage\(this\.ctx\(\), value\)/.test(layoutPage))
ok('Gallery detail header reads the preference and swaps primary/secondary title',
  /@Local titlePref: GalleryTitleState = connectGalleryTitle\(\)/.test(header) &&
  /private primaryTitle\(\): string \{[\s\S]*this\.gallery\.displayTitle\(this\.titlePref\.japaneseTitleInGalleryPage\)/.test(header) &&
  /private secondaryTitle\(\): string \{[\s\S]*this\.gallery\.secondaryTitle\(this\.titlePref\.japaneseTitleInGalleryPage\)/.test(header) &&
  /Text\(this\.primaryTitle\(\)\)/.test(header) &&
  /Text\(this\.secondaryTitle\(\)\)/.test(header))
ok('Gallery detail nav title follows the same preference',
  /@Local titlePref: GalleryTitleState = connectGalleryTitle\(\)/.test(detail) &&
  /this\.vm\.gallery\.displayTitle\(this\.titlePref\.japaneseTitleInGalleryPage\)/.test(detail))
ok('This lane does not silently change list-card global title behavior',
  /Text\(this\.gallery\.title\(\)\)/.test(listCard) &&
  !/connectGalleryTitle/.test(listCard))

for (const locale of locales) {
  const src = read(locale)
  ok(`${locale} defines gallery title setting keys`,
    /"name": "settings_japanese_title_in_gallery"/.test(src) &&
    /"name": "settings_japanese_title_in_gallery_hint"/.test(src))
}

console.log(`✓ gallery title preference contract: ${passed} assertions passed`)

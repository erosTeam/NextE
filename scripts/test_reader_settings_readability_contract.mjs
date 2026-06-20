#!/usr/bin/env node
/**
 * Contract: Reader Settings rows keep visible separators and long subtitles remain readable.
 *
 * Run: node scripts/test_reader_settings_readability_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const readAbsolute = (p) => readFileSync(p, 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const row = read('shared/src/main/ets/components/ConciseListRow.ets')
const page = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')
const layoutPage = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')
const hdsApi = readAbsolute('/Applications/DevEco-Studio.app/Contents/sdk/default/hms/ets/api/@hms.hds.hdsBaseComponent.d.ets')
const feSettingItem = read('../eros_fe/lib/pages/item/setting_item.dart')

ok('FE settings rows use explicit dividers between rows',
  /if \(widget\.topDivider\) _settingItemDivider\(\)/.test(feSettingItem) &&
  /if \(widget\.bottomDivider\) _settingItemDivider\(\)/.test(feSettingItem) &&
  /Divider\([\s\S]*indent: 45\.0/.test(feSettingItem))

ok('ConciseListRow defaults ordinary setting subtitles to two readable lines',
  /@Param subtitleMaxLines: number = 2/.test(row) &&
  /\.maxLines\(this\.subtitleMaxLines\)/.test(row))

ok('HDS cardHeight is optional, so ConciseListRow lets HDS measure subtitle rows naturally',
  /cardHeight\?: Dimension/.test(hdsApi) &&
  !/private cardHeight\(\): number/.test(row) &&
  !/cardHeight:/.test(row))

ok('LayoutSettings Japanese-title hint benefits from the shared default without a page-local max-lines patch',
  /settings_japanese_title_in_gallery[\s\S]*settings_japanese_title_in_gallery_hint/.test(layoutPage) &&
  !/settings_japanese_title_in_gallery[\s\S]*subtitleMaxLines/.test(layoutPage))

ok('ReaderSettingsPage defines a native separator matching other Settings pages',
  /@Builder[\s\S]*private rowDivider\(\) \{[\s\S]*Divider\(\)[\s\S]*strokeWidth\(0\.5\)[\s\S]*ohos_id_color_list_separator[\s\S]*ThemeConstants\.SPACE_MD/.test(page))

ok('ReaderSettingsPage inserts separators between reader setting rows',
  (page.match(/this\.rowDivider\(\)/g) || []).length >= 3)

ok('ReaderSettingsPage lets the long volume-key subtitle wrap up to three lines',
  /settings_reader_volume_key[\s\S]*settings_reader_volume_key_hint[\s\S]*subtitleMaxLines: 3/.test(page))

console.log(`✓ reader settings readability contract: ${passed} assertions passed`)

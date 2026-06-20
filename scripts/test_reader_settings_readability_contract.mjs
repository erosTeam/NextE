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
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const row = read('shared/src/main/ets/components/ConciseListRow.ets')
const page = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')
const feSettingItem = read('../eros_fe/lib/pages/item/setting_item.dart')

ok('FE settings rows use explicit dividers between rows',
  /if \(widget\.topDivider\) _settingItemDivider\(\)/.test(feSettingItem) &&
  /if \(widget\.bottomDivider\) _settingItemDivider\(\)/.test(feSettingItem) &&
  /Divider\([\s\S]*indent: 45\.0/.test(feSettingItem))

ok('ConciseListRow exposes an opt-in subtitle max-line policy without changing default one-line rows',
  /@Param subtitleMaxLines: number = 1/.test(row) &&
  /\.maxLines\(this\.subtitleMaxLines\)/.test(row))

ok('ConciseListRow expands row height for multiline subtitles',
  /private cardHeight\(\): number \{[\s\S]*this\.subtitle && this\.subtitleMaxLines > 1[\s\S]*return 84[\s\S]*return this\.subtitle \? 60 : 52/.test(row))

ok('ReaderSettingsPage defines a native separator matching other Settings pages',
  /@Builder[\s\S]*private rowDivider\(\) \{[\s\S]*Divider\(\)[\s\S]*strokeWidth\(0\.5\)[\s\S]*ohos_id_color_list_separator[\s\S]*ThemeConstants\.SPACE_MD/.test(page))

ok('ReaderSettingsPage inserts separators between reader setting rows',
  (page.match(/this\.rowDivider\(\)/g) || []).length >= 3)

ok('ReaderSettingsPage lets the long volume-key subtitle wrap up to three lines',
  /settings_reader_volume_key[\s\S]*settings_reader_volume_key_hint[\s\S]*subtitleMaxLines: 3/.test(page))

console.log(`✓ reader settings readability contract: ${passed} assertions passed`)

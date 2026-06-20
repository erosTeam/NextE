#!/usr/bin/env node
/**
 * Contract: Settings exposes a dedicated Layout settings page for existing NextE layout/display state.
 * This is a reachability and information-architecture lane, not a theme/locale/tabbar expansion.
 *
 * Run: node scripts/test_settings_layout_entry_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    console.error(`✗ ${msg}`)
    failures++
  }
}

const grounding = [
  'eros_fe: lib/pages/tab/controller/setting_controller.dart routes Layout to EHRoutes.layoutSetting; lib/pages/setting/layout_setting_page.dart renders layout/display controls',
  'primary information: existing list and gallery-display layout settings, not account or search data',
  'primary actions: choose list mode, fixed list row height, hide gallery thumbnails, horizontal thumbnails; back is secondary',
  'scope: Settings entry + HDS child page for persisted NextE layout state; no theme, locale, tag translation, tabbar customization, or blur-cover expansion',
  'Harmony expression: HdsNavDestination + SecondaryListScaffold + GroupedListSection + ConciseListRow settings rows',
]

ok(grounding.length === 5, 'layout settings lane has five-line grounding')
ok(grounding[0].includes('setting_controller.dart') && grounding[0].includes('layout_setting_page.dart'),
  'grounding names concrete eros_fe Layout settings files')
ok(grounding[3].includes('no theme') && grounding[4].includes('HdsNavDestination'),
  'grounding limits scope and names Harmony expression')

const settingsRoot = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
const entry = read('entry/src/main/ets/pages/Index.ets')
const layoutPage = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')

ok(/export \{ LayoutSettingsPage \}/.test(settingsIndex), 'settings module exports LayoutSettingsPage')
ok(/LayoutSettingsPage/.test(entry) && /name === 'LayoutSettings'[\s\S]*LayoutSettingsPage\(\)/.test(entry),
  'entry registers LayoutSettings route')
ok(/settings_layout/.test(settingsRoot) && /pushPathByName\('LayoutSettings', null\)/.test(settingsRoot),
  'Settings root exposes a Layout row that pushes LayoutSettings')

ok(!/settings_list_fixed_height/.test(settingsRoot), 'fixed-height switch is not left in Settings root')
ok(!/settings_hide_gallery_thumbnails/.test(settingsRoot), 'hide-thumbnails switch is not left in Settings root')
ok(!/settings_horizontal_thumbnails/.test(settingsRoot), 'horizontal-thumbnails switch is not left in Settings root')
ok(!/toggleView\(\)|viewModeLabel\(\)/.test(settingsRoot), 'old one-tap root view cycler is removed from Settings root')

ok(/export struct LayoutSettingsPage/.test(layoutPage) && /HdsNavDestination/.test(layoutPage),
  'LayoutSettingsPage is a native HDS destination')
ok(/@Local listMode: ListModeState = connectListMode\(\)/.test(layoutPage),
  'page reads V2 list mode state')
ok(/@Local thumbMode: ThumbnailModeState = connectThumbnailMode\(\)/.test(layoutPage),
  'page reads V2 thumbnail mode state')
ok(/settings_view/.test(layoutPage) && /ViewModeMenu/.test(layoutPage) &&
  /ListModeSettings\.setMode\(this\.ctx\(\), mode\)/.test(layoutPage),
  'page owns list mode menu and persists through ListModeSettings')
ok(/ListMode\.WATERFALL/.test(layoutPage) && /view_waterfall/.test(layoutPage),
  'page exposes Waterfall as a distinct persisted list mode')
ok(/settings_list_fixed_height/.test(layoutPage) &&
  /ListModeSettings\.setFixedHeight\(this\.ctx\(\), value\)/.test(layoutPage),
  'page owns fixed-height switch')
ok(/settings_hide_gallery_thumbnails/.test(layoutPage) &&
  /ThumbnailModeSettings\.setHideGalleryThumbnails\(this\.ctx\(\), value\)/.test(layoutPage),
  'page owns hide-thumbnails switch')
ok(/settings_horizontal_thumbnails/.test(layoutPage) &&
  /ThumbnailModeSettings\.setHorizontalThumbnails\(this\.ctx\(\), value\)/.test(layoutPage),
  'page owns horizontal-thumbnails switch')
ok(!/ThemeSettings|LocaleSettings|TagTrans|Tabbar|Blur|blur/.test(layoutPage),
  'page does not expand theme, locale, tag translation, tabbar, or blur-cover settings')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(strings.includes('"name": "settings_layout"'), `${locale}: settings_layout string exists`)
}

if (failures > 0) {
  console.error(`\n✗ settings layout entry contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ settings layout entry contract: Layout settings route and existing display controls locked')

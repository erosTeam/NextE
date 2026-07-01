#!/usr/bin/env node
/**
 * Contract: Settings exposes the current native diagnostics loop honestly, without labeling it as
 * eros_fe's full Advanced maintenance surface.
 *
 * Run: node scripts/test_settings_advanced_entry_contract.mjs
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
  'eros_fe: lib/pages/tab/controller/setting_controller.dart routes Advanced to EHRoutes.advancedSetting; lib/pages/setting/advanced_setting_page.dart contains language, blockers, cache, proxy, import/export, HTTP, and Log maintenance rows',
  'primary information: NextE currently exposes only native diagnostics, not the full Advanced maintenance set',
  'primary action: write a native diagnostics marker to HiLog; back is secondary',
  'scope: honest Diagnostics entry + HDS child page for native hilog diagnostics; no proxy, cache clearing, import/export, blocker, language, WebDAV, or file-log viewer',
  'Harmony expression: HdsNavDestination + SecondaryListScaffold + GroupedListSection + ConciseListRow, using DiagnosticLogger/native HiLog',
]

ok(grounding.length === 5, 'advanced settings lane has five-line grounding')
ok(grounding[0].includes('setting_controller.dart') && grounding[0].includes('advanced_setting_page.dart'),
  'grounding names concrete eros_fe Advanced settings files')
ok(grounding[3].includes('no proxy') && grounding[4].includes('DiagnosticLogger'),
  'grounding limits scope and names native diagnostics expression')

const settingsRoot = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
const entry = read('entry/src/main/ets/pages/Index.ets')
const advancedPage = read('feature/settings/src/main/ets/pages/AdvancedSettingsPage.ets')
const advancedPageCode = advancedPage.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '')

ok(/export \{ AdvancedSettingsPage \}/.test(settingsIndex), 'settings module exports AdvancedSettingsPage')
ok(/AdvancedSettingsPage/.test(entry) && /name === 'AdvancedSettings'[\s\S]*AdvancedSettingsPage\(\)/.test(entry),
  'entry registers AdvancedSettings route')
ok(/settings_advanced/.test(settingsRoot) && /pushPathByName\('AdvancedSettings', null\)/.test(settingsRoot),
  'Settings root exposes an Advanced row that pushes the advanced route')
ok(/title:\s*\$r\('app\.string\.settings_advanced'\)[\s\S]*pushPathByName\('AdvancedSettings', null\)/.test(settingsRoot),
  'Settings root labels the grouped low-frequency page as Advanced')

ok(/export struct AdvancedSettingsPage/.test(advancedPage) && /HdsNavDestination/.test(advancedPage),
  'AdvancedSettingsPage is a native HDS destination')
ok(/immersiveTitleBar\(AppStrings\.get\('settings_advanced'\)\)/.test(advancedPage),
  'advanced page title matches the grouped low-frequency scope')
ok(/settings_security/.test(advancedPage) && /pushPathByName\('SecuritySettings', null\)/.test(advancedPage),
  'advanced page exposes Security as a child row')
ok(/diagnostics_enabled/.test(advancedPage) && /diagnostics_min_level/.test(advancedPage),
  'page exposes native diagnostics controls')
ok(/advanced_write_marker/.test(advancedPage) &&
  /DiagnosticLogger\.info\('diagnostics', 'manual_marker', `ts=\$\{Date\.now\(\)\}`\)/.test(advancedPage),
  'page writes a timestamped manual diagnostics marker')
ok(/this\.toast\(\$r\('app\.string\.advanced_marker_written'\)\)/.test(advancedPage),
  'marker action gives immediate visible feedback')
ok(!/Proxy|proxy|import_app|export_app|blockers|WebDAV|Language|Locale/.test(advancedPageCode),
  'page does not expose unrelated advanced rows')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'settings_advanced',
    'advanced_diagnostics',
    'advanced_diagnostics_hint',
    'advanced_write_marker',
    'advanced_marker_written',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ settings advanced entry contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ settings advanced entry contract: Advanced diagnostics route and marker action locked')

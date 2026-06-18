#!/usr/bin/env node
/**
 * Contract: Reader column-mode switching is parked during P0 core recovery.
 *
 * The persisted setting and settings-page menu remain for follow-up work, but
 * the Reader runtime must not switch into double-page spread rendering until
 * layout and gesture acceptance is restored.
 *
 * Run: node scripts/test_reader_column_mode_switch_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')

ok('settings page still exposes the saved column-mode preference for a later lane',
  /settings_reader_double_page/.test(settingsPage) &&
  /ReadColumnMode\.SINGLE/.test(settingsPage) &&
  /ReadColumnMode\.ODD_LEFT/.test(settingsPage) &&
  /ReadColumnMode\.EVEN_LEFT/.test(settingsPage))
ok('ReaderPage runtime ignores the saved double-page preference',
  /private doublePageEnabled\(\): boolean \{[\s\S]*return false[\s\S]*\}/.test(reader))
ok('cycleColumnMode is a no-op in ReaderPage during recovery',
  /private cycleColumnMode\(\): void \{[\s\S]*return[\s\S]*\}/.test(reader) &&
  !/private cycleColumnMode\(\): void \{[\s\S]*ReadModeSettings\.setColumnMode/.test(reader))
ok('bottom chrome cannot advertise active double-page A/B in ReaderPage',
  /private columnModeLabel\(\): Resource \{[\s\S]*return \$r\('app\.string\.common_off'\)[\s\S]*\}/.test(reader) &&
  !/private columnModeLabel\(\): Resource \{[\s\S]*read_double_page_a/.test(reader) &&
  !/private columnModeLabel\(\): Resource \{[\s\S]*read_double_page_b/.test(reader))
ok('horizontal reader path remains single-page Swiper',
  /@Builder\s+HorizontalReader\(\)[\s\S]*Swiper\(\)[\s\S]*ForEach\(\s*this\.vm\.images/.test(reader))

console.log(`✓ reader column-mode parked contract: ${passed} assertions passed`)

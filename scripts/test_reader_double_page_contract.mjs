#!/usr/bin/env node
/**
 * Contract: Reader double-page rendering is parked during P0 core recovery.
 *
 * The state/settings model is left intact for a later lane, but ReaderPage must
 * not let a persisted double-page preference squeeze the online reading canvas
 * into a half-width spread while gesture/loading recovery is being accepted.
 *
 * Run: node scripts/test_reader_double_page_contract.mjs
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

const state = read('shared/src/main/ets/state/ReadModeState.ets')
const settings = read('shared/src/main/ets/settings/ReadModeSettings.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')
const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')

ok('ReadColumnMode model remains available for a later double-page lane',
  /export enum ReadColumnMode/.test(state) &&
  /SINGLE\s*=\s*'single'/.test(state) &&
  /ODD_LEFT\s*=\s*'oddLeft'/.test(state) &&
  /EVEN_LEFT\s*=\s*'evenLeft'/.test(state))
ok('ReadModeSettings still owns persistence of the parked preference',
  /StorageKeys\.READING_DOUBLE_PAGE/.test(settings) &&
  /static async setColumnMode/.test(settings))
ok('settings surface is not cleaned up in this recovery lane',
  /settings_reader_double_page/.test(settingsPage) &&
  /ReadModeSettings\.setColumnMode/.test(settingsPage))
ok('ReaderPage routes horizontal reading directly to HorizontalReader',
  /if \(this\.readMode\.mode === ReadMode\.VERTICAL\) \{[\s\S]*this\.VerticalReader\(\)[\s\S]*\} else \{[\s\S]*this\.HorizontalReader\(\)[\s\S]*\}/.test(reader) &&
  !/else if \(this\.doublePageEnabled\(\)\)[\s\S]*this\.DoublePageReader\(\)/.test(reader))
ok('ReaderPage runtime disables double-page rendering',
  /private doublePageEnabled\(\): boolean \{[\s\S]*return false[\s\S]*\}/.test(reader))
ok('Reader bottom chrome reports the parked column mode as off',
  /private columnModeLabel\(\): Resource \{[\s\S]*return \$r\('app\.string\.common_off'\)[\s\S]*\}/.test(reader))
ok('Reader bottom chrome cannot cycle into double-page during recovery',
  /private cycleColumnMode\(\): void \{[\s\S]*return[\s\S]*\}/.test(reader) &&
  !/private cycleColumnMode\(\): void \{[\s\S]*ReadModeSettings\.setColumnMode/.test(reader))

console.log(`✓ reader double-page parked contract: ${passed} assertions passed`)

#!/usr/bin/env node
/**
 * Contract: Reader double-page rendering is live again without regressing the
 * accepted single-page gesture baseline.
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
ok('ReaderPage routes vertical to vertical, double-page to DoublePageReader, and single horizontal to HorizontalReader',
  /if \(this\.readMode\.mode === ReadMode\.VERTICAL\) \{[\s\S]*this\.VerticalReader\(\)[\s\S]*\} else if \(this\.doublePageEnabled\(\)\) \{[\s\S]*this\.DoublePageReader\(\)[\s\S]*\} else \{[\s\S]*this\.HorizontalReader\(\)/.test(reader))
ok('ReaderPage enables double-page only for horizontal non-single column modes',
  /private doublePageEnabled\(\): boolean \{[\s\S]*return this\.readMode\.mode !== ReadMode\.VERTICAL && this\.readMode\.columnMode !== ReadColumnMode\.SINGLE[\s\S]*\}/.test(reader))
ok('Reader bottom chrome labels off, double-page A, and double-page B',
  /private columnModeLabel\(\): Resource \{[\s\S]*ReadColumnMode\.ODD_LEFT[\s\S]*read_double_page_a[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*read_double_page_b[\s\S]*common_off/.test(reader))
ok('Reader bottom chrome cycles single -> A -> B -> single and persists through ReadModeSettings',
  /private cycleColumnMode\(\): void \{[\s\S]*ReadColumnMode\.ODD_LEFT[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*ReadColumnMode\.SINGLE[\s\S]*ReadModeSettings\.setColumnMode\(ctx, next\)/.test(reader))
ok('DoublePageReader preserves spread rendering, RTL row reversal, and parent double-tap routing',
  /@Builder\s+DoublePageReader\(\)[\s\S]*this\.spreadStarts\(\)[\s\S]*this\.spreadRowReversed\(\)[\s\S]*this\.SpreadSecondSlot\(start\)[\s\S]*this\.SpreadImage\(start\)[\s\S]*TapGesture\(\{ count: 2 \}\)/.test(reader))
ok('Double-page spread image pages still report zoom and image-loaded state',
  /@Builder\s+SpreadImage\(index: number\)[\s\S]*ReaderImagePage\(\{[\s\S]*onZoomChange[\s\S]*onImageLoaded: \(page: number\) => \{[\s\S]*this\.markPageImageLoaded\(page\)/.test(reader))

console.log(`✓ reader double-page runtime contract: ${passed} assertions passed`)

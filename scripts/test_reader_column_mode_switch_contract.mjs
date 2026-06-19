#!/usr/bin/env node
/**
 * Contract: Reader column-mode switching is live, but remains gated out of
 * vertical reading and normalizes the current image to the target spread.
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
ok('ReaderPage runtime gates double-page to horizontal non-single column modes',
  /private doublePageEnabled\(\): boolean \{[\s\S]*this\.readMode\.mode !== ReadMode\.VERTICAL[\s\S]*this\.readMode\.columnMode !== ReadColumnMode\.SINGLE/.test(reader))
ok('cycleColumnMode is disabled in vertical mode but persists horizontal changes',
  /private cycleColumnMode\(\): void \{[\s\S]*if \(this\.readMode\.mode === ReadMode\.VERTICAL\) \{[\s\S]*return[\s\S]*ReadModeSettings\.setColumnMode\(ctx, next\)/.test(reader))
ok('cycleColumnMode normalizes current index and slider value for the target mode',
  /const targetIndex: number = this\.normalizedIndexForColumnMode\(next\)/.test(reader) &&
  /this\.vm\.currentIndex = targetIndex[\s\S]*this\.sliderValue = targetIndex \+ 1/.test(reader))
ok('bottom chrome advertises active double-page A/B while keeping vertical as off',
  /private columnModeLabel\(\): Resource \{[\s\S]*ReadMode\.VERTICAL[\s\S]*common_off[\s\S]*ReadColumnMode\.ODD_LEFT[\s\S]*read_double_page_a[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*read_double_page_b/.test(reader))
ok('single horizontal reader path remains a full-page Swiper',
  /@Builder\s+HorizontalReader\(\)[\s\S]*Swiper\(\)[\s\S]*ForEach\(\s*this\.vm\.images/.test(reader))
ok('double-page horizontal reader path uses spread starts instead of raw image pages',
  /@Builder\s+DoublePageReader\(\)[\s\S]*ForEach\(\s*this\.spreadStarts\(\)/.test(reader))

console.log(`✓ reader column-mode switch contract: ${passed} assertions passed`)

#!/usr/bin/env node
/**
 * Contract for Reader auto page turn.
 *
 * Locks:
 *   - auto page interval is stored in ReadModeState / ReadModeSettings;
 *   - ReaderPage owns only the session timer and stops it on close/end;
 *   - zoom, slider drag, and far jump loading pause the timer instead of fighting user control;
 *   - double-page mode advances by spread, not by raw image index;
 *   - ReaderSettingsPage exposes a native menu for interval selection.
 *
 * Run: node scripts/test_reader_auto_page_contract.mjs
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
const eq = (name, got, want) => {
  assert.deepStrictEqual(got, want, name)
  passed++
}

const normalize = (seconds) => {
  if (!Number.isFinite(seconds)) return 3
  const rounded = Math.round(seconds)
  if (rounded < 2) return 2
  if (rounded > 30) return 30
  return rounded
}
eq('normalizes NaN to default', normalize(Number.NaN), 3)
eq('normalizes low interval to min', normalize(1), 2)
eq('normalizes high interval to max', normalize(31), 30)
eq('rounds fractional interval', normalize(7.6), 8)

const nextAutoTarget = (doublePage, columnMode, currentIndex) => {
  if (!doublePage) return currentIndex + 1
  const spreadIndex =
    columnMode === 'evenLeft' && currentIndex > 0
      ? Math.floor((currentIndex + 1) / 2)
      : Math.floor(currentIndex / 2)
  const nextSpread = spreadIndex + 1
  return columnMode === 'evenLeft' ? (nextSpread <= 0 ? 0 : nextSpread * 2 - 1) : nextSpread * 2
}
eq('single page auto advances one image', nextAutoTarget(false, 'single', 4), 5)
eq('oddLeft auto advances by next spread start', nextAutoTarget(true, 'oddLeft', 2), 4)
eq('evenLeft cover auto advances to page 2 spread', nextAutoTarget(true, 'evenLeft', 0), 1)
eq('evenLeft paired spread advances to next paired spread', nextAutoTarget(true, 'evenLeft', 2), 3)

{
  const state = read('shared/src/main/ets/state/ReadModeState.ets')
  ok('ReadModeState traces autoPageSeconds', /@Trace\s+autoPageSeconds:\s*number\s*=\s*3/.test(state))
}

{
  const settings = read('shared/src/main/ets/settings/ReadModeSettings.ets')
  ok('settings defines auto page default', /AUTO_PAGE_SECONDS_DEFAULT:\s*number\s*=\s*3/.test(settings))
  ok('settings defines min interval', /AUTO_PAGE_SECONDS_MIN:\s*number\s*=\s*2/.test(settings))
  ok('settings defines max interval', /AUTO_PAGE_SECONDS_MAX:\s*number\s*=\s*30/.test(settings))
  ok('settings normalizes invalid seconds', /static normalizeAutoPageSeconds\(seconds: number\): number[\s\S]*Number\.isFinite/.test(settings))
  ok('restore reads READING_AUTO_PAGE_SEC', /getSync\(StorageKeys\.READING_AUTO_PAGE_SEC,\s*AUTO_PAGE_SECONDS_DEFAULT\)/.test(settings))
  ok('restore writes connectReadMode autoPageSeconds', /connectReadMode\(\)\.autoPageSeconds\s*=\s*autoPageSeconds/.test(settings))
  ok('setAutoPageSeconds persists READING_AUTO_PAGE_SEC', /putSync\(StorageKeys\.READING_AUTO_PAGE_SEC,\s*normalized\)/.test(settings))
}

{
  const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
  ok('ReaderPage imports AppStrings for localized auto label', /AppStrings/.test(reader))
  ok('ReaderPage tracks auto page enabled as V2 local state', /@Local\s+autoPageEnabled:\s*boolean\s*=\s*false/.test(reader))
  ok('ReaderPage keeps a timer id', /private\s+autoPageTimer:\s*number\s*=\s*-1/.test(reader))
  ok('clearAutoPageTimer clears timeout', /clearAutoPageTimer\(\)[\s\S]*clearTimeout\(this\.autoPageTimer\)/.test(reader))
  ok('stopAutoPage disables session state', /stopAutoPage\(\)[\s\S]*this\.autoPageEnabled\s*=\s*false/.test(reader))
  ok('toggle starts and stops auto page', /toggleAutoPage\(\)[\s\S]*this\.stopAutoPage\(\)[\s\S]*this\.autoPageEnabled\s*=\s*true[\s\S]*this\.scheduleAutoPage\(\)/.test(reader))
  ok('timer uses normalized setting seconds', /ReadModeSettings\.normalizeAutoPageSeconds\(this\.readMode\.autoPageSeconds\)[\s\S]*seconds \* 1000/.test(reader))
  ok('page change resets auto timer', /onPageChanged\(\)[\s\S]*if \(this\.autoPageEnabled\)[\s\S]*this\.scheduleAutoPage\(\)/.test(reader))
  ok('close stops auto page before wakelock restore', /aboutToDisappear\(\): void \{[\s\S]*this\.stopAutoPage\(\)[\s\S]*setReaderKeepScreenOn\(false\)/.test(reader))
  ok('auto target advances by spread in double page', /nextAutoPageTarget\(\): number[\s\S]*this\.doublePageEnabled\(\)[\s\S]*this\.spreadStartIndex\(this\.spreadIndexForImage\(this\.vm\.currentIndex\) \+ 1\)/.test(reader))
  ok('auto page yields during zoom slider and jump', /this\.imageZoomed \|\| this\.sliderPreview >= 0 \|\| this\.vm\.jumping/.test(reader))
  ok('auto page stops at gallery end', /if \(target >= this\.vm\.totalPages\(\)\) \{[\s\S]*this\.stopAutoPage\(\)/.test(reader))
  ok('advanceAutoPage does not schedule directly after turnTo', !/this\.turnTo\(target\)[\s\S]{0,120}this\.scheduleAutoPage\(\)/.test(reader))
  ok('bottom bar exposes localized auto pill', /Text\(this\.autoPageLabel\(\)\)[\s\S]*this\.toggleAutoPage\(\)/.test(reader))
  ok('auto label uses reader_auto_page string', /AppStrings\.get\('reader_auto_page'\)/.test(reader))
}

{
  const page = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')
  ok('settings page tracks auto page menu state', /@Local\s+autoPageMenuShown:\s*boolean\s*=\s*false/.test(page))
  ok('settings page persists interval through ReadModeSettings', /ReadModeSettings\.setAutoPageSeconds/.test(page))
  ok('settings page shows native AutoPageMenu', /@Builder\s+AutoPageMenu\(\)[\s\S]*Menu\(\)/.test(page))
  ok('settings page offers expected intervals', /\[2,\s*3,\s*5,\s*8,\s*12,\s*20,\s*30\]/.test(page))
  ok('settings page row uses localized interval title', /settings_reader_auto_page_interval/.test(page))
  ok('settings page binds auto page menu', /bindMenu\(this\.autoPageMenuShown,\s*this\.AutoPageMenu/.test(page))
}

{
  for (const loc of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
    const json = JSON.parse(read(`entry/src/main/resources/${loc}/element/string.json`))
    for (const key of ['settings_reader_auto_page_interval', 'reader_auto_page']) {
      const entry = json.string.find((x) => x.name === key)
      ok(`${loc}: ${key} exists`, entry && entry.value.trim().length > 0)
    }
  }
}

console.log(`✓ reader auto page contract: ${passed} assertions passed`)

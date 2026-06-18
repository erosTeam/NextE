#!/usr/bin/env node
/**
 * Contract for Reader horizontal double-page mode (eros_fe ViewColumnMode).
 *
 * Locks:
 *   - ReadModeState carries single / oddLeft(A) / evenLeft(B);
 *   - ReadModeSettings restores and persists StorageKeys.READING_DOUBLE_PAGE;
 *   - ReaderSettingsPage exposes a native row/menu for the double-page mode;
 *   - ReaderPage renders a separate DoublePageReader only for horizontal modes, disables it in vertical,
 *     and uses eros_fe's page grouping math.
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
const eq = (name, got, want) => {
  assert.deepStrictEqual(got, want, name)
  passed++
}

const spreadIndexForImage = (mode, index) => {
  if (mode === 'single' || index <= 0) return 0
  if (mode === 'evenLeft') return Math.floor((index + 1) / 2)
  return Math.floor(index / 2)
}
const spreadStartIndex = (mode, spreadIndex) => {
  if (mode === 'single') return spreadIndex
  if (mode === 'evenLeft') return spreadIndex <= 0 ? 0 : spreadIndex * 2 - 1
  return spreadIndex * 2
}
const spreadCount = (mode, total) => {
  if (mode === 'single' || total <= 1) return total
  if (mode === 'evenLeft') return Math.round(total / 2) + ((total + 1) % 2)
  return Math.round(total / 2)
}
const starts = (mode, total) => {
  const out = []
  for (let i = 0; i < spreadCount(mode, total); i++) out.push(spreadStartIndex(mode, i))
  return out
}
const secondIndex = (mode, start) => {
  if (mode === 'evenLeft' && start <= 0) return -1
  return start + 1
}
const spreadSlots = (readMode, columnMode, start, total) => {
  const first = start
  const second = secondIndex(columnMode, start)
  const secondSlot = second >= 0 && second < total ? second : null
  const slots = [first, secondSlot]
  return readMode === 'rtl' ? slots.reverse() : slots
}

eq('oddLeft groups pages 1/2, 3/4, 5', starts('oddLeft', 5), [0, 2, 4])
eq('evenLeft groups page 1, then 2/3, 4/5', starts('evenLeft', 5), [0, 1, 3])
eq('evenLeft four pages => page 1, 2/3, 4', starts('evenLeft', 4), [0, 1, 3])
eq('single groups every page separately', starts('single', 4), [0, 1, 2, 3])
eq('oddLeft spread index mirrors eros_fe currentItemIndex ~/ 2', [0, 0, 1, 1, 2].map((_, i) => spreadIndexForImage('oddLeft', i)), [0, 0, 1, 1, 2])
eq('evenLeft spread index mirrors eros_fe (currentItemIndex + 1) ~/ 2', [0, 1, 1, 2, 2].map((_, i) => spreadIndexForImage('evenLeft', i)), [0, 1, 1, 2, 2])
eq('evenLeft cover spread renders page 1 alone', secondIndex('evenLeft', 0), -1)
eq('evenLeft next spread renders pages 2/3', secondIndex('evenLeft', 1), 2)
eq('ltr oddLeft spread keeps first page visually left', spreadSlots('ltr', 'oddLeft', 0, 5), [0, 1])
eq('rtl oddLeft spread reverses visual order like eros_fe pageList.reversed', spreadSlots('rtl', 'oddLeft', 0, 5), [1, 0])
eq('ltr evenLeft paired spread keeps lower page visually left', spreadSlots('ltr', 'evenLeft', 1, 5), [1, 2])
eq('rtl evenLeft paired spread reverses visual order', spreadSlots('rtl', 'evenLeft', 1, 5), [2, 1])
eq('rtl evenLeft cover spread keeps page 1 in the right slot', spreadSlots('rtl', 'evenLeft', 0, 5), [null, 0])

{
  const state = read('shared/src/main/ets/state/ReadModeState.ets')
  ok('ReadColumnMode enum exists', /export enum ReadColumnMode/.test(state))
  ok('ReadColumnMode has SINGLE', /SINGLE\s*=\s*'single'/.test(state))
  ok('ReadColumnMode has ODD_LEFT', /ODD_LEFT\s*=\s*'oddLeft'/.test(state))
  ok('ReadColumnMode has EVEN_LEFT', /EVEN_LEFT\s*=\s*'evenLeft'/.test(state))
  ok('ReadModeState traces columnMode default single', /@Trace\s+columnMode:\s*string\s*=\s*ReadColumnMode\.SINGLE/.test(state))
  ok('shared barrel exports ReadColumnMode', /export \{ ReadMode, ReadColumnMode, ReadModeState, connectReadMode \}/.test(read('shared/src/main/ets/Index.ets')))
}

{
  const settings = read('shared/src/main/ets/settings/ReadModeSettings.ets')
  ok('restore reads READING_DOUBLE_PAGE default single', /getSync\(\s*StorageKeys\.READING_DOUBLE_PAGE,\s*ReadColumnMode\.SINGLE/.test(settings))
  ok('restore writes connectReadMode().columnMode', /connectReadMode\(\)\.columnMode\s*=\s*columnMode/.test(settings))
  ok('setColumnMode is the single writer', /static async setColumnMode\(context: common\.UIAbilityContext, columnMode: string\)/.test(settings))
  ok('setColumnMode persists READING_DOUBLE_PAGE', /putSync\(StorageKeys\.READING_DOUBLE_PAGE,\s*columnMode\)/.test(settings))
}

{
  const page = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')
  ok('settings page imports ReadColumnMode', /ReadColumnMode/.test(page))
  ok('settings page has double-page row label', /settings_reader_double_page/.test(page))
  ok('settings page has ColumnMenu', /@Builder\s+ColumnMenu\(\)/.test(page))
  ok('settings page offers off/A/B values', /ReadColumnMode\.SINGLE/.test(page) && /ReadColumnMode\.ODD_LEFT/.test(page) && /ReadColumnMode\.EVEN_LEFT/.test(page))
  ok('settings page persists via ReadModeSettings.setColumnMode', /ReadModeSettings\.setColumnMode/.test(page))
}

{
  const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
  ok('ReaderPage imports ReadColumnMode', /ReadColumnMode/.test(reader))
  ok('ReaderPage routes vertical before double-page', /this\.readMode\.mode === ReadMode\.VERTICAL[\s\S]*this\.VerticalReader\(\)[\s\S]*else if \(this\.doublePageEnabled\(\)\)[\s\S]*this\.DoublePageReader\(\)/.test(reader))
  ok('doublePageEnabled excludes vertical and single', /this\.readMode\.mode !== ReadMode\.VERTICAL && this\.readMode\.columnMode !== ReadColumnMode\.SINGLE/.test(reader))
  ok('tap step is 2 only in double page', /private\s+pageStep\(\):\s*number\s*\{[\s\S]*this\.doublePageEnabled\(\) \? 2 : 1/.test(reader))
  ok('spreadIndexForImage implements evenLeft math', /Math\.floor\(\(index \+ 1\) \/ 2\)/.test(reader))
  ok('spreadStartIndex implements evenLeft first-single math', /spreadIndex <= 0 \? 0 : spreadIndex \* 2 - 1/.test(reader))
  ok('spreadCount implements evenLeft page count math', /Math\.round\(total \/ 2\) \+ \(\(total \+ 1\) % 2\)/.test(reader))
  ok('DoublePageReader suppresses evenLeft cover spread second slot', /private spreadSecondIndex\(start: number\): number[\s\S]*ReadColumnMode\.EVEN_LEFT && start <= 0[\s\S]*return -1/.test(reader))
  ok('DoublePageReader has a second-slot builder', /@Builder\s+SpreadSecondSlot\(start: number\)[\s\S]*this\.SpreadImage\(this\.spreadSecondIndex\(start\)\)/.test(reader))
  ok('DoublePageReader detects RTL spread row ordering', /private spreadRowReversed\(\): boolean[\s\S]*this\.readMode\.mode === ReadMode\.RTL/.test(reader))
  ok('DoublePageReader reverses row slot order for RTL', /if \(this\.spreadRowReversed\(\)\) \{[\s\S]*this\.SpreadSecondSlot\(start\)[\s\S]*this\.SpreadImage\(start\)[\s\S]*\} else \{[\s\S]*this\.SpreadImage\(start\)[\s\S]*this\.SpreadSecondSlot\(start\)/.test(reader))
  ok('bottom bar cycles column mode', /cycleColumnMode\(\)/.test(reader) && /ReadModeSettings\.setColumnMode/.test(reader))
}

{
  for (const loc of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
    const json = JSON.parse(read(`entry/src/main/resources/${loc}/element/string.json`))
    for (const key of ['settings_reader_double_page', 'common_off', 'read_double_page_a', 'read_double_page_b']) {
      const entry = json.string.find((x) => x.name === key)
      ok(`${loc}: ${key} exists`, entry && entry.value.trim().length > 0)
    }
  }
}

console.log(`✓ reader double-page contract: ${passed} assertions passed`)

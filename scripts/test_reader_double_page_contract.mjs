#!/usr/bin/env node
/**
 * Contract: Reader double-page rendering stays in the current interim grouped-row
 * mitigation without regressing the accepted single-page gesture baseline.
 *
 * This does not prove the final ideal single visual spread renderer. It only
 * prevents a regression to the older split ReaderImagePage double-page path where
 * two independently transformed image surfaces could overlap each other.
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
function component(name) {
  const start = reader.indexOf(`struct ${name}`)
  assert.ok(start >= 0, `missing component ${name}`)
  const next = reader.indexOf('\n@ComponentV2', start + name.length)
  return reader.slice(start, next >= 0 ? next : reader.length)
}

const spreadSurface = component('ReaderSpreadSurface')
const spreadLayer = component('ReaderSpreadImageLayer')
function builder(name) {
  const start = reader.indexOf(`@Builder\n  ${name}`)
  assert.ok(start >= 0, `missing builder ${name}`)
  const next = reader.indexOf('\n  @Builder', start + name.length)
  return reader.slice(start, next >= 0 ? next : reader.length)
}

const doublePageReader = builder('DoublePageReader()')

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
ok('ReaderSpreadResolver owns double-page eligibility and spread math',
  /class ReaderSpreadResolver \{[\s\S]*static isDoublePage\(mode: string, columnMode: string\): boolean \{[\s\S]*mode !== ReadMode\.VERTICAL && columnMode !== ReadColumnMode\.SINGLE/.test(reader) &&
  /static spreadIndexForImage\(columnMode: string, index: number\): number \{[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*Math\.floor\(\(index \+ 1\) \/ 2\)[\s\S]*Math\.floor\(index \/ 2\)/.test(reader) &&
  /static spreadStartIndex\(columnMode: string, spreadIndex: number\): number \{[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*spreadIndex \* 2 - 1[\s\S]*spreadIndex \* 2/.test(reader) &&
  /static spreadCount\(enabled: boolean, columnMode: string, total: number\): number \{[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*Math\.round\(total \/ 2\) \+ \(\(total \+ 1\) % 2\)[\s\S]*Math\.round\(total \/ 2\)/.test(reader) &&
  /static spreadSecondVisible\(columnMode: string, start: number, total: number\): boolean \{[\s\S]*ReaderSpreadResolver\.spreadSecondIndex/.test(reader))
ok('ReaderPage delegates double-page eligibility and spread math to ReaderSpreadResolver',
  /private doublePageEnabled\(\): boolean \{[\s\S]*return ReaderSpreadResolver\.isDoublePage\(this\.readMode\.mode, this\.readMode\.columnMode\)/.test(reader) &&
  /private spreadIndexForImage\(index: number\): number \{[\s\S]*return ReaderSpreadResolver\.spreadIndexForImage\(this\.readMode\.columnMode, index\)/.test(reader) &&
  /private spreadStartIndex\(spreadIndex: number\): number \{[\s\S]*return ReaderSpreadResolver\.spreadStartIndex\(this\.readMode\.columnMode, spreadIndex\)/.test(reader) &&
  /private spreadCount\(\): number \{[\s\S]*return ReaderSpreadResolver\.spreadCount\(/.test(reader) &&
  /private spreadSecondVisible\(start: number\): boolean \{[\s\S]*return ReaderSpreadResolver\.spreadSecondVisible\(this\.readMode\.columnMode, start, this\.vm\.totalPages\(\)\)/.test(reader))
ok('Reader bottom chrome labels off, double-page A, and double-page B',
  /private columnModeLabel\(\): Resource \{[\s\S]*ReadColumnMode\.ODD_LEFT[\s\S]*read_double_page_a[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*read_double_page_b[\s\S]*common_off/.test(reader))
ok('Reader bottom chrome cycles single -> A -> B -> single and persists through ReadModeSettings',
  /private cycleColumnMode\(\): void \{[\s\S]*ReadColumnMode\.ODD_LEFT[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*ReadColumnMode\.SINGLE[\s\S]*ReadModeSettings\.setColumnMode\(ctx, next\)/.test(reader))
ok('DoublePageReader renders each spread through one ReaderSpreadSurface, not split image surfaces',
  /@Builder\s+DoublePageReader\(\)[\s\S]*this\.spreadStarts\(\)[\s\S]*ReaderSpreadSurface\(\{[\s\S]*first: this\.hasSpreadImage\(start\) \? this\.vm\.images\[start\]/.test(reader) &&
  /ReaderSpreadSurface\(\{[\s\S]*second: this\.hasSpreadImage\(this\.spreadSecondIndex\(start\)\) \? this\.vm\.images\[this\.spreadSecondIndex\(start\)\]/.test(reader) &&
  /ReaderSpreadSurface\(\{[\s\S]*rowReversed: this\.spreadRowReversed\(\)[\s\S]*onZoomChange[\s\S]*this\.markPageImageLoaded\(page\)/.test(reader) &&
  !/@Builder\s+SpreadImage\(index: number\)/.test(reader) &&
  !/this\.SpreadSecondSlot\(start\)|this\.SpreadImage\(start\)/.test(reader) &&
  !/ReaderImagePage\(\{/.test(doublePageReader))
ok('ReaderSpreadSurface owns double-page zoom/pan as one interim transformed row group',
  /Row\(\{ space: ThemeConstants\.SPACE_XS \}\)[\s\S]*\.scale\(\{ x: this\.zoomScale, y: this\.zoomScale \}\)[\s\S]*\.translate\(\{ x: this\.offsetX, y: this\.offsetY \}\)[\s\S]*\.clip\(true\)/.test(spreadSurface) &&
  /GestureGroup\(\s*GestureMode\.Parallel,[\s\S]*PinchGesture\(\{\s*fingers:\s*2\s*\}\)[\s\S]*PanGesture\(\{\s*fingers:\s*1,\s*direction:\s*PanDirection\.All/.test(spreadSurface) &&
  /Image\(this\.imageUrl\)[\s\S]*\.objectFit\(ImageFit\.Contain\)/.test(spreadLayer) &&
  !/\.scale\(\{ x: this\.zoomScale|TapGesture|PinchGesture|PanGesture/.test(spreadLayer))
ok('ReaderSpreadImageLayer remains a passive image/loading layer with no independent z-order or transform',
  !/zIndex\(|position\(|\.translate\(|\.scale\(|\.renderGroup\(/.test(spreadLayer) &&
  !/@Local zoomScale|@Local offsetX|@Local offsetY/.test(spreadLayer))

console.log(`✓ reader double-page runtime contract: ${passed} assertions passed`)

#!/usr/bin/env node
/**
 * Contract: Reader double-page rendering uses one spread surface, global on/off
 * state, and per-gallery pairing stored with read progress.
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
function builder(name) {
  const start = reader.indexOf(`@Builder\n  ${name}`)
  assert.ok(start >= 0, `missing builder ${name}`)
  const next = reader.indexOf('\n  @Builder', start + name.length)
  return reader.slice(start, next >= 0 ? next : reader.length)
}

const spreadSurface = component('ReaderSpreadSurface')
const spreadLayer = component('ReaderSpreadImageLayer')
const doublePageReader = builder('DoublePageReader()')
const singleSpreadBranchStart = spreadSurface.indexOf('if (!this.hasSecond)')
assert.ok(singleSpreadBranchStart >= 0, 'missing single-image spread branch')
const singleSpreadBranchEnd = spreadSurface.indexOf('} else if (this.rowReversed)', singleSpreadBranchStart)
assert.ok(singleSpreadBranchEnd > singleSpreadBranchStart, 'single-image spread branch must be followed by double-image branch')
const singleSpreadBranch = spreadSurface.slice(singleSpreadBranchStart, singleSpreadBranchEnd)

ok('ReadModeState keeps global enabled and current-gallery pairing separately',
  /@Trace doublePageEnabled: boolean = false/.test(state) &&
    /@Trace columnMode: string = ReadColumnMode\.SINGLE/.test(state))
ok('ReadModeSettings persists the global double-page switch',
  /StorageKeys\.READING_DOUBLE_PAGE/.test(settings) &&
    /static async setDoublePageEnabled/.test(settings) &&
    /store\.putSync\(StorageKeys\.READING_DOUBLE_PAGE, enabled\)/.test(settings))
ok('settings surface is a switch, not a column-mode dropdown',
  /settings_reader_double_page/.test(settingsPage) &&
    /hasSwitch:\s*true/.test(settingsPage) &&
    !/ColumnMenu|read_double_page_a|read_double_page_b/.test(settingsPage))
ok('ReaderPage routes vertical to vertical, double-page to DoublePageReader, and single horizontal to HorizontalReader',
  /if \(this\.readMode\.mode === ReadMode\.VERTICAL\) \{[\s\S]*this\.VerticalReader\(\)[\s\S]*\} else if \(this\.doublePageEnabled\(\)\) \{[\s\S]*this\.DoublePageReader\(\)[\s\S]*\} else \{[\s\S]*this\.HorizontalReader\(\)/.test(reader))
ok('ReaderSpreadResolver owns double-page eligibility and spread math',
  /static isDoublePage\(mode: string, enabled: boolean\): boolean \{[\s\S]*mode !== ReadMode\.VERTICAL && enabled/.test(reader) &&
    /static spreadIndexForImage\(columnMode: string, index: number\): number \{[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*Math\.floor\(\(index \+ 1\) \/ 2\)[\s\S]*Math\.floor\(index \/ 2\)/.test(reader) &&
    /static spreadStartIndex\(columnMode: string, spreadIndex: number\): number \{[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*spreadIndex \* 2 - 1[\s\S]*spreadIndex \* 2/.test(reader) &&
    /static spreadCount\(enabled: boolean, columnMode: string, total: number\): number \{[\s\S]*ReadColumnMode\.EVEN_LEFT[\s\S]*Math\.round\(total \/ 2\) \+ \(\(total \+ 1\) % 2\)[\s\S]*Math\.round\(total \/ 2\)/.test(reader))
ok('ReaderPage delegates spread math but gates with doublePageEnabled',
  /private doublePageEnabled\(\): boolean \{[\s\S]*ReaderSpreadResolver\.isDoublePage\(this\.readMode\.mode, this\.readMode\.doublePageEnabled\)/.test(reader) &&
    /private spreadIndexForImage\(index: number\): number \{[\s\S]*return ReaderSpreadResolver\.spreadIndexForImage\(this\.readMode\.columnMode, index\)/.test(reader) &&
    /private spreadStartIndex\(spreadIndex: number\): number \{[\s\S]*return ReaderSpreadResolver\.spreadStartIndex\(this\.readMode\.columnMode, spreadIndex\)/.test(reader))
ok('bottom chrome toggles double-page and offers one-page pairing shift',
  /private toggleDoublePage\(\): void/.test(reader) &&
    /private turnOnePageInDoublePage\(\): void/.test(reader) &&
    /sys\.symbol\.book_open_fill/.test(reader) &&
    /sys\.symbol\.forward_end_fill/.test(reader))
ok('DoublePageReader renders each spread through one ReaderSpreadSurface, not split image surfaces',
  /@Builder\s+DoublePageReader\(\)[\s\S]*this\.spreadStartSource\(\)[\s\S]*ReaderSpreadSurface\(\{[\s\S]*first: this\.vm\.imageAt\(start\)/.test(reader) &&
    /ReaderSpreadSurface\(\{[\s\S]*second: this\.hasSpreadImage\(this\.spreadSecondIndex\(start\)\) \? this\.vm\.imageAt\(this\.spreadSecondIndex\(start\)\)/.test(reader) &&
    /ReaderSpreadSurface\(\{[\s\S]*rowReversed: this\.spreadRowReversed\(\)[\s\S]*onZoomChange[\s\S]*this\.markPageImageLoaded\(page\)/.test(reader) &&
    !/ReaderImagePage\(\{/.test(doublePageReader))
ok('ReaderSpreadSurface owns double-page zoom/pan as one transformed row group',
  /Row\(\)[\s\S]*\.scale\(\{ x: this\.zoomScale, y: this\.zoomScale \}\)[\s\S]*\.translate\(\{ x: this\.offsetX, y: this\.offsetY \}\)[\s\S]*\.clip\(true\)/.test(spreadSurface) &&
    !/ThemeConstants\.SPACE_XS/.test(spreadSurface) &&
    /GestureGroup\(\s*GestureMode\.Parallel,[\s\S]*PinchGesture\(\{\s*fingers:\s*2\s*\}\)[\s\S]*PanGesture\(\{\s*fingers:\s*1,\s*direction:\s*PanDirection\.All/.test(spreadSurface) &&
    /Image\(this\.imageUrl\)[\s\S]*\.objectFit\(ImageFit\.Contain\)/.test(spreadLayer))
ok('ReaderSpreadSurface expands a single-image spread instead of keeping a blank second pane',
  /this\.SpreadImageLayer\(this\.first, this\.hasFirst/.test(singleSpreadBranch) &&
    !/this\.SpreadImageLayer\(this\.second/.test(singleSpreadBranch))
ok('ReaderSpreadImageLayer remains a passive image/loading layer with no independent transform',
  !/zIndex\(|position\(|\.translate\(|\.scale\(|\.renderGroup\(/.test(spreadLayer) &&
    !/@Local zoomScale|@Local offsetX|@Local offsetY/.test(spreadLayer))

console.log(`✓ reader double-page runtime contract: ${passed} assertions passed`)

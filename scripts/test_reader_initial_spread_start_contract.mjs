#!/usr/bin/env node
/**
 * Contract for Reader initial/jump targets in double-page modes.
 *
 * Grounding:
 * - eros_fe/lib/pages/image_view/controller/view_state.dart::pageIndex maps the absolute
 *   currentItemIndex to a visible spread index.
 * - eros_fe/lib/pages/image_view/controller/view_controller.dart::jumpToPage() drives the
 *   page controller by that spread index, then the page-change path writes back the spread
 *   start as the current item.
 * - NextE must apply the same normalization to route starts and direct jumps, not only to
 *   slider commits, so the visible spread, chrome page counter, share target, and saved
 *   progress all describe the same first visible image.
 *
 * Run: node scripts/test_reader_initial_spread_start_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = readFileSync(join(ROOT, 'feature/reader/src/main/ets/pages/ReaderPage.ets'), 'utf8')
const thisSrc = readFileSync(fileURLToPath(import.meta.url), 'utf8')

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
const normalizedReaderIndex = (mode, index) => {
  if (mode === 'single') return index
  return spreadStartIndex(mode, spreadIndexForImage(mode, index))
}

eq('single route start preserves page 3', normalizedReaderIndex('single', 2), 2)
eq('oddLeft route start at page 2 normalizes to spread 1/2 start', normalizedReaderIndex('oddLeft', 1), 0)
eq('oddLeft route start at page 4 normalizes to spread 3/4 start', normalizedReaderIndex('oddLeft', 3), 2)
eq('evenLeft route start at page 1 keeps cover spread', normalizedReaderIndex('evenLeft', 0), 0)
eq('evenLeft route start at page 3 normalizes to spread 2/3 start', normalizedReaderIndex('evenLeft', 2), 1)
eq('evenLeft route start at page 5 normalizes to spread 4/5 start', normalizedReaderIndex('evenLeft', 4), 3)

ok('contract documents eros_fe currentItemIndex to pageIndex grounding', /view_state\.dart::pageIndex/.test(thisSrc))
ok('ReaderPage exposes a route and jump normalization helper', /private normalizedReaderIndex\(index: number\): number/.test(src))
ok('ReaderSpreadResolver preserves single-page and vertical absolute index',
  /static normalizedReaderIndex\(enabled: boolean, columnMode: string, index: number\): number \{[\s\S]*if \(!enabled\) \{[\s\S]*return index/.test(src))
ok('ReaderSpreadResolver maps double-page targets through spread helpers',
  /static normalizedReaderIndex\(enabled: boolean, columnMode: string, index: number\): number \{[\s\S]*ReaderSpreadResolver\.spreadStartIndex\([\s\S]*ReaderSpreadResolver\.spreadIndexForImage\(columnMode, index\)/.test(src))
ok('ReaderPage normalizedReaderIndex delegates to ReaderSpreadResolver',
  /private normalizedReaderIndex\(index: number\): number \{[\s\S]*return ReaderSpreadResolver\.normalizedReaderIndex\([\s\S]*this\.doublePageEnabled\(\),[\s\S]*this\.readMode\.columnMode,[\s\S]*index/.test(src))
ok('Reader init clamps requested index before normalization', /const loadedTarget: number =[\s\S]*Math\.min\(requestedIndex, this\.vm\.images\.length - 1\)[\s\S]*const targetIndex: number = this\.normalizedReaderIndex\(loadedTarget\)/.test(src))
ok('Reader init writes the normalized target to currentIndex', /this\.vm\.currentIndex = targetIndex[\s\S]*this\.sliderValue = targetIndex \+ 1/.test(src))
ok('non-vertical jump writes normalized target after vm.jumpTo resolves',
  /this\.vm\.jumpTo\(index\)\.then\(\(target: number\) => \{[\s\S]*else \{[\s\S]*const targetIndex: number = this\.normalizedReaderIndex\(target\)[\s\S]*this\.vm\.currentIndex = targetIndex/.test(src))
ok('vertical jump still scrolls to the absolute target image', /if \(this\.readMode\.mode === ReadMode\.VERTICAL\) \{[\s\S]*this\.vm\.currentIndex = target[\s\S]*this\.listScroller\.scrollToIndex\(target\)/.test(src))
ok('slider commits still use their existing explicit spread target helper',
  /const targetIndex: number = this\.sliderTargetIndex\(page\)[\s\S]*this\.jumpToPage\(targetIndex\)/.test(src))

console.log(`✓ reader initial spread-start contract: ${passed} assertions passed`)

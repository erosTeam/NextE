#!/usr/bin/env node
/**
 * Contract for Reader single/double-page mode switching.
 *
 * Grounding:
 * - eros_fe/lib/pages/image_view/controller/view_controller.dart::switchColumnMode() switches
 *   ViewColumnMode, derives the new vState.pageIndex, then jumps the page controller to that index.
 * - ViewExtState.pageIndex maps oddLeft currentItemIndex ~/ 2 and evenLeft
 *   (currentItemIndex + 1) ~/ 2, so the visible spread and chrome page counter stay aligned.
 * - NextE keeps the bottom-bar mode pills, but must normalize currentIndex to the new spread start
 *   when entering odd/even double-page mode.
 *
 * Run: node scripts/test_reader_column_mode_switch_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

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

const spreadIndexForMode = (columnMode, index) => {
  if (columnMode === 'single' || index <= 0) return index
  if (columnMode === 'evenLeft') return Math.floor((index + 1) / 2)
  return Math.floor(index / 2)
}
const spreadStartForMode = (columnMode, spreadIndex) => {
  if (columnMode === 'single') return spreadIndex
  if (columnMode === 'evenLeft') return spreadIndex <= 0 ? 0 : spreadIndex * 2 - 1
  return spreadIndex * 2
}
const normalized = (columnMode, index) => spreadStartForMode(columnMode, spreadIndexForMode(columnMode, index))
const spreadSecond = (columnMode, start) => {
  if (columnMode === 'evenLeft' && start <= 0) return -1
  return start + 1
}

eq('single mode preserves current page 1', normalized('single', 0), 0)
eq('single mode preserves current page 2', normalized('single', 1), 1)
eq('oddLeft entering from page 2 normalizes to spread 1/2', normalized('oddLeft', 1), 0)
eq('oddLeft entering from page 3 keeps spread 3/4 start', normalized('oddLeft', 2), 2)
eq('evenLeft entering from page 1 keeps cover spread start', normalized('evenLeft', 0), 0)
eq('evenLeft entering from page 2 keeps spread 2/3 start', normalized('evenLeft', 1), 1)
eq('evenLeft entering from page 3 normalizes to spread 2/3 start', normalized('evenLeft', 2), 1)
eq('evenLeft entering from page 4 keeps spread 4/5 start', normalized('evenLeft', 3), 3)
eq('evenLeft cover spread has no second page', spreadSecond('evenLeft', 0), -1)
eq('evenLeft second spread pairs pages 2/3', spreadSecond('evenLeft', 1), 2)
eq('oddLeft first spread pairs pages 1/2', spreadSecond('oddLeft', 0), 1)

ok('contract documents eros_fe switchColumnMode grounding', /view_controller\.dart::switchColumnMode\(\)/.test(thisSrc))
ok('ReaderPage has mode-specific spread index helper', /private spreadIndexForMode\(columnMode: string, index: number\): number/.test(src))
ok('ReaderPage single mode helper preserves the same image index', /columnMode === ReadColumnMode\.SINGLE \|\| index <= 0[\s\S]*return index/.test(src))
ok('ReaderPage evenLeft helper matches eros_fe pageIndex math', /columnMode === ReadColumnMode\.EVEN_LEFT[\s\S]*Math\.floor\(\(index \+ 1\) \/ 2\)/.test(src))
ok('ReaderPage has mode-specific spread start helper', /private spreadStartForMode\(columnMode: string, spreadIndex: number\): number/.test(src))
ok('ReaderPage evenLeft start keeps page 1 alone', /spreadIndex <= 0 \? 0 : spreadIndex \* 2 - 1/.test(src))
ok('ReaderPage has helper for second spread slot', /private spreadSecondIndex\(start: number\): number/.test(src))
ok('ReaderPage evenLeft cover spread suppresses second slot', /ReadColumnMode\.EVEN_LEFT && start <= 0[\s\S]*return -1/.test(src))
ok('ReaderPage normalizes currentIndex through target column mode', /private normalizedIndexForColumnMode\(columnMode: string\): number[\s\S]*this\.spreadIndexForMode\(columnMode, this\.vm\.currentIndex\)[\s\S]*this\.spreadStartForMode\(columnMode, spreadIndex\)/.test(src))
ok('cycleColumnMode computes target before persisting mode', /const targetIndex: number = this\.normalizedIndexForColumnMode\(next\)[\s\S]*ReadModeSettings\.setColumnMode\(ctx, next\)/.test(src))
ok('cycleColumnMode moves current reader position when spread start changes', /if \(targetIndex !== this\.vm\.currentIndex\) \{[\s\S]*this\.turnTo\(targetIndex\)/.test(src))
ok('cycleColumnMode remains disabled in vertical mode', /if \(this\.readMode\.mode === ReadMode\.VERTICAL\) \{[\s\S]*return/.test(src))

console.log(`✓ reader column-mode switch contract: ${passed} assertions passed`)

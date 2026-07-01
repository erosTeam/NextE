#!/usr/bin/env node
/**
 * Contract: route starts and jumps preserve absolute image page. Double-page
 * math maps that absolute index to a Swiper spread index only for display.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = readFileSync(join(ROOT, 'feature/reader/src/main/ets/pages/ReaderPage.ets'), 'utf8')

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
  if (index <= 0) return 0
  if (mode === 'evenLeft') return Math.floor((index + 1) / 2)
  return Math.floor(index / 2)
}

eq('oddLeft page 4 absolute index maps to spread index 1', spreadIndexForImage('oddLeft', 3), 1)
eq('evenLeft page 5 absolute index maps to spread index 2', spreadIndexForImage('evenLeft', 4), 2)

ok('Reader no longer exposes normalizedReaderIndex for progress writes',
  !/normalizedReaderIndex/.test(src) &&
    !/normalizedIndexForColumnMode/.test(src))
ok('Reader init clamps requested index and writes that absolute target',
  /const loadedTarget: number = total > 0 \? Math\.min\(requestedIndex, total - 1\) : 0[\s\S]*const targetIndex: number = loadedTarget[\s\S]*this\.vm\.currentIndex = targetIndex[\s\S]*this\.sliderValue = targetIndex \+ 1/.test(src))
ok('Reader init maps absolute target to pager index only after currentIndex is set',
  /this\.readerPagerIndex = this\.readerPagerIndexFor\(targetIndex\)/.test(src) &&
    /this\.syncReaderPagerToIndex\(targetIndex, false\)/.test(src))
ok('turnTo writes the absolute target to page state in horizontal mode',
  /private turnTo\(target: number\): void \{[\s\S]*this\.readerPagerIndex = this\.readerPagerIndexFor\(target\)[\s\S]*this\.vm\.onPageChange\(target\)[\s\S]*this\.syncReaderPagerToIndex\(target, false\)/.test(src))
ok('jumpToPage writes the absolute target after vm.jumpTo resolves',
  /this\.vm\.jumpTo\(index\)\.then\(\(target: number\) => \{[\s\S]*this\.readerPagerIndex = this\.readerPagerIndexFor\(target\)[\s\S]*this\.vm\.currentIndex = target[\s\S]*this\.syncReaderPagerToIndex\(target, false\)/.test(src))
ok('vertical jump still scrolls to the absolute target image',
  /if \(this\.readMode\.mode === ReadMode\.VERTICAL\) \{[\s\S]*this\.vm\.currentIndex = target[\s\S]*this\.listScroller\.scrollToIndex\(target\)/.test(src))

console.log(`✓ reader initial absolute-index contract: ${passed} assertions passed`)

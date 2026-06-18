#!/usr/bin/env node
/**
 * Contract for Reader vertical-mode index sync.
 *
 * Bug class: when the user enters Reader at a later page (preview tap, progress resume, or slider jump)
 * and the reader is in vertical mode, the List must mount at vm.currentIndex. Otherwise the counter can
 * say "26 / 138" while the visible List starts at page 1.
 *
 * Run: node scripts/test_reader_vertical_initial_index_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = readFileSync(join(ROOT, 'feature/reader/src/main/ets/pages/ReaderPage.ets'), 'utf8')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok(
  'vertical List mounts at the current reader index',
  /VerticalReader\(\)[\s\S]*List\(\{\s*initialIndex:\s*this\.vm\.currentIndex,\s*scroller:\s*this\.listScroller\s*\}\)/.test(src),
)
ok(
  'vertical jump still scrolls the mounted List to target',
  /jumpToPage\(index: number\)[\s\S]*ReadMode\.VERTICAL[\s\S]*this\.listScroller\.scrollToIndex\(target\)/.test(src),
)
ok(
  'vertical in-range tap navigation still scrolls the mounted List to target',
  /turnTo\(target: number\)[\s\S]*ReadMode\.VERTICAL[\s\S]*this\.listScroller\.scrollToIndex\(target\)/.test(src),
)
ok(
  'horizontal reader remains Swiper-index driven',
  /HorizontalReader\(\)[\s\S]*Swiper\(\)[\s\S]*\.index\(this\.vm\.currentIndex\)/.test(src),
)

console.log(`✓ reader vertical initial-index contract: ${passed} assertions passed`)

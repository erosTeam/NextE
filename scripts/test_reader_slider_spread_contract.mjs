#!/usr/bin/env node
/**
 * Contract: slider commits target absolute image pages. Spread math is only a
 * display mapping inside readerPagerIndexFor().
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

const sliderTargetIndex = (page) => page - 1
eq('slider page 1 targets image index 0', sliderTargetIndex(1), 0)
eq('slider page 3 targets image index 2', sliderTargetIndex(3), 2)

ok('ReaderSpreadResolver converts 1-based slider page to absolute 0-based image index',
  /static sliderTargetIndex\(page: number\): number \{[\s\S]*return page - 1/.test(src))
ok('ReaderPage sliderTargetIndex delegates without double-page normalization',
  /private sliderTargetIndex\(page: number\): number \{[\s\S]*return ReaderSpreadResolver\.sliderTargetIndex\(page\)/.test(src) &&
    !/ReaderSpreadResolver\.sliderTargetIndex\(this\.doublePageEnabled/.test(src))
ok('Slider moving and commit both use the same absolute helper',
  /this\.scrollThumbStripTo\(this\.sliderTargetIndex\(page\), true\)/.test(src) &&
    /const targetIndex: number = this\.sliderTargetIndex\(page\)[\s\S]*this\.jumpToPage\(targetIndex\)/.test(src))
ok('double-page pager mapping remains isolated in readerPagerIndexFor',
  /private readerPagerIndexFor\(index: number\): number \{[\s\S]*return this\.doublePageEnabled\(\) \? this\.spreadIndexForImage\(index\) : index/.test(src))

console.log(`✓ reader slider absolute-index contract: ${passed} assertions passed`)

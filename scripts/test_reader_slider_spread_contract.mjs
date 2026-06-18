#!/usr/bin/env node
/**
 * Contract for Reader slider commits in double-page modes.
 *
 * Grounding:
 * - eros_fe/lib/pages/image_view/controller/view_controller.dart::handOnSliderChangedEnd()
 *   stores the absolute image index, then jumpToPage() maps through ViewExtState.pageIndex.
 * - In double-page mode, NextE's visible Swiper index is a spread index, so a slider commit to an
 *   image inside a spread must normalize to that spread's first visible image index.
 *
 * Run: node scripts/test_reader_slider_spread_contract.mjs
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
  if (mode === 'single' || index <= 0) return 0
  if (mode === 'evenLeft') return Math.floor((index + 1) / 2)
  return Math.floor(index / 2)
}
const spreadStartIndex = (mode, spreadIndex) => {
  if (mode === 'single') return spreadIndex
  if (mode === 'evenLeft') return spreadIndex <= 0 ? 0 : spreadIndex * 2 - 1
  return spreadIndex * 2
}
const sliderTargetIndex = (mode, page) => {
  const index = page - 1
  if (mode === 'single') return index
  return spreadStartIndex(mode, spreadIndexForImage(mode, index))
}

eq('single slider page 1 targets image index 0', sliderTargetIndex('single', 1), 0)
eq('single slider page 3 targets image index 2', sliderTargetIndex('single', 3), 2)
eq('oddLeft slider page 2 stays on spread 1/2 start', sliderTargetIndex('oddLeft', 2), 0)
eq('oddLeft slider page 3 targets spread 3/4 start', sliderTargetIndex('oddLeft', 3), 2)
eq('evenLeft slider page 1 targets cover spread', sliderTargetIndex('evenLeft', 1), 0)
eq('evenLeft slider page 2 targets spread 2/3 start', sliderTargetIndex('evenLeft', 2), 1)
eq('evenLeft slider page 3 normalizes back to spread 2/3 start', sliderTargetIndex('evenLeft', 3), 1)
eq('evenLeft slider page 4 targets spread 4/5 start', sliderTargetIndex('evenLeft', 4), 3)

ok('ReaderPage exposes sliderTargetIndex helper', /private sliderTargetIndex\(page: number\): number/.test(src))
ok('sliderTargetIndex converts 1-based slider page to 0-based image index', /const index: number = page - 1/.test(src))
ok('sliderTargetIndex leaves single page and vertical slider commits absolute', /if \(!this\.doublePageEnabled\(\)\) \{[\s\S]*return index/.test(src))
ok('sliderTargetIndex normalizes double-page commits through spread helpers', /return this\.spreadStartIndex\(this\.spreadIndexForImage\(index\)\)/.test(src))
ok('Slider commit jumps to sliderTargetIndex instead of raw page minus one', /this\.jumpToPage\(this\.sliderTargetIndex\(page\)\)/.test(src))
ok('Slider commit no longer jumps directly to raw slider page', !/this\.jumpToPage\(page - 1\)/.test(src))

console.log(`✓ reader slider spread contract: ${passed} assertions passed`)

#!/usr/bin/env node
/**
 * Contract for Reader tap/adjacent-page navigation over sparse preview-page gaps.
 *
 * A target can be inside ReaderViewModel.images while still being only a placeholder produced by a
 * direct later-preview-page load. ReaderPage must treat that slot as unloaded until it has a real /s/
 * image-page URL; otherwise ReaderImagePage resolves an empty URL and the reader shows a failure.
 *
 * Run: node scripts/test_reader_placeholder_gap_turn_contract.mjs
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
const eq = (name, got, expected) => {
  assert.deepStrictEqual(got, expected, name)
  passed++
}

function hasPreviewAt(images, index) {
  if (index < 0 || index >= images.length) {
    return false
  }
  return images[index].sUrl.length > 0
}

function turnDecision(images, target) {
  if (target < 0) {
    return 'noop'
  }
  if (target >= images.length || !hasPreviewAt(images, target)) {
    return 'jump'
  }
  return 'direct'
}

{
  const images = []
  for (let i = 0; i < 40; i++) {
    images.push({ page: i + 1, sUrl: i < 20 ? `https://e-hentai.org/s/p${i + 1}/g-${i + 1}` : '' })
  }
  images[36] = { page: 37, sUrl: 'https://e-hentai.org/s/p37/g-37' }
  eq('later target page can be loaded while previous page remains a placeholder', hasPreviewAt(images, 36), true)
  eq('placeholder gap page is inside images[] but is not renderable', hasPreviewAt(images, 35), false)
  eq('tap next/prev into a placeholder gap must route through jump loading', turnDecision(images, 35), 'jump')
  eq('tap next/prev onto a real preview slot can use direct navigation', turnDecision(images, 36), 'direct')
  eq('target beyond current sparse array still uses jump loading', turnDecision(images, 60), 'jump')
  eq('target before page zero is ignored', turnDecision(images, -1), 'noop')
}

const vmSrc = read('feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets')
ok('Reader exposes hasPreviewAt to page navigation', /\n  hasPreviewAt\(index: number\): boolean \{/.test(vmSrc))
ok('hasPreviewAt checks the actual /s/ image-page URL', /return this\.images\[index\]\.sUrl\.length > 0/.test(vmSrc))

const pageSrc = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
ok('ReaderPage turnTo treats sparse placeholders as unloaded', /target >= this\.vm\.images\.length \|\| !this\.vm\.hasPreviewAt\(target\)/.test(pageSrc))
ok('ReaderPage placeholder route goes through jumpToPage', /if \(target >= this\.vm\.images\.length \|\| !this\.vm\.hasPreviewAt\(target\)\) \{[\s\S]*this\.jumpToPage\(target\)/.test(pageSrc))
ok('ReaderPage direct vertical path only runs after preview presence check', /this\.vm\.hasPreviewAt\(target\)[\s\S]*if \(this\.readMode\.mode === ReadMode\.VERTICAL\)/.test(pageSrc))

const imageResolveSrc = read('shared/src/main/ets/services/ImageResolveService.ets')
ok('ImageResolveService still rejects empty /s/ URLs, so UI must avoid placeholders', /image\.sUrl\.length === 0[\s\S]*image has no \/s\/ page url/.test(imageResolveSrc))

console.log(`✓ reader placeholder gap turn contract: ${passed} assertions passed`)

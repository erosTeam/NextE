#!/usr/bin/env node
/**
 * Contract test for the reader's far-jump preview-page loading (ReaderViewModel.ensureLoaded).
 *
 * `jumpPages` is copy-equal to the from/to computation in ensureLoaded: a far jump fetches the
 * CONTIGUOUS set of missing preview pages [previewPage+1 .. targetPage], capped by the gallery
 * length, and issues them CONCURRENTLY (Promise.all) instead of one-by-one. The set fetched is
 * identical to the old sequential loop's coverage — only the scheduling changed — so this also
 * guards against the parallel path skipping or duplicating a page.
 *
 * Run: node scripts/test_reader_jump_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// Mirror of ensureLoaded's page-range computation (the parallel fetch set). Returns the ordered list
// of preview-page numbers to fetch, or [] when the target is already loaded / past the end.
function jumpPages(previewPage, perPage, targetIndex, fileCount, loadedLen) {
  if (loadedLen > targetIndex) return [] // already loaded through the target
  if (perPage <= 0) return null // sequential fallback (caller crawls one at a time)
  const from = previewPage + 1
  const lastPage = fileCount > 0 ? Math.ceil(fileCount / perPage) - 1 : Math.floor(targetIndex / perPage)
  const to = Math.min(Math.floor(targetIndex / perPage), lastPage)
  const pages = []
  for (let p = from; p <= to; p++) pages.push(p)
  return pages
}

// The OLD sequential loop fetched page-by-page until images.length > targetIndex. Reconstruct which
// pages that visited, to prove the parallel set has IDENTICAL coverage (no skip/dup/gap).
function sequentialPages(previewPage, perPage, targetIndex, fileCount) {
  const pages = []
  let loaded = (previewPage + 1) * perPage
  let p = previewPage + 1
  const totalPages = fileCount > 0 ? Math.ceil(fileCount / perPage) : Infinity
  while (loaded <= targetIndex && p < totalPages) {
    pages.push(p)
    loaded += perPage
    p++
  }
  return pages
}

let failures = 0
const eqArr = (got, want, label) => {
  const a = JSON.stringify(got), b = JSON.stringify(want)
  if (a !== b) { console.error(`✗ ${label}\n    got:  ${a}\n    want: ${b}`); failures++ }
}
const ok = (c, label) => { if (!c) { console.error(`✗ ${label}`); failures++ } }

// Far jump page 0 → index 500 (perPage 20, 1978-page gallery): fetch preview pages 1..25 together.
eqArr(jumpPages(0, 20, 500, 1978, 20), [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25], 'far jump 0→500: contiguous pages 1..25')
// Already loaded through the target → no fetch.
eqArr(jumpPages(25, 20, 500, 1978, 520), [], 'target already loaded → no fetch')
// Tail cap: jump beyond the gallery length must NOT request empty tail pages.
eqArr(jumpPages(0, 20, 5000, 1978, 20), sequentialPages(0, 20, 5000, 1978), 'tail jump capped to last real page (== sequential coverage)')
ok(jumpPages(0, 20, 5000, 1978, 20).at(-1) === Math.ceil(1978/20)-1, 'tail jump stops at last preview page (98)')
// perPage 40 (large preview mode): index 200 → pages 1..5.
eqArr(jumpPages(0, 40, 200, 1978, 40), [1,2,3,4,5], 'perPage 40: index 200 → pages 1..5')
// perPage unknown → sequential fallback signal.
ok(jumpPages(-1, 0, 100, 1978, 0) === null, 'perPage unknown → null (sequential fallback)')

// Coverage equivalence: the parallel set must equal the old sequential set across many positions.
for (const target of [0, 19, 20, 21, 100, 499, 500, 999, 1977]) {
  const par = jumpPages(0, 20, target, 1978, 20)
  if (par === null || par.length === 0) continue
  eqArr(par, sequentialPages(0, 20, target, 1978), `parallel == sequential coverage @ index ${target}`)
}

// Structural wiring
const VM = readFileSync(join(ROOT, 'feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets'), 'utf8')
ok(VM.includes('Promise.all('), 'VM: far jump uses Promise.all (concurrent fetch)')
ok(VM.includes('this.perPage = more.length'), 'VM: perPage inferred from first loaded page')
ok(VM.includes('private async ensureLoaded('), 'VM: ensureLoaded (parallel-capable)')
ok(VM.includes('ensureSequential('), 'VM: sequential fallback retained for unknown perPage')
ok(VM.includes('await this.ensureLoaded(index)'), 'VM: jumpTo uses ensureLoaded')
ok(VM.includes('Math.ceil(this.fileCount / this.perPage)'), 'VM: tail page capped by fileCount')

if (failures > 0) { console.error(`\n✗ reader jump contract: ${failures} failure(s)`); process.exit(1) }
console.log('✓ reader jump contract: far-jump fetches the contiguous capped page set concurrently (== sequential coverage)')

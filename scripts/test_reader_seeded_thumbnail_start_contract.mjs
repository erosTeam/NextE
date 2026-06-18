#!/usr/bin/env node
/**
 * Contract for opening Reader from later AllThumbnails pages.
 *
 * The bug class: tapping a thumbnail from page 2/3 of the preview grid must not boot the Reader with
 * only page-1 previews and then visually snap to the first pages. The Reader route params carry the
 * already-loaded preview entries (absolute page + /s/ image-page URL), and ReaderViewModel seeds its
 * image list before calling ensureLoaded.
 *
 * Run: node scripts/test_reader_seeded_thumbnail_start_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

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

// Mirror the seeded-start model: loaded preview rows are absolute pages with /s/ URLs.
const makeImages = (count) =>
  Array.from({ length: count }, (_v, i) => ({
    page: i + 1,
    sUrl: `https://e-hentai.org/s/key${i + 1}/3989982-${i + 1}`,
  }))

function applySeed(seedImages, seedLoadedPages, seedPerPage, fileCount) {
  if (seedImages.length === 0 || seedLoadedPages <= 0) {
    return { images: [], previewPage: -1, perPage: 0, exhausted: false }
  }
  const images = seedImages.map((img) => ({ ...img }))
  return {
    images,
    previewPage: Math.max(0, seedLoadedPages - 1),
    perPage: seedPerPage > 0 ? seedPerPage : seedImages.length,
    exhausted: fileCount > 0 && images.length >= fileCount,
  }
}

{
  const seed = makeImages(40)
  const state = applySeed(seed, 2, 20, 138)
  eq('seed keeps already-loaded absolute pages', state.images.map((i) => i.page).slice(35, 38), [36, 37, 38])
  ok('target page has its /s/ URL available immediately', state.images[36].sUrl.endsWith('/3989982-37'))
  eq('previewPage points at last loaded preview page', state.previewPage, 1)
  eq('perPage preserves first preview page size', state.perPage, 20)
  eq('not exhausted when gallery has more pages', state.exhausted, false)
}

{
  const state = applySeed(makeImages(20), 1, 20, 20)
  eq('exact full-gallery seed marks exhausted', state.exhausted, true)
}

const paramsSrc = read('shared/src/main/ets/model/RouteParams.ets')
ok('ReaderParams carries seedImages', /seedImages:\s*EhGalleryImage\[\]\s*=\s*\[\]/.test(paramsSrc))
ok('ReaderParams carries seedLoadedPages', /seedLoadedPages:\s*number\s*=\s*0/.test(paramsSrc))
ok('ReaderParams carries seedPerPage', /seedPerPage:\s*number\s*=\s*0/.test(paramsSrc))

const allVmSrc = read('feature/gallery/src/main/ets/viewmodel/AllThumbnailsViewModel.ets')
ok('AllThumbnails VM exposes copied loaded images', /loadedImages\(\):\s*EhGalleryImage\[\][\s\S]*img\.copy\(\)/.test(allVmSrc))
ok('AllThumbnails VM exposes loaded preview page count', /loadedPreviewPages\(\):\s*number[\s\S]*return this\.loadedPages/.test(allVmSrc))
ok('AllThumbnails VM preserves first page count', /firstPageCount/.test(allVmSrc) && /this\.firstPageCount = p\.firstPage\.length/.test(allVmSrc))

const allPageSrc = read('feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets')
ok('AllThumbnails passes absolute clicked index', /this\.openReader\(img\.page - 1\)/.test(allPageSrc))
ok('AllThumbnails passes loaded image seed to ReaderParams', /new ReaderParams\([\s\S]*this\.vm\.loadedImages\(\)/.test(allPageSrc))
ok('AllThumbnails passes seed loaded page count', /this\.vm\.loadedPreviewPages\(\)/.test(allPageSrc))
ok('AllThumbnails passes seed per-page count', /this\.vm\.seedPerPage\(\)/.test(allPageSrc))

const readerPageSrc = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
ok('ReaderPage forwards seed params into VM init', /this\.vm\.init\(p\.gid, p\.token, p\.fileCount, p\.index, p\.seedImages, p\.seedLoadedPages, p\.seedPerPage\)/.test(readerPageSrc))
ok('ReaderPage preserves requested route index across early vertical onScrollIndex callbacks', /const requestedIndex: number = p\.index/.test(readerPageSrc))
ok('ReaderPage re-syncs current index and slider from requested index after async VM init', /const targetIndex: number =[\s\S]*Math\.min\(requestedIndex, this\.vm\.images\.length - 1\)[\s\S]*this\.vm\.currentIndex = targetIndex[\s\S]*this\.sliderValue = targetIndex \+ 1/.test(readerPageSrc))
ok('ReaderPage scrolls vertical mode to the requested target after async VM init', /this\.readMode\.mode === ReadMode\.VERTICAL[\s\S]*this\.listScroller\.scrollToIndex\(targetIndex\)/.test(readerPageSrc))

const readerVmSrc = read('feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets')
ok('ReaderViewModel accepts seed args', /seedImages:\s*EhGalleryImage\[\]\s*=\s*\[\][\s\S]*seedLoadedPages:\s*number\s*=\s*0[\s\S]*seedPerPage:\s*number\s*=\s*0/.test(readerVmSrc))
ok('ReaderViewModel applies seed before ensureLoaded', /this\.applySeed\(seedImages, seedLoadedPages, seedPerPage\)[\s\S]*await this\.ensureLoaded\(startIndex \+ 2\)/.test(readerVmSrc))
ok('ReaderViewModel copies seed images', /private applySeed[\s\S]*seeded\.push\(img\.copy\(\)\)/.test(readerVmSrc))
ok('ReaderViewModel sets previewPage from seedLoadedPages', /this\.previewPage = Math\.max\(0, seedLoadedPages - 1\)/.test(readerVmSrc))
ok('ReaderViewModel sets perPage from seedPerPage', /this\.perPage = seedPerPage > 0 \? seedPerPage : seedImages\.length/.test(readerVmSrc))

console.log(`✓ reader seeded thumbnail start contract: ${passed} assertions passed`)

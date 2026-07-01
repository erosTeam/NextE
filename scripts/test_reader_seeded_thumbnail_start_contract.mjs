#!/usr/bin/env node
/**
 * Contract for opening Reader from later AllThumbnails pages.
 *
 * The bug class: tapping a thumbnail from page 2/3 of the preview grid must not boot the Reader with
 * only page-1 previews and then visually snap to the first pages. The Reader route params carry the
 * already-loaded preview entries (absolute page + /s/ image-page URL), and ReaderViewModel seeds its
 * image list before loading the requested target first. Neighbor pages are warm-up only.
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

function applySeed(seedImages, seedLoadedPages, seedPerPage, fileCount, seedPreviewPages = []) {
  if (seedImages.length === 0 || seedLoadedPages <= 0) {
    return { images: [], previewPage: -1, perPage: 0, loadedPreviewPages: [], exhausted: false }
  }
  const images = []
  for (const img of seedImages) {
    const targetIndex = img.page > 0 ? img.page - 1 : images.length
    for (let i = images.length; i <= targetIndex; i++) {
      images.push({ page: i + 1, sUrl: '' })
    }
    images[targetIndex] = { ...img }
  }
  const loadedPreviewPages = seedPreviewPages.length > 0
    ? seedPreviewPages.slice()
    : Array.from({ length: seedLoadedPages }, (_v, i) => i)
  let previewPage = -1
  while (loadedPreviewPages.includes(previewPage + 1)) previewPage++
  return {
    images,
    previewPage,
    perPage: seedPerPage > 0 ? seedPerPage : seedImages.length,
    loadedPreviewPages,
    exhausted: fileCount > 0 && images.length >= fileCount &&
      images.slice(0, fileCount).every((img) => img.sUrl.length > 0),
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
  const seed = makeImages(20).concat(makeImages(20).map((img) => ({
    page: img.page + 80,
    sUrl: `https://e-hentai.org/s/key${img.page + 80}/3989982-${img.page + 80}`,
  })))
  const state = applySeed(seed, 2, 20, 138, [0, 4])
  eq('sparse seed pads gaps so later previews stay at absolute reader indices', state.images[85].page, 86)
  ok('sparse seed target page has its /s/ URL at its absolute index immediately',
    state.images[85].sUrl.endsWith('/3989982-86'))
  eq('sparse seed keeps an unloaded placeholder for a missing gap page', state.images[30], { page: 31, sUrl: '' })
  eq('sparse seed marks loaded preview pages exactly', state.loadedPreviewPages, [0, 4])
  eq('sparse seed contiguous pointer stops before unloaded gaps', state.previewPage, 0)
}

function applySeedImagePageUrl(images, index, seedImagePageUrl) {
  if (index < 0 || seedImagePageUrl.length === 0 || !/\/s\/[0-9a-f]+\//.test(seedImagePageUrl)) {
    return images
  }
  const next = images.map((img) => ({ ...img }))
  for (let i = next.length; i <= index; i++) {
    next.push({ page: i + 1, sUrl: '' })
  }
  next[index] = { ...next[index], page: index + 1, sUrl: seedImagePageUrl }
  return next
}

{
  const images = applySeedImagePageUrl([], 86, 'https://e-hentai.org/s/abc123/3989982-87')
  eq('seed image page URL creates the tapped absolute slot', images[86], {
    page: 87,
    sUrl: 'https://e-hentai.org/s/abc123/3989982-87',
  })
  eq('seed image page URL pads earlier unloaded slots as placeholders', images[0], { page: 1, sUrl: '' })
}

{
  const state = applySeed(makeImages(20), 1, 20, 20)
  eq('exact full-gallery seed marks exhausted', state.exhausted, true)
}

{
  const seed = [makeImages(1)[0], {
    page: 100,
    sUrl: 'https://e-hentai.org/s/key100/3989982-100',
  }]
  const state = applySeed(seed, 2, 20, 100, [0, 4])
  eq('sparse seed reaching fileCount does not mark gaps exhausted', state.exhausted, false)
}

const paramsSrc = read('shared/src/main/ets/model/RouteParams.ets')
ok('ReaderParams carries seedImages', /seedImages:\s*EhGalleryImage\[\]\s*=\s*\[\]/.test(paramsSrc))
ok('ReaderParams carries seedLoadedPages', /seedLoadedPages:\s*number\s*=\s*0/.test(paramsSrc))
ok('ReaderParams carries seedPerPage', /seedPerPage:\s*number\s*=\s*0/.test(paramsSrc))
ok('ReaderParams carries exact seed preview page markers', /seedPreviewPages:\s*number\[\]\s*=\s*\[\]/.test(paramsSrc))
ok('ReaderParams carries exact tapped image-page URL', /seedImagePageUrl:\s*string\s*=\s*''/.test(paramsSrc))

const allVmSrc = read('feature/gallery/src/main/ets/viewmodel/AllThumbnailsViewModel.ets')
ok('AllThumbnails VM exposes copied loaded images', /loadedImages\(\):\s*EhGalleryImage\[\][\s\S]*img\.copy\(\)/.test(allVmSrc))
ok('AllThumbnails VM exposes loaded preview page count', /loadedPreviewPages\(\):\s*number[\s\S]*return this\.loadedPages/.test(allVmSrc))
ok('AllThumbnails VM exposes exact loaded preview page numbers', /loadedPreviewPageNumbers\(\):\s*number\[\][\s\S]*this\.loadedPreviewPageMarkers/.test(allVmSrc))
ok('AllThumbnails VM preserves first page count', /firstPageCount/.test(allVmSrc) && /this\.firstPageCount = p\.firstPage\.length/.test(allVmSrc))

const allPageSrc = read('feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets')
ok('AllThumbnails opens Reader from the tapped image object', /this\.openReader\(img\)/.test(allPageSrc))
ok('AllThumbnails derives Reader index from absolute image page', /const pageZeroBased: number = img\.page > 0 \? img\.page - 1 : 0/.test(allPageSrc))
ok('AllThumbnails passes loaded image seed to ReaderParams', /new ReaderParams\([\s\S]*this\.vm\.loadedImages\(\)/.test(allPageSrc))
ok('AllThumbnails passes seed loaded page count', /this\.vm\.loadedPreviewPages\(\)/.test(allPageSrc))
ok('AllThumbnails passes seed per-page count', /this\.vm\.seedPerPage\(\)/.test(allPageSrc))
ok('AllThumbnails passes exact loaded preview page markers', /this\.vm\.loadedPreviewPageNumbers\(\)/.test(allPageSrc))
ok('AllThumbnails passes tapped /s/ image-page URL as Reader seed', /this\.vm\.loadedPreviewPageNumbers\(\),[\s\S]*img\.sUrl/.test(allPageSrc))

const readerPageSrc = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
ok('ReaderPage forwards seed params into VM init', /this\.vm\.init\([\s\S]*p\.seedImages,[\s\S]*p\.seedLoadedPages,[\s\S]*p\.seedPerPage,[\s\S]*p\.seedPreviewPages,[\s\S]*p\.seedImagePageUrl/.test(readerPageSrc))
ok('ReaderPage preserves requested route index across early vertical onScrollIndex callbacks', /const requestedIndex: number = p\.index/.test(readerPageSrc))
ok('ReaderPage re-syncs current index and slider from requested absolute index after async VM init', /const total: number = this\.vm\.totalPages\(\)[\s\S]*const loadedTarget: number = total > 0 \? Math\.min\(requestedIndex, total - 1\) : 0[\s\S]*const targetIndex: number = loadedTarget[\s\S]*this\.vm\.currentIndex = targetIndex[\s\S]*this\.sliderValue = targetIndex \+ 1/.test(readerPageSrc))
ok('ReaderPage scrolls vertical mode to the requested target after async VM init', /this\.readMode\.mode === ReadMode\.VERTICAL[\s\S]*this\.listScroller\.scrollToIndex\(targetIndex\)/.test(readerPageSrc))

const readerVmSrc = read('feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets')
ok('ReaderViewModel accepts seed args', /seedImages:\s*EhGalleryImage\[\]\s*=\s*\[\][\s\S]*seedLoadedPages:\s*number\s*=\s*0[\s\S]*seedPerPage:\s*number\s*=\s*0[\s\S]*seedPreviewPages:\s*number\[\]\s*=\s*\[\][\s\S]*seedImagePageUrl:\s*string\s*=\s*''/.test(readerVmSrc))
ok('ReaderViewModel applies seed before target-first ensureLoaded', /this\.applySeed\(seedImages, seedLoadedPages, seedPerPage, seedPreviewPages\)[\s\S]*this\.applySeedImagePageUrl\(startIndex, seedImagePageUrl\)[\s\S]*await this\.ensureLoaded\(startIndex, 'init-start'\)/.test(readerVmSrc))
ok('ReaderViewModel does not block initial reader start on neighbor preload', !/await this\.ensureLoaded\(startIndex \+ 2\)/.test(readerVmSrc))
ok('ReaderViewModel warms neighbor previews only after currentIndex is settled', /this\.currentIndex = total > 0 \? Math\.min\(startIndex, total - 1\) : 0[\s\S]*this\.precacheFrom\(this\.currentIndex\)[\s\S]*this\.warmPreviewAhead\(this\.currentIndex\)/.test(readerVmSrc))
ok('ReaderViewModel places seed images by absolute page index', /const targetIndex: number = img\.page > 0 \? img\.page - 1 : order[\s\S]*copy\.page = targetIndex \+ 1[\s\S]*this\.previewImagesByIndex\.set\(targetIndex, copy\)/.test(readerVmSrc))
ok('ReaderViewModel marks explicit sparse seed preview pages', /seedPreviewPages\.length > 0[\s\S]*this\.markPreviewPageLoaded\(p\)/.test(readerVmSrc))
ok('ReaderViewModel advances contiguous pointer from loaded seed markers', /this\.advanceContiguousPreviewPage\(\)/.test(readerVmSrc))
ok('ReaderViewModel sets perPage from seedPerPage', /this\.perPage = seedPerPage > 0 \? seedPerPage : seedImages\.length/.test(readerVmSrc))
ok('ReaderViewModel only marks seed exhausted when every gallery slot has a /s/ URL',
  /private seedCoversWholeGallery\(\): boolean[\s\S]*this\.fileCount <= 0[\s\S]*for \(let i: number = 0; i < this\.fileCount; i\+\+\)[\s\S]*!this\.hasPreviewAt\(i\)[\s\S]*return true/.test(readerVmSrc))
ok('ReaderViewModel creates a target slot from seedImagePageUrl', /private applySeedImagePageUrl[\s\S]*EhUrlRouter\.parseImagePage\(seedImagePageUrl\)[\s\S]*this\.previewImagesByIndex\.set\(index, img\)/.test(readerVmSrc))
ok('ReaderViewModel resolves the seed image page URL before normal target loading', /await this\.resolveSeedImage\(startIndex, imagePageSeed\)[\s\S]*await this\.ensureLoaded\(startIndex, 'init-start'\)/.test(readerVmSrc))
ok('ReaderViewModel caches resolved seed image back into the target slot', /private async resolveSeedImage[\s\S]*ImageResolveService\.getInstance\(\)\.resolve\(image\)[\s\S]*this\.applyExactSeed\(index, image\)/.test(readerVmSrc))

console.log(`✓ reader seeded thumbnail start contract: ${passed} assertions passed`)

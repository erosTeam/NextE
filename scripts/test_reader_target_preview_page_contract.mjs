#!/usr/bin/env node
/**
 * Contract for Reader starts/jumps that target a later image whose preview page is not contiguous yet.
 *
 * eros_fe does not derive a full image URL from the gallery URL. It first loads the thumbnail/preview
 * page containing the target `ser`, keeps that entry's /s/ image-page URL, and lets the reader resolve
 * the real full image from that page. NextE must preserve that behavior for image-page deep links,
 * saved-progress starts, and later all-thumbnails taps.
 *
 * Run: node scripts/test_reader_target_preview_page_contract.mjs
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

const makePreviewPage = (previewPage, perPage) =>
  Array.from({ length: perPage }, (_v, i) => {
    const page = previewPage * perPage + i + 1
    return {
      page,
      sUrl: `https://e-hentai.org/s/key${page}/3989982-${page}`,
    }
  })

function mergePreviewPage(images, previewPage, pageImages, perPage, loadedPages, contiguousPreviewPage) {
  const next = images.map((img) => ({ ...img }))
  const startIndex = previewPage * (perPage > 0 ? perPage : pageImages.length)
  const minLength = startIndex + pageImages.length
  for (let i = next.length; i < minLength; i++) {
    next.push({ page: i + 1, sUrl: '' })
  }
  for (let i = 0; i < pageImages.length; i++) {
    const img = pageImages[i]
    const targetIndex = img.page > 0 ? img.page - 1 : startIndex + i
    for (let j = next.length; j <= targetIndex; j++) {
      next.push({ page: j + 1, sUrl: '' })
    }
    next[targetIndex] = { ...img }
  }
  const marked = loadedPages.includes(previewPage) ? loadedPages : loadedPages.concat([previewPage])
  let contiguous = contiguousPreviewPage
  while (marked.includes(contiguous + 1)) {
    contiguous++
  }
  return { images: next, loadedPages: marked, contiguousPreviewPage: contiguous }
}

{
  let state = {
    images: makePreviewPage(0, 20),
    loadedPages: [0],
    contiguousPreviewPage: 0,
  }
  state = mergePreviewPage(state.images, 4, makePreviewPage(4, 20), 20, state.loadedPages, state.contiguousPreviewPage)
  eq('target-page direct fetch pads the list up to the target preview page', state.images.length, 100)
  eq('target absolute page is written at its zero-based index', state.images[86].page, 87)
  ok('target absolute page carries the /s/ image-page URL immediately', state.images[86].sUrl.endsWith('/3989982-87'))
  eq('unfetched gap keeps page-number placeholders', state.images[25], { page: 26, sUrl: '' })
  eq('contiguous pointer does not skip over unfetched gaps', state.contiguousPreviewPage, 0)
  eq('loaded page marker remembers the direct target page', state.loadedPages, [0, 4])
  state = mergePreviewPage(state.images, 1, makePreviewPage(1, 20), 20, state.loadedPages, state.contiguousPreviewPage)
  eq('sequential load can fill the first gap later', state.images[25].page, 26)
  ok('filled gap gains its /s/ image-page URL', state.images[25].sUrl.endsWith('/3989982-26'))
  eq('contiguous pointer advances only through continuous loaded preview pages', state.contiguousPreviewPage, 1)
}

const erosController = read('../../eros_fe/lib/pages/gallery/controller/gallery_page_controller.dart')
ok('eros_fe has direct target-ser preview-page loader', /Future<void> loadImagesForSer\(int ser/.test(erosController))
ok('eros_fe computes target preview page from ser and first page length', /final int page = \(ser - 1\) ~\/ flen/.test(erosController))
ok('eros_fe requests exactly that preview page', /getGalleryImageList\([\s\S]*page: page/.test(erosController))

const vmSrc = read('feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets')
ok('Reader tracks non-contiguous loaded preview pages', /private loadedPreviewPages: number\[\] = \[\]/.test(vmSrc))
ok('Reader resets loaded preview page tracking on init', /this\.loadedPreviewPages = \[\]/.test(vmSrc))
ok('Reader accepts exact sparse seed preview page markers', /seedPreviewPages:\s*number\[\]\s*=\s*\[\]/.test(vmSrc))
ok('Reader seeds explicit preview page markers when provided', /seedPreviewPages\.length > 0[\s\S]*this\.markPreviewPageLoaded\(p\)/.test(vmSrc))
ok('Reader keeps contiguous fallback for older seedLoadedPages callers', /for \(let p: number = 0; p < seedLoadedPages; p\+\+\)[\s\S]*this\.markPreviewPageLoaded\(p\)/.test(vmSrc))
ok('Reader ensureLoaded tests for an actual /s/ preview at the target index', /this\.hasPreviewAt\(index\)/.test(vmSrc))
ok('Reader loads target preview page before concurrent gap filling', /const loadedTarget: boolean = await this\.loadPreviewPageForIndex\(index\)[\s\S]*if \(loadedTarget \|\| this\.exhausted\)/.test(vmSrc))
ok('Reader computes target preview page from index and perPage', /const targetPreviewPage: number = Math\.floor\(index \/ this\.perPage\)/.test(vmSrc))
ok('Reader requests only the target preview page', /getPreviewImages\([\s\S]*targetPreviewPage/.test(vmSrc))
ok('Reader merges preview pages by absolute image page', /const targetIndex: number = img\.page > 0 \? img\.page - 1 : startIndex \+ i/.test(vmSrc))
ok('Reader pads gaps with page-number placeholders', /next\.push\(new EhGalleryImage\(j \+ 1\)\)/.test(vmSrc))
ok('Reader does not move contiguous previewPage past unloaded gaps', /advanceContiguousPreviewPage\(\): void[\s\S]*while \(this\.isPreviewPageLoaded\(next\)\)/.test(vmSrc))
ok('Reader loadMore uses mergePreviewPage instead of blind concat', /this\.mergePreviewPage\(next, more\)/.test(vmSrc) && !/this\.images = this\.images\.concat\(more\)/.test(vmSrc))
ok('Reader onPageChange loads a missing target slot', /if \(!this\.exhausted && !this\.hasPreviewAt\(index\)\)[\s\S]*this\.ensureLoaded\(index\)/.test(vmSrc))
ok('Reader vertical scroll loads a missing target slot', /if \(!this\.exhausted && !this\.hasPreviewAt\(start\)\)[\s\S]*this\.ensureLoaded\(start\)/.test(vmSrc))
ok('Reader precache still skips unresolved placeholders', /img\.imageUrl\.length === 0 && img\.sUrl\.length > 0/.test(vmSrc))

const parserSrc = read('shared/src/main/ets/parser/EhImagePageParser.ets')
ok('Image-page parser extracts total fileCount beside the serial', /fileCount: number = 0/.test(parserSrc) && /RE_SER_TOTAL/.test(parserSrc))
const indexSrc = read('entry/src/main/ets/pages/Index.ets')
const searchSrc = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
ok('Index /s/ deep links pass parsed fileCount to Reader', /new ReaderParams\(target\.gid, target\.token, target\.index, target\.fileCount/.test(indexSrc))
ok('Search /s/ jumps pass parsed fileCount to Reader', /new ReaderParams\(target\.gid, target\.token, target\.index, target\.fileCount/.test(searchSrc))
const allPageSrc = read('feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets')
ok('AllThumbnails passes exact sparse seed preview page markers to Reader', /new ReaderParams\([\s\S]*this\.vm\.loadedPreviewPageNumbers\(\)/.test(allPageSrc))

console.log(`✓ reader target preview page contract: ${passed} assertions passed`)

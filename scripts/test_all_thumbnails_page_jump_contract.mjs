#!/usr/bin/env node
/**
 * Contract for AllThumbnails page-number jump + first-page return + previous preview pull.
 *
 * Bug class: users need to reach later thumbnail pages without manually scrolling/loading every earlier
 * preview page. Jump input is the global image page number (the same labels shown on thumbnails);
 * the VM must directly load the containing preview page, keep absolute page numbers, and scroll to the
 * target's visible data-source index.
 *
 * Run: node scripts/test_all_thumbnails_page_jump_contract.mjs
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

function targetPreviewPage(pageOneBased, perPreviewPage) {
  if (pageOneBased <= 0 || perPreviewPage <= 0) return -1
  return Math.floor((pageOneBased - 1) / perPreviewPage)
}

function nextForwardPreviewPage(currentPreviewPage, loadedMarkers, totalPreviewPages) {
  let next = currentPreviewPage + 1
  while (next < totalPreviewPages && loadedMarkers.includes(next)) {
    next++
  }
  return next < totalPreviewPages ? next : -1
}

eq('page 1 stays on preview page 0', targetPreviewPage(1, 20), 0)
eq('page 20 stays on preview page 0', targetPreviewPage(20, 20), 0)
eq('page 21 jumps to preview page 1', targetPreviewPage(21, 20), 1)
eq('page 37 jumps to preview page 1', targetPreviewPage(37, 20), 1)
eq('page 138 jumps to preview page 6', targetPreviewPage(138, 20), 6)
eq('1000-page gallery jump to page 600 anchors preview page 29', targetPreviewPage(600, 20), 29)
eq('after far jump, next load starts at target neighbor, not early page 1',
  nextForwardPreviewPage(29, [0, 29], 50), 30)
eq('after loading previous target neighbor, forward load skips already loaded target page',
  nextForwardPreviewPage(28, [0, 28, 29], 50), 30)
eq('last loaded preview page has no bottom next even when early gaps remain',
  nextForwardPreviewPage(49, [0, 49], 50), -1)

const vmSrc = read('feature/gallery/src/main/ets/viewmodel/AllThumbnailsViewModel.ets')
const loadNextSrc = vmSrc.match(/async loadNext\(\): Promise<void> \{[\s\S]*?\n  \}/)?.[0] ?? ''
ok('VM exposes direct image-page loader', /async loadImagePage\(pageOneBased: number\): Promise<boolean>/.test(vmSrc))
ok('VM maps image page to containing preview page', /Math\.floor\(\(pageOneBased - 1\) \/ this\.firstPageCount\)/.test(vmSrc))
ok('VM requests exactly the target preview page', /getPreviewImages\([\s\S]*targetPreviewPage/.test(vmSrc))
ok('VM tracks the current sparse preview page for previous-page pulls',
  /private currentPreviewPage: number = 0/.test(vmSrc) &&
  /this\.currentPreviewPage = targetPreviewPage/.test(vmSrc))
ok('VM bottom pagination follows current sparse anchor instead of contiguous first-page cursor',
  /private nextForwardPreviewPage\(\): number \{[\s\S]*let next: number = this\.currentPreviewPage \+ 1[\s\S]*this\.isPreviewPageLoaded\(next\)[\s\S]*return next < this\.totalPages \? next : -1/.test(vmSrc) &&
  /const nextPage: number = this\.nextForwardPreviewPage\(\)/.test(vmSrc) &&
  !/const nextPage: number = this\.loadedPages/.test(vmSrc))
ok('VM bottom hasMore is based on sparse forward neighbor availability',
  /hasMore\(\): boolean \{\s*return this\.nextForwardPreviewPage\(\) >= 0\s*\}/.test(vmSrc))
ok('VM loadNext moves current sparse anchor after a successful forward page load',
  /async loadNext\(\): Promise<void> \{[\s\S]*this\.mergePreviewPage\(nextPage, more\)[\s\S]*this\.advanceContiguousLoadedPages\(\)[\s\S]*this\.currentPreviewPage = nextPage/.test(vmSrc))
ok('VM exposes direct previous-preview loader',
  /async loadPreviousPreviewPage\(\): Promise<number>/.test(vmSrc))
ok('VM previous loader targets currentPreviewPage - 1',
  /const targetPreviewPage: number = this\.currentPreviewPage - 1/.test(vmSrc))
ok('VM previous loader requests exactly that previous preview page',
  /loadPreviousPreviewPage\(\): Promise<number>[\s\S]*getPreviewImages\([\s\S]*targetPreviewPage/.test(vmSrc))
ok('VM previous loader returns the first absolute image page of the loaded preview page',
  /return targetPreviewPage \* this\.firstPageCount \+ 1/.test(vmSrc))
ok('VM previous loader does not crawl through all earlier preview pages',
  !/while \(this\.currentPreviewPage > 0\)/.test(vmSrc) &&
  !/for \(let .*targetPreviewPage/.test(vmSrc))
ok('VM does not serialize jump through all earlier preview pages', !/while \(this\.loadedPages <= targetPreviewPage && this\.hasMore\(\)\)/.test(vmSrc))
ok('VM merges preview page entries by absolute page', /private mergePreviewPage\(previewPage: number, pageImages: EhGalleryImage\[\]\): void[\s\S]*img\.page/.test(vmSrc))
ok('VM sorts sparse visible thumbnails by absolute page', /merged\.sort\(\(a: EhGalleryImage, b: EhGalleryImage\): number => a\.page - b\.page\)/.test(vmSrc))
ok('VM exposes visible index lookup for sparse jump targets', /visibleIndexForImagePage\(pageOneBased: number\): number[\s\S]*items\[i\]\.page === pageOneBased/.test(vmSrc))
ok('VM succeeds only when target image exists in data source', /return this\.visibleIndexForImagePage\(pageOneBased\) >= 0/.test(vmSrc))
ok('VM tracks exact loaded preview page numbers', /loadedPreviewPageMarkers: number\[\]/.test(vmSrc) && /loadedPreviewPageNumbers\(\): number\[\]/.test(vmSrc))
ok('VM advances contiguous next-page pointer only through loaded markers', /advanceContiguousLoadedPages\(\): void[\s\S]*while \(this\.isPreviewPageLoaded\(next\)\)/.test(vmSrc))
ok('VM keeps contiguous loadedPages only as first-page/reader seed count, not as bottom request source',
  /loadedPreviewPages\(\): number \{\s*return this\.loadedPages\s*\}/.test(vmSrc) &&
  !/this\.loadedPages/.test(loadNextSrc))

const pageSrc = read('feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets')
ok('AllThumbnails title bar includes a jump menu', /'menu': this\.jumpMenu\(\)/.test(pageSrc))
ok('Jump menu includes first-page and jump title actions',
  /const items: Record<string, Object>\[\] = \[\s*\{ 'content': firstInner \},\s*\{ 'content': jumpInner \},\s*\][\s\S]*return \{ 'value': items, 'maxCount': 2 \}/.test(pageSrc))
ok('First-page action uses a title-bar symbol and calls the helper',
  /'label': \$r\('app\.string\.gallery_preview_first_page'\)[\s\S]*'icon': \$r\('sys\.symbol\.arrow_up_circle'\)[\s\S]*this\.backToFirstPage\(\)/.test(pageSrc))
ok('First-page helper directly loads image page 1 and scrolls to its visible index',
  /private async backToFirstPage\(\): Promise<void> \{[\s\S]*await this\.vm\.loadImagePage\(1\)[\s\S]*const targetIndex: number = this\.vm\.visibleIndexForImagePage\(1\)[\s\S]*this\.scroller\.scrollToIndex\(targetIndex\)/.test(pageSrc))
ok('AllThumbnails top pull-refresh loads the previous preview page',
  /onRefresh: async \(\) => \{[\s\S]*await this\.loadPreviousPreviewPage\(\)/.test(pageSrc))
ok('Page helper scrolls to the first image in the previous preview page',
  /private async loadPreviousPreviewPage\(\): Promise<void> \{[\s\S]*const firstImagePage: number = await this\.vm\.loadPreviousPreviewPage\(\)[\s\S]*const targetIndex: number = this\.vm\.visibleIndexForImagePage\(firstImagePage\)[\s\S]*this\.scroller\.scrollToIndex\(targetIndex\)/.test(pageSrc))
ok('Jump menu uses a symbol icon and opens the jump sheet', /'icon': \$r\('sys\.symbol\.arrow_right'\)[\s\S]*this\.jumpSheetShown = true/.test(pageSrc))
ok('Jump sheet opens with the next unloaded image page prefilled', /this\.jumpPageText = `\$\{this\.defaultJumpPage\(\)\}`/.test(pageSrc))
ok('Default jump page advances past the loaded thumbnail count', /return Math\.min\(maxPage, this\.vm\.itemCount \+ 1\)/.test(pageSrc))
ok('Jump sheet uses numeric TextInput', /TextInput\(\{ text: this\.jumpPageText[\s\S]*\.type\(InputType\.Number\)/.test(pageSrc))
ok('Jump validates against fileCount when known', /const maxPage: number = this\.maxImagePage\(\)[\s\S]*page > maxPage/.test(pageSrc))
ok('Jump asks VM to load the containing preview page directly', /await this\.vm\.loadImagePage\(page\)/.test(pageSrc))
ok('Jump scrolls the Grid to the target visible index', /const targetIndex: number = this\.vm\.visibleIndexForImagePage\(page\)[\s\S]*this\.scroller\.scrollToIndex\(targetIndex\)/.test(pageSrc))
ok('AllThumbnails keeps Reader seed params intact', /this\.vm\.loadedImages\(\)[\s\S]*this\.vm\.loadedPreviewPages\(\)[\s\S]*this\.vm\.seedPerPage\(\)[\s\S]*this\.vm\.loadedPreviewPageNumbers\(\)/.test(pageSrc))
ok('AllThumbnails uses immersive title bar options for menu support', /immersiveTitleBarOpts/.test(pageSrc))

for (const loc of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${loc}/element/string.json`)
  for (const key of [
    'gallery_preview_first_page',
    'gallery_preview_jump',
    'gallery_preview_jump_help',
    'gallery_preview_jump_placeholder',
    'gallery_preview_jump_invalid',
  ]) {
    ok(`${loc} has ${key}`, strings.includes(`"name": "${key}"`))
  }
}

console.log(`✓ all-thumbnails page jump contract: ${passed} assertions passed`)

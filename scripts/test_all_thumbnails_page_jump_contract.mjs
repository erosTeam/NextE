#!/usr/bin/env node
/**
 * Contract for AllThumbnails page-number jump.
 *
 * Bug class: users need to reach later thumbnail pages without manually scrolling/loading one preview
 * page at a time. Jump input is the global image page number (the same labels shown on thumbnails);
 * the VM must load through the containing preview page before the Grid scroller moves to that image.
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

eq('page 1 stays on preview page 0', targetPreviewPage(1, 20), 0)
eq('page 20 stays on preview page 0', targetPreviewPage(20, 20), 0)
eq('page 21 jumps to preview page 1', targetPreviewPage(21, 20), 1)
eq('page 37 jumps to preview page 1', targetPreviewPage(37, 20), 1)
eq('page 138 jumps to preview page 6', targetPreviewPage(138, 20), 6)

const vmSrc = read('feature/gallery/src/main/ets/viewmodel/AllThumbnailsViewModel.ets')
ok('VM exposes loadThroughImagePage', /async loadThroughImagePage\(pageOneBased: number\): Promise<boolean>/.test(vmSrc))
ok('VM maps image page to containing preview page', /Math\.floor\(\(pageOneBased - 1\) \/ this\.firstPageCount\)/.test(vmSrc))
ok('VM loads pages until target preview page is included', /while \(this\.loadedPages <= targetPreviewPage && this\.hasMore\(\)\)/.test(vmSrc))
ok('VM detects no-progress load failure to avoid spinning', /const before: number = this\.loadedPages[\s\S]*this\.loadedPages === before/.test(vmSrc))
ok('VM succeeds only when target image exists in data source', /return this\.dataSource\.totalCount\(\) >= pageOneBased/.test(vmSrc))

const pageSrc = read('feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets')
ok('AllThumbnails title bar includes a jump menu', /'menu': this\.jumpMenu\(\)/.test(pageSrc))
ok('Jump menu uses a symbol icon and opens the jump sheet', /'icon': \$r\('sys\.symbol\.arrow_right'\)[\s\S]*this\.jumpSheetShown = true/.test(pageSrc))
ok('Jump sheet opens with the next unloaded image page prefilled', /this\.jumpPageText = `\$\{this\.defaultJumpPage\(\)\}`/.test(pageSrc))
ok('Default jump page advances past the loaded thumbnail count', /return Math\.min\(maxPage, this\.vm\.itemCount \+ 1\)/.test(pageSrc))
ok('Jump sheet uses numeric TextInput', /TextInput\(\{ text: this\.jumpPageText[\s\S]*\.type\(InputType\.Number\)/.test(pageSrc))
ok('Jump validates against fileCount when known', /const maxPage: number = this\.maxImagePage\(\)[\s\S]*page > maxPage/.test(pageSrc))
ok('Jump asks VM to load through the image page', /await this\.vm\.loadThroughImagePage\(page\)/.test(pageSrc))
ok('Jump scrolls the Grid to the target global index', /const targetIndex: number = page - 1[\s\S]*this\.scroller\.scrollToIndex\(targetIndex\)/.test(pageSrc))
ok('AllThumbnails keeps Reader seed params intact', /this\.vm\.loadedImages\(\)[\s\S]*this\.vm\.loadedPreviewPages\(\)[\s\S]*this\.vm\.seedPerPage\(\)/.test(pageSrc))
ok('AllThumbnails uses immersive title bar options for menu support', /immersiveTitleBarOpts/.test(pageSrc))

for (const loc of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${loc}/element/string.json`)
  for (const key of [
    'gallery_preview_jump',
    'gallery_preview_jump_help',
    'gallery_preview_jump_placeholder',
    'gallery_preview_jump_invalid',
  ]) {
    ok(`${loc} has ${key}`, strings.includes(`"name": "${key}"`))
  }
}

console.log(`✓ all-thumbnails page jump contract: ${passed} assertions passed`)

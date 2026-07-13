#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const detailPage = readFileSync(
  join(ROOT, 'feature/gallery/src/main/ets/pages/GalleryDetailPage.ets'),
  'utf8',
)
const detailVm = readFileSync(
  join(ROOT, 'feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets'),
  'utf8',
)
const layoutState = readFileSync(
  join(ROOT, 'shared/src/main/ets/state/LayoutSafeAreaState.ets'),
  'utf8',
)
const entryAbility = readFileSync(
  join(ROOT, 'entry/src/main/ets/entryability/EntryAbility.ets'),
  'utf8',
)

let passed = 0
function ok(name, condition) {
  assert.ok(condition, name)
  passed += 1
}

ok('recent detail cache is applied synchronously before loading is published',
  /const memoryDetailApplied: boolean = this\.applyRecentDetailIfAvailable\(run\)[\s\S]*this\.loading = true/.test(detailVm))

ok('resolved detail widths survive destination recreation for both root navigation modes',
  /@Trace galleryDetailStackContentWidth: number = 0/.test(layoutState) &&
  /@Trace galleryDetailSplitContentWidth: number = 0/.test(layoutState) &&
  /rememberedGalleryDetailContentWidth\(rootNavigationSplit: boolean\)/.test(layoutState) &&
  /@Local detailRootWidth: number = connectLayoutSafeArea\(\)\.rememberedGalleryDetailContentWidth\([\s\S]*connectNavStack\(\)\.isSplitMode/.test(detailPage))

ok('only a real window-size change invalidates remembered detail widths',
  /windowSizeChangeCallback = \(size: window\.Size\)[\s\S]*publishMainWindowSizePx\(size\.width, size\.height\)[\s\S]*invalidateGalleryDetailContentWidths\(\)/.test(entryAbility))

ok('a memory hit enters the complete compact or split detail tree without a bootstrap gate',
  /if \(this\.usesSplitDetailLayout\(\)\)[\s\S]*this\.DetailMetadataPane\(false\)[\s\S]*this\.FullPreviewPane\(\)[\s\S]*this\.DetailMetadataPane\(true\)/.test(detailPage) &&
  !detailPage.includes('DetailFirstFrame') &&
  !detailPage.includes('detailContentMounted') &&
  !detailPage.includes('FrameCallback') &&
  !detailPage.includes('postFrameCallback'))

ok('the complete metadata tree includes cached relations, tags, comments, and previews',
  /private DetailMetadataPane\(showCompactPreview: boolean\)[\s\S]*this\.relationsRow\(\)[\s\S]*GalleryTagsCard\([\s\S]*GalleryCommentsCard\([\s\S]*GalleryPreviewGrid\(/.test(detailPage))

ok('measured width updates the stable layout state without gating the first-frame data',
  /LayoutSafeAreaBridge\.publishGalleryDetailContentWidth\(width, this\.navStackHolder\.isSplitMode\)/.test(detailPage))

console.log(`✓ gallery detail cached first-frame contract: ${passed} assertions passed`)

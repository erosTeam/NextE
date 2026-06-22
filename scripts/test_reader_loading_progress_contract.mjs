#!/usr/bin/env node
/**
 * Contract: Reader loading-stage UI stays lightweight and cannot regress core Reader interaction.
 *
 * Reader image loading uses an isolated pending surface:
 * - HTML/image-page resolving stage can show the resolving placeholder.
 * - Image-byte download stage can show a progress bar while no renderable file exists.
 * - Once a local cached image path exists, the Image branch must not be hidden behind opacity or covered
 *   by a loading overlay.
 *
 * Run: node scripts/test_reader_loading_progress_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const cacheService = read('shared/src/main/ets/services/CachedImageFileService.ets')

ok('Reader root uses the pre-overlay bottom stack baseline',
  /Stack\(\{ alignContent: Alignment\.Bottom \}\)/.test(reader))
ok('root empty loading shows resolving stage and jump loading does not cover readable content',
  /else \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader) &&
  /if \(this\.vm\.jumping && !this\.readerContentReady\(\)\) \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader))
ok('horizontal image resolving shows resolving stage',
  /struct ReaderImagePage[\s\S]*else \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader))
ok('vertical image resolving shows compact resolving stage',
  /struct ReaderVerticalImage[\s\S]*else \{[\s\S]*ReaderLoadingStage\(\{[\s\S]*reader_loading_resolving[\s\S]*compact: true/.test(reader))
ok('ReaderLoadingOverlay is not present in ReaderPage',
  !/ReaderLoadingOverlay|ReaderLoadingLine/.test(reader))
ok('Reader uses the shared cached image file service for full image bytes',
  /CachedImageFileService/.test(reader) &&
  /CachedImageFileService\.load\(/.test(reader))
ok('cached image service separates disk path from ArkUI display URI',
  /interface CachedImageFileResult[\s\S]*filePath: string[\s\S]*displayUri: string/.test(cacheService) &&
  /static displayUri\(path: string\): string/.test(cacheService))
ok('image presentation is not hidden behind imageLoaded opacity gates',
  !/\.opacity\(this\.imageLoaded \? 1 : 0\)/.test(reader))
ok('image download progress appears only before a cached render path exists',
  (reader.match(/else if \(this\.sourceImageUrl\.length > 0\) \{[\s\S]*?reader_loading_image/g) || []).length >= 3)
ok('resolved remote URLs are converted into cached display URIs before presentation',
  (reader.match(/await this\.loadResolvedImage\(resolved\)/g) || []).length >= 3 &&
  (reader.match(/this\.imageUrl = result\.displayUri/g) || []).length >= 3)
ok('Image.onComplete still records page loaded state for warmers and auto-read',
  /\.onComplete\(\(event\?: ReaderImageLoadEvent\) => \{[\s\S]*this\.imageLoaded = true/.test(reader) &&
  /\.onComplete\(\(e\) => \{[\s\S]*this\.imageLoaded = true/.test(reader))
ok('bottom chrome is not re-anchored against a centered root',
  !/ReaderBottomBar\(\)[\s\S]*\.align\(Alignment\.Bottom\)/.test(reader))

console.log(`✓ reader loading recovery contract: ${passed} assertions passed`)

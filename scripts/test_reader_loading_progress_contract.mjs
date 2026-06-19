#!/usr/bin/env node
/**
 * Contract: Reader loading-stage UI stays lightweight and cannot regress core Reader interaction.
 *
 * The old streamed byte-progress/file-cache path remains parked, but the reader should still show
 * centered resolving/loading stages instead of a dead black canvas. Stage UI must disappear after
 * Image.onComplete and must not intercept gestures while an Image is mounted.
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

ok('Reader root uses the pre-overlay bottom stack baseline',
  /Stack\(\{ alignContent: Alignment\.Bottom \}\)/.test(reader))
ok('root empty and jump loading show resolving stage',
  /else \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader) &&
  /if \(this\.vm\.jumping\) \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader))
ok('horizontal image resolving shows resolving stage',
  /struct ReaderImagePage[\s\S]*else \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader))
ok('vertical image resolving shows compact resolving stage',
  /struct ReaderVerticalImage[\s\S]*else \{[\s\S]*ReaderLoadingStage\(\{[\s\S]*reader_loading_resolving[\s\S]*compact: true/.test(reader))
ok('ReaderLoadingOverlay is not present in ReaderPage',
  !/ReaderLoadingOverlay|ReaderLoadingLine/.test(reader))
ok('image-loading stage is explicitly tied to Image not-yet-complete state',
  /if \(!this\.imageLoaded\) \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_image'\) \}\)[\s\S]*hitTestBehavior\(HitTestMode\.None\)/.test(reader) &&
  /if \(!this\.imageLoaded\) \{[\s\S]*reader_loading_image[\s\S]*compact: true[\s\S]*hitTestBehavior\(HitTestMode\.None\)/.test(reader))
ok('Image.onComplete clears the loading stage',
  /\.onComplete\(\(event\?: ReaderImageLoadEvent\) => \{[\s\S]*this\.imageLoaded = true/.test(reader) &&
  /\.onComplete\(\(e\) => \{[\s\S]*this\.imageLoaded = true/.test(reader))
ok('bottom chrome is not re-anchored against a centered root',
  !/ReaderBottomBar\(\)[\s\S]*\.align\(Alignment\.Bottom\)/.test(reader))

console.log(`✓ reader loading recovery contract: ${passed} assertions passed`)

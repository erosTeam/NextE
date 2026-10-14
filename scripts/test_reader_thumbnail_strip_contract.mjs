#!/usr/bin/env node
/**
 * Contract: Reader chrome includes an eros_fe-style bottom thumbnail strip.
 *
 * The strip is navigation UI, not a second image-loading pipeline: it must reuse the ReaderViewModel
 * preview image list, render EH sprite thumbnails through the shared thumbnail primitive, highlight the
 * current page, and delegate taps to the existing jumpToPage path.
 *
 * Run: node scripts/test_reader_thumbnail_strip_contract.mjs
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
const shared = read('shared/src/main/ets/Index.ets')
const sprite = read('shared/src/main/ets/components/EhSpriteThumbnail.ets')

ok('shared barrel exports EhSpriteThumbnail', /export \{ EhSpriteThumbnail \}/.test(shared))
ok('Reader imports EhSpriteThumbnail from shared barrel', /EhSpriteThumbnail/.test(reader) && /from 'shared'/.test(reader))
ok('Reader owns a thumbnail scroller', /private\s+thumbScroller:\s+Scroller\s*=\s*new Scroller\(\)/.test(reader))
ok('ReaderBottomBar mounts ReaderThumbnailStrip before Slider', /ReaderThumbnailStrip\(\)[\s\S]*Slider\(\{/.test(reader))
ok('strip sizing is derived from ThemeConstants tokens', /const READER_THUMB_IMAGE_H:\s*number\s*=\s*ThemeConstants\.FLOAT_BAR_HEIGHT - ThemeConstants\.SPACE_XS/.test(reader) && /const READER_THUMB_STRIP_H:\s*number\s*=/.test(reader))
ok('ReaderThumbnailStrip iterates vm.images', /@Builder\s+ReaderThumbnailStrip\(\)[\s\S]*ForEach\(\s*this\.vm\.images/.test(reader))
ok('strip uses horizontal List', /\.listDirection\(Axis\.Horizontal\)/.test(reader))
ok('strip reuses EhSpriteThumbnail in fitHeight mode', /EhSpriteThumbnail\(\{[\s\S]*fitHeight:\s*true[\s\S]*displayHeight:\s*READER_THUMB_IMAGE_H/.test(reader))
ok('strip has a missing-thumb placeholder instead of resolving full images', /img\.thumbUrl\.length > 0[\s\S]*else[\s\S]*READER_THUMB_PLACEHOLDER_W/.test(reader))
ok('current page is highlighted by vm.currentIndex', /img\.page - 1 === this\.vm\.currentIndex \? READER_THUMB_SELECTED_BORDER : 0/.test(reader))
ok('tapping a thumbnail delegates to existing jumpToPage', /\.onClick\(\(\) => \{[\s\S]*this\.jumpToPage\(img\.page - 1\)/.test(reader))
ok('page changes keep thumbnail strip centered on current page', /@Monitor\('vm\.currentIndex'\)[\s\S]*this\.scrollThumbToCurrent\(\)/.test(reader))
ok('showing chrome scrolls thumbnail strip to current page', /@Monitor\('showChrome'\)[\s\S]*onChromeVisibilityChanged\(\)[\s\S]*this\.scrollThumbToCurrent\(\)/.test(reader))
ok('scrollThumbToCurrent clamps against loaded vm.images', /this\.vm\.currentIndex < 0 \|\| this\.vm\.currentIndex >= this\.vm\.images\.length/.test(reader))
ok('scrollThumbToCurrent uses thumbScroller.scrollToIndex', /this\.thumbScroller\.scrollToIndex\(this\.vm\.currentIndex\)/.test(reader))
ok('shared sprite primitive still keeps thumbnails ratio-safe', /fitHeight[\s\S]*displayHeight \/ this\.thumbHeight/.test(sprite))

console.log(`✓ reader thumbnail strip contract: ${passed} assertions passed`)

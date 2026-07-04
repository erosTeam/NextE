#!/usr/bin/env node
/**
 * Contract: Reader thumbnail filmstrip is a secondary navigation aid.
 *
 * It must:
 * - live inside Reader bottom chrome, behind a local toggle;
 * - render already-loaded EH preview thumbnails via EhSpriteThumbnail;
 * - jump through the existing jumpToPage path;
 * - not introduce a full-gallery thumbnail prefetch loop or a new gesture stack.
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

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const bottomStart = reader.indexOf('@Builder\n  ReaderBottomBar()')
const bottomEnd = reader.indexOf('\n  @Builder\n  ReaderThumbStrip()', bottomStart)
const bottomChrome = bottomStart >= 0 && bottomEnd > bottomStart ? reader.slice(bottomStart, bottomEnd) : ''

ok(
  'Reader imports the shared EH sprite thumbnail renderer',
  /EhSpriteThumbnail/.test(reader) &&
    /from 'shared'/.test(reader),
)

ok(
  'Reader owns a local filmstrip toggle instead of a global setting or SearchFilter state',
  /@Local showThumbStrip: boolean = false/.test(reader) &&
    /this\.showThumbStrip = !this\.showThumbStrip/.test(reader),
)

ok(
  'bottom chrome exposes the filmstrip as a secondary icon control',
  /ReaderBottomBar\(\)[\s\S]*sys\.symbol\.square_grid_2x2[\s\S]*this\.showThumbStrip/.test(reader),
)

ok(
  'closed filmstrip collapses height instead of becoming a hidden hit-test spacer',
  bottomChrome.includes('this.ReaderThumbStrip()') &&
    bottomChrome.includes('.height(this.showThumbStrip ? READER_THUMB_STRIP_HEIGHT + ThemeConstants.SPACE_SM * 2 : 0)') &&
    bottomChrome.includes('top: this.showThumbStrip ? ThemeConstants.SPACE_SM : 0') &&
    bottomChrome.includes('bottom: this.showThumbStrip ? ThemeConstants.SPACE_SM : 0') &&
    bottomChrome.includes('.clip(true)') &&
    bottomChrome.includes('(this.showThumbStrip ? READER_THUMB_STRIP_HEIGHT + ThemeConstants.SPACE_SM * 2 : 0)') &&
    !bottomChrome.includes('.visibility(this.showThumbStrip ? Visibility.Visible : Visibility.Hidden)') &&
    !/if \(this\.showThumbStrip\) \{[\s\S]*this\.ReaderThumbStrip\(\)/.test(bottomChrome),
)

ok(
  'filmstrip renders sprites only when real image-page and thumbnail data exist',
  /private hasRenderableThumb\(img: EhGalleryImage\): boolean \{[\s\S]*img\.sUrl\.length > 0 && img\.thumbUrl\.length > 0/.test(reader) &&
    /if \(this\.hasRenderableThumb\(image\)\)/.test(reader),
)

ok(
  'missing thumbnail metadata stays in-place and warms the target preview page',
  /LoadingProgress\(\)[\s\S]*thumb_placeholder_appear[\s\S]*this\.vm\.warmPreviewForIndex\(index, 'thumb-strip'\)/.test(reader),
)

ok(
  'filmstrip reuses EhSpriteThumbnail with true sprite dimensions',
  /ReaderThumbImage\(index: number, image: EhGalleryImage\)[\s\S]*EhSpriteThumbnail\(\{[\s\S]*url: image\.thumbUrl[\s\S]*thumbWidth: image\.thumbWidth[\s\S]*thumbHeight: image\.thumbHeight[\s\S]*offsetX: image\.thumbOffsetX[\s\S]*spriteWidth: image\.spriteWidth[\s\S]*spriteHeight: image\.spriteHeight[\s\S]*fitHeight: true/.test(reader),
)

ok(
  'tap on a thumbnail goes through existing jumpToPage',
  /private jumpToThumb\(index: number\): void \{[\s\S]*this\.jumpToPage\(index\)/.test(reader) &&
    /\.onClick\(\(\) => \{[\s\S]*this\.jumpToThumb\(index\)/.test(reader),
)

ok(
  'current page is visibly highlighted from vm.currentIndex',
  /index === this\.vm\.currentIndex[\s\S]*ThemeConstants\.BRAND_PRIMARY/.test(reader),
)

ok(
  'filmstrip does not add a whole-gallery thumbnail prefetch loop',
  !/for \(let .*< this\.vm\.totalPages\(\)[\s\S]*getPreviewImages/.test(reader) &&
    !/ReaderThumbStrip[\s\S]*loadPreviewPageForIndex/.test(reader),
)

console.log(`✓ reader thumbnail filmstrip contract: ${passed} assertions passed`)

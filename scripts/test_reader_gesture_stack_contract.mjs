#!/usr/bin/env node
/**
 * Contract: Reader base gestures are interaction-critical. The image page may own
 * pinch/double-tap/zoomed pan, but an unzoomed horizontal drag must still turn the page
 * reliably and loading overlays must never remain above a rendered image.
 *
 * Run: node scripts/test_reader_gesture_stack_contract.mjs
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

const grounding = [
  'eros_fe: lib/pages/image_view/view/view_page.dart tap zones and image_page_view*.dart PhotoView/ExtendedImage gesture ownership',
  'primary information: Reader is an immersive image canvas; once an image is visible, it must be directly interactive',
  'primary actions: one clear horizontal swipe turns page, pinch/double-tap zoom, zoomed pan moves the image, center tap toggles chrome',
  'scope: recover the Reader gesture stack and loading boundary only; no auto-page-turn, visual polish, download executor, or new reader features',
  'Harmony expression: ReaderImagePage owns a single pan pipeline, dispatching unzoomed horizontal swipes to ReaderPage and zoomed pans to transform state',
]

ok('grounding has exactly five lines', grounding.length === 5)
ok('grounding names concrete eros_fe gesture files', grounding[0].includes('view_page.dart') &&
  grounding[0].includes('image_page_view'))
ok('scope excludes feature expansion', grounding[3].includes('no auto-page-turn') &&
  grounding[3].includes('no') &&
  grounding[3].includes('new reader features'))

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')

ok('Reader has explicit unzoomed image pan handler',
  /private onImageFitPan\(deltaX: number, deltaY: number\): void/.test(reader))
ok('unzoomed image pan has a horizontal threshold',
  /Math\.abs\(deltaX\)[\s\S]*READER_FIT_SWIPE_THRESHOLD/.test(reader))
ok('unzoomed image pan ignores mostly vertical drags',
  /absX < absY \* READER_FIT_SWIPE_AXIS_RATIO/.test(reader))
ok('left and right image drags reuse direction-aware tap semantics',
  /if \(deltaX < 0\) \{[\s\S]*this\.tapRight\(\)[\s\S]*\} else \{[\s\S]*this\.tapLeft\(\)/.test(reader))
ok('horizontal Swiper does not compete for touch gestures',
  /HorizontalReader\(\)[\s\S]*\.disableSwipe\(true\)/.test(reader))
ok('double-page Swiper does not compete for touch gestures',
  /DoublePageReader\(\)[\s\S]*\.disableSwipe\(true\)/.test(reader))
ok('horizontal Swiper has manual pan page-turn fallback',
  /HorizontalReader\(\)[\s\S]*PanGesture\(\{ fingers: 1, direction: PanDirection\.Horizontal \}\)[\s\S]*this\.finishReaderPan\(\)/.test(reader))
ok('double-page Swiper has manual pan page-turn fallback',
  /DoublePageReader\(\)[\s\S]*PanGesture\(\{ fingers: 1, direction: PanDirection\.Horizontal \}\)[\s\S]*this\.finishReaderPan\(\)/.test(reader))
ok('manual Swiper pan respects zoom ownership',
  /private finishReaderPan\(\): void \{[\s\S]*if \(!this\.imageZoomed\) \{[\s\S]*this\.onImageFitPan\(this\.readerPanOffsetX, this\.readerPanOffsetY\)/.test(reader))
ok('ReaderImagePage accepts fit pan callback',
  /@Param onFitHorizontalSwipe: \(deltaX: number, deltaY: number\) => void/.test(reader))
ok('ReaderImagePage stores last pan delta',
  /private lastPanOffsetX: number = 0/.test(reader) &&
  /private lastPanOffsetY: number = 0/.test(reader))
ok('unzoomed pan dispatches to parent instead of mutating image offset',
  /onActionEnd\(\(\) => \{[\s\S]*if \(this\.zoomScale <= 1\.01\) \{[\s\S]*this\.onFitHorizontalSwipe\(this\.lastPanOffsetX, this\.lastPanOffsetY\)/.test(reader))
ok('zoomed pan still supports both axes',
  /PanGesture\(\{ fingers: 1, direction: PanDirection\.All \}\)/.test(reader) &&
  /this\.offsetX = this\.clampOffsetX\(this\.baseOffsetX \+ \(e\.offsetX as number\), this\.zoomScale\)/.test(reader) &&
  /this\.offsetY = this\.clampOffsetY\([\s\S]*this\.baseOffsetY \+ \(e\.offsetY as number\)/.test(reader))
ok('pinch zoom path remains present',
  /PinchGesture\(\{ fingers: 2 \}\)[\s\S]*ReaderImageTransformCoordinator\.pinchOffset/.test(reader))
ok('double tap path remains present',
  /TapGesture\(\{ count: 2 \}\)[\s\S]*this\.onDoubleTap\(tapX, tapY\)/.test(reader))
ok('visible image branch does not render ReaderLoadingOverlay',
  !/if \(!this\.imageLoaded\) \{[\s\S]*ReaderLoadingOverlay/.test(reader))
ok('image loading progress is shown before local image URL is assigned',
  /else if \(this\.imageProgress >= 0\) \{[\s\S]*ReaderLoadingOverlay\(\{ label: \$r\('app\.string\.reader_loading_image'\), progress: this\.imageProgress \}\)/.test(reader))

console.log(`✓ reader gesture stack contract: ${passed} assertions passed`)

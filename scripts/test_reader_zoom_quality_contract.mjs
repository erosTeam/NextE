#!/usr/bin/env node
/**
 * Contract: Reader image zoom preserves the user's focal point and allows panning in both axes
 * after zoom. This protects the high-frequency online reading surface from regressing to a
 * center-only double-tap or vertical-only pan.
 *
 * Run: node scripts/test_reader_zoom_quality_contract.mjs
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
  'eros_fe: lib/pages/image_view/view/view_image.dart _onDoubleTap() reads pointerDownPosition and passes it to handleDoubleTap(); image_page_view*.dart delegates zoom/pan to PhotoView/ExtendedImage',
  'primary information: the Reader remains an immersive image canvas; the tapped detail should stay stable when zooming',
  'primary actions: read, double-tap/pinch zoom, and pan zoomed content; secondary chrome/retry/share/settings keep current weight',
  'scope: improve ReaderImagePage transform math and pan direction only; no auto-page-turn, save-original, orientation, download executor, or thumbnail strip',
  'Harmony expression: V2 local state with a small ReaderImageTransformCoordinator mirroring V2Next ImagePreviewCoordinator fit/clamp/focal transform patterns',
]

ok('grounding has exactly five lines', grounding.length === 5)
ok('grounding names concrete eros_fe double-tap implementation', grounding[0].includes('view_image.dart') &&
  grounding[0].includes('_onDoubleTap') &&
  grounding[0].includes('pointerDownPosition'))
ok('scope excludes unrelated reader/download lanes', grounding[3].includes('no auto-page-turn') &&
  grounding[3].includes('download executor'))

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const coordinator = read('shared/src/main/ets/utils/ReaderImageTransformCoordinator.ets')
const barrel = read('shared/src/main/ets/Index.ets')

ok('shared barrel exports ReaderImageTransformCoordinator',
  /export \{ ReaderImageTransformCoordinator \} from '\.\/utils\/ReaderImageTransformCoordinator'/.test(barrel))
ok('Reader imports ReaderImageTransformCoordinator from shared',
  /ReaderImageTransformCoordinator,\s*\} from 'shared'/.test(reader))
ok('Reader records intrinsic image size from Image.onComplete',
  /\.onComplete\(\(e\) => \{[\s\S]*this\.intrinsicW = this\.getUIContext\(\)\.px2vp\(e\.width\)[\s\S]*this\.intrinsicH = this\.getUIContext\(\)\.px2vp\(e\.height\)/.test(reader))
ok('display size uses contain fit, not raw component dimensions',
  /private displayWidth\(\): number \{[\s\S]*ReaderImageTransformCoordinator\.displaySize\(/.test(reader) &&
  /static fitScale\(viewportW: number, viewportH: number, intrinsicW: number, intrinsicH: number\)/.test(coordinator) &&
  /Math\.min\(viewportW \/ intrinsicW, viewportH \/ intrinsicH\)/.test(coordinator))
ok('offset clamps use fitted display dimensions',
  /private clampOffsetX\(value: number, scale: number\): number \{[\s\S]*this\.displayWidth\(\)/.test(reader) &&
  /private clampOffsetY\(value: number, scale: number\): number \{[\s\S]*this\.displayHeight\(\)/.test(reader))
ok('double-tap receives tap location and zooms toward that point',
  /TapGesture\(\{ count: 2 \}\)\.onAction\(\(e\?: GestureEvent\) => \{[\s\S]*e\.tapLocation[\s\S]*this\.onDoubleTap\(tapX, tapY\)/.test(reader) &&
  /private onDoubleTap\(tapX: number, tapY: number\)/.test(reader) &&
  /ReaderImageTransformCoordinator\.doubleTapOffset\(tapX, this\.compW, target\)/.test(reader) &&
  /static doubleTapOffset\(tap: number, viewport: number, targetScale: number\): number \{[\s\S]*\(1 - targetScale\) \* \(tap - viewport \/ 2\)/.test(coordinator))
ok('pinch records and applies focal center correction',
  /PinchGesture\(\{ fingers: 2 \}\)[\s\S]*this\.pinchStartCenterX = e\.pinchCenterX as number[\s\S]*ReaderImageTransformCoordinator\.pinchOffset\(/.test(reader) &&
  /static pinchOffset\([\s\S]*startCenter: number[\s\S]*currentCenter: number[\s\S]*scaleRatio: number/.test(coordinator))
ok('zoomed pan supports both axes',
  /PanGesture\(\{ fingers: 1, direction: PanDirection\.All \}\)/.test(reader) &&
  /this\.offsetX = this\.clampOffsetX\(this\.baseOffsetX \+ \(e\.offsetX as number\), this\.zoomScale\)/.test(reader) &&
  /this\.offsetY = this\.clampOffsetY\([\s\S]*this\.baseOffsetY \+ \(e\.offsetY as number\)/.test(reader))
ok('ReaderImagePage no longer uses center-only double-tap constants',
  !/const DOUBLE_TAP_SCALE: number/.test(reader) &&
  !/private onDoubleTap\(\): void/.test(reader))
ok('ReaderImagePage no longer restricts zoomed pan to vertical only',
  !/PanGesture\(\{ direction: PanDirection\.Vertical \}\)/.test(reader))

console.log(`✓ reader zoom quality contract: ${passed} assertions passed`)

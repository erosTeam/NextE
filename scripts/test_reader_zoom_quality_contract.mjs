#!/usr/bin/env node
/**
 * Contract: Reader zoom is restored to the simpler baseline during P0 core recovery.
 *
 * The focal-point transform enhancement is parked because its PanDirection.All child
 * gesture competed with page turning on device. Baseline still requires pinch, double-tap
 * toggle, and vertical pan while zoomed.
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

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')

ok('ReaderPage does not import ReaderImageTransformCoordinator',
  !/ReaderImageTransformCoordinator/.test(reader))
ok('baseline zoom constants are local to ReaderPage',
  /const MAX_SCALE: number = 4/.test(reader) &&
  /const DOUBLE_TAP_SCALE: number = 2\.5/.test(reader))
ok('pinch zoom remains present',
  /PinchGesture\(\)[\s\S]*this\.zoomScale = Math\.min\(MAX_SCALE, Math\.max\(1, this\.baseZoom \* e\.scale\)\)/.test(reader))
ok('double tap still toggles zoom',
  /TapGesture\(\{ count: 2 \}\)\.onAction\(\(\) => \{[\s\S]*this\.onDoubleTap\(\)/.test(reader) &&
  /private onDoubleTap\(\): void[\s\S]*this\.zoomScale = DOUBLE_TAP_SCALE/.test(reader))
ok('zoomed pan is vertical-only baseline and does not steal horizontal page turns',
  /PanGesture\(\{ direction: PanDirection\.Vertical \}\)/.test(reader) &&
  !/PanDirection\.All/.test(reader))
ok('parent Swiper owns horizontal page turn unless image is zoomed',
  /\.disableSwipe\(this\.imageZoomed\)/.test(reader))
ok('zoom state is still reported to parent',
  /this\.onZoomChange\(zoomed\)/.test(reader))

console.log(`✓ reader zoom baseline contract: ${passed} assertions passed`)

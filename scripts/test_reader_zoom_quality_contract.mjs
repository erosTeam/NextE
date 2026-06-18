#!/usr/bin/env node
/**
 * Contract: Reader zoom surface uses PhotoView-style behavior while preserving page turns.
 *
 * The online Reader must not regress to the old center-only double tap / vertical-only pan
 * baseline. It should use contain-fit display bounds, focal-point double tap, pinch-center
 * correction, and zoomed two-axis pan. The pan is bound as a parallel gesture and the
 * parent Swiper is disabled only while zoomed so fit-state page turning remains available.
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

ok('zoom constants are local to ReaderPage',
  /const MAX_SCALE: number = 4/.test(reader) &&
  /const DOUBLE_TAP_SCALE: number = 2\.5/.test(reader))
ok('reader captures intrinsic image size from Image.onComplete',
  /interface ReaderImageLoadEvent/.test(reader) &&
  /this\.intrinsicW = this\.getUIContext\(\)\.px2vp\(event\.width\)/.test(reader) &&
  /this\.intrinsicH = this\.getUIContext\(\)\.px2vp\(event\.height\)/.test(reader))
ok('pan bounds use contain-fitted display size instead of raw viewport only',
  /private fitScale\(\): number[\s\S]*Math\.min\(scaleW, scaleH\)/.test(reader) &&
  /private displayW\(\): number[\s\S]*this\.intrinsicW \* this\.fitScale\(\)/.test(reader) &&
  /private displayH\(\): number[\s\S]*this\.intrinsicH \* this\.fitScale\(\)/.test(reader) &&
  /private clampOffsetX\(value: number, scale: number\): number[\s\S]*this\.maxOffset\(this\.compW, this\.displayW\(\), scale\)/.test(reader) &&
  /private clampOffsetY\(value: number, scale: number\): number[\s\S]*this\.maxOffset\(this\.compH, this\.displayH\(\), scale\)/.test(reader))
ok('pinch zoom uses two fingers and pinch center correction',
  /PinchGesture\(\{\s*fingers:\s*2\s*\}\)/.test(reader) &&
  /this\.pinchCenterStartX = e\.pinchCenterX as number/.test(reader) &&
  /\(this\.pinchCenterStartX - this\.compW \/ 2\) \* \(1 - k\) \+ k \* this\.pinchStartOffX \+ dx/.test(reader) &&
  /this\.offsetX = this\.clampOffsetX\(nextX, nextScale\)/.test(reader))
ok('double tap uses tapLocation and zooms toward that point',
  /TapGesture\(\{\s*count:\s*2\s*\}\)\.onAction\(\(e\?: GestureEvent\) => \{[\s\S]*const loc = e \? e\.tapLocation : undefined[\s\S]*this\.onDoubleTap\(tapX, tapY\)/.test(reader) &&
  /private onDoubleTap\(tapX: number, tapY: number\): void[\s\S]*\(1 - target\) \* \(tapX - this\.compW \/ 2\)/.test(reader))
ok('zoomed pan is two-axis and parallel so fit-state page turns can reach Swiper',
  /\.parallelGesture\([\s\S]*PanGesture\(\{\s*fingers:\s*1,\s*direction:\s*PanDirection\.All\s*\}\)/.test(reader) &&
  /this\.offsetX = this\.clampOffsetX\(this\.panStartOffX \+ \(e\.offsetX as number\), this\.zoomScale\)/.test(reader) &&
  /this\.offsetY = this\.clampOffsetY\(this\.panStartOffY \+ \(e\.offsetY as number\), this\.zoomScale\)/.test(reader) &&
  !/PanGesture\(\{ direction: PanDirection\.Vertical \}\)/.test(reader))
ok('parent Swiper owns horizontal page turn unless image is zoomed',
  /\.disableSwipe\(this\.imageZoomed\)/.test(reader))
ok('zoom state is still reported to parent',
  /this\.onZoomChange\(zoomed\)/.test(reader))

console.log(`✓ reader zoom surface contract: ${passed} assertions passed`)

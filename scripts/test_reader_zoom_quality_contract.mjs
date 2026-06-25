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
function section(name) {
  const start = reader.indexOf(`@Builder\n  ${name}`)
  assert.ok(start >= 0, `missing section ${name}`)
  const next = reader.indexOf('\n  @Builder', start + name.length)
  return reader.slice(start, next >= 0 ? next : reader.length)
}

const horizontalReader = section('HorizontalReader()')
const doublePageReader = section('DoublePageReader()')
const tapOverlay = section('ReaderTapOverlay()')
function component(name) {
  const start = reader.indexOf(`struct ${name}`)
  assert.ok(start >= 0, `missing component ${name}`)
  const next = reader.indexOf('\n@ComponentV2', start + name.length)
  return reader.slice(start, next >= 0 ? next : reader.length)
}

const spreadSurface = component('ReaderSpreadSurface')
const spreadLayer = component('ReaderSpreadImageLayer')
function exclusiveDoubleBeforeSingle(src) {
  const exclusive = src.indexOf('GestureMode.Exclusive')
  const doubleTap = src.indexOf('TapGesture({ count: 2, distanceThreshold: 8 })')
  const doubleAction = src.indexOf('this.onReaderDoubleTap(tapX, tapY)')
  const singleTap = src.indexOf('TapGesture({ count: 1 })')
  const singleAction = src.indexOf('this.onReaderTap(tapX, tapY)')
  return exclusive >= 0 &&
    doubleTap > exclusive &&
    doubleAction > doubleTap &&
    singleTap > doubleAction &&
    singleAction > singleTap
}

ok('zoom constants are local to ReaderPage',
  /const MAX_SCALE: number = 4/.test(reader) &&
  /const DOUBLE_TAP_SCALE: number = 2\.5/.test(reader))
ok('ReaderZoomCoordinator owns shared zoom math for single-page and spread surfaces',
  /class ReaderZoomCoordinator \{[\s\S]*static isZoomed\(scale: number\): boolean[\s\S]*scale > 1\.01/.test(reader) &&
  /static clampScale\(value: number\): number[\s\S]*MAX_SCALE/.test(reader) &&
  /static fitScale\([\s\S]*viewportW: number,[\s\S]*viewportH: number,[\s\S]*intrinsicW: number,[\s\S]*intrinsicH: number[\s\S]*Math\.min\(scaleW, scaleH\)/.test(reader) &&
  /static displaySize\(viewport: number, intrinsic: number, fitScale: number\): number[\s\S]*intrinsic \* fitScale/.test(reader) &&
  /static clampOffset\(value: number, viewport: number, displaySize: number, scale: number\): number[\s\S]*ReaderZoomCoordinator\.maxOffset/.test(reader) &&
  /static pinchAnchor\([\s\S]*center: number,[\s\S]*viewport: number,[\s\S]*displaySize: number,[\s\S]*scale: number,[\s\S]*offset: number[\s\S]*\(center - displayStart\) \/ displayed/.test(reader) &&
  /static anchoredOffset\([\s\S]*center: number,[\s\S]*viewport: number,[\s\S]*displaySize: number,[\s\S]*scale: number,[\s\S]*anchor: number[\s\S]*return center - point/.test(reader))
ok('reader captures intrinsic image size from Image.onComplete',
  /interface ReaderImageLoadEvent/.test(reader) &&
  /this\.intrinsicW = this\.getUIContext\(\)\.px2vp\(event\.width\)/.test(reader) &&
  /this\.intrinsicH = this\.getUIContext\(\)\.px2vp\(event\.height\)/.test(reader))
ok('pan bounds use contain-fitted display size instead of raw viewport only',
  /private fitScale\(\): number \{[\s\S]*return ReaderZoomCoordinator\.fitScale\(this\.compW, this\.compH, this\.intrinsicW, this\.intrinsicH\)/.test(reader) &&
  /private displayW\(\): number \{[\s\S]*return ReaderZoomCoordinator\.displaySize\(this\.compW, this\.intrinsicW, this\.fitScale\(\)\)/.test(reader) &&
  /private displayH\(\): number \{[\s\S]*return ReaderZoomCoordinator\.displaySize\(this\.compH, this\.intrinsicH, this\.fitScale\(\)\)/.test(reader) &&
  /private clampOffsetX\(value: number, scale: number\): number \{[\s\S]*return ReaderZoomCoordinator\.clampOffset\(value, this\.compW, this\.displayW\(\), scale\)/.test(reader) &&
  /private clampOffsetY\(value: number, scale: number\): number \{[\s\S]*return ReaderZoomCoordinator\.clampOffset\(value, this\.compH, this\.displayH\(\), scale\)/.test(reader))
ok('pinch zoom uses two fingers and keeps the same image point under the pinch center',
  /PinchGesture\(\{\s*fingers:\s*2\s*\}\)/.test(reader) &&
  /\.gesture\(\s*GestureGroup\(\s*GestureMode\.Parallel,[\s\S]*PinchGesture\(\{\s*fingers:\s*2\s*\}\)/.test(reader) &&
  !/gatePagerDuringPinch|reader-zoom|pinchLogCount|shouldFreezeLimitedPinch/.test(reader) &&
  /\.onActionCancel\(\(\) => \{[\s\S]*this\.isPinching = false[\s\S]*this\.clampOffset\(\)[\s\S]*this\.notifyZoom\(\)/.test(reader) &&
  /this\.pinchAnchorX = ReaderZoomCoordinator\.pinchAnchor\([\s\S]*e\.pinchCenterX as number,[\s\S]*this\.compW,[\s\S]*this\.displayW\(\),[\s\S]*this\.zoomScale,[\s\S]*this\.offsetX/.test(reader) &&
  /const nextX: number = ReaderZoomCoordinator\.anchoredOffset\([\s\S]*e\.pinchCenterX as number,[\s\S]*this\.compW,[\s\S]*this\.displayW\(\),[\s\S]*nextScale,[\s\S]*this\.pinchAnchorX/.test(reader) &&
  /const clampedX: number = this\.clampOffsetX\(nextX, nextScale\)[\s\S]*this\.offsetX = clampedX/.test(reader))
ok('transparent tap overlay captures double tap and routes it to the tapped image page',
  /@Local doubleTapSeq: number = 0/.test(reader) &&
  /@Local doubleTapTargetPage: number = 0/.test(reader) &&
  /private doubleTapTargetForPoint\(x: number\): number[\s\S]*this\.doublePageEnabled\(\)[\s\S]*this\.spreadRowReversed\(\)[\s\S]*tapLeftSide[\s\S]*return target \+ 1/.test(reader) &&
  /private onReaderDoubleTap\(x: number, y: number\): void[\s\S]*this\.doubleTapSeq = this\.doubleTapSeq \+ 1/.test(reader) &&
  /private onReaderDoubleTap\(x: number, y: number\): void[\s\S]*this\.doubleTapTargetPage = this\.doubleTapTargetForPoint\(x\)/.test(reader) &&
  /TapGesture\(\{ count: 2, distanceThreshold: 8 \}\)/.test(tapOverlay) &&
  !/TapGesture\(\{ count: 2[, ]/.test(horizontalReader) &&
  !/TapGesture\(\{ count: 2[, ]/.test(doublePageReader) &&
  exclusiveDoubleBeforeSingle(tapOverlay) &&
  /@Monitor\('doubleTapSeq'\)[\s\S]*onDoubleTapCommand\(\): void[\s\S]*const targetPage: number = this\.doubleTapTargetPage > 0 \? this\.doubleTapTargetPage : this\.activeIndex \+ 1[\s\S]*this\.image\.page !== targetPage[\s\S]*this\.onDoubleTap\(this\.doubleTapX, this\.doubleTapY\)/.test(reader))
ok('transparent tap overlay owns chrome tap without binding tap gestures to the pager',
  /ReaderTapOverlay\(\)/.test(reader) &&
  /hitTestBehavior\(HitTestMode\.Transparent\)/.test(tapOverlay) &&
  /TapGesture\(\{ count: 1 \}\)[\s\S]*this\.onReaderTap\(tapX, tapY\)/.test(tapOverlay) &&
  !/TapGesture\(\{ count: [12][, ]/.test(horizontalReader) &&
  !/TapGesture\(\{ count: [12][, ]/.test(doublePageReader))
ok('single and double tap are not mixed through onClick plus parallelGesture',
  !/\.onClick\(\(e: ClickEvent\) => \{[\s\S]*this\.onReaderTap\(e\.x, e\.y\)/.test(horizontalReader) &&
    !/\.onClick\(\(e: ClickEvent\) => \{[\s\S]*this\.onReaderTap\(e\.x, e\.y\)/.test(doublePageReader) &&
    !/tapDispatchSeq|consumeNextTapAfterDoubleTap|suppressTapUntilMs|performReaderTap/.test(reader))
ok('double tap zooms through the same image-anchor path as pinch zoom',
  /private onDoubleTap\(tapX: number, tapY: number\): void[\s\S]*const anchorX: number = ReaderZoomCoordinator\.pinchAnchor\(tapX, this\.compW, this\.displayW\(\), this\.zoomScale, this\.offsetX\)[\s\S]*const nextX: number = ReaderZoomCoordinator\.anchoredOffset\(tapX, this\.compW, this\.displayW\(\), target, anchorX\)/.test(reader) &&
  !/doubleTapOffset/.test(reader) &&
  /ReaderImagePage\(\{[\s\S]*doubleTapSeq: this\.doubleTapSeq,[\s\S]*doubleTapX: this\.doubleTapX,[\s\S]*doubleTapY: this\.doubleTapY,[\s\S]*doubleTapTargetPage: this\.doubleTapTargetPage/.test(reader))
ok('double-page uses one spread surface for zoom, pan, and double-tap',
  /ReaderSpreadSurface\(\{[\s\S]*doubleTapSeq: this\.doubleTapSeq,[\s\S]*doubleTapX: this\.doubleTapX,[\s\S]*doubleTapY: this\.doubleTapY,[\s\S]*doubleTapTargetPage: this\.doubleTapTargetPage/.test(reader) &&
  /@Monitor\('doubleTapSeq'\)[\s\S]*onDoubleTapCommand\(\): void[\s\S]*this\.includesPage\(targetPage\)[\s\S]*this\.onDoubleTap\(this\.doubleTapX, this\.doubleTapY\)/.test(spreadSurface) &&
  /GestureGroup\(\s*GestureMode\.Parallel,[\s\S]*PinchGesture\(\{\s*fingers:\s*2\s*\}\)[\s\S]*PanGesture\(\{\s*fingers:\s*1,\s*direction:\s*PanDirection\.All/.test(spreadSurface) &&
  /Image\(this\.imageUrl\)[\s\S]*\.objectFit\(ImageFit\.Contain\)[\s\S]*\.draggable\(false\)/.test(spreadLayer) &&
  !/TapGesture|PinchGesture|PanGesture/.test(spreadLayer))
ok('double-page spread clamp uses image metrics from child layers',
  /@Local firstIntrinsicW: number = 0/.test(spreadSurface) &&
  /@Local secondIntrinsicH: number = 0/.test(spreadSurface) &&
  /private recordImageMetrics\(page: number, width: number, height: number\): void[\s\S]*this\.getUIContext\(\)\.px2vp\(width\)[\s\S]*this\.firstIntrinsicW = w[\s\S]*this\.secondIntrinsicW = w[\s\S]*this\.clampOffset\(\)/.test(spreadSurface) &&
  /private displayW\(\): number[\s\S]*this\.imageDisplayW\(this\.firstIntrinsicW, this\.firstIntrinsicH\)[\s\S]*this\.imageDisplayW\(this\.secondIntrinsicW, this\.secondIntrinsicH\)/.test(spreadSurface) &&
  /private clampOffsetX\(value: number, scale: number\): number \{[\s\S]*ReaderZoomCoordinator\.clampOffset\(value, this\.compW, this\.displayW\(\), scale\)/.test(spreadSurface) &&
  /@Param onImageMetrics: \(page: number, width: number, height: number\) => void/.test(spreadLayer) &&
  /onImageMetrics: \(page: number, width: number, height: number\) => \{[\s\S]*this\.recordImageMetrics\(page, width, height\)/.test(spreadSurface))
ok('double tap zoom transition is animated instead of an abrupt state jump',
  /private beginZoomAnimation\(\): void \{[\s\S]*this\.zoomAnimating = true[\s\S]*READER_ZOOM_ANIM_DURATION \+ ThemeConstants\.ANIM_DONE_DELAY_MS/.test(reader) &&
  /private onDoubleTap\(tapX: number, tapY: number\): void \{[\s\S]*this\.beginZoomAnimation\(\)/.test(reader) &&
  /\.animation\(\{ duration: this\.zoomAnimating \? READER_ZOOM_ANIM_DURATION : 0, curve: Curve\.FastOutSlowIn \}\)/.test(reader) &&
  /this\.resetZoom\(\)[\s\S]*this\.notifyZoom\(\)/.test(reader))
ok('zoomed pan is two-axis and shares the image gesture group with pinch',
  /private panDistance\(\): number \{[\s\S]*return ReaderZoomCoordinator\.panDistance\(this\.zoomScale, this\.compW, this\.compH\)/.test(reader) &&
  /GestureGroup\(\s*GestureMode\.Parallel,[\s\S]*PinchGesture\(\{\s*fingers:\s*2\s*\}\)[\s\S]*PanGesture\(\{\s*fingers:\s*1,\s*direction:\s*PanDirection\.All,\s*distance:\s*this\.panDistance\(\)\s*\}\)/.test(reader) &&
  /private ignorePanSequence: boolean = false/.test(reader) &&
  /this\.isPinching = true[\s\S]*this\.ignorePanSequence = true[\s\S]*this\.zoomAnimating = false/.test(reader) &&
  /this\.ignorePanSequence = this\.isPinching[\s\S]*this\.panStartOffX = this\.offsetX/.test(reader) &&
  /!e \|\| this\.ignorePanSequence \|\| this\.isPinching/.test(reader) &&
  /const nextX: number = this\.clampOffsetX\(this\.panStartOffX \+ \(e\.offsetX as number\), this\.zoomScale\)[\s\S]*this\.offsetX = nextX/.test(reader) &&
  /const nextY: number = this\.clampOffsetY\(this\.panStartOffY \+ \(e\.offsetY as number\), this\.zoomScale\)[\s\S]*this\.offsetY = nextY/.test(reader) &&
  !/PanGesture\(\{ direction: PanDirection\.Vertical \}\)/.test(reader))
ok('reader zoom path is free of temporary gesture diagnostics and dead base state',
  !/reader-gesture|pinchTraceCount|panTraceCount|baseZoom|baseOffsetX|baseOffsetY/.test(reader))
ok('parent Swiper owns horizontal page turn unless image is zoomed',
  /\.disableSwipe\(this\.imageZoomed\)/.test(reader))
ok('zoom state is still reported to parent',
  /this\.onZoomChange\(zoomed\)/.test(reader))
ok('page navigation clears stale parent zoom gate before changing active image',
  /private clearZoomGate\(\): void \{[\s\S]*this\.imageZoomed = false[\s\S]*\}/.test(reader) &&
  /private turnTo\(target: number\): void \{[\s\S]*this\.clearZoomGate\(\)[\s\S]*this\.vm\.onPageChange\(targetIndex\)/.test(reader) &&
  /private jumpToPage\(index: number\): void \{[\s\S]*this\.clearZoomGate\(\)[\s\S]*this\.vm\.jumpTo\(index\)/.test(reader) &&
  /\.onChange\(\(i: number\) => \{[\s\S]{0,180}this\.clearZoomGate\(\)[\s\S]{0,360}horizontal_swipe_change[\s\S]{0,180}this\.vm\.onPageChange\(i\)/.test(reader) &&
  /\.onChange\(\(i: number\) => \{[\s\S]{0,180}this\.clearZoomGate\(\)[\s\S]{0,420}double_swipe_change[\s\S]{0,180}this\.vm\.onPageChange\(target\)/.test(reader))
ok('cached image pages reset zoom after leaving the active page',
  /@Monitor\('activeIndex'\)[\s\S]*onActiveIndexChanged\(\): void \{[\s\S]*this\.image\.page !== this\.activeIndex \+ 1[\s\S]*this\.resetZoom\(\)[\s\S]*this\.notifyZoom\(\)/.test(reader))

console.log(`✓ reader zoom surface contract: ${passed} assertions passed`)

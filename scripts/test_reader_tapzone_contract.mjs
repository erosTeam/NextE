#!/usr/bin/env node
/**
 * Contract test for reader tap-zone navigation in
 *   feature/reader/src/main/ets/pages/ReaderPage.ets (onReaderTap / tapLeft / tapRight / toPrev/Next)
 *
 * The function below is copy-equal to that logic (no UI — pure region→action math). It locks the
 * eros_fe reader tap regions (view_page.dart 3×3 grid: lrRatio=1/3, tbRatio=1/5):
 *   • left third → tapLeft, right third → tapRight (LTR/vertical: left=prev,right=next; RTL inverts).
 *   • center column: top fifth → prev, bottom fifth → next (page-index relative, NEVER RTL-inverted),
 *     middle → chrome toggle.
 *   • all three view modes navigate (vertical scrolls one image; eros_fe tap-navigates topToBottom).
 *   • while zoomed, a tap never turns the page — chrome toggle only (eros_fe defers to the image).
 *   • a turn before page 0 is a no-op.
 * If the .ets logic changes, mirror it here.
 *
 * Run: node scripts/test_reader_tapzone_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// Mirror of ReaderPage.onReaderTap + tapLeft/tapRight + toPrev/toNext + turnTo.
function turn(dir, currentIndex) {
  const target = currentIndex + (dir === 'next' ? 1 : -1)
  if (target < 0) return { action: 'noop' }
  return { action: 'turn', target }
}
function tapAction(x, y, width, height, mode, currentIndex, zoomed) {
  if (zoomed || width <= 0) return { action: 'chrome' }
  const lr = width / 3
  if (x < lr) {
    // tapLeft: RTL → next, else (LTR / vertical) → prev
    return turn(mode === 'rtl' ? 'next' : 'prev', currentIndex)
  }
  if (x > width - lr) {
    // tapRight: RTL → prev, else → next
    return turn(mode === 'rtl' ? 'prev' : 'next', currentIndex)
  }
  if (height > 0 && y < height / 5) return turn('prev', currentIndex) // center-top (not RTL-inverted)
  if (height > 0 && y > (height * 4) / 5) return turn('next', currentIndex) // center-bottom
  return { action: 'chrome' } // center-middle
}

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b)

const W = 300 // lr edge = 100
const H = 500 // tb edge = 100 (top fifth y<100, bottom fifth y>400)
const MID_Y = 250 // center-middle band

// 1. LTR horizontal thirds
{
  ok('ltr left → prev', eq(tapAction(10, MID_Y, W, H, 'ltr', 5, false), { action: 'turn', target: 4 }))
  ok('ltr right → next', eq(tapAction(290, MID_Y, W, H, 'ltr', 5, false), { action: 'turn', target: 6 }))
  ok('ltr center-middle → chrome', tapAction(150, MID_Y, W, H, 'ltr', 5, false).action === 'chrome')
}

// 2. RTL inverts the left/right thirds (but NOT the center fifths)
{
  ok('rtl right → prev', eq(tapAction(290, MID_Y, W, H, 'rtl', 5, false), { action: 'turn', target: 4 }))
  ok('rtl left → next', eq(tapAction(10, MID_Y, W, H, 'rtl', 5, false), { action: 'turn', target: 6 }))
  ok('rtl center-top → prev (NOT inverted)', eq(tapAction(150, 10, W, H, 'rtl', 5, false), { action: 'turn', target: 4 }))
  ok('rtl center-bottom → next (NOT inverted)', eq(tapAction(150, 490, W, H, 'rtl', 5, false), { action: 'turn', target: 6 }))
}

// 3. center column top/bottom fifths navigate; middle toggles chrome (eros_fe tbRatio 1/5)
{
  ok('center-top → prev', eq(tapAction(150, 10, W, H, 'ltr', 5, false), { action: 'turn', target: 4 }))
  ok('center-bottom → next', eq(tapAction(150, 490, W, H, 'ltr', 5, false), { action: 'turn', target: 6 }))
  ok('center-middle → chrome', tapAction(150, MID_Y, W, H, 'ltr', 5, false).action === 'chrome')
}

// 4. vertical mode ALSO navigates (eros_fe tap-navigates topToBottom) — not blanket chrome
{
  ok('vertical left → prev', eq(tapAction(10, MID_Y, W, H, 'vertical', 5, false), { action: 'turn', target: 4 }))
  ok('vertical right → next', eq(tapAction(290, MID_Y, W, H, 'vertical', 5, false), { action: 'turn', target: 6 }))
  ok('vertical center-top → prev', eq(tapAction(150, 10, W, H, 'vertical', 5, false), { action: 'turn', target: 4 }))
  ok('vertical center-bottom → next', eq(tapAction(150, 490, W, H, 'vertical', 5, false), { action: 'turn', target: 6 }))
  ok('vertical center-middle → chrome', tapAction(150, MID_Y, W, H, 'vertical', 5, false).action === 'chrome')
}

// 5. zoom gate: while zoomed, ANY tap is chrome-only (no page turn)
{
  ok('zoomed left → chrome', tapAction(10, MID_Y, W, H, 'ltr', 5, true).action === 'chrome')
  ok('zoomed right → chrome', tapAction(290, MID_Y, W, H, 'ltr', 5, true).action === 'chrome')
  ok('zoomed center-top → chrome', tapAction(150, 10, W, H, 'ltr', 5, true).action === 'chrome')
}

// 6. before page 0 is a no-op; width 0 fallback
{
  ok('ltr left at page 0 → noop', tapAction(10, MID_Y, W, H, 'ltr', 0, false).action === 'noop')
  ok('center-top at page 0 → noop', tapAction(150, 10, W, H, 'ltr', 0, false).action === 'noop')
  ok('width 0 → chrome', tapAction(10, MID_Y, 0, H, 'ltr', 5, false).action === 'chrome')
}

// 7. structural: the wiring exists in the .ets
{
  const src = readFileSync(join(ROOT, 'feature/reader/src/main/ets/pages/ReaderPage.ets'), 'utf8')
  ok('has onReaderTap(x, y)', /private onReaderTap\(x: number, y: number\)/.test(src))
  ok('zoom gate first', /if \(this\.imageZoomed \|\| this\.viewWidth <= 0\)/.test(src))
  ok('horizontal thirds', /const lr: number = this\.viewWidth \/ 3/.test(src))
  ok('center-top fifth → prev', /y < this\.viewHeight \/ 5[\s\S]*this\.toPrev\(\)/.test(src))
  ok('center-bottom fifth → next', /y > \(this\.viewHeight \* 4\) \/ 5[\s\S]*this\.toNext\(\)/.test(src))
  ok('tapLeft RTL-inverts', /tapLeft[\s\S]*ReadMode\.RTL[\s\S]*this\.toNext\(\)[\s\S]*this\.toPrev\(\)/.test(src))
  ok('vertical turn scrolls the list', /VERTICAL[\s\S]*this\.listScroller\.scrollToIndex\(target\)/.test(src))
  ok('captures viewport height', /this\.viewHeight = n\.height as number/.test(src))
  ok('onClick passes x and y', /this\.onReaderTap\(e\.x, e\.y\)/.test(src))
}

console.log(`✓ reader tap-zone contract: ${passed} assertions passed`)

import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import vm from 'node:vm'

const source = readFileSync(process.env.READER_ENTRY_WINDOW_SOURCE ??
  new URL('../feature/reader/src/main/ets/lab/NextEReaderLabPage.ets', import.meta.url), 'utf8')
function method(name, optional = false) {
  const start = source.indexOf(`  private ${name}(`)
  if (optional && start < 0) return ''
  assert.ok(start >= 0, name)
  const body = source.indexOf('{', start)
  let depth = 0
  for (let i = body; i < source.length; i++) {
    if (source[i] === '{') depth++
    if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1)
  }
  throw new Error(`unterminated ${name}`)
}
const declaration = source.match(/^const READER_ENTRY_STATUS_BAR_HIDE_DELAY_MS: number = (\d+)$/m)
const delay = declaration === null ? 500 : Number(declaration[1])
// These admission methods use only void/boolean annotations. Strip those for
// the Node runtime; no SDK or compiler is needed by the normal CI preflight.
const methods = ['scheduleSystemEntryWindowPresentation', 'clearSystemEntryWindowPresentation',
  'rootWindowPresentationSettled'].map(name => method(name, name !== 'rootWindowPresentationSettled'))
  .join('\n').replaceAll('private ', '').replaceAll(': void', '').replaceAll(': boolean', '')
const code = `exports.Host = class Host {
  routeActive = false; volumeDisposed = false; closeRequested = false; hostClosing = false;
  systemEntryWindowReady = false; systemEntryWindowTimer = -1;
  readMode = { fullscreen: true }; labVisibility = { foreground: true };
  request = { work: 'gallery' };
  readerThumbnailTransition = { galleryId: '', active: () => false, presentationSettledFor: () => false };
  ${methods}
}`

function fixture() {
  const exports = {}, timers = new Map()
  let now = 0, serial = 0
  vm.runInNewContext(code, {
    exports, READER_ENTRY_STATUS_BAR_HIDE_DELAY_MS: delay,
    setTimeout(action, delay) { const id = ++serial; timers.set(id, { action, at: now + delay }); return id },
    clearTimeout(id) { timers.delete(id) },
  })
  const host = new exports.Host()
  return { host, timers, show() { host.scheduleSystemEntryWindowPresentation?.(); host.routeActive = true },
    advance(ms) {
      now += ms
      for (const [id, timer] of timers) if (timer.at <= now) { timers.delete(id); timer.action() }
    } }
}

test('system fullscreen entry keeps source ownership until the existing 500ms boundary', () => {
  const v = fixture()
  assert.equal(v.host.rootWindowPresentationSettled(), false)
  v.show()
  assert.equal(v.host.rootWindowPresentationSettled(), false)
  v.advance(499)
  assert.equal(v.host.rootWindowPresentationSettled(), false)
  v.advance(1)
  assert.equal(v.host.rootWindowPresentationSettled(), true)
})

test('active custom entry remains governed by the real root handoff, on either side of 500ms', () => {
  const v = fixture()
  let settled = false
  v.host.readerThumbnailTransition = { galleryId: 'gallery', active: () => true,
    presentationSettledFor: () => settled }
  v.show()
  v.advance(400)
  assert.equal(v.host.rootWindowPresentationSettled(), false)
  settled = true
  assert.equal(v.host.rootWindowPresentationSettled(), true)
  settled = false
  v.advance(100)
  assert.equal(v.host.rootWindowPresentationSettled(), false)
})

test('close, unmount, hidden route and background cannot release a pending system entry', () => {
  for (const invalidate of [h => { h.closeRequested = true }, h => { h.hostClosing = true },
    h => { h.volumeDisposed = true }, h => { h.routeActive = false },
    h => { h.labVisibility.foreground = false }]) {
    const v = fixture(); v.show(); invalidate(v.host); v.advance(500)
    assert.equal(v.host.systemEntryWindowReady, false)
    assert.equal(v.host.rootWindowPresentationSettled(), false)
  }
})

test('hide cancels its timer, and a later shown route gets its own complete protection interval', () => {
  const v = fixture(); v.show(); v.advance(300)
  v.host.routeActive = false; v.host.clearSystemEntryWindowPresentation?.()
  assert.equal(v.timers.size, 0)
  v.show(); v.advance(200)
  assert.equal(v.host.rootWindowPresentationSettled(), false)
  v.advance(300)
  assert.equal(v.host.rootWindowPresentationSettled(), true)
})

test('non-fullscreen entry does not add an entry timer', () => {
  const v = fixture(); v.host.readMode.fullscreen = false; v.show()
  assert.equal(v.timers.size, 0)
  assert.equal(v.host.rootWindowPresentationSettled(), true)
})

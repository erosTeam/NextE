import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import vm from 'node:vm'
import { test } from 'node:test'

const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
function setup() {
  const site = { isEx: false }
  function load(file) {
    const exports = {}
    const source = readFileSync(new URL(`../shared/src/main/ets/${file}.ets`, import.meta.url), 'utf8')
    vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
    } }).outputText, { exports, require(name) {
      assert.equal(name, '../state/SiteModeState')
      return { connectSiteMode: () => site }
    } })
    return exports
  }
  const { ReaderTrialEntryRelay: relay } = load('navigation/ReaderTrialEntryRelay')
  const { EhThumbnailSnapshotSource: Snapshot } = load('components/EhThumbnailSnapshotSource')
  const { ReaderTrialEntryProbe: probe } = load('navigation/ReaderTrialEntryProbe')
  const image = { page: 1, sUrl: 'page', imgkey: 'key', thumbUrl: 'sheet', thumbWidth: 100,
    thumbHeight: 200, thumbOffsetX: 100, spriteWidth: 800, spriteHeight: 200 }
  let live = true; let ready = true
  const handle = relay.bindSource('source', image, () => live)
  const snapshot = new Snapshot('sheet', 'key', 100, 200, 100, 800, 200, () => ready)
  const open = (gallery = 'work', index = 0, value = image) => relay.tryOpen(gallery, index, value, 'source')
  return { relay, probe, site, image, handle, snapshot, open,
    retire: () => { live = false }, invalidate: () => { ready = false } }
}

test('default production is untouched and a live unready source reaches only the explicit optional host', () => {
  const v = setup(); assert.equal(v.open(), false)
  let captured
  v.relay.install('eh', 'work', source => { captured = source; return true })
  assert.equal(v.relay.isSnapshotReady('eh', 'source'), false)
  assert.equal(v.open(), true); assert.equal(captured.snapshot, null)
  assert.equal(captured.snapshotComponentId, 'source-content'); assert.equal(v.open(), false)
})

test('ready is exact live crop identity; a null from an older child cannot erase a current source', () => {
  const v = setup(); v.relay.updateSnapshot(v.handle, v.snapshot)
  assert.equal(v.relay.isSnapshotReady('eh', 'source'), true)
  v.relay.updateSnapshot(v.handle, null)
  assert.equal(v.relay.isSnapshotReady('eh', 'source'), true)
  v.invalidate(); assert.equal(v.relay.isSnapshotReady('eh', 'source'), false)
  v.relay.updateSnapshot(v.handle, null); assert.equal(v.handle.snapshot, null)
})

test('retired handle cleanup and stale crop callbacks cannot mutate replacement ownership', () => {
  const v = setup()
  const replacement = v.relay.bindSource('source', v.image, () => true)
  v.relay.updateSnapshot(replacement, v.snapshot)
  v.relay.unbindSource(v.handle); v.relay.updateSnapshot(v.handle, null)
  assert.equal(v.relay.isSnapshotReady('eh', 'source'), true)
  v.relay.updateSnapshot(replacement, { ...v.snapshot, offsetX: 200, isCurrent: () => true })
  assert.equal(replacement.snapshot, v.snapshot)
})

test('site, gallery, current leaf, page and image fences do not consume the registered handler', () => {
  for (const mutation of ['site', 'gallery', 'live', 'page', 'image']) {
    const v = setup(); let calls = 0
    v.relay.install('eh', 'work', () => { calls++; return true })
    if (mutation === 'site') v.site.isEx = true
    if (mutation === 'live') v.retire()
    assert.equal(v.open(mutation === 'gallery' ? 'other' : 'work', mutation === 'page' ? 1 : 0,
      mutation === 'image' ? { ...v.image, imgkey: 'other' } : v.image), false, mutation)
    assert.equal(calls, 0)
  }
})

test('one-shot clear and old pending release preserve replacements created inside the handler', () => {
  const v = setup(); let calls = 0; let pending = 0
  const old = v.relay.holdPending('eh', 'old', () => false)
  v.relay.install('eh', 'work', () => {
    pending = v.relay.holdPending('eh', 'work', () => true)
    v.relay.install('eh', 'work', () => { calls++; return true })
    return true
  })
  assert.equal(v.open(), true); v.relay.releasePending(old)
  assert.equal(v.open(), true); assert.equal(calls, 0)
  assert.equal(v.relay.cancelPending('eh', 'other'), false)
  assert.equal(v.relay.cancelPending('eh', 'work'), true)
  v.relay.releasePending(pending); assert.equal(v.open(), true); assert.equal(calls, 1)
})

test('native evidence is detached and retired epochs cannot complete or close a fresh entry', () => {
  const { probe } = setup()
  probe.begin(1, 'eh', 'work', 0, 'source', true)
  probe.captured(1, true); probe.phase(1, 'finished'); probe.close(1)
  assert.equal(probe.read().movingObserved, true); assert.equal(probe.read().closed, true)
  probe.begin(2, 'eh', 'work', 1, 'new-source', false)
  probe.captured(1, true); probe.phase(1, 'finished'); probe.close(1)
  probe.read().snapshotCaptured = true
  assert.equal(probe.read().epoch, 2); assert.equal(probe.read().snapshotCaptured, false)
  assert.equal(probe.read().movingObserved, false); assert.equal(probe.read().closed, false)
})

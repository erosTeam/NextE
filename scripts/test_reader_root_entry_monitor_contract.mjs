import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

const host = readFileSync(new URL('../feature/reader/src/main/ets/lab/NextEReaderLabPage.ets', import.meta.url), 'utf8')
const root = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8')
const transition = readFileSync(
  new URL('../third_party/reader-kit/reader-ui/src/main/ets/ReaderEntryTransition.ets', import.meta.url), 'utf8',
)

// Execute the shared handoff rather than maintaining a duplicate phase algorithm.
import vm from 'node:vm'
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const source = readFileSync(new URL('../third_party/reader-kit/reader-ui/src/main/ets/ReaderRootEntryHandoff.ets', import.meta.url), 'utf8')
const runtime = { exports: {} }
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, runtime)

function method(source, name, next) {
  const start = source.indexOf(`private ${name}()`)
  const end = source.indexOf(`  private ${next}(`, start)
  assert.ok(start >= 0 && end > start, `missing ${name}`)
  return source.slice(start, end)
}

test('NextE root entry observes legal computed target and phase projections', () => {
  assert.match(host, /@Computed\s+private get rootEntryTarget\(\): ReaderEntryTarget \| null \{\s*return this\.entryTransition\?\.target \?\? null\s*\}/)
  assert.match(host, /@Computed\s+private get rootEntryPhase\(\): ReaderEntryPhase \{\s*return this\.entryTransition\?\.phase \?\? 'finished'\s*\}/)
  assert.match(host, /@Monitor\('rootEntryTarget', 'rootEntryPhase', 'readerThumbnailTransition\.phase'/)
  assert.doesNotMatch(host, /@Monitor\([^)]*['"]entryTransition\.(?:target|phase)['"][^)]*\)/s)
  assert.match(transition,
    /export type ReaderEntryPhase = 'layout' \| 'moving' \| 'waiting' \| 'revealing' \| 'finished' \| 'cancelled'/)
})

test('NextE root entry reacts when publishTarget replaces decoded readiness at the same layout revision', () => {
  const sync = host.slice(host.indexOf('private syncRootOwnedEntryTarget'), host.indexOf('  aboutToDisappear'))
  assert.match(sync, /this\.rootEntryHandoff\.sync\(entry, /)
  assert.match(transition, /publishTarget\(value: ReaderEntryTarget\): void \{[\s\S]*?this\.target = value\.copy\(\)/)
  const events = []
  const handoff = new runtime.exports.ReaderRootEntryHandoff()
  const entry = { entryId: 1, phase: 'layout',
    target: { layoutRevision: 7, geometryReady: true, decodedReady: false, contentRect: { valid: () => true }, part: { sourceIndex: 1 } },
    holdNeighborUntilArrival() {}, beginMove() { this.phase = 'moving' }, arrived() { this.phase = 'waiting' },
    reveal() { this.phase = 'revealing'; events.push('reveal') }, finish() { this.phase = 'finished' } }
  const bridge = { authorizeDeparture: () => true, setOpeningTarget: () => true,
    startOpening: done => { events.push('start'); done() },
    revealOriginal: (commit, done) => { commit(); done() }, notifyReaderImageReady: page => events.push(page) }
  handoff.sync(entry, true, true, bridge)
  assert.deepEqual(events, ['start'])
  handoff.sync(entry, true, true, bridge)
  assert.deepEqual(events, ['start'])
  entry.target = { ...entry.target, decodedReady: true }
  handoff.sync(entry, true, true, bridge)
  assert.deepEqual(events, ['start', 'reveal', 2])
  handoff.sync(entry, true, true, bridge)
  assert.equal(events.length, 3)

})

test('NextE root Index projects nullable entry phase for both root monitors', () => {
  const finish = method(root, 'finishSourceEntryPending', 'syncReaderTrialWindow')
  const windowSync = method(root, 'syncReaderTrialWindow', 'retireReaderTrialWindow')
  assert.match(root, /@Computed\s+private get readerEntryPhase\(\): ReaderEntryPhase \{\s*return this\.readerEntryTransition\?\.phase \?\? 'finished'\s*\}/)
  assert.doesNotMatch(root, /@Monitor\([^)]*['"]readerEntryTransition\.phase['"][^)]*\)/s)
  assert.match(root, /@Monitor\('readerEntryPhase'\)\s+private finishSourceEntryPending/)
  assert.match(root, /@Monitor\('readerEntryPhase', 'readerEntryVisibility\.foreground'\)\s+private syncReaderTrialWindow/)
  assert.match(finish, /const phase = this\.readerEntryPhase/)
  assert.match(finish, /ReaderTrialEntryProbe\.phase\(this\.readerEntryTransition\.entryId, phase\)/)
  assert.match(finish, /phase !== 'layout'/)
  assert.match(windowSync, /const phase = this\.readerEntryPhase/)
  assert.match(windowSync, /phase === 'cancelled'/)
  assert.match(windowSync, /phase === 'layout'/)
})

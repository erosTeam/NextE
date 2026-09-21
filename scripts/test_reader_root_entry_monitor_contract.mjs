import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

const host = readFileSync(new URL('../feature/reader/src/main/ets/lab/NextEReaderLabPage.ets', import.meta.url), 'utf8')
const root = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8')
const transition = readFileSync(
  new URL('../third_party/reader-kit/reader-ui/src/main/ets/ReaderEntryTransition.ets', import.meta.url), 'utf8',
)

function rootSync(phase, target, waitingReaderContent = true) {
  if (phase === 'layout') return target?.geometryReady === true ? 'start-moving' : 'idle'
  if (phase !== 'waiting' || target === null || !target.decodedReady || !waitingReaderContent) return 'idle'
  return 'reveal'
}

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
  assert.match(sync, /const target = this\.rootEntryTarget/)
  assert.match(sync, /const phase = this\.rootEntryPhase/)
  assert.match(sync, /if \(phase === 'layout'\)/)
  assert.match(sync, /if \(phase !== 'waiting' \|\| target === null \|\| !target\.decodedReady/)
  assert.match(transition, /publishTarget\(value: ReaderEntryTarget\): void \{[\s\S]*?this\.target = value\.copy\(\)/)

  const measured = { layoutRevision: 7, geometryReady: true, decodedReady: false }
  const decoded = { layoutRevision: 7, geometryReady: true, decodedReady: true }
  assert.equal(rootSync('layout', measured), 'start-moving')
  assert.equal(rootSync('waiting', measured), 'idle')
  assert.notEqual(decoded, measured)
  assert.equal(decoded.layoutRevision, measured.layoutRevision)
  assert.equal(rootSync('waiting', decoded), 'reveal')
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

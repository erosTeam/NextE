#!/usr/bin/env node
/**
 * Contract test for per-gallery reading-progress persistence:
 *   shared/src/main/ets/state/GalleryReadProgressState.ets   (in-memory map + newest-wins)
 *   shared/src/main/ets/settings/GalleryReadProgressSettings.ets (JSON [{g,i,t}] serialize/parse)
 *
 * The functions below are copy-equal to that ArkTS logic (no preferences/runtime — pure data).
 * They lock the eros_fe port (view_state.dart saveLastIndex + GalleryCacheController.setIndex):
 *   • setIndex is last-write-wins for the page, while `t` advances monotonically per gallery so
 *     deferred persistence can reject an old snapshot that finishes after a newer page turn.
 *   • serialize ⇄ parse round-trips; parse is defensive (bad JSON / shape / fields → dropped).
 *   • the detail READ button resumes at, and labels with, the saved page (resumeIndex>0).
 *   • a resumed start index that overshoots the loaded page count is clamped (ReaderViewModel.init).
 * If the .ets logic changes, mirror it here.
 *
 * Run: node scripts/test_read_progress_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// ── Mirror of GalleryReadProgressState (in-memory map, newest-wins) ──────────────────────
class ProgressStore {
  constructor() {
    this.indexMap = new Map()
    this.timeMap = new Map()
    this.columnModeMap = new Map()
    this.revision = 0
  }
  getIndex(gid) {
    if (this.revision < 0) return 0 // (touches revision in .ets for reactivity)
    if (!gid) return 0
    const v = this.indexMap.get(gid)
    return v === undefined ? 0 : v
  }
  nextUpdatedAt(gid, requestedTime) {
    const previous = this.timeMap.get(gid)
    const requested = Math.max(0, Math.floor(requestedTime))
    if (previous === undefined || requested > previous) return requested
    return previous + 1
  }
  setIndex(gid, index, time) {
    if (!gid || index < 0) return
    this.indexMap.set(gid, index) // last-write-wins (matches eros_fe local setIndex)
    this.timeMap.set(gid, this.nextUpdatedAt(gid, time))
    this.revision += 1
  }
  getColumnMode(gid) {
    if (this.revision < 0) return 'oddLeft'
    if (!gid) return 'oddLeft'
    const v = this.columnModeMap.get(gid)
    return v === 'evenLeft' || v === 'oddLeft' ? v : 'oddLeft'
  }
  setColumnMode(gid, columnMode, time) {
    if (!gid || (columnMode !== 'oddLeft' && columnMode !== 'evenLeft')) return
    if (!this.indexMap.has(gid)) this.indexMap.set(gid, 0)
    this.columnModeMap.set(gid, columnMode)
    this.timeMap.set(gid, this.nextUpdatedAt(gid, time))
    this.revision += 1
  }
  adoptPersistedTimestamp(gid, timestamp) {
    const index = this.indexMap.get(gid)
    if (index === undefined) return null
    const previous = this.timeMap.get(gid) ?? 0
    const requested = Math.max(0, Math.floor(timestamp))
    const next = Math.max(previous, requested)
    if (next !== previous) {
      this.timeMap.set(gid, next)
      this.revision += 1
    }
    const columnMode = this.columnModeMap.get(gid)
    return { g: gid, i: index, t: next, c: columnMode === undefined ? '' : columnMode }
  }
  getEntry(gid) {
    if (this.revision < 0 || !gid) return null
    const i = this.indexMap.get(gid)
    if (i === undefined) return null
    const t = this.timeMap.get(gid)
    const c = this.columnModeMap.get(gid)
    return { g: gid, i, t: t === undefined ? 0 : t, c: c === undefined ? '' : c }
  }
  snapshot() {
    const out = []
    for (const [g, i] of this.indexMap) {
      const t = this.timeMap.get(g)
      const c = this.columnModeMap.get(g)
      out.push({ g, i, t: t === undefined ? 0 : t, c: c === undefined ? '' : c })
    }
    return out
  }
  replaceAll(entries) {
    this.indexMap.clear()
    this.timeMap.clear()
    this.columnModeMap.clear()
    for (const e of entries) {
      if (e.g && e.i >= 0) {
        this.indexMap.set(e.g, e.i)
        this.timeMap.set(e.g, e.t)
        if (e.c === 'oddLeft' || e.c === 'evenLeft') {
          this.columnModeMap.set(e.g, e.c)
        }
      }
    }
    this.revision += 1
  }
  mergeNewest(entries) {
    let changed = false
    for (const entry of entries) {
      if (!entry.g || entry.i < 0) continue
      const currentTime = this.timeMap.get(entry.g)
      if (currentTime !== undefined && currentTime > entry.t) continue
      const currentIndex = this.indexMap.get(entry.g)
      const currentColumnMode = this.columnModeMap.get(entry.g)
      const nextColumnMode = entry.c === 'oddLeft' || entry.c === 'evenLeft' ? entry.c : ''
      if (currentTime === entry.t && currentIndex === entry.i &&
        (currentColumnMode === undefined ? '' : currentColumnMode) === nextColumnMode) continue
      this.indexMap.set(entry.g, entry.i)
      this.timeMap.set(entry.g, entry.t)
      if (nextColumnMode) this.columnModeMap.set(entry.g, nextColumnMode)
      else this.columnModeMap.delete(entry.g)
      changed = true
    }
    if (changed) this.revision += 1
  }
}

// ── Mirror of GalleryReadProgressSettings serialize/parse ────────────────────────────────
const serialize = (entries) => JSON.stringify(entries)
function parse(raw) {
  const out = []
  try {
    const arr = JSON.parse(raw)
    if (Array.isArray(arr)) {
      for (const rec of arr) {
        if (
          rec !== null &&
          typeof rec.g === 'string' &&
          rec.g.length > 0 &&
          typeof rec.i === 'number' &&
          rec.i >= 0
        ) {
          out.push({
            g: rec.g,
            i: rec.i,
            t: typeof rec.t === 'number' ? rec.t : 0,
            c: typeof rec.c === 'string' ? rec.c : '',
          })
        }
      }
    }
  } catch {
    // malformed → empty
  }
  return out
}

// ── The detail READ button's resume-label rule (GalleryHeaderCard.readLabel) ──────────────
const usesResumeLabel = (resumeIndex) => resumeIndex > 0
const resumePageLabel = (resumeIndex) => resumeIndex + 1 // 1-based page shown to the user
function entriesChangedSince(before, current) {
  const previousTimes = new Map(before.map((entry) => [entry.g, entry.t]))
  return current.filter((entry) => {
    const previous = previousTimes.get(entry.g)
    return previous === undefined || entry.t > previous
  })
}

function rebaseAfterRestore(stored, changed, restoredAt, now) {
  let nextTime = Math.max(now, restoredAt)
  for (const entry of stored) nextTime = Math.max(nextTime, entry.t)
  for (const entry of changed) nextTime = Math.max(nextTime, entry.t)
  nextTime += 1
  return changed.map((entry) => {
    const rebased = { ...entry, t: nextTime }
    nextTime += 1
    return rebased
  })
}

function mergeDirtyEntries(dirty, entries) {
  for (const entry of entries) {
    const current = dirty.get(entry.g)
    if (current === undefined || current.t <= entry.t) dirty.set(entry.g, { ...entry })
  }
}

// Mirror of GalleryReadProgressSettings' dirty-entry persistence ownership. A batch removes a
// dirty gid only if no newer local mutation replaced its timestamp while RDB was awaiting.
class DirtyProgressWrites {
  constructor(state) {
    this.state = state
    this.dirty = new Map()
    this.writes = []
  }
  mark(gid) {
    const entry = this.state.getEntry(gid)
    if (entry !== null) this.dirty.set(gid, { ...entry })
  }
  snapshot() {
    return [...this.dirty.values()].map((entry) => ({ ...entry }))
  }
  complete(entries) {
    this.writes.push(entries.map((entry) => ({ ...entry })))
    for (const entry of entries) {
      const current = this.dirty.get(entry.g)
      if (current !== undefined && current.t === entry.t) this.dirty.delete(entry.g)
    }
  }
}

function reconcilePersisted(state, dirty, requested, persisted) {
  const requestedTimes = new Map(requested.map((entry) => [entry.g, entry.t]))
  for (const entry of persisted) {
    const requestedTime = requestedTimes.get(entry.g)
    if (requestedTime === undefined) continue
    const current = dirty.get(entry.g)
    if (current === undefined || current.t !== requestedTime) continue
    const adopted = state.adoptPersistedTimestamp(entry.g, entry.t)
    if (adopted !== null) dirty.delete(entry.g)
  }
}

// Mirror of GalleryReadProgressSettings.enqueueRdbWrite. A rejected write must not poison the
// tail, and a backup replacement queued after an already-started save must execute afterward.
class SerialRdbWriteTail {
  constructor() {
    this.tail = Promise.resolve()
  }
  enqueue(work) {
    const next = this.tail.then(
      () => work(),
      () => work(),
    )
    this.tail = next
    return next
  }
}

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

// 1. round-trip: serialize ∘ parse is identity for valid records
{
  const s = new ProgressStore()
  s.setIndex('111', 4, 1000)
  s.setIndex('222', 0, 1001)
  s.setIndex('333', 87, 1002)
  s.setColumnMode('333', 'evenLeft', 1003)
  const round = parse(serialize(s.snapshot()))
  const restored = new ProgressStore()
  restored.replaceAll(round)
  ok('round-trip 111→4', restored.getIndex('111') === 4)
  ok('round-trip 222→0', restored.getIndex('222') === 0)
  ok('round-trip 333→87', restored.getIndex('333') === 87)
  ok('round-trip 333 column mode', restored.getColumnMode('333') === 'evenLeft')
  ok('round-trip preserves count', round.length === 3)
}

// 1b. column mode is per-gallery and does not alter the saved page index
{
  const s = new ProgressStore()
  s.setIndex('g', 5, 100)
  s.setColumnMode('g', 'evenLeft', 101)
  ok('column mode saved per gid', s.getColumnMode('g') === 'evenLeft')
  ok('column mode does not rewrite index', s.getIndex('g') === 5)
  ok('unknown column mode defaults', s.getColumnMode('x') === 'oddLeft')
}

// 2. last-write-wins locally, with a monotonic mutation time for durable stale-write rejection.
{
  const s = new ProgressStore()
  s.setIndex('g', 10, 5000)
  s.setIndex('g', 3, 4000) // later call wins regardless of timestamp ordering
  ok('last write wins', s.getIndex('g') === 3)
  ok('older requested time is advanced for durability', s.snapshot()[0].t === 5001)
  s.setIndex('g', 7, 6000)
  ok('subsequent write wins', s.getIndex('g') === 7)
}

// 2b. Choosing a double-page pairing before turning a page still creates a durable page-zero record.
{
  const s = new ProgressStore()
  s.setColumnMode('g', 'evenLeft', 100)
  const entries = s.snapshot()
  ok('column-only choice creates a progress record', entries.length === 1 && entries[0].i === 0)
  ok('column-only choice is included in the snapshot', entries[0].c === 'evenLeft' && entries[0].t === 100)
}

// 2c. A provider refresh keeps only a page mutation that happened after its initial snapshot.
{
  const state = new ProgressStore()
  state.setIndex('g', 2, 100)
  const before = state.snapshot()
  state.setIndex('g', 7, 100)
  const changed = entriesChangedSince(before, state.snapshot())
  state.replaceAll([{ g: 'g', i: 3, t: 100, c: 'oddLeft' }])
  state.mergeNewest(changed)
  ok('sync refresh preserves a concurrent local page turn', state.getIndex('g') === 7)
  ok('sync refresh keeps the newer mutation time', state.snapshot()[0].t === 101)
}

// 2d. Normal reader writes persist only the modified gid, not every retained history entry.
{
  const state = new ProgressStore()
  state.setIndex('old-a', 1, 10)
  state.setIndex('old-b', 2, 11)
  state.setIndex('active', 3, 12)
  const writes = new DirtyProgressWrites(state)
  writes.mark('active')
  const batch = writes.snapshot()
  ok('dirty persistence snapshots only the active changed gid', batch.length === 1 && batch[0].g === 'active')
  writes.complete(batch)
  ok('completed dirty batch removes only its own gid', writes.snapshot().length === 0)
}

// 2e. Repeated turns for one gid are coalesced to last-write-wins before RDB starts.
{
  const state = new ProgressStore()
  const writes = new DirtyProgressWrites(state)
  state.setIndex('g', 1, 100)
  writes.mark('g')
  state.setIndex('g', 2, 100)
  writes.mark('g')
  const batch = writes.snapshot()
  ok('same-gid dirty work is coalesced to one entry', batch.length === 1)
  ok('same-gid dirty work keeps the newest page and timestamp', batch[0].i === 2 && batch[0].t === 101)
}

// 2f. A page turn during an RDB await remains dirty after the older batch completes.
{
  const state = new ProgressStore()
  const writes = new DirtyProgressWrites(state)
  state.setIndex('g', 1, 100)
  writes.mark('g')
  const first = writes.snapshot()
  state.setIndex('g', 2, 100)
  writes.mark('g')
  writes.complete(first)
  const second = writes.snapshot()
  ok('older completed batch cannot clear a newer dirty page turn', second.length === 1 && second[0].i === 2 && second[0].t === 101)
  writes.complete(second)
  ok('newer completed batch clears the matching dirty entry', writes.snapshot().length === 0)
}

// 2f-1. RDB can rebase a local write above a future cross-device tombstone. The in-memory entry
// adopts that committed clock only when it is still the same page turn; a newer turn remains dirty.
{
  const state = new ProgressStore()
  const dirty = new Map()
  state.setIndex('g', 1, 100)
  const first = [state.getEntry('g')]
  dirty.set('g', first[0])
  reconcilePersisted(state, dirty, first, [{ g: 'g', i: 1, t: 9001, c: '' }])
  ok('committed logical time is adopted by the live reader state', state.getEntry('g').t === 9001)
  ok('matching committed page turn is no longer dirty', dirty.size === 0)

  state.setIndex('g', 2, 100)
  const oldRequest = [{ g: 'g', i: 1, t: 9001, c: '' }]
  const newer = state.getEntry('g')
  dirty.set('g', newer)
  reconcilePersisted(state, dirty, oldRequest, [{ g: 'g', i: 1, t: 9002, c: '' }])
  ok('a newer page turn is not cleared by an older rebased write', dirty.get('g').i === 2)
  ok('a newer page turn keeps its own pending logical time', state.getEntry('g').t === 9002)

  const retry = [state.getEntry('g')]
  reconcilePersisted(state, dirty, retry, [{ g: 'g', i: 2, t: 9003, c: '' }])
  ok('the later flush adopts its committed time and clears the newer page turn',
    state.getEntry('g').t === 9003 && dirty.size === 0)
}

// 2g. A backup replacement cannot overtake an already-running dirty RDB write, and a failed
// write cannot permanently poison the queue used by later page turns or restores.
{
  const tail = new SerialRdbWriteTail()
  const order = []
  let releaseOldWrite = null
  const oldWrite = tail.enqueue(() => new Promise((resolve) => {
    order.push('old-start')
    releaseOldWrite = () => {
      order.push('old-end')
      resolve()
    }
  }))
  await Promise.resolve()
  const restore = tail.enqueue(() => {
    order.push('restore')
    return Promise.resolve()
  })
  ok('backup restore waits for an already-running dirty write', order.join(',') === 'old-start')
  releaseOldWrite()
  await Promise.all([oldWrite, restore])
  ok('backup replacement runs after the old dirty write completes', order.join(',') === 'old-start,old-end,restore')

  const failed = tail.enqueue(() => Promise.reject(new Error('expected read-progress write failure')))
  await assert.rejects(failed)
  await tail.enqueue(() => {
    order.push('recovered')
    return Promise.resolve()
  })
  ok('a failed queued write does not block the next RDB operation', order[order.length - 1] === 'recovered')
}

// 2h. A page turn during a successful backup restore is rebased past both its tombstone and any
// future-dated backup record; a failed restore restores only the older pending dirty records.
{
  const rebased = rebaseAfterRestore(
    [{ g: 'backup', i: 3, t: 900, c: '' }],
    [{ g: 'active', i: 7, t: 100, c: 'evenLeft' }],
    1000,
    800,
  )
  ok('restore-time page turn is rebased above the replacement tombstone', rebased[0].t > 1000)
  ok('rebased page turn also exceeds future-dated backup rows', rebased[0].t > 900)
  ok('rebased page turn keeps its index and pairing', rebased[0].i === 7 && rebased[0].c === 'evenLeft')

  const pendingAfterFailedRestore = new Map([
    ['newer', { g: 'newer', i: 9, t: 201, c: '' }],
  ])
  mergeDirtyEntries(pendingAfterFailedRestore, [
    { g: 'older', i: 2, t: 100, c: '' },
    { g: 'newer', i: 1, t: 200, c: '' },
  ])
  ok('failed restore restores a canceled old dirty entry', pendingAfterFailedRestore.get('older').t === 100)
  ok('failed restore never replaces a newer in-flight page turn', pendingAfterFailedRestore.get('newer').t === 201)
}

// 3. getIndex defaults to 0 for unknown / empty gid
{
  const s = new ProgressStore()
  ok('unknown gid → 0', s.getIndex('nope') === 0)
  ok('empty gid → 0', s.getIndex('') === 0)
}

// 4. setIndex rejects empty gid and negative index (no phantom entries)
{
  const s = new ProgressStore()
  s.setIndex('', 5, 1)
  s.setIndex('g', -1, 1)
  ok('empty gid not stored', s.snapshot().length === 0)
  ok('negative index not stored', s.getIndex('g') === 0)
}

// 5. parse is defensive: bad JSON, non-array, and malformed records are dropped
{
  ok('malformed JSON → []', parse('{not json').length === 0)
  ok('non-array → []', parse('{"g":"1","i":2}').length === 0)
  const mixed = parse(
    JSON.stringify([
      { g: '1', i: 2, t: 9 }, // valid
      { g: '', i: 3, t: 9 }, // empty gid → drop
      { g: '2', i: -5, t: 9 }, // negative index → drop
      { g: '3', i: '4', t: 9 }, // non-number index → drop
      { g: '4', i: 6 }, // missing t → t defaults 0
    ]),
  )
  ok('mixed keeps only valid', mixed.length === 2)
  ok('missing t defaults 0', mixed.find((e) => e.g === '4').t === 0)
}

// 6. resume-label rule: only saved progress (>0) flips the button to "resume page N"
{
  ok('no progress → plain read', usesResumeLabel(0) === false)
  ok('progress → resume', usesResumeLabel(4) === true)
  ok('1-based page label', resumePageLabel(4) === 5)
}

// 7. structural: the wiring exists in the .ets (reader writes + flushes; detail resumes)
{
  const readerSrc = readFileSync(
    join(ROOT, 'feature/reader/src/main/ets/pages/ReaderPage.ets'),
    'utf8',
  )
  ok('reader writes progress on page change', /GalleryReadProgressSettings\.setIndex\(/.test(readerSrc))
  ok('reader writes per-gallery column mode from one-page action',
    /GalleryReadProgressSettings\.setColumnMode\(this\.hostContext\(\), this\.params\.gid, columnMode\)/.test(readerSrc))
  ok('reader flushes on close', /aboutToDisappear[\s\S]*GalleryReadProgressSettings\.flush\(/.test(readerSrc))
  const detailSrc = readFileSync(
    join(ROOT, 'feature/gallery/src/main/ets/pages/GalleryDetailPage.ets'),
    'utf8',
  )
  ok('detail resumes at saved index', /openReader\(this\.resumeIndex\(\)\)/.test(detailSrc))
  const bootSrc = readFileSync(
    join(ROOT, 'shared/src/main/ets/settings/SettingsBootstrap.ets'),
    'utf8',
  )
  ok('progress restored at startup', /GalleryReadProgressSettings\.restore\(/.test(bootSrc))
  const stateSrc = readFileSync(
    join(ROOT, 'shared/src/main/ets/state/GalleryReadProgressState.ets'),
    'utf8',
  )
  const settingsSrc = readFileSync(
    join(ROOT, 'shared/src/main/ets/settings/GalleryReadProgressSettings.ets'),
    'utf8',
  )
  const repoSrc = readFileSync(
    join(ROOT, 'shared/src/main/ets/storage/ReadProgressRepository.ets'),
    'utf8',
  )
  ok('normal progress persistence tracks only durable-shaped dirty entries',
    /getEntry\(gid: string\): ReadProgressEntry \| null/.test(stateSrc) &&
    /private static dirtyEntries: Map<string, ReadProgressEntry>/.test(settingsSrc) &&
    /GalleryReadProgressSettings\.markDirty\(state, gid\)/.test(settingsSrc) &&
    /private static dirtySnapshot\(\): ReadProgressEntry\[\]/.test(settingsSrc))
  ok('dirty progress batch is written through the dedicated repository method and adopts matching committed timestamps',
    /static async saveEntries\([\s\S]*?\): Promise<ReadProgressEntry\[]>/.test(repoSrc) &&
    /await ReadProgressRepository\.saveEntries\(context, entries\)/.test(settingsSrc) &&
    /reconcilePersisted\(state, entries, persisted\)/.test(settingsSrc) &&
    /state\.adoptPersistedTimestamp\(entry\.g, entry\.t\)/.test(settingsSrc))
  ok('backup restore is queued behind stale progress writes and repairs both restore races',
    /private static rdbWriteTail: Promise<void> = Promise\.resolve\(\)/.test(settingsSrc) &&
    /private static enqueueRdbWrite\(work: \(\) => Promise<void>\): Promise<void>/.test(settingsSrc) &&
    /static async restoreBackup[\s\S]*pendingBeforeRestore[\s\S]*GalleryReadProgressSettings\.clearPending\(\)[\s\S]*enqueueRdbWrite[\s\S]*ReadProgressRepository\.replaceAll/.test(settingsSrc) &&
    /rebaseAfterRestore\(stored, changedWhileRestoring, restoredAt\)[\s\S]*markDirty\(state, entry\.g\)[\s\S]*persist\(context, false\)/.test(settingsSrc) &&
    /catch \(error\) \{[\s\S]*mergeDirtyEntries\(pendingBeforeRestore\)[\s\S]*schedulePersist\(context\)/.test(settingsSrc) &&
    /private static async persist[\s\S]*enqueueRdbWrite[\s\S]*saveEntries[\s\S]*reconcilePersisted/.test(settingsSrc))
  const vmSrc = readFileSync(
    join(ROOT, 'feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets'),
    'utf8',
  )
  ok('reader init clamps the start index', /const total: number = this\.totalPages\(\)[\s\S]*this\.currentIndex = total > 0 \? Math\.min\(startIndex, total - 1\) : 0/.test(vmSrc))
}

// 8. clamp rule (ReaderViewModel.init): a resumed index over the loaded page count is pinned
{
  const clampStart = (startIndex, loaded) => (loaded > 0 ? Math.min(startIndex, loaded - 1) : 0)
  ok('overshoot clamps to last', clampStart(87, 20) === 19)
  ok('in-range stays', clampStart(5, 20) === 5)
  ok('empty gallery → 0', clampStart(87, 0) === 0)
}

console.log(`✓ read-progress contract: ${passed} assertions passed`)

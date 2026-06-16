#!/usr/bin/env node
/**
 * Contract test for per-gallery reading-progress persistence:
 *   shared/src/main/ets/state/GalleryReadProgressState.ets   (in-memory map + newest-wins)
 *   shared/src/main/ets/settings/GalleryReadProgressSettings.ets (JSON [{g,i,t}] serialize/parse)
 *
 * The functions below are copy-equal to that ArkTS logic (no preferences/runtime — pure data).
 * They lock the eros_fe port (view_state.dart saveLastIndex + GalleryCacheController.setIndex):
 *   • setIndex is last-write-wins (eros_fe's local setIndex overwrites unconditionally; `t` is
 *     recorded as metadata for the future sync layer, not compared here).
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
    this.revision = 0
  }
  getIndex(gid) {
    if (this.revision < 0) return 0 // (touches revision in .ets for reactivity)
    if (!gid) return 0
    const v = this.indexMap.get(gid)
    return v === undefined ? 0 : v
  }
  setIndex(gid, index, time) {
    if (!gid || index < 0) return
    this.indexMap.set(gid, index) // last-write-wins (matches eros_fe local setIndex)
    this.timeMap.set(gid, time)
    this.revision += 1
  }
  snapshot() {
    const out = []
    for (const [g, i] of this.indexMap) {
      const t = this.timeMap.get(g)
      out.push({ g, i, t: t === undefined ? 0 : t })
    }
    return out
  }
  replaceAll(entries) {
    this.indexMap.clear()
    this.timeMap.clear()
    for (const e of entries) {
      if (e.g && e.i >= 0) {
        this.indexMap.set(e.g, e.i)
        this.timeMap.set(e.g, e.t)
      }
    }
    this.revision += 1
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
          out.push({ g: rec.g, i: rec.i, t: typeof rec.t === 'number' ? rec.t : 0 })
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
  const round = parse(serialize(s.snapshot()))
  const restored = new ProgressStore()
  restored.replaceAll(round)
  ok('round-trip 111→4', restored.getIndex('111') === 4)
  ok('round-trip 222→0', restored.getIndex('222') === 0)
  ok('round-trip 333→87', restored.getIndex('333') === 87)
  ok('round-trip preserves count', round.length === 3)
}

// 2. last-write-wins locally (eros_fe setIndex overwrites unconditionally; t is metadata only)
{
  const s = new ProgressStore()
  s.setIndex('g', 10, 5000)
  s.setIndex('g', 3, 4000) // later call wins regardless of timestamp ordering
  ok('last write wins', s.getIndex('g') === 3)
  s.setIndex('g', 7, 6000)
  ok('subsequent write wins', s.getIndex('g') === 7)
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
  const vmSrc = readFileSync(
    join(ROOT, 'feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets'),
    'utf8',
  )
  ok('reader init clamps the start index', /this\.currentIndex = this\.images\.length > 0 \? Math\.min\(startIndex/.test(vmSrc))
}

// 8. clamp rule (ReaderViewModel.init): a resumed index over the loaded page count is pinned
{
  const clampStart = (startIndex, loaded) => (loaded > 0 ? Math.min(startIndex, loaded - 1) : 0)
  ok('overshoot clamps to last', clampStart(87, 20) === 19)
  ok('in-range stays', clampStart(5, 20) === 5)
  ok('empty gallery → 0', clampStart(87, 0) === 0)
}

console.log(`✓ read-progress contract: ${passed} assertions passed`)

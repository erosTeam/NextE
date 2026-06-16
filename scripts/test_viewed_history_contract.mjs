#!/usr/bin/env node
/**
 * Contract test for the viewed-history store:
 *   shared/src/main/ets/settings/ViewedHistorySettings.ets (add: dedup move-to-front + cap; parse/persist)
 *   shared/src/main/ets/state/ViewedHistoryState.ets · model/ViewedGallery.ets
 *
 * The functions below are copy-equal to that ArkTS logic (no preferences runtime — pure data). They
 * lock the eros_fe HistoryController behavior:
 *   • add dedups by gid and moves the entry to the FRONT with a fresh time (newest first).
 *   • the list is capped (MAX_HISTORY) — the oldest drops off.
 *   • serialize ⇄ parse round-trips; parse is defensive (bad JSON / shape / no-gid → dropped).
 *   • the 5s open-debounce lives at the call site (detail page schedules + cancels), NOT in add().
 * If the .ets logic changes, mirror it here.
 *
 * Run: node scripts/test_viewed_history_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// Mirror of ViewedHistorySettings.add (dedup move-to-front + cap).
function add(items, entry, max) {
  const next = [entry]
  for (const it of items) {
    if (it.gid !== entry.gid && next.length < max) next.push(it)
  }
  return next
}
const serialize = (items) => JSON.stringify(items)
// Mirror of ViewedHistorySettings.parse (defensive).
function parse(raw) {
  const out = []
  let arr
  try {
    arr = JSON.parse(raw)
  } catch {
    return out
  }
  if (!Array.isArray(arr)) return out
  for (const rec of arr) {
    if (rec !== null && typeof rec === 'object' && typeof rec.gid === 'string' && rec.gid.length > 0) {
      out.push({
        gid: rec.gid,
        token: typeof rec.token === 'string' ? rec.token : '',
        title: typeof rec.title === 'string' ? rec.title : '',
        time: typeof rec.time === 'number' ? rec.time : 0,
      })
    }
  }
  return out
}

const g = (gid, time) => ({ gid, token: 't' + gid, title: 'T' + gid, time })
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}
const gids = (items) => items.map((i) => i.gid).join(',')

// 1. add to empty
{
  ok('add to empty → single entry', gids(add([], g('1', 100), 200)) === '1')
}

// 2. add a new gid → prepended (newest first), existing pushed after
{
  const items = [g('1', 100), g('2', 90)]
  ok('new gid goes to front', gids(add(items, g('3', 110), 200)) === '3,1,2')
}

// 3. add an EXISTING gid → moved to front, deduped (no duplicate, count unchanged), time refreshed
{
  const items = [g('1', 100), g('2', 90), g('3', 80)]
  const next = add(items, g('2', 120), 200)
  ok('existing gid moves to front', gids(next) === '2,1,3')
  ok('no duplicate gid', new Set(next.map((i) => i.gid)).size === next.length)
  ok('count unchanged on dedup', next.length === 3)
  ok('time refreshed', next[0].time === 120)
}

// 4. cap: adding beyond MAX drops the oldest
{
  const items = [g('1', 100), g('2', 90), g('3', 80)]
  const next = add(items, g('4', 110), 3) // cap 3
  ok('cap drops the oldest', gids(next) === '4,1,2')
  ok('cap respected', next.length === 3)
}

// 5. serialize → parse round-trip
{
  const items = [g('10', 5), g('20', 4)]
  const round = parse(serialize(items))
  ok('round-trip count', round.length === 2)
  ok('round-trip gids+order', gids(round) === '10,20')
  ok('round-trip token', round[0].token === 't10')
}

// 6. defensive parse
{
  ok('bad JSON → []', parse('{not json').length === 0)
  ok('non-array → []', parse('{"gid":"1"}').length === 0)
  const mixed = parse(JSON.stringify([{ gid: '1', time: 9 }, { gid: '', time: 9 }, { time: 9 }, { gid: 5 }]))
  ok('drops records without a string gid', mixed.length === 1 && mixed[0].gid === '1')
}

// 7. structural: wiring exists (5s schedule + cancel on leave; bootstrap restore; key; cap=200)
{
  const read = (p) => readFileSync(join(ROOT, p), 'utf8')
  const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
  ok('detail schedules a 5s history add', /setTimeout\(\(\) => \{[\s\S]*ViewedHistorySettings\.add\(/.test(detail))
  ok('5s delay constant', /\}, 5000\)/.test(detail))
  ok('cancels the timer on leave', /aboutToDisappear[\s\S]*clearTimeout\(this\.historyTimer\)/.test(detail))
  const settings = read('shared/src/main/ets/settings/ViewedHistorySettings.ets')
  ok('add dedups by gid', /it\.gid !== entry\.gid/.test(settings))
  ok('history is capped', /MAX_HISTORY: number = 200/.test(settings))
  const boot = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
  ok('bootstrap restores history', /ViewedHistorySettings\.restore\(/.test(boot))
  const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
  ok('storage key registered', /VIEWED_HISTORY: string = 'viewed\.history'/.test(keys))
}

console.log(`✓ viewed-history contract: ${passed} assertions passed`)

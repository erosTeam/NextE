#!/usr/bin/env node
/**
 * Contract: ordinary viewed-history opens are bounded, tombstone-safe RDB mutations rather than a
 * whole-history rewrite. This mirrors the timestamp/trim rules in ViewedHistoryRepository.
 * Run: node scripts/test_viewed_history_rdb_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (path) => readFileSync(join(ROOT, path), 'utf8')

let passed = 0
const ok = (name, condition) => {
  assert.ok(condition, name)
  passed += 1
}

const effectiveTime = (row) => Math.max(row.viewedAt, row.deletedAt)

// Pure mirror of ViewedHistoryRepository.upsertAndTrim + SQL_APPLY_VIEWED_HISTORY. It proves the
// durable rules without requiring a device RDB fixture in this Node-only contract.
class HistoryRows {
  constructor() {
    this.rows = new Map()
  }

  nextViewedAt(requestedTime, now) {
    let latest = 0
    for (const row of this.rows.values()) latest = Math.max(latest, effectiveTime(row))
    return Math.max(now, Math.max(0, Math.floor(requestedTime)), latest + 1)
  }

  localVisit(gid, requestedTime, now, limit = 200) {
    const viewedAt = this.nextViewedAt(requestedTime, now)
    const previous = this.rows.get(gid)
    if (previous === undefined || viewedAt >= effectiveTime(previous)) {
      this.rows.set(gid, { gid, viewedAt, deletedAt: 0, payload: `local-${viewedAt}` })
    }
    const active = [...this.rows.values()]
      .filter((row) => row.deletedAt === 0)
      .sort((a, b) => b.viewedAt - a.viewedAt || b.gid.localeCompare(a.gid))
    for (let index = limit; index < active.length; index += 1) {
      const row = active[index]
      if (row.viewedAt <= viewedAt) row.deletedAt = viewedAt
    }
    return viewedAt
  }

  applyRemote(row) {
    const current = this.rows.get(row.gid)
    if (current === undefined || effectiveTime(row) >= effectiveTime(current)) {
      this.rows.set(row.gid, { ...row })
    }
  }

  replaceAll(rows, now) {
    const replacedAt = this.nextViewedAt(now, now)
    for (const row of this.rows.values()) {
      if (row.deletedAt === 0) row.deletedAt = replacedAt
    }
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index]
      this.rows.set(row.gid, {
        ...row,
        viewedAt: Math.max(row.viewedAt, replacedAt + rows.length - index),
        deletedAt: 0,
      })
    }
    return replacedAt
  }

  active() {
    return [...this.rows.values()]
      .filter((row) => row.deletedAt === 0)
      .sort((a, b) => b.viewedAt - a.viewedAt || b.gid.localeCompare(a.gid))
  }
}

const history = new HistoryRows()
for (let index = 0; index < 201; index += 1) {
  history.localVisit(`g${index}`, index + 1, index + 1)
}
ok('201 ordinary visits retain exactly 200 active rows', history.active().length === 200)
const evicted = history.rows.get('g0')
ok('retention trims with a sync-visible tombstone instead of deleting the evicted row',
  evicted !== undefined && evicted.deletedAt > evicted.viewedAt)
ok('latest visit is first after the bounded trim', history.active()[0].gid === 'g200')

const revisitedAt = history.localVisit('g20', 1, 1)
ok('revisiting a gid keeps one durable row and promotes it to first',
  history.rows.size === 201 && history.active()[0].gid === 'g20' &&
    history.rows.get('g20').viewedAt === revisitedAt)
ok('same-millisecond or clock-backward visits still advance logical time', revisitedAt > 201)

const tombstoneClock = new HistoryRows()
tombstoneClock.applyRemote({ gid: 'old', viewedAt: 20, deletedAt: 9000, payload: 'remote' })
const freshAt = tombstoneClock.localVisit('fresh', 1, 10)
ok('a local visit advances past a future tombstone before writing', freshAt > 9000)

const stale = new HistoryRows()
stale.applyRemote({ gid: 'same', viewedAt: 20, deletedAt: 0, payload: 'new' })
stale.applyRemote({ gid: 'same', viewedAt: 19, deletedAt: 0, payload: 'old' })
ok('an older delayed record cannot overwrite a newer local row', stale.rows.get('same').payload === 'new')
stale.applyRemote({ gid: 'same', viewedAt: 20, deletedAt: 21, payload: 'delete' })
ok('a newer remote tombstone wins over an active row', stale.rows.get('same').deletedAt === 21)
const readdedAt = stale.localVisit('same', 1, 1)
ok('a later local revisit advances above the winning tombstone',
  stale.rows.get('same').deletedAt === 0 && readdedAt > 21)

const remoteOverflow = new HistoryRows()
for (let index = 0; index < 250; index += 1) {
  remoteOverflow.applyRemote({ gid: `remote${index}`, viewedAt: index + 1, deletedAt: 0, payload: 'remote' })
}
remoteOverflow.localVisit('local', 1, 1)
ok('the next normal visit converges an oversized synced table back to 200 active rows',
  remoteOverflow.active().length === 200)
ok('overflow convergence preserves discarded rows as tombstones',
  [...remoteOverflow.rows.values()].some((row) => row.deletedAt > row.viewedAt))

const replacement = new HistoryRows()
replacement.applyRemote({ gid: 'old-delete', viewedAt: 20, deletedAt: 9000, payload: 'remote' })
replacement.localVisit('before', 1, 1)
const beforeReplacement = replacement.rows.get('before')
const replacementAt = replacement.replaceAll(
  [{ gid: 'backup', viewedAt: 3, deletedAt: 0, payload: 'backup' }],
  50,
)
ok('backup replacement remains exact rather than merging the previous active list',
  replacement.active().length === 1 && replacement.active()[0].gid === 'backup' &&
    replacement.rows.get('before').deletedAt === replacementAt)
ok('backup replacement advances past future tombstones and rebases restored rows above its tombstone',
  replacementAt > 9000 && replacement.rows.get('backup').viewedAt > replacementAt &&
    replacement.rows.get('before').deletedAt > beforeReplacement.viewedAt)

const settings = read('shared/src/main/ets/settings/ViewedHistorySettings.ets')
const repository = read('shared/src/main/ets/storage/ViewedHistoryRepository.ets')
const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
const syncService = read('shared/src/main/ets/sync/SyncService.ets')
const huaweiCloud = read('shared/src/main/ets/sync/HuaweiCloudSyncService.ets')

const addStart = settings.indexOf('static async add')
const addEnd = settings.indexOf('\n  static async clear', addStart)
const addMethod = settings.slice(addStart, addEnd)
ok('ordinary add uses one upsert-and-trim mutation instead of replaceAll',
  /ViewedHistoryRepository\.upsertAndTrim\(context, entry, MAX_HISTORY\)/.test(settings) &&
    !/replaceAll/.test(addMethod))
ok('settings serializes history writes and drains them before exports or providers read RDB',
  /private static rdbWriteTail: Promise<void> = Promise\.resolve\(\)/.test(settings) &&
    /private static enqueueRdbWrite\(work: \(\) => Promise<void>\): Promise<void>/.test(settings) &&
    /static async flushForSync\(_context: common\.UIAbilityContext\): Promise<void>/.test(settings) &&
    /exportForBackup[\s\S]*flushForSync\(context\)/.test(settings))
ok('history refresh does not replace a local mutation that raced its storage read',
  /private static mutationRevision: number = 0/.test(settings) &&
    /refreshFromStorage[\s\S]*revision === ViewedHistorySettings\.mutationRevision/.test(settings))
ok('full replacements stay transactional and are reserved for backup, clear, and migration',
  /static async replaceAll[\s\S]*store\.beginTransaction\(\)[\s\S]*nextViewedAt\(store, Date\.now\(\)\)[\s\S]*SQL_TOMBSTONE_SCOPE[\s\S]*snapshotTime[\s\S]*SQL_RESTORE_UPSERT[\s\S]*store\.commit\(\)[\s\S]*catch \(error\) \{[\s\S]*store\.rollBack\(\)/.test(repository) &&
    /restoreBackup[\s\S]*ViewedHistoryRepository\.replaceAll/.test(settings) &&
    /migrateLegacyPreferences[\s\S]*ViewedHistoryRepository\.replaceAll/.test(settings))
ok('legacy history only migrates into an empty canonical RDB and preserves its only copy on write failure',
  /SQL_HAS_PERSISTED_STATE/.test(repository) &&
    /static async hasPersistedState/.test(repository) &&
    /migrateLegacyPreferences[\s\S]*const revision: number = ViewedHistorySettings\.mutationRevision[\s\S]*ViewedHistoryRepository\.hasPersistedState\(context\)[\s\S]*history_migrate_failed[\s\S]*Keep the only legacy copy intact/.test(settings))
ok('ordinary history writes use a transaction, global logical time, and tombstone-only overflow trim',
  /static async upsertAndTrim[\s\S]*store\.beginTransaction\(\)[\s\S]*nextViewedAt[\s\S]*SQL_TOMBSTONE_OVERFLOW[\s\S]*store\.commit\(\)/.test(repository) &&
    /SQL_SELECT_MAX_EFFECTIVE_TIME/.test(repository) &&
    /gid NOT IN \(SELECT gid FROM viewed_history/.test(repository) &&
    !/DELETE FROM viewed_history/.test(repository))
ok('normal and remote viewed-history upserts reject older effective timestamps',
  /WHERE excluded\.viewed_at >= CASE WHEN COALESCE\(viewed_history\.deleted_at, 0\) >/.test(repository) &&
    /SQL_APPLY_VIEWED_HISTORY[\s\S]*WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) >/.test(syncAdapter) &&
    /COALESCE\(viewed_history\.viewed_at, 0\)/.test(syncAdapter))
ok('WebDAV and Huawei providers drain pending viewed-history writes before reading RDB',
  /mergeRemoteEnvelope[\s\S]*selection\.viewedHistory[\s\S]*ViewedHistorySettings\.flushForSync\(context\)[\s\S]*exportEnvelope/.test(syncService) &&
    /cloudSyncNow[\s\S]*selection\.viewedHistory[\s\S]*ViewedHistorySettings\.flushForSync\(context\)[\s\S]*markDistributedTables/.test(huaweiCloud))

console.log(`✓ viewed-history RDB contract: ${passed} assertions passed`)

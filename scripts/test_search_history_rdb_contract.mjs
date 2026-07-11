#!/usr/bin/env node
/**
 * Contract: ordinary search-history updates are bounded one-row RDB mutations rather than a whole
 * snapshot rewrite. The pure mirror below protects MRU ordering, tombstones, and LWW behavior.
 * Run: node scripts/test_search_history_rdb_contract.mjs
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

const effectiveTime = (row) => Math.max(row.updatedAt, row.deletedAt)

class SearchRows {
  constructor() {
    this.rows = new Map()
  }

  orderedActive() {
    return [...this.rows.values()]
      .filter((row) => row.deletedAt === 0)
      .sort((a, b) => a.positionIndex - b.positionIndex || b.updatedAt - a.updatedAt)
  }

  nextMutationTime(requestedTime, now) {
    let latest = 0
    for (const row of this.rows.values()) latest = Math.max(latest, effectiveTime(row))
    return Math.max(now, Math.max(0, Math.floor(requestedTime)), latest + 1)
  }

  nextPositionIndex() {
    const active = this.orderedActive()
    return active.length === 0 ? 0 : active[0].positionIndex - 1
  }

  localSearch(query, now, limit = 100) {
    const updatedAt = this.nextMutationTime(now, now)
    const row = {
      query,
      positionIndex: this.nextPositionIndex(),
      updatedAt,
      deletedAt: 0,
      payload: `local-${updatedAt}`,
    }
    const previous = this.rows.get(query)
    if (previous === undefined || updatedAt >= effectiveTime(previous)) this.rows.set(query, row)
    const active = this.orderedActive()
    for (let index = limit; index < active.length; index += 1) {
      const overflow = active[index]
      if (overflow.updatedAt <= updatedAt) overflow.deletedAt = updatedAt
    }
    return updatedAt
  }

  tombstone(query, now) {
    const deletedAt = this.nextMutationTime(now, now)
    const previous = this.rows.get(query)
    if (previous === undefined || deletedAt >= effectiveTime(previous)) {
      this.rows.set(query, {
        query,
        positionIndex: previous?.positionIndex ?? 0,
        updatedAt: previous?.updatedAt ?? 0,
        deletedAt,
        payload: 'tombstone',
      })
    }
    return deletedAt
  }

  applyRemote(row) {
    const previous = this.rows.get(row.query)
    if (previous === undefined || effectiveTime(row) >= effectiveTime(previous)) {
      this.rows.set(row.query, { ...row })
    }
  }

  replaceAll(items, now) {
    const replacedAt = this.nextMutationTime(now, now)
    for (const row of this.rows.values()) {
      if (row.deletedAt === 0) row.deletedAt = replacedAt
    }
    const snapshot = []
    for (const item of items) {
      const query = item.trim()
      if (query.length > 0 && !snapshot.includes(query) && snapshot.length < 100) snapshot.push(query)
    }
    snapshot.forEach((query, index) => {
      this.rows.set(query, {
        query,
        positionIndex: index,
        updatedAt: replacedAt + snapshot.length - index,
        deletedAt: 0,
        payload: 'snapshot',
      })
    })
    return replacedAt
  }
}

const history = new SearchRows()
for (let index = 0; index < 101; index += 1) history.localSearch(`q${index}`, index + 1)
ok('101 ordinary searches retain exactly 100 active rows', history.orderedActive().length === 100)
ok('overflow keeps the oldest query as a sync-visible tombstone',
  history.rows.get('q0').deletedAt > history.rows.get('q0').updatedAt)
ok('the newest ordinary search is first without reindexing every active row',
  history.orderedActive()[0].query === 'q100' && history.orderedActive()[0].positionIndex < 0)

const revisitedAt = history.localSearch('q10', 1)
ok('a duplicate search remains one row and moves to the front',
  history.rows.size === 101 && history.orderedActive()[0].query === 'q10')
ok('same-millisecond or clock-backward searches still advance logical time', revisitedAt > 101)

const stale = new SearchRows()
stale.applyRemote({ query: 'same', positionIndex: 8, updatedAt: 20, deletedAt: 0, payload: 'new' })
stale.applyRemote({ query: 'same', positionIndex: 0, updatedAt: 19, deletedAt: 0, payload: 'old' })
ok('an older delayed envelope cannot overwrite a newer local query', stale.rows.get('same').payload === 'new')
stale.applyRemote({ query: 'same', positionIndex: 8, updatedAt: 20, deletedAt: 21, payload: 'delete' })
ok('a newer remote tombstone wins over an active query', stale.rows.get('same').deletedAt === 21)
const readdedAt = stale.localSearch('same', 1)
ok('a later local search advances above the winning tombstone',
  stale.rows.get('same').deletedAt === 0 && readdedAt > 21)

const deleted = new SearchRows()
deleted.localSearch('remove-me', 1)
const deletedAt = deleted.tombstone('remove-me', 1)
deleted.applyRemote({ query: 'remove-me', positionIndex: 0, updatedAt: deletedAt - 1, deletedAt: 0, payload: 'old' })
ok('a single-query tombstone blocks an older delayed record from reviving the query',
  deleted.rows.get('remove-me').deletedAt === deletedAt)

const remoteOverflow = new SearchRows()
for (let index = 0; index < 250; index += 1) {
  remoteOverflow.applyRemote({
    query: `remote${index}`,
    positionIndex: index,
    updatedAt: index + 1,
    deletedAt: 0,
    payload: 'remote',
  })
}
remoteOverflow.localSearch('local', 1)
ok('the next normal search converges an oversized synced table back to 100 active rows',
  remoteOverflow.orderedActive().length === 100)
ok('overflow convergence preserves discarded searches as tombstones',
  [...remoteOverflow.rows.values()].some((row) => row.deletedAt > row.updatedAt))

const replacement = new SearchRows()
replacement.applyRemote({ query: 'future', positionIndex: 0, updatedAt: 9000, deletedAt: 0, payload: 'remote' })
const replacedAt = replacement.replaceAll(['backup'], 1)
ok('full backup replacement rebases above a future row and keeps the snapshot exact',
  replacement.orderedActive().length === 1 && replacement.orderedActive()[0].query === 'backup' &&
    replacement.rows.get('future').deletedAt === replacedAt && replacedAt > 9000)

const settings = read('shared/src/main/ets/settings/SearchHistorySettings.ets')
const repository = read('shared/src/main/ets/storage/SearchHistoryRepository.ets')
const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
const syncService = read('shared/src/main/ets/sync/SyncService.ets')
const huaweiCloud = read('shared/src/main/ets/sync/HuaweiCloudSyncService.ets')

const addStart = settings.indexOf('static async add')
const addEnd = settings.indexOf('\n  static async clear', addStart)
const addMethod = settings.slice(addStart, addEnd)
const removeStart = settings.indexOf('static async remove')
const removeEnd = settings.indexOf('\n  private static async persistAdd', removeStart)
const removeMethod = settings.slice(removeStart, removeEnd)
ok('ordinary add/remove use one-row mutations instead of replaceAll',
  /persistAdd\(context, q\)/.test(addMethod) && !/replaceAll/.test(addMethod) &&
    /persistRemoval\(context, q\)/.test(removeMethod) && !/replaceAll/.test(removeMethod))
ok('settings serializes writes and drains them before backup or provider reads',
  /private static rdbWriteTail: Promise<void> = Promise\.resolve\(\)/.test(settings) &&
    /private static enqueueRdbWrite\(work: \(\) => Promise<void>\): Promise<void>/.test(settings) &&
    /static async flushForSync\(_context: common\.UIAbilityContext\): Promise<void>/.test(settings) &&
    /exportForBackup[\s\S]*flushForSync\(context\)/.test(settings))
ok('storage refresh cannot replace a local mutation that raced its load',
  /private static mutationRevision: number = 0/.test(settings) &&
    /refreshFromStorage[\s\S]*revision === SearchHistorySettings\.mutationRevision/.test(settings))
ok('full replacement is transactional and reserved for clear, backup, and migration',
  /static async replaceAll[\s\S]*store\.beginTransaction\(\)[\s\S]*nextMutationTime\(store, Date\.now\(\)\)[\s\S]*SQL_TOMBSTONE_SCOPE[\s\S]*SQL_RESTORE_UPSERT[\s\S]*store\.commit\(\)[\s\S]*catch \(error\) \{[\s\S]*store\.rollBack\(\)/.test(repository) &&
    /static async clear[\s\S]*SearchHistoryRepository\.replaceAll/.test(settings) &&
    /restoreBackup[\s\S]*SearchHistoryRepository\.replaceAll/.test(settings) &&
    /migrateLegacyPreferences[\s\S]*SearchHistoryRepository\.replaceAll/.test(settings))
ok('legacy migration cannot overwrite durable search history or discard its only recoverable copy',
  /static async hasPersistedState[\s\S]*SQL_HAS_PERSISTED_STATE[\s\S]*resultSet\.goToNextRow\(\)/.test(repository) &&
    /const revision: number = SearchHistorySettings\.mutationRevision/.test(settings) &&
    /await SearchHistoryRepository\.hasPersistedState\(context\)/.test(settings) &&
    /revision !== SearchHistorySettings\.mutationRevision/.test(settings) &&
    /if \(items\.length > 0\)[\s\S]*SearchHistoryRepository\.replaceAll/.test(settings) &&
    /searchhistory_migrate_failed/.test(settings) &&
    /Keep the only legacy copy intact/.test(settings))
ok('ordinary search writes use a transaction, global logical time, min-position promotion, and tombstone trim',
  /static async upsertAndTrim[\s\S]*store\.beginTransaction\(\)[\s\S]*nextMutationTime[\s\S]*nextPositionIndex[\s\S]*SQL_TOMBSTONE_OVERFLOW[\s\S]*store\.commit\(\)/.test(repository) &&
    /SQL_SELECT_MAX_EFFECTIVE_TIME/.test(repository) && /SQL_SELECT_MIN_POSITION/.test(repository) &&
    /query_text NOT IN \(SELECT query_text FROM search_history/.test(repository) &&
    !/DELETE FROM search_history/.test(repository))
ok('normal and remote search-history writes reject older effective timestamps',
  /WHERE excluded\.updated_at >= CASE WHEN COALESCE\(search_history\.deleted_at, 0\) >/.test(repository) &&
    /SQL_APPLY_SEARCH_HISTORY[\s\S]*WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) >/.test(syncAdapter) &&
    /COALESCE\(search_history\.updated_at, 0\)/.test(syncAdapter))
ok('WebDAV and Huawei providers drain pending search-history writes before reading RDB',
  /mergeRemoteEnvelope[\s\S]*selection\.searchHistory[\s\S]*SearchHistorySettings\.flushForSync\(context\)[\s\S]*exportEnvelope/.test(syncService) &&
    /cloudSyncNow[\s\S]*selection\.searchHistory[\s\S]*SearchHistorySettings\.flushForSync\(context\)[\s\S]*markDistributedTables/.test(huaweiCloud))

console.log(`✓ search-history RDB contract: ${passed} assertions passed`)

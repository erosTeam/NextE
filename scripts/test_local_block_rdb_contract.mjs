#!/usr/bin/env node
/**
 * Contract: ordinary local-block changes are bounded, tombstone-safe RDB mutations rather than
 * whole-rule-list rewrites. The pure mirror below protects settings/rule independence, durable
 * order, global logical time, and LWW behavior without requiring a device RDB fixture.
 * Run: node scripts/test_local_block_rdb_contract.mjs
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

// Pure mirror of LocalBlockRepository's ordinary methods and full replacement path. It reflects
// the shared logical clock because settings and rules are exported together as one sync dataset.
class LocalBlockRows {
  constructor() {
    this.settings = undefined
    this.rules = new Map()
  }

  nextMutationTime(requestedTime, now) {
    let latest = this.settings === undefined ? 0 : effectiveTime(this.settings)
    for (const row of this.rules.values()) latest = Math.max(latest, effectiveTime(row))
    return Math.max(now, Math.max(0, Math.floor(requestedTime)), latest + 1)
  }

  activeRules() {
    return [...this.rules.values()]
      .filter((row) => row.deletedAt === 0)
      .sort((a, b) => a.positionIndex - b.positionIndex || a.id.localeCompare(b.id))
  }

  setSettings(payload, requestedTime, now) {
    const updatedAt = this.nextMutationTime(requestedTime, now)
    const next = { ...payload, updatedAt, deletedAt: 0 }
    if (this.settings === undefined || updatedAt >= effectiveTime(this.settings)) this.settings = next
    return updatedAt
  }

  upsertRule(id, payload, requestedTime, now) {
    const updatedAt = this.nextMutationTime(requestedTime, now)
    const previous = this.rules.get(id)
    let positionIndex = 0
    if (previous !== undefined && previous.deletedAt === 0) {
      positionIndex = previous.positionIndex
    } else if (this.rules.size > 0) {
      positionIndex = Math.max(...[...this.rules.values()].map((row) => row.positionIndex)) + 1
    }
    const next = { id, positionIndex, ...payload, updatedAt, deletedAt: 0 }
    if (previous === undefined || updatedAt >= effectiveTime(previous)) this.rules.set(id, next)
    return updatedAt
  }

  tombstoneRule(id, requestedTime, now) {
    const deletedAt = this.nextMutationTime(requestedTime, now)
    const previous = this.rules.get(id)
    const next = {
      id,
      positionIndex: previous?.positionIndex ?? 0,
      payload: previous?.payload ?? 'tombstone',
      updatedAt: previous?.updatedAt ?? 0,
      deletedAt,
    }
    if (previous === undefined || deletedAt >= effectiveTime(previous)) this.rules.set(id, next)
    return deletedAt
  }

  applyRemoteSettings(row) {
    if (this.settings === undefined || effectiveTime(row) >= effectiveTime(this.settings)) {
      this.settings = { ...row }
    }
  }

  applyRemoteRule(row) {
    const previous = this.rules.get(row.id)
    if (previous === undefined || effectiveTime(row) >= effectiveTime(previous)) {
      this.rules.set(row.id, { ...row })
    }
  }

  replaceAll(snapshot, requestedTime, now) {
    const replacedAt = this.nextMutationTime(requestedTime, now)
    if (this.settings !== undefined) this.settings = { ...this.settings, deletedAt: replacedAt }
    for (const [id, row] of this.rules) this.rules.set(id, { ...row, deletedAt: replacedAt })
    this.settings = { ...snapshot.settings, updatedAt: replacedAt + 1, deletedAt: 0 }
    snapshot.rules.forEach((rule, index) => {
      this.rules.set(rule.id, {
        ...rule,
        positionIndex: index,
        updatedAt: replacedAt + snapshot.rules.length + 1 - index,
        deletedAt: 0,
      })
    })
    return replacedAt
  }
}

const rows = new LocalBlockRows()
rows.setSettings({ score: -20, mode: 'hide', payload: 'initial' }, 10, 10)
rows.upsertRule('one', { payload: 'one-v1', enabled: true }, 10, 10)
rows.upsertRule('two', { payload: 'two-v1', enabled: true }, 10, 10)
const firstRulePositions = rows.activeRules().map((row) => `${row.id}:${row.positionIndex}`).join(',')
rows.setSettings({ score: -5, mode: 'collapse', payload: 'settings-only' }, 1, 10)
ok('an ordinary score/display change updates the settings record without rewriting rules',
  rows.settings.payload === 'settings-only' &&
    rows.activeRules().map((row) => `${row.id}:${row.positionIndex}`).join(',') === firstRulePositions)

const editedAt = rows.upsertRule('one', { payload: 'one-v2', enabled: false }, 1, 10)
ok('editing an active rule preserves its durable position and changes only that row',
  rows.rules.get('one').positionIndex === 0 && rows.rules.get('one').payload === 'one-v2' &&
    rows.rules.get('two').payload === 'two-v1')
ok('the shared logical clock advances a rule edit past prior settings and rules',
  editedAt > rows.settings.updatedAt && editedAt > rows.rules.get('two').updatedAt)

const removedAt = rows.tombstoneRule('one', 1, 10)
ok('removing one rule leaves its sibling active and retains a sync-visible tombstone',
  rows.activeRules().length === 1 && rows.activeRules()[0].id === 'two' &&
    rows.rules.get('one').deletedAt === removedAt)
rows.applyRemoteRule({ id: 'one', positionIndex: 0, payload: 'stale', updatedAt: removedAt - 1, deletedAt: 0 })
ok('an older remote rule cannot revive a local per-rule tombstone', rows.rules.get('one').deletedAt === removedAt)

const readdedAt = rows.upsertRule('one', { payload: 'one-v3', enabled: true }, 1, 10)
ok('re-adding a removed rule advances above its tombstone and appends after occupied positions',
  readdedAt > removedAt && rows.rules.get('one').deletedAt === 0 && rows.rules.get('one').positionIndex === 2)

const staleSettings = new LocalBlockRows()
staleSettings.applyRemoteSettings({ score: -20, mode: 'hide', payload: 'new', updatedAt: 50, deletedAt: 0 })
staleSettings.applyRemoteSettings({ score: -5, mode: 'collapse', payload: 'old', updatedAt: 49, deletedAt: 0 })
ok('an older remote settings record cannot overwrite a newer local setting', staleSettings.settings.payload === 'new')
staleSettings.applyRemoteSettings({ score: -20, mode: 'hide', payload: 'deleted', updatedAt: 50, deletedAt: 51 })
ok('a newer settings tombstone wins by effective timestamp', staleSettings.settings.deletedAt === 51)

const future = new LocalBlockRows()
future.applyRemoteRule({ id: 'future-active', positionIndex: 0, payload: 'remote', updatedAt: 9000, deletedAt: 0 })
future.applyRemoteRule({ id: 'future-deleted', positionIndex: 1, payload: 'remote', updatedAt: 100, deletedAt: 9500 })
const replacedAt = future.replaceAll({
  settings: { score: -20, mode: 'hide', payload: 'backup' },
  rules: [{ id: 'backup-rule', payload: 'backup', enabled: true }],
}, 1, 10)
ok('a full replacement rebases above future active and tombstoned rows',
  replacedAt > 9500 && future.activeRules().length === 1 && future.activeRules()[0].id === 'backup-rule')
future.applyRemoteRule({ id: 'future-deleted', positionIndex: 1, payload: 'stale-revive', updatedAt: replacedAt - 1, deletedAt: 0 })
ok('an omitted prior tombstone is also rebased, so an older remote record cannot revive it',
  future.rules.get('future-deleted').deletedAt === replacedAt)

const settings = read('shared/src/main/ets/settings/LocalBlockSettings.ets')
const repository = read('shared/src/main/ets/storage/LocalBlockRepository.ets')
const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
const syncService = read('shared/src/main/ets/sync/SyncService.ets')
const huaweiCloud = read('shared/src/main/ets/sync/HuaweiCloudSyncService.ets')

const upsertStart = settings.indexOf('static async upsertRule')
const upsertEnd = settings.indexOf('\n  static async removeRule', upsertStart)
const upsertMethod = settings.slice(upsertStart, upsertEnd)
const removeStart = settings.indexOf('static async removeRule')
const removeEnd = settings.indexOf('\n  static async setRuleEnabled', removeStart)
const removeMethod = settings.slice(removeStart, removeEnd)
ok('ordinary UI mutations use granular repositories rather than whole-state replacement',
  /persistRule\(context, next\)/.test(upsertMethod) && !/replaceAll/.test(upsertMethod) &&
    /persistRuleRemoval\(context, ruleId\)/.test(removeMethod) && !/replaceAll/.test(removeMethod))
ok('repository uses a cross-table clock, preserves active positions, and does not physically delete rules',
  /SQL_SELECT_MAX_EFFECTIVE_TIME/.test(repository) && /positionForUpsert/.test(repository) &&
    /SQL_SELECT_MAX_RULE_POSITION/.test(repository) && /SQL_TOMBSTONE_RULE/.test(repository) &&
    !/DELETE FROM local_block_/.test(repository))
const tombstoneRulesStart = repository.indexOf('const SQL_TOMBSTONE_RULES')
const tombstoneRulesEnd = repository.indexOf('const SQL_TOMBSTONE_RULE:', tombstoneRulesStart)
const tombstoneRules = repository.slice(tombstoneRulesStart, tombstoneRulesEnd)
ok('full replacement advances every prior rule tombstone before restoring its snapshot',
  /UPDATE local_block_rules SET deleted_at = \?[\s\S]*?WHERE scope_key = \?/.test(tombstoneRules) &&
    !/COALESCE\(deleted_at, 0\) = 0/.test(tombstoneRules))
ok('legacy migration keeps RDB canonical when any settings or rule row already exists',
  /static async hasPersistedState[\s\S]*?SQL_HAS_PERSISTED_SETTINGS[\s\S]*?SQL_HAS_PERSISTED_RULES/.test(repository) &&
    /migrateLegacyPreferences[\s\S]*?hasPersistedState\(context\)/.test(settings))
ok('providers drain queued writes and remote applies use LWW for both local block tables',
  /SQL_APPLY_LOCAL_BLOCK_SETTINGS[\s\S]*?WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) >/.test(syncAdapter) &&
    /SQL_APPLY_LOCAL_BLOCK_RULE[\s\S]*?WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) >/.test(syncAdapter) &&
    /mergeRemoteEnvelope[\s\S]*?selection\.localBlock[\s\S]*?LocalBlockSettings\.flushForSync\(context\)/.test(syncService) &&
    /cloudSyncNow[\s\S]*?selection\.localBlock[\s\S]*?LocalBlockSettings\.flushForSync\(context\)/.test(huaweiCloud))

console.log(`✓ local-block RDB contract: ${passed} assertions passed`)

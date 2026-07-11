#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

let passed = 0
const ok = (name, condition) => {
  assert.ok(condition, name)
  passed += 1
}

// Model the retention rule: expired rows are removed first; the most recently cached active rows survive.
{
  const rows = [
    { id: 'expired', cachedAt: 99, expiresAt: 100 },
    { id: 'old', cachedAt: 1, expiresAt: 200 },
    { id: 'middle', cachedAt: 2, expiresAt: 200 },
    { id: 'new', cachedAt: 3, expiresAt: 200 },
  ]
  const now = 100
  const limit = 2
  const retained = rows
    .filter((row) => row.expiresAt > now)
    .sort((left, right) => right.cachedAt - left.cachedAt)
    .slice(0, limit)
    .map((row) => row.id)
  ok('persistent cache retention drops expired rows and keeps the latest active rows',
    retained.join(',') === 'new,middle')
}

const ROOT = process.cwd()
const service = readFileSync(join(ROOT, 'shared/src/main/ets/services/CommentTranslationService.ets'), 'utf8')
const store = readFileSync(join(ROOT, 'shared/src/main/ets/storage/LocalDataStore.ets'), 'utf8')

ok('comment translation RDB cache has a bounded latest-first retention query',
  /MAX_PERSISTED_COMMENT_TRANSLATION_ENTRIES: number = 512/.test(service) &&
    /DELETE FROM comment_translation_cache WHERE rowid NOT IN/.test(service) &&
    /ORDER BY cached_at DESC LIMIT \?/.test(service))
ok('each persisted translation upserts its target row before bounded maintenance',
  /await store\.executeSql\(SQL_UPSERT_COMMENT_TRANSLATION, \[[\s\S]*?if \(!CommentTranslationService\.cacheEpoch\.isCurrent\(cacheEpoch\)\) \{[\s\S]*?shouldRunPersistedCacheMaintenance\(\)/.test(service) &&
    /MAX_PERSISTED_COMMENT_TRANSLATION_ENTRIES/.test(service))
ok('durable translation maintenance is batched, recoverable, and safe under concurrent saves',
  /COMMENT_TRANSLATION_MAINTENANCE_INTERVAL: number = 32/.test(service) &&
    /persistedCacheWritesSinceMaintenance: number = -1/.test(service) &&
    /persistedCacheMaintenanceInFlight: boolean = false/.test(service) &&
    /persistedCacheMaintenanceFollowUp: boolean = false/.test(service) &&
    /private static shouldRunPersistedCacheMaintenance\(\): boolean/.test(service) &&
    /persistedCacheWritesSinceMaintenance < 0[\s\S]*?persistedCacheWritesSinceMaintenance >= COMMENT_TRANSLATION_MAINTENANCE_INTERVAL - 1/.test(service) &&
    /persistedCacheMaintenanceInFlight\) \{[\s\S]*?persistedCacheMaintenanceFollowUp = true/.test(service) &&
    /await store\.executeSql\(SQL_DELETE_EXPIRED_COMMENT_TRANSLATIONS, \[now\]\)[\s\S]*?await store\.executeSql\(SQL_PRUNE_COMMENT_TRANSLATIONS, \[[\s\S]*?comment_cache_maintenance_failed[\s\S]*?finishPersistedCacheMaintenance\(maintenanceSucceeded\)/.test(service) &&
    /succeeded && !hasFollowUp[\s\S]*?COMMENT_TRANSLATION_MAINTENANCE_INTERVAL - 1/.test(service))
ok('RDB schema indexes cached_at for bounded pruning',
  /idx_comment_translation_cache_cached/.test(store) && /cached_at DESC/.test(store))

console.log(`✓ comment translation persistent cache contract: ${passed} assertions passed`)

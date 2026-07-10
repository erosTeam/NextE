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
ok('every persisted translation clears expiry then trims the durable cache',
  /SQL_DELETE_EXPIRED_COMMENT_TRANSLATIONS[\s\S]*?SQL_UPSERT_COMMENT_TRANSLATION[\s\S]*?SQL_PRUNE_COMMENT_TRANSLATIONS/.test(service) &&
    /MAX_PERSISTED_COMMENT_TRANSLATION_ENTRIES/.test(service))
ok('RDB schema indexes cached_at for bounded pruning',
  /idx_comment_translation_cache_cached/.test(store) && /cached_at DESC/.test(store))

console.log(`✓ comment translation persistent cache contract: ${passed} assertions passed`)

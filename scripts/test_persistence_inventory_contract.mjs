#!/usr/bin/env node
import fs from 'fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
let failures = 0

function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

function unique(values) {
  return Array.from(new Set(values)).sort()
}

const doc = read('docs/plans/active/persistence-dataset-inventory.md')
const storageKeys = read('shared/src/main/ets/constants/StorageKeys.ets')
const localStore = read('shared/src/main/ets/storage/LocalDataStore.ets')
const backupAdapter = read('shared/src/main/ets/backup/BackupPreferencesAdapter.ets')
const localDataAdapter = read('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')

const storageKeyNames = unique(
  Array.from(storageKeys.matchAll(/static readonly (\w+): string = '[^']+'/g)).map((m) => m[1]),
)
const tableNames = unique(
  Array.from(localStore.matchAll(/CREATE TABLE(?: IF NOT EXISTS)? ([a-zA-Z0-9_]+)/g)).map((m) => m[1]),
)

for (const name of storageKeyNames) {
  ok(`inventory covers StorageKeys.${name}`,
    new RegExp(`\\|\\s*StorageKeys\\.${name}\\s*\\|`).test(doc))
}

for (const name of tableNames) {
  ok(`inventory covers table ${name}`,
    new RegExp(`\\|\\s*${name}\\s*\\|`).test(doc))
}

const allowedBackups = new Set(['plaintext', 'encrypted-only', 'localData', 'excluded'])
const allowedSyncs = new Set([
  'excluded',
  'WebDAV',
  'HuaweiCloud',
  'WebDAV+HuaweiCloud',
  'metadata-only',
  'migration',
])

for (const line of doc.split('\n')) {
  const row = line.match(/^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|/)
  if (!row || row[1] === 'Key' || row[1] === 'Table' || row[1] === '---') {
    continue
  }
  ok(`${row[1]} has an allowed backup classification`, allowedBackups.has(row[3].trim()))
  ok(`${row[1]} has an allowed sync classification`, allowedSyncs.has(row[4].trim()))
}

ok('runtime StorageKeys remain excluded from backup and sync',
  /\| StorageKeys\.SYNC_LAST_RUN_AT \| runtime \| excluded \| excluded \|/.test(doc) &&
    /\| StorageKeys\.SYNC_HUAWEI_CLOUD_LAST_DETAIL \| runtime \| excluded \| excluded \|/.test(doc) &&
    /\| StorageKeys\.SAFE_MODE_UNLOCKED \| runtime \| excluded \| excluded \|/.test(doc))

ok('image-block physical tables stay split by responsibility',
  /\| image_block_subscriptions \| metadata \| excluded \| WebDAV \|/.test(doc) &&
    /\| image_block_rules \| subscription-cache \| excluded \| excluded \|/.test(doc) &&
    /\| image_block_user_rules \| local-data \| localData \| WebDAV\+HuaweiCloud \|/.test(doc))

const legacyLocalDataKeys = [
  'SEARCH_HISTORY',
  'LOCAL_FAVORITES',
  'VIEWED_HISTORY',
  'READING_PROGRESS',
  'LOCAL_BLOCK_RULES',
  'HOME_CUSTOM_PROFILES',
  'HOME_CUSTOM_PROFILES_SELECTED',
]

for (const key of legacyLocalDataKeys) {
  ok(`${key} legacy Preferences blob is excluded from plaintext backup`,
    new RegExp(`StorageKeys\\.${key}`).test(backupAdapter) &&
      new RegExp(`\\| StorageKeys\\.${key} \\| legacy-local-data \\| excluded \\| excluded \\|`).test(doc))
}

ok('backup localData restores supported legacy local-data blobs but not download queues',
  /GalleryReadProgressSettings\.migrateLegacyPreferences\(context\)/.test(localDataAdapter) &&
    /ViewedHistorySettings\.migrateLegacyPreferences\(context\)/.test(localDataAdapter) &&
    /LocalFavSettings\.migrateLegacyPreferences\(context\)/.test(localDataAdapter) &&
    /SearchHistorySettings\.migrateLegacyPreferences\(context\)/.test(localDataAdapter) &&
    /LocalBlockSettings\.migrateLegacyPreferences\(context\)/.test(localDataAdapter) &&
    /CustomProfilesSettings\.migrateLegacyPreferences\(context\)/.test(localDataAdapter) &&
    !/DownloadQueueSettings\.migrateLegacyPreferences\(context\)/.test(localDataAdapter) &&
    /\| StorageKeys\.DOWNLOAD_GALLERY_QUEUE \| legacy-local-data \| excluded \| excluded \|/.test(doc))

if (failures === 0) {
  console.log('✓ persistence inventory contract passed')
  process.exit(0)
}
console.error(`✗ persistence inventory contract: ${failures} failure(s)`)
process.exit(1)

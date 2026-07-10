#!/usr/bin/env node
/**
 * Contract: reading progress is durable local data, not a growing Preferences JSON blob.
 * Run: node scripts/test_read_progress_rdb_contract.mjs
 */
import fs from 'fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
ok('LocalDataStore has a schema version',
  /LOCAL_DATA_SCHEMA_VERSION: number = \d+/.test(store) &&
    /schema_meta/.test(store) &&
    /store\.version = LOCAL_DATA_SCHEMA_VERSION/.test(store))
ok('RDB table stores gallery read progress with sync-ready metadata',
  /gallery_read_progress/.test(store) &&
    /scope_key TEXT/.test(store) &&
    /gid TEXT/.test(store) &&
    /page_index INTEGER/.test(store) &&
    /column_mode TEXT/.test(store) &&
    /updated_at INTEGER/.test(store) &&
    /deleted_at INTEGER DEFAULT 0/.test(store) &&
    /PRIMARY KEY\(scope_key, gid\)/.test(store))

const repo = read('shared/src/main/ets/storage/ReadProgressRepository.ets')
ok('repository loads and tombstones read progress through RDB',
    /class ReadProgressRepository/.test(repo) &&
    /LocalDataStore\.open\(context\)/.test(repo) &&
    /TABLE_GALLERY_READ_PROGRESS: string = 'gallery_read_progress'/.test(repo) &&
    /SELECT gid, page_index, column_mode, updated_at FROM '\s*\+ TABLE_GALLERY_READ_PROGRESS/.test(repo) &&
    /column_mode = excluded\.column_mode/.test(repo) &&
    /ON CONFLICT\(scope_key, gid\) DO UPDATE/.test(repo) &&
    /UPDATE '\s*\+ TABLE_GALLERY_READ_PROGRESS \+ ' SET deleted_at = \?/.test(repo))
ok('repository rejects stale deferred progress writes by effective record time',
  /WHERE excluded\.updated_at >= CASE WHEN COALESCE\(gallery_read_progress\.deleted_at, 0\) >/.test(repo) &&
    /COALESCE\(gallery_read_progress\.updated_at, 0\)/.test(repo))
{
  const replaceStart = repo.indexOf('static async replaceAll')
  const replaceEnd = repo.indexOf('\n  }\n}', replaceStart)
  const replaceAll = repo.substring(replaceStart, replaceEnd)
  ok('full read-progress replacements are transactional',
    /store\.beginTransaction\(\)[\s\S]*?SQL_TOMBSTONE_SCOPE[\s\S]*?SQL_RESTORE_UPSERT[\s\S]*?store\.commit\(\)[\s\S]*?catch \(error\) \{[\s\S]*?store\.rollBack\(\)[\s\S]*?throw error as Error/.test(replaceAll))
}

const progressState = read('shared/src/main/ets/state/GalleryReadProgressState.ets')
ok('state keeps per-gallery mutation times monotonic and persists column-only choices',
  /private nextUpdatedAt\(gid: string, requestedTime: number\)/.test(progressState) &&
    /if \(!this\.indexMap\.has\(gid\)\) \{\s*this\.indexMap\.set\(gid, 0\)/.test(progressState))

const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
ok('sync apply cannot overwrite a newer local read-progress mutation with an older merge snapshot',
  /SQL_APPLY_READ_PROGRESS[\s\S]*?WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) >/.test(syncAdapter) &&
    /COALESCE\(gallery_read_progress\.deleted_at, 0\)/.test(syncAdapter))

const settings = read('shared/src/main/ets/settings/GalleryReadProgressSettings.ets')
ok('settings facade reads/writes RDB and keeps legacy migration',
  /ReadProgressRepository\.load\(context\)/.test(settings) &&
    /ReadProgressRepository\.saveAll\(context, entries\)/.test(settings) &&
    /migrateLegacyPreferences/.test(settings) &&
    /store\.deleteSync\(StorageKeys\.READING_PROGRESS\)/.test(settings))
ok('settings no longer persists reading progress back to Preferences JSON',
  !/store\.putSync\(StorageKeys\.READING_PROGRESS/.test(settings))
ok('settings persists per-gallery double-page pairing through read progress records',
  /static setColumnMode\(context: common\.UIAbilityContext, gid: string, columnMode: string\): void/.test(settings) &&
    /ReadProgressRepository\.saveAll\(context, entries\)/.test(settings))
ok('sync refresh flushes current reader state and merges only mutations made during the refresh',
  /static async flushForSync\(context: common\.UIAbilityContext\)/.test(settings) &&
    /static async refreshAfterSync\(context: common\.UIAbilityContext\)/.test(settings) &&
    /entriesChangedSince\(before, state\.snapshot\(\)\)/.test(settings) &&
    /state\.mergeNewest\(changedWhileRefreshing\)/.test(settings))

const backupTypes = read('shared/src/main/ets/backup/BackupTypes.ets')
const backupService = read('shared/src/main/ets/backup/BackupService.ets')
const backupAdapter = read('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
ok('backup has a plaintext localData section for read progress',
  /'preferences' \| 'localData' \| 'secrets'/.test(backupTypes) &&
    /BACKUP_SECTION_NAMES: BackupSectionName\[\] = \['preferences', 'localData'\]/.test(backupTypes) &&
    /interface BackupLocalDataSection/.test(backupTypes) &&
    /readProgress: BackupReadProgressEntry\[\]/.test(backupTypes) &&
    /c\?: string/.test(backupTypes))
ok('backup exports/restores localData and migrates old prefs-only backups',
  /BackupLocalDataAdapter\.exportSection\(context\)/.test(backupService) &&
    /BackupLocalDataAdapter\.restoreSection\(context, envelope\.data\.localData\)/.test(backupService) &&
    /BackupLocalDataAdapter\.restoreLegacyPreferences\(context\)/.test(backupService) &&
    /GalleryReadProgressSettings\.exportForBackup\(context\)/.test(backupAdapter) &&
    /GalleryReadProgressSettings\.restoreBackup\(context, entries\)/.test(backupAdapter))

if (failures === 0) {
  console.log('✓ read-progress RDB contract passed')
  process.exit(0)
}
console.error(`✗ read-progress RDB contract: ${failures} failure(s)`)
process.exit(1)

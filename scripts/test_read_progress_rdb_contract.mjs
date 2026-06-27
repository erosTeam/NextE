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
    /updated_at INTEGER/.test(store) &&
    /deleted_at INTEGER DEFAULT 0/.test(store) &&
    /PRIMARY KEY\(scope_key, gid\)/.test(store))

const repo = read('shared/src/main/ets/storage/ReadProgressRepository.ets')
ok('repository loads and replaces read progress through RDB',
  /class ReadProgressRepository/.test(repo) &&
    /LocalDataStore\.open\(context\)/.test(repo) &&
    /SELECT gid, page_index, updated_at FROM gallery_read_progress/.test(repo) &&
    /INSERT OR REPLACE INTO gallery_read_progress/.test(repo) &&
    /DELETE FROM gallery_read_progress WHERE scope_key = \?/.test(repo))

const settings = read('shared/src/main/ets/settings/GalleryReadProgressSettings.ets')
ok('settings facade reads/writes RDB and keeps legacy migration',
  /ReadProgressRepository\.load\(context\)/.test(settings) &&
    /ReadProgressRepository\.saveAll\(context, entries\)/.test(settings) &&
    /migrateLegacyPreferences/.test(settings) &&
    /store\.deleteSync\(StorageKeys\.READING_PROGRESS\)/.test(settings))
ok('settings no longer persists reading progress back to Preferences JSON',
  !/store\.putSync\(StorageKeys\.READING_PROGRESS/.test(settings))

const backupTypes = read('shared/src/main/ets/backup/BackupTypes.ets')
const backupService = read('shared/src/main/ets/backup/BackupService.ets')
const backupAdapter = read('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
ok('backup has a plaintext localData section for read progress',
  /'preferences' \| 'localData' \| 'secrets'/.test(backupTypes) &&
    /BACKUP_SECTION_NAMES: BackupSectionName\[\] = \['preferences', 'localData'\]/.test(backupTypes) &&
    /interface BackupLocalDataSection/.test(backupTypes) &&
    /readProgress: BackupReadProgressEntry\[\]/.test(backupTypes))
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

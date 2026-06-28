#!/usr/bin/env node
/**
 * Contract: gallery and archiver download queues are local task state in RDB, not growing Preferences blobs.
 * Run: node scripts/test_download_queue_rdb_contract.mjs
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
ok('LocalDataStore creates gallery download task and seed tables',
  /download_gallery_tasks/.test(store) &&
    /download_gallery_seeds/.test(store) &&
    /PRIMARY KEY\(scope_key, gid, token\)/.test(store) &&
    /PRIMARY KEY\(scope_key, gid, token, image_page_url\)/.test(store) &&
    /idx_download_gallery_tasks_queued/.test(store) &&
    /idx_download_gallery_seeds_position/.test(store) &&
    /prefer_original INTEGER NOT NULL DEFAULT 0/.test(store))
ok('LocalDataStore migrates existing download task rows to include per-task original preference',
  /LOCAL_DATA_SCHEMA_VERSION: number = 10/.test(store) &&
    /migrateDownloadGalleryPreferOriginal/.test(store) &&
    /ALTER TABLE download_gallery_tasks ADD COLUMN prefer_original/.test(store))
ok('LocalDataStore creates archiver download task table',
  /download_archiver_tasks/.test(store) &&
    /PRIMARY KEY\(scope_key, tag\)/.test(store) &&
    /idx_download_archiver_tasks_queued/.test(store) &&
    /bytes_written INTEGER NOT NULL/.test(store) &&
    /file_path TEXT NOT NULL/.test(store))

const repo = read('shared/src/main/ets/storage/DownloadQueueRepository.ets')
ok('repository loads and replaces queue through RDB',
  /class DownloadQueueRepository/.test(repo) &&
    /LocalDataStore\.open\(context\)/.test(repo) &&
    /SELECT gid, token, title/.test(repo) &&
    /INSERT OR REPLACE INTO download_gallery_tasks/.test(repo) &&
    /INSERT OR REPLACE INTO download_gallery_seeds/.test(repo) &&
    /DELETE FROM download_gallery_tasks WHERE scope_key = \?/.test(repo) &&
    /DELETE FROM download_gallery_seeds WHERE scope_key = \?/.test(repo))
ok('repository restores downloaded seed metadata',
  /seed\.filePath/.test(repo) &&
    /seed\.bytesWritten/.test(repo) &&
    /seed\.downloadedAt/.test(repo) &&
    /seed\.downloadError/.test(repo))
ok('repository persists task original preference',
  /prefer_original/.test(repo) &&
    /task\.preferOriginal/.test(repo))
ok('repository loads and replaces archiver queue through RDB',
  /loadArchiver\(context/.test(repo) &&
    /replaceAllArchiver\(context/.test(repo) &&
    /INSERT OR REPLACE INTO download_archiver_tasks/.test(repo) &&
    /DELETE FROM download_archiver_tasks WHERE scope_key = \?/.test(repo) &&
    /readArchiverTask/.test(repo))

const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
ok('settings facade uses RDB and only reads old Preferences for migration',
  /DownloadQueueRepository\.load\(context\)/.test(settings) &&
    /DownloadQueueRepository\.replaceAll\(context, tasks\)/.test(settings) &&
    /DownloadQueueRepository\.loadArchiver\(context\)/.test(settings) &&
    /DownloadQueueRepository\.replaceAllArchiver\(context, tasks\)/.test(settings) &&
    /migrateLegacyPreferences/.test(settings) &&
    /store\.getSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE/.test(settings) &&
    /store\.deleteSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE\)/.test(settings))
ok('settings no longer writes the queue back to Preferences',
  !/store\.putSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE/.test(settings))
ok('restore normalizes stale in-process gallery download states to resumable states',
  /normalizeRestoredGalleryTasks\(await DownloadQueueRepository\.load\(context\)\)/.test(settings) &&
    /out\.status === DownloadGalleryTaskStatus\.PREPARING \|\|[\s\S]*out\.status === DownloadGalleryTaskStatus\.DOWNLOADING/.test(settings) &&
    /normalizeRestoredGalleryStatus\(out\)/.test(settings) &&
    /task\.downloadedCount\(\) > 0[\s\S]*DownloadGalleryTaskStatus\.PARTIAL/.test(settings) &&
    /task\.seededCount\(\) > 0[\s\S]*DownloadGalleryTaskStatus\.READY/.test(settings))
ok('restore validates downloaded seed file paths before trusting complete state',
  /out\.imageSeeds = DownloadQueueSettings\.normalizeRestoredSeeds\(out\.imageSeeds\)/.test(settings) &&
    /downloadedFileSize\(item\.filePath\)/.test(settings) &&
    /fs\.accessSync\(path\)[\s\S]*fs\.statSync\(path\)[\s\S]*stat\.isFile\(\)/.test(settings) &&
    /item\.filePath = ''[\s\S]*item\.bytesWritten = 0[\s\S]*item\.downloadedAt = 0/.test(settings) &&
    /out\.status === DownloadGalleryTaskStatus\.COMPLETE && out\.pendingDownloadCount\(\) > 0[\s\S]*normalizeRestoredGalleryStatus\(out\)/.test(settings))
ok('restore normalizes stale archiver download state to retryable error',
  /normalizeRestoredArchiverTasks\(await DownloadQueueRepository\.loadArchiver\(context\)\)/.test(settings) &&
    /out\.status === DownloadGalleryTaskStatus\.DOWNLOADING[\s\S]*DownloadGalleryTaskStatus\.ERROR/.test(settings) &&
    /download interrupted/.test(settings))
ok('restore validates completed archiver package before keeping read-ready state',
  /out\.status === DownloadGalleryTaskStatus\.COMPLETE[\s\S]*normalizeRestoredArchiverComplete\(out\)/.test(settings) &&
    /downloadedFileSize\(task\.filePath\)/.test(settings) &&
    /bytes > 0[\s\S]*task\.progress = 100[\s\S]*task\.error = ''/.test(settings) &&
    /task\.status = DownloadGalleryTaskStatus\.ERROR[\s\S]*task\.filePath = ''[\s\S]*task\.bytesWritten = 0[\s\S]*archive file missing/.test(settings))
ok('remove deletes gallery download content after the last task for that gid is removed',
  /removeGallery\([\s\S]*let removed: DownloadGalleryTask \| null = null[\s\S]*removed = it\.copy\(\)[\s\S]*persist\(context, next\)[\s\S]*!DownloadQueueSettings\.hasGalleryTaskWithGid\(next, gid\)[\s\S]*deleteGalleryContent\(context, removed\)/.test(settings) &&
    /deleteGalleryContent\([\s\S]*context\.filesDir[\s\S]*download-gallery[\s\S]*safePathPart\(task\.gid\)[\s\S]*deleteSandboxPath/.test(settings))
ok('remove deletes archiver package and extracted reader cache',
  /removeArchiver\([\s\S]*let removed: DownloadArchiverTask \| null = null[\s\S]*removed = it\.copy\(\)[\s\S]*persistArchiver\(context, next\)[\s\S]*deleteArchiverContent\(context, removed\)/.test(settings) &&
    /deleteArchiverContent\([\s\S]*deleteSandboxPath\(task\.filePath[\s\S]*deleteArchiverExtracts\(context, task\)/.test(settings) &&
    /ARCHIVER_READ_CACHE_DIR: string = 'download-archiver-read'/.test(settings) &&
    /names\[i\]\.startsWith\(prefix\)[\s\S]*deleteSandboxPath/.test(settings))
ok('download content cleanup uses platform recursive directory removal',
  /deleteSandboxPath\(path: string, event: string\)[\s\S]*fs\.statSync\(path\)[\s\S]*stat\.isDirectory\(\)[\s\S]*fs\.rmdirSync\(path\)[\s\S]*fs\.unlinkSync\(path\)/.test(settings))

if (failures === 0) {
  console.log('✓ download queue RDB contract passed')
  process.exit(0)
}
console.error(`✗ download queue RDB contract: ${failures} failure(s)`)
process.exit(1)

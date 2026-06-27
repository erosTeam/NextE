#!/usr/bin/env node
/**
 * Contract: gallery download queue is local task state in RDB, not a growing Preferences blob.
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
ok('LocalDataStore creates download task and seed tables',
  /download_gallery_tasks/.test(store) &&
    /download_gallery_seeds/.test(store) &&
    /PRIMARY KEY\(scope_key, gid, token\)/.test(store) &&
    /PRIMARY KEY\(scope_key, gid, token, image_page_url\)/.test(store) &&
    /idx_download_gallery_tasks_queued/.test(store) &&
    /idx_download_gallery_seeds_position/.test(store))

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

const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
ok('settings facade uses RDB and only reads old Preferences for migration',
  /DownloadQueueRepository\.load\(context\)/.test(settings) &&
    /DownloadQueueRepository\.replaceAll\(context, tasks\)/.test(settings) &&
    /migrateLegacyPreferences/.test(settings) &&
    /store\.getSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE/.test(settings) &&
    /store\.deleteSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE\)/.test(settings))
ok('settings no longer writes the queue back to Preferences',
  !/store\.putSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE/.test(settings))

if (failures === 0) {
  console.log('✓ download queue RDB contract passed')
  process.exit(0)
}
console.error(`✗ download queue RDB contract: ${failures} failure(s)`)
process.exit(1)

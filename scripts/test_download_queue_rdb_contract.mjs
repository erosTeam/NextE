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
    /PRIMARY KEY\(scope_key, gid, token, prefer_original\)/.test(store) &&
    /PRIMARY KEY\(scope_key, gid, token, prefer_original, image_page_url\)/.test(store) &&
    /idx_download_gallery_tasks_queued/.test(store) &&
    /idx_download_gallery_seeds_position/.test(store) &&
    /prefer_original INTEGER NOT NULL DEFAULT 0/.test(store))
ok('LocalDataStore migrates existing download task rows to include per-task original preference',
  /LOCAL_DATA_SCHEMA_VERSION: number = 15/.test(store) &&
    /migrateDownloadGalleryPreferOriginal/.test(store) &&
    /ALTER TABLE download_gallery_tasks ADD COLUMN prefer_original/.test(store))
ok('LocalDataStore migrates gallery queue keys so original and resampled tasks can coexist',
  /migrateDownloadGalleryTaskQualityKey/.test(store) &&
    /hasPrimaryKeyColumn\([\s\S]*download_gallery_tasks[\s\S]*prefer_original/.test(store) &&
    /hasPrimaryKeyColumn\([\s\S]*download_gallery_seeds[\s\S]*prefer_original/.test(store) &&
    /download_gallery_tasks_v15/.test(store) &&
    /download_gallery_seeds_v15/.test(store) &&
    /ALTER TABLE download_gallery_tasks_v15 RENAME TO download_gallery_tasks/.test(store) &&
    /ALTER TABLE download_gallery_seeds_v15 RENAME TO download_gallery_seeds/.test(store))
ok('LocalDataStore persists gallery upgrade source for incremental downloads',
  /upgrade_from_gid TEXT NOT NULL DEFAULT/.test(store) &&
    /migrateDownloadGalleryUpgradeFromGid/.test(store) &&
    /ALTER TABLE download_gallery_tasks ADD COLUMN upgrade_from_gid/.test(store))
ok('LocalDataStore creates archiver download task table',
    /download_archiver_tasks/.test(store) &&
    /PRIMARY KEY\(scope_key, tag\)/.test(store) &&
    /idx_download_archiver_tasks_queued/.test(store) &&
    /token TEXT NOT NULL DEFAULT \\\'\\\'/.test(store) &&
    /thumb_url TEXT NOT NULL DEFAULT \\\'\\\'/.test(store) &&
    /parse_source TEXT NOT NULL DEFAULT \\\'official\\\'/.test(store) &&
    /bytes_written INTEGER NOT NULL/.test(store) &&
    /file_path TEXT NOT NULL/.test(store))
ok('LocalDataStore migrates existing archiver tasks to include source gallery token',
  /migrateDownloadArchiverToken/.test(store) &&
    /ALTER TABLE download_archiver_tasks ADD COLUMN token/.test(store))
ok('LocalDataStore migrates existing archiver tasks to include gallery cover',
  /migrateDownloadArchiverThumbUrl/.test(store) &&
    /ALTER TABLE download_archiver_tasks ADD COLUMN thumb_url/.test(store))
ok('LocalDataStore migrates existing archiver tasks to include parse source',
  /migrateDownloadArchiverParseSource/.test(store) &&
    /ALTER TABLE download_archiver_tasks ADD COLUMN parse_source/.test(store))

const repo = read('shared/src/main/ets/storage/DownloadQueueRepository.ets')
const model = read('shared/src/main/ets/model/DownloadGalleryTask.ets')
ok('repository loads and replaces queue through RDB',
  /class DownloadQueueRepository/.test(repo) &&
    /LocalDataStore\.open\(context\)/.test(repo) &&
    /SELECT gid, token, title/.test(repo) &&
    /INSERT OR REPLACE INTO download_gallery_tasks/.test(repo) &&
    /INSERT OR REPLACE INTO download_gallery_seeds/.test(repo) &&
    /SQL_DELETE_SEEDS_FOR_TASK/.test(repo) &&
    /replaceGalleryTask\(context: common\.UIAbilityContext, task: DownloadGalleryTask\)/.test(repo) &&
    /DELETE FROM download_gallery_tasks WHERE scope_key = \?/.test(repo) &&
    /DELETE FROM download_gallery_seeds WHERE scope_key = \?/.test(repo))
ok('repository replaces gallery and archiver queues atomically',
  /static async replaceAll\(context: common\.UIAbilityContext, tasks: DownloadGalleryTask\[\]\): Promise<void> \{[\s\S]*store\.beginTransaction\(\)[\s\S]*SQL_DELETE_SEEDS[\s\S]*SQL_DELETE_TASKS[\s\S]*upsertTask[\s\S]*store\.commit\(\)[\s\S]*catch \(error\) \{[\s\S]*store\.rollBack\(\)[\s\S]*throw error as Error/.test(repo) &&
    /static async replaceAllArchiver\(context: common\.UIAbilityContext, tasks: DownloadArchiverTask\[\]\): Promise<void> \{[\s\S]*store\.beginTransaction\(\)[\s\S]*SQL_DELETE_ARCHIVER_TASKS[\s\S]*upsertArchiverTask[\s\S]*store\.commit\(\)[\s\S]*catch \(error\) \{[\s\S]*store\.rollBack\(\)[\s\S]*throw error as Error/.test(repo),
  'large download queue replacement cannot leave partially deleted seed rows on interruption')
ok('repository restores downloaded seed metadata',
  /seed\.filePath/.test(repo) &&
    /seed\.bytesWritten/.test(repo) &&
    /seed\.downloadedAt/.test(repo) &&
    /seed\.downloadError/.test(repo))
ok('repository persists task original preference',
  /prefer_original/.test(repo) &&
    /task\.preferOriginal/.test(repo) &&
    /WHERE scope_key = \? AND gid = \? AND token = \? AND prefer_original = \?/.test(repo) &&
    /SQL_DELETE_SEEDS_FOR_TASK[\s\S]*prefer_original = \?/.test(repo) &&
    /loadSeeds\(store, task\.gid, task\.token, task\.preferOriginal\)/.test(repo) &&
    /upsertSeed\(store, task\.gid, task\.token, task\.preferOriginal, seed, i\)/.test(repo))
ok('repository persists gallery upgrade source gid',
  /upgrade_from_gid/.test(repo) &&
    /task\.upgradeFromGid/.test(repo))
ok('repository does not persist false complete status for partially downloaded galleries',
  /normalizedGalleryStatusForWrite\(task\)/.test(repo) &&
    /status === DownloadGalleryTaskStatus\.COMPLETE && !task\.isDownloadComplete\(\)/.test(repo) &&
    /task\.downloadedCount\(\) > 0[\s\S]*DownloadGalleryTaskStatus\.PARTIAL/.test(repo))
ok('repository loads and replaces archiver queue through RDB',
  /loadArchiver\(context/.test(repo) &&
    /replaceAllArchiver\(context/.test(repo) &&
    /replaceArchiverTask\(context: common\.UIAbilityContext, task: DownloadArchiverTask\)/.test(repo) &&
    /SELECT tag, gid, token/.test(repo) &&
    /thumb_url/.test(repo) &&
    /parse_source/.test(repo) &&
    /scope_key, tag, gid, token/.test(repo) &&
    /task\.token/.test(repo) &&
    /task\.thumbUrl/.test(repo) &&
    /task\.parseSource/.test(repo) &&
    /INSERT OR REPLACE INTO download_archiver_tasks/.test(repo) &&
    /DELETE FROM download_archiver_tasks WHERE scope_key = \?/.test(repo) &&
    /readArchiverTask/.test(repo))
ok('paused download status is a durable queue state',
  /static readonly PAUSED: string = 'paused'/.test(model) &&
    /status === DownloadGalleryTaskStatus\.PAUSED/.test(repo) &&
    /status === DownloadGalleryTaskStatus\.PAUSED/.test(read('shared/src/main/ets/settings/DownloadQueueSettings.ets')))

const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const imageResolve = read('shared/src/main/ets/services/ImageResolveService.ets')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const autoResumeBody = settings.match(/shouldAutoResumeGalleryTask\(task: DownloadGalleryTask\): boolean \{[\s\S]*?\n  \}/)?.[0] ?? ''
ok('settings facade uses RDB and only reads old Preferences for migration',
  /DownloadQueueRepository\.load\(context\)/.test(settings) &&
    /DownloadQueueRepository\.replaceAll\(context, tasks\)/.test(settings) &&
    /DownloadQueueRepository\.replaceGalleryTask\(context, task\)/.test(settings) &&
    /DownloadQueueRepository\.loadArchiver\(context\)/.test(settings) &&
    /DownloadQueueRepository\.replaceAllArchiver\(context, tasks\)/.test(settings) &&
    /DownloadQueueRepository\.replaceArchiverTask\(context, task\)/.test(settings) &&
    /migrateLegacyPreferences/.test(settings) &&
    /store\.getSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE/.test(settings) &&
    /store\.deleteSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE\)/.test(settings))
ok('settings no longer writes the queue back to Preferences',
  !/store\.putSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE/.test(settings))
ok('download directories keep per-task metadata sidecars for queue recovery',
  /DOWNLOAD_METADATA_FILE: string = 'metadata\.json'/.test(settings) &&
    /ARCHIVER_METADATA_SUFFIX: string = '\.metadata\.json'/.test(settings) &&
    /DOWNLOAD_PUBLIC_APP_DIR: string = 'com\.erosteam\.nexte'/.test(settings) &&
    /DOWNLOAD_PUBLIC_DOCS_URI: string = 'file:\/\/docs\/storage\/Users\/currentUser\/Download'/.test(settings) &&
    /Environment\.getUserDownloadDir\(\)/.test(settings) &&
    /new fileUri\.FileUri\(DownloadQueueSettings\.joinPath\(DOWNLOAD_PUBLIC_DOCS_URI, DOWNLOAD_PUBLIC_APP_DIR\)\)\.path/.test(settings) &&
    /downloadRootCandidates\(context: common\.UIAbilityContext\)[\s\S]*publicDownloadRootDir\(\)[\s\S]*context\.filesDir/.test(settings) &&
    /galleryRootDirs\(context: common\.UIAbilityContext\)[\s\S]*DOWNLOAD_GALLERY_DIR/.test(settings) &&
    /archiverRootDirs\(context: common\.UIAbilityContext\)[\s\S]*DOWNLOAD_ARCHIVER_DIR/.test(settings) &&
    /class DownloadGalleryTaskMetadata/.test(settings) &&
    /class DownloadArchiverTaskMetadata/.test(settings) &&
    /writeGalleryMetadataTasks\(context, tasks\)/.test(settings) &&
    /writeArchiverMetadataTasks\(context, tasks\)/.test(settings) &&
    /writeGalleryMetadataTask\(context, task\)/.test(settings) &&
    /writeArchiverMetadataTask\(context, task\)/.test(settings) &&
    /JSON\.stringify\(\[DownloadQueueSettings\.galleryTaskMetadata\(task\)\]\)/.test(settings) &&
    /JSON\.stringify\(\[DownloadQueueSettings\.archiverTaskMetadata\(task\)\]\)/.test(settings) &&
    !/JSON\.stringify\(\[task\]\)/.test(settings) &&
    /galleryMetadataPath\(context: common\.UIAbilityContext, task: DownloadGalleryTask\)[\s\S]*ensureGalleryDownloadDir\(context, task\.gid, task\.preferOriginal\)[\s\S]*DOWNLOAD_METADATA_FILE/.test(settings) &&
    /archiverMetadataPath\(context: common\.UIAbilityContext, task: DownloadArchiverTask\)[\s\S]*ensureArchiverDownloadDir\(context\)[\s\S]*ARCHIVER_METADATA_SUFFIX/.test(settings) &&
    /writeTextFile\(path: string, text: string, event: string\)[\s\S]*fs\.OpenMode\.CREATE[\s\S]*fs\.OpenMode\.TRUNC[\s\S]*fs\.writeSync/.test(settings))
ok('restore falls back to download metadata sidecars without overriding RDB rows',
    /mergeRestoredGalleryTasks\([\s\S]*normalizeRestoredGalleryTasks\(await DownloadQueueRepository\.load\(context\)\)[\s\S]*loadGalleryMetadataTasks\(context\)/.test(settings) &&
    /mergeRestoredArchiverTasks\([\s\S]*normalizeRestoredArchiverTasks\(await DownloadQueueRepository\.loadArchiver\(context\)\)[\s\S]*loadArchiverMetadataTasks\(context\)/.test(settings) &&
    /loadGalleryMetadataTasks\(context: common\.UIAbilityContext\)[\s\S]*galleryRootDirs\(context\)[\s\S]*legacyGalleryRootDir\(context\)[\s\S]*fs\.listFileSync\(root\)/.test(settings) &&
    /loadArchiverMetadataTasks\(context: common\.UIAbilityContext\)[\s\S]*archiverRootDirs\(context\)[\s\S]*legacyArchiverRootDir\(context\)[\s\S]*fs\.listFileSync\(root\)/.test(settings) &&
    /mergeRestoredGalleryTasks\([\s\S]*const out: DownloadGalleryTask\[\] = primary\.map[\s\S]*sameGalleryTask\(it, task\.gid, task\.token, task\.preferOriginal\)[\s\S]*out\.push\(task\.copy\(\)\)/.test(settings) &&
    /mergeRestoredArchiverTasks\([\s\S]*const out: DownloadArchiverTask\[\] = primary\.map[\s\S]*it\.tag === task\.tag[\s\S]*out\.push\(task\.copy\(\)\)/.test(settings))
ok('archiver tasks inherit missing title token and cover from matching gallery queue tasks',
  /hydrateArchiverTasksFromGalleryTasks\([\s\S]*mergeRestoredArchiverTasks\([\s\S]*galleryTasks/.test(settings) &&
    /fillArchiverTaskFromGalleryTask\([\s\S]*task\.token\.length === 0[\s\S]*task\.token = galleryTask\.token/.test(settings) &&
    /task\.title\.length === 0[\s\S]*task\.title = galleryTask\.title/.test(settings) &&
    /task\.thumbUrl\.length === 0[\s\S]*task\.thumbUrl = galleryTask\.thumbUrl/.test(settings) &&
    /enqueueArchiver\([\s\S]*fillArchiverTaskFromGalleryTask\([\s\S]*findGalleryTaskIn\(state\.galleryTasks, refreshed\.gid, refreshed\.token\)/.test(settings))
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
    /out\.status === DownloadGalleryTaskStatus\.COMPLETE[\s\S]*out\.pendingDownloadCount\(\) > 0[\s\S]*normalizeRestoredGalleryStatus\(out\)/.test(settings))
ok('restore normalizes stale archiver download state to queued resume',
  /normalizeRestoredArchiverTasks\(await DownloadQueueRepository\.loadArchiver\(context\)\)/.test(settings) &&
    /out\.status === DownloadGalleryTaskStatus\.DOWNLOADING[\s\S]*DownloadGalleryTaskStatus\.QUEUED/.test(settings) &&
    /out\.error = ''/.test(settings))
ok('bootstrap resumes restored queued gallery and archiver downloads without blocking first paint',
  /DownloadQueueSettings\.resumePendingDownloads\(context\)/.test(bootstrap) &&
    !/await DownloadQueueSettings\.resumePendingDownloads/.test(bootstrap) &&
    /static async resumePendingDownloads/.test(settings) &&
    /pendingResume: Promise<void> \| null/.test(settings) &&
    /shouldAutoResumeGalleryTask/.test(settings) &&
    /shouldAutoResumeArchiverTask/.test(settings) &&
    /downloadGalleryImages\([\s\S]*context,[\s\S]*galleryTasks\[i\]\.gid,[\s\S]*galleryTasks\[i\]\.token,[\s\S]*galleryTasks\[i\]\.preferOriginal/.test(settings) &&
    /downloadArchiver\(context, archiverTasks\[i\]\.tag\)/.test(settings))
ok('bootstrap auto-resumes failed tasks only when the Download setting is enabled',
  /connectDownloadSettings\(\)\.autoRetryFailed && task\.status === DownloadGalleryTaskStatus\.ERROR/.test(autoResumeBody) &&
    /shouldAutoResumeArchiverTask\(task: DownloadArchiverTask\): boolean \{[\s\S]*connectDownloadSettings\(\)\.autoRetryFailed && task\.status === DownloadGalleryTaskStatus\.ERROR/.test(settings))
ok('bootstrap does not auto-resume paused gallery downloads',
  /DownloadGalleryTaskStatus\.QUEUED[\s\S]*DownloadGalleryTaskStatus\.READY[\s\S]*DownloadGalleryTaskStatus\.PARTIAL/.test(autoResumeBody) &&
    !/DownloadGalleryTaskStatus\.PAUSED/.test(autoResumeBody))
ok('gallery resume fetches seeds before downloading when a restored task has no image-page seeds',
  /static async downloadGalleryImages/.test(settings) &&
    /found !== null[\s\S]*found\.imageSeeds\.length === 0[\s\S]*refreshGallerySeedsFromRemote\(context, gid, token, connectSiteMode\(\)\.isEx, preferOriginal\)/.test(settings) &&
    /downloadGalleryImages\(context, gid, token, preferOriginal\)/.test(settings))
ok('failed image download retries re-resolve stale EH one-shot image URLs',
  /const shouldRefreshImageUrl: boolean = i > 0/.test(settings) &&
    /resolveOriginal\(image, shouldRefreshImageUrl\)/.test(settings) &&
    /resolve\(image, shouldRefreshImageUrl\)/.test(settings) &&
    /async resolveOriginal\(image: EhGalleryImage, changeSource: boolean = false\): Promise<string>/.test(imageResolve) &&
    /const cached: ImagePageResult \| undefined = changeSource \? undefined : this\.resolved\.get\(image\.sUrl\)/.test(imageResolve) &&
    /await this\.doResolve\(image, changeSource\)/.test(imageResolve))
ok('restore validates completed archiver package before keeping read-ready state',
  /out\.status === DownloadGalleryTaskStatus\.COMPLETE[\s\S]*normalizeRestoredArchiverComplete\(out\)/.test(settings) &&
    /downloadedFileSize\(task\.filePath\)/.test(settings) &&
    /bytes > 0[\s\S]*task\.progress = 100[\s\S]*task\.error = ''/.test(settings) &&
    /task\.status = DownloadGalleryTaskStatus\.ERROR[\s\S]*task\.filePath = ''[\s\S]*task\.bytesWritten = 0[\s\S]*archive file missing/.test(settings))
ok('duplicate archiver submit only suppresses download for a valid completed package',
  /let shouldDownload: boolean = true/.test(settings) &&
    /it\.status === DownloadGalleryTaskStatus\.COMPLETE[\s\S]*downloadedFileSize\(it\.filePath\) > 0[\s\S]*shouldDownload = false/.test(settings) &&
    /it\.status === DownloadGalleryTaskStatus\.DOWNLOADING[\s\S]*refreshed\.status = DownloadGalleryTaskStatus\.DOWNLOADING/.test(settings) &&
    /return shouldDownload/.test(settings) &&
    /const shouldDownload: boolean = await DownloadQueueSettings\.enqueueArchiver/.test(read('feature/gallery/src/main/ets/pages/GalleryArchiverPage.ets')))
ok('ordinary gallery task identity includes original/resampled quality for matching and storage',
  /sameGalleryTask\([\s\S]*task\.gid === gid && task\.token === token && task\.preferOriginal === preferOriginal/.test(settings) &&
    /taskKey\(gid: string, token: string, preferOriginal: boolean\)[\s\S]*galleryQuality\(preferOriginal\)/.test(settings) &&
    /galleryDirName\(gid: string, preferOriginal: boolean\)[\s\S]*preferOriginal \? `\$\{base\}-original` : base/.test(settings) &&
    /ensureGalleryDownloadDir\([\s\S]*galleryDirName\(gid, preferOriginal\)/.test(settings))
ok('incremental gallery downloads inherit files only from the same ordinary quality',
  /findGalleryTaskIn\([\s\S]*preferOriginal: boolean \| null = null[\s\S]*task\.preferOriginal !== preferOriginal/.test(settings) &&
    /findGalleryTaskIn\([\s\S]*task\.upgradeFromGid,[\s\S]*'',[\s\S]*task\.preferOriginal/.test(settings) &&
    /inheritDownloadedSeedsFromParent\([\s\S]*task\.preferOriginal,[\s\S]*parent/.test(settings))
ok('remove deletes only the selected gallery download quality content',
  /removeGallery\([\s\S]*preferOriginal: boolean = false[\s\S]*taskKey\(gid, token, preferOriginal\)[\s\S]*sameGalleryTask\(it, gid, token, preferOriginal\)[\s\S]*deleteGalleryContent\(context, removed\)/.test(settings) &&
    /deleteGalleryContent\([\s\S]*galleryRootDirs\(context\)[\s\S]*legacyGalleryRootDir\(context\)[\s\S]*galleryDirName\(task\.gid, task\.preferOriginal\)[\s\S]*deleteSandboxPath/.test(settings))
ok('remove cancels in-flight gallery workers and discards late batch files',
  /cancelledGalleryDownloads: Set<string>/.test(settings) &&
    /removeGallery\([\s\S]*galleryDownloads\.has\(key\)[\s\S]*cancelledGalleryDownloads\.add\(key\)/.test(settings) &&
    /cancelledGalleryDownloads\.has\(key\)[\s\S]*deleteDownloadSeedResults\(results\)[\s\S]*return/.test(settings) &&
    /deleteDownloadSeedResults\(results: DownloadSeedResult\[\]\)[\s\S]*deleteSandboxPath\(result\.filePath, 'gallery_cancelled_file_delete_failed'\)/.test(settings))
ok('pause marks running gallery workers cancelled while keeping the task resumable',
  /static async pauseGalleryDownload/.test(settings) &&
    /galleryDownloads\.has\(key\)[\s\S]*cancelledGalleryDownloads\.add\(key\)[\s\S]*updateGalleryTaskAfterPause\(context, gid, token, preferOriginal\)/.test(settings) &&
    /updateGalleryStreamProgress\([\s\S]*preferOriginal: boolean[\s\S]*const key: string = DownloadQueueSettings\.taskKey\(gid, token, preferOriginal\)[\s\S]*cancelledGalleryDownloads\.has\(key\)[\s\S]*return[\s\S]*task\.status = DownloadGalleryTaskStatus\.DOWNLOADING/.test(settings) &&
    /updateGalleryTaskAfterPause[\s\S]*task\.status = DownloadGalleryTaskStatus\.PAUSED[\s\S]*task\.prepareError = ''[\s\S]*persistGalleryTask\(context, updatedTask\)/.test(settings))
ok('batch gallery actions reuse per-task resume and pause executors',
  /static async resumeAllGalleryDownloads\(context: common\.UIAbilityContext\)/.test(settings) &&
    /canResumeGalleryTask\(tasks\[i\]\)[\s\S]*downloadGalleryImages\(context, tasks\[i\]\.gid, tasks\[i\]\.token, tasks\[i\]\.preferOriginal\)/.test(settings) &&
    /static async pauseAllGalleryDownloads\(context: common\.UIAbilityContext\)/.test(settings) &&
    /tasks\[i\]\.status === DownloadGalleryTaskStatus\.DOWNLOADING[\s\S]*pauseGalleryDownload\(context, tasks\[i\]\.gid, tasks\[i\]\.token, tasks\[i\]\.preferOriginal\)/.test(settings))
ok('remove deletes archiver package, metadata sidecar, and extracted reader cache',
  /removeArchiver\([\s\S]*let removed: DownloadArchiverTask \| null = null[\s\S]*removed = it\.copy\(\)[\s\S]*persistArchiver\(context, next\)[\s\S]*deleteArchiverContent\(context, removed\)/.test(settings) &&
    /deleteArchiverContent\([\s\S]*archiverMetadataPath\(context, task\)[\s\S]*deleteSandboxPath\(task\.filePath[\s\S]*deleteArchiverExtracts\(context, task\)/.test(settings) &&
    /ARCHIVER_READ_CACHE_DIR: string = 'download-archiver-read'/.test(settings) &&
    /names\[i\]\.startsWith\(prefix\)[\s\S]*deleteSandboxPath/.test(settings))
ok('remove cancels in-flight archiver workers and deletes late package files',
  /cancelledArchiverDownloads: Set<string>/.test(settings) &&
    /removeArchiver\([\s\S]*archiverDownloads\.has\(tag\)[\s\S]*cancelledArchiverDownloads\.add\(tag\)/.test(settings) &&
    /cancelledArchiverDownloads\.has\(tag\)[\s\S]*deleteSandboxPath\(filePath, 'archiver_cancelled_file_delete_failed'\)[\s\S]*return/.test(settings) &&
    /shouldContinueAfterJoinedArchiverDownload/.test(settings))
ok('pause marks running archiver workers cancelled and suppresses late progress callbacks',
  /static async pauseArchiverDownload/.test(settings) &&
    /archiverDownloads\.has\(tag\)[\s\S]*cancelledArchiverDownloads\.add\(tag\)[\s\S]*it\.status = DownloadGalleryTaskStatus\.PAUSED/.test(settings) &&
    /updateArchiverProgress\(tag: string[\s\S]*cancelledArchiverDownloads\.has\(tag\)[\s\S]*return/.test(settings))
ok('batch archiver actions reuse per-task resume and pause executors',
  /static async resumeAllArchiverDownloads\(context: common\.UIAbilityContext\)/.test(settings) &&
    /canResumeArchiverTask\(tasks\[i\]\)[\s\S]*downloadArchiver\(context, tasks\[i\]\.tag\)/.test(settings) &&
    /static async pauseAllArchiverDownloads\(context: common\.UIAbilityContext\)/.test(settings) &&
    /tasks\[i\]\.status === DownloadGalleryTaskStatus\.DOWNLOADING[\s\S]*pauseArchiverDownload\(context, tasks\[i\]\.tag\)/.test(settings))
ok('archiver tasks can switch a failed official original archive to bot parsing without keeping stale package state',
  /static async switchArchiverToBot\([\s\S]*updateArchiverTask\(context, tag, \(task: DownloadArchiverTask\) =>/.test(settings) &&
    /task\.parseSource = DownloadArchiverParseSource\.BOT/.test(settings) &&
    /task\.url = ''[\s\S]*task\.fileName = ''[\s\S]*task\.filePath = ''/.test(settings) &&
    /task\.bytesWritten = 0[\s\S]*task\.bytesTotal = 0[\s\S]*task\.progress = 0/.test(settings) &&
    /task\.status = DownloadGalleryTaskStatus\.QUEUED/.test(settings) &&
    /isOriginalArchiverTask\(task: DownloadArchiverTask\)/.test(settings))
ok('bot archiver resolve pauses when bot settings are incomplete instead of sending a doomed request',
  /ARCHIVE_BOT_SETTINGS_INCOMPLETE: string = 'Archive bot settings are incomplete'/.test(settings) &&
    /resolveArchiverBotUrl\([\s\S]*const settings: DownloadSettingsState = connectDownloadSettings\(\)[\s\S]*!DownloadSettings\.archiveBotReady\(settings\)[\s\S]*it\.status = DownloadGalleryTaskStatus\.PAUSED[\s\S]*it\.error = ARCHIVE_BOT_SETTINGS_INCOMPLETE[\s\S]*archive_bot_resolve_paused_not_ready[\s\S]*return[\s\S]*ArchiveBotService\.requestResolve\([\s\S]*settings/.test(settings))
ok('download content cleanup uses platform recursive directory removal',
  /deleteSandboxPath\(path: string, event: string\)[\s\S]*fs\.statSync\(path\)[\s\S]*stat\.isDirectory\(\)[\s\S]*fs\.rmdirSync\(path\)[\s\S]*fs\.unlinkSync\(path\)/.test(settings))

if (failures === 0) {
  console.log('✓ download queue RDB contract passed')
  process.exit(0)
}
console.error(`✗ download queue RDB contract: ${failures} failure(s)`)
process.exit(1)

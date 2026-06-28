#!/usr/bin/env node
/**
 * Contract: Gallery detail can enqueue a local gallery download task, and the Downloads tab renders
 * that real Gallery queue. This is not the background downloader or archive submit lane.
 *
 * Run: node scripts/test_gallery_download_queue_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    console.error(`✗ ${msg}`)
    failures++
  }
}

const grounding = [
  'eros_fe: lib/pages/gallery/view/sliver/slivers.dart GalleryActions / DownloadGalleryButton; lib/pages/gallery/controller/gallery_page_controller.dart downloadGallery() / _downloadGallery()',
  'primary information: detail keeps cover/title/uploader/read first; Downloads shows selected queue status and task rows',
  'primary action: Read stays primary on detail; gallery download is secondary but high-frequency; Downloads manages queue visibility',
  'scope: detail tap enqueues one local Gallery task and Downloads renders/dedups it; later lanes may advance image handling, but this contract still excludes archive remote submit, full background agents, and pause/resume engine',
  'Harmony expression: low-weight detail action row plus HDS grouped list queue rows; segmented Gallery/Archiver stays in title-bar bottomBuilder',
]

ok(grounding.length === 5, 'gallery download queue lane has five-line grounding')
ok(grounding[0].includes('slivers.dart') && grounding[0].includes('DownloadGalleryButton') &&
  grounding[0].includes('gallery_page_controller.dart') && grounding[0].includes('downloadGallery'),
  'grounding names concrete eros_fe files/components/methods')
ok(grounding[3].includes('full background agents') && grounding[4].includes('bottomBuilder'),
  'grounding states scope boundary and Harmony expression')

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const queuePage = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
const model = read('shared/src/main/ets/model/DownloadGalleryTask.ets')
const state = read('shared/src/main/ets/state/DownloadQueueState.ets')
const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const imageCache = read('shared/src/main/ets/services/CachedImageFileService.ets')
const repository = read('shared/src/main/ets/storage/DownloadQueueRepository.ets')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
const shared = read('shared/src/main/ets/Index.ets')

ok(/export class DownloadGalleryTask/.test(model) && /static fromGallery/.test(model) &&
  /pageCountText/.test(model), 'gallery download task captures display metadata from EhGallery')
ok(/DownloadGalleryTaskStatus\.QUEUED/.test(model), 'gallery task status starts as queued')
ok(/@ObservedV2\s+export class DownloadQueueState/.test(state) &&
  /@Trace galleryTasks: DownloadGalleryTask\[\] = \[\]/.test(state) &&
  /AppStorageV2\.connect\(\s*DownloadQueueState/.test(state),
  'download queue state is V2-only and AppStorageV2-backed')
ok(/DOWNLOAD_GALLERY_QUEUE/.test(keys) && /download\.galleryQueue/.test(keys),
  'download queue has a centralized storage key')
ok(/class DownloadQueueSettings/.test(settings) && /static async restore/.test(settings) &&
  /static async enqueueGallery/.test(settings) && /static async removeGallery/.test(settings),
  'download queue settings owns restore/enqueue/remove')
ok(/it\.gid === task\.gid && it\.token === task\.token/.test(settings) &&
  /return !existed/.test(settings), 'enqueue dedups by gid/token and reports duplicate state')
ok(/DownloadQueueRepository\.replaceAll\(context, tasks\)/.test(settings) &&
  /DownloadQueueRepository\.load\(context\)/.test(settings),
  'queue persists through RDB repository')
ok(!/store\.putSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE/.test(settings),
  'queue no longer writes the large task list to Preferences')
ok(/migrateLegacyPreferences/.test(settings) && /parse\(raw/.test(settings) &&
  /store\.deleteSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE\)/.test(settings),
  'queue still imports and deletes the old Preferences JSON')
ok(/download_gallery_tasks/.test(repository) && /download_gallery_seeds/.test(repository) &&
  /SQL_UPSERT_TASK/.test(repository) && /SQL_UPSERT_SEED/.test(repository),
  'queue repository stores task metadata and image seeds in RDB tables')
ok(/DownloadQueueSettings/.test(bootstrap) && /DownloadQueueSettings\.restore\(context\)/.test(bootstrap),
  'settings bootstrap restores the queue before first paint')
ok(/DownloadGalleryTask/.test(shared) && /connectDownloadQueue/.test(shared) &&
  /DownloadQueueSettings/.test(shared), 'shared barrel exports queue model/state/settings')

ok(/@Local downloadQueue: DownloadQueueState = connectDownloadQueue\(\)/.test(detail),
  'detail page reads queue state')
ok(/enqueueGalleryDownload/.test(detail) && /DownloadGalleryTask\.fromGallery/.test(detail) &&
  /DownloadQueueSettings\.enqueueGallery/.test(detail), 'detail page enqueues gallery task')
ok(/detail_download/.test(detail) && /download_status_queued/.test(detail) &&
  /download_gallery_added/.test(detail) && /download_gallery_already_queued/.test(detail),
  'detail page exposes download/queued labels and toast feedback')
ok(/this\.openReader\(this\.resumeIndex\(\)\)/.test(detail),
  'detail Read action remains the primary header action')

ok(/@Local downloadQueue: DownloadQueueState = connectDownloadQueue\(\)/.test(queuePage),
  'downloads page reads queue state')
ok(/this\.downloadView\.viewType === DownloadViewType\.GALLERY && this\.downloadQueue\.galleryTasks\.length > 0/.test(queuePage),
  'downloads page switches from empty state to real Gallery task rows by task count')
ok(/GalleryTaskSection/.test(queuePage) && /ForEach\(\s*this\.downloadQueue\.galleryTasks/.test(queuePage) &&
  /task\.displayTitle\(\)/.test(queuePage), 'downloads page renders real task rows')
ok(/RemoveTaskButton/.test(queuePage) && /DownloadQueueSettings\.removeGallery/.test(queuePage),
  'downloads page can remove local queued tasks')
ok(/private ReadTaskButton\(task: DownloadGalleryTask\)/.test(queuePage) &&
  /sys\.symbol\.arrow_right/.test(queuePage) &&
  /new ReaderParams\(task\.gid, task\.token, 0, images\.length, task\.displayTitle\(\), images, 1, images\.length\)/.test(queuePage),
  'completed gallery tasks expose a local Reader entry with the full downloaded seed set')
ok(!/const fileCount: number = task\.pageCount|const loadedPages: number = task\.previewPageCount|const perPage: number = task\.firstPageCount/.test(queuePage),
  'downloaded gallery Reader entry does not reuse EH preview-page seed params')
ok(/downloadedSeedImages\(task: DownloadGalleryTask\)/.test(queuePage) &&
  /image\.sUrl = seed\.imagePageUrl/.test(queuePage) &&
  /image\.imageUrl = CachedImageFileService\.displayUri\(seed\.filePath\)/.test(queuePage),
  'downloaded tasks keep EH /s/ identity while feeding local file:// image URLs to Reader')
ok(/localFilePath\(url: string\)/.test(imageCache) &&
  /url\.startsWith\('file:\/\/'\)/.test(imageCache) &&
  /throw new Error\('local image file missing'\)/.test(imageCache),
  'reader image cache treats local file:// images as local files, not network downloads')
ok(!/postArchiver|downloadRemote|downloadLoacal|downloadLocal|DownloadAgentService|PauseTask/.test(
  `${detail}\n${queuePage}\n${settings}`,
), 'queue surface does not submit archives or introduce a separate pause engine')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'detail_download',
    'download_status_queued',
    'download_gallery_added',
    'download_gallery_already_queued',
    'common_remove',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ gallery download queue contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ gallery download queue contract: detail enqueue + real Gallery queue locked')

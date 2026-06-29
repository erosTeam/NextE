#!/usr/bin/env node
/**
 * Contract: the Gallery download queue advances from `/s/` seed preparation to a bounded
 * full-gallery image executor. The executor consumes persisted download settings, records per-page
 * file metadata, and completes the task when every prepared seed has a local file.
 *
 * Run: node scripts/test_gallery_download_first_file_contract.mjs
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
  'eros_fe: lib/common/controller/download_controller.dart downloadGallery() / _addGalleryTask() / _startImageTask(); lib/common/controller/download/image_download_processor.dart downloadImageFlow() / getImageDownloadInfo() / fetchImageInfo()',
  'primary information: Downloads task row shows real file download progress through completion, not only seed preparation',
  'primary action: detail Read remains primary; Download remains secondary; queue row foregrounds download status/progress while Remove is secondary',
  'scope: resolve prepared /s/ seeds to real image URLs, write files under the app sandbox, honor image concurrency, and record per-page metadata; archiver and offline-reader source resolver remain separate lanes',
  'Harmony expression: HDS grouped list task row with downloaded progress in the subtitle; NetworkKit request plus CoreFileKit sandbox write, no new heavy UI',
]

ok(grounding.length === 5, 'download executor lane has five-line grounding')
ok(grounding[0].includes('download_controller.dart') &&
  grounding[0].includes('image_download_processor.dart') &&
  grounding[0].includes('downloadImageFlow') &&
  grounding[0].includes('fetchImageInfo'), 'grounding names concrete eros_fe files and methods')
ok(grounding[3].includes('/s/ seeds') && grounding[3].includes('image concurrency') &&
  grounding[3].includes('per-page metadata'), 'grounding states full executor scope')

const model = read('shared/src/main/ets/model/DownloadGalleryTask.ets')
const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const repo = read('shared/src/main/ets/storage/DownloadQueueRepository.ets')
const client = read('shared/src/main/ets/network/EhHttpClient.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const queue = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')

ok(/filePath: string = ''/.test(model) && /bytesWritten: number = 0/.test(model) &&
  /downloadError: string = ''/.test(model), 'download seed records sandbox file path, bytes, and error')
ok(/downloadedAt: number = 0/.test(model) && /downloadedCount/.test(model) &&
  /downloadProgressText/.test(model) && /pendingDownloadCount/.test(model),
  'gallery task tracks image download progress and remaining work')
ok(/DOWNLOADING: string = 'downloading'/.test(model) &&
  /PARTIAL: string = 'partial'/.test(model) &&
  /COMPLETE: string = 'complete'/.test(model), 'gallery task has full executor statuses')
ok(/preferOriginal: boolean = false/.test(model) && /task\.preferOriginal = this\.preferOriginal/.test(model),
  'gallery task persists the per-task original-image preference')

ok(/downloadGalleryImages/.test(settings) &&
  /connectDownloadSettings\(\)\.concurrency/.test(settings) &&
  /pendingSeeds/.test(settings), 'queue executor consumes persisted concurrency to pick pending work')
ok(/static async downloadGalleryImages[\s\S]*found: DownloadGalleryTask \| null = DownloadQueueSettings\.findTask\(gid, token\)[\s\S]*found\.imageSeeds\.length === 0[\s\S]*shouldRefreshIncompleteSeedList\(found\)[\s\S]*refreshGallerySeedsFromRemote\(context, gid, token, connectSiteMode\(\)\.isEx\)/.test(settings),
  'manual gallery resume fetches remote seeds instead of marking no-seed or incomplete-seed tasks ready')
ok(/galleryDownloads: Map<string, Promise<void>>/.test(settings) &&
  /static async downloadGalleryImages[\s\S]*galleryDownloads\.get\(key\)[\s\S]*await running[\s\S]*runGalleryImageDownload\(context, gid, token\)[\s\S]*galleryDownloads\.delete\(key\)/.test(settings),
  'queue executor joins an in-flight gallery download instead of starting duplicate workers')
ok(/gallery_download_start/.test(settings) &&
  /gallery_download_batch_done/.test(settings) &&
  /gallery_download_done/.test(settings) &&
  /galleryBatchSummary/.test(settings),
  'gallery executor emits redacted start/batch/done diagnostics for real download QA')
ok(/let firstError: string = ''/.test(settings) &&
  /firstError = result\.error\.replace\([\s\S]*substring\(0, 160\)/.test(settings) &&
  /firstError=\$\{firstError\}/.test(settings),
  'failed gallery batches log the first seed error for device-side QA')
ok(/Promise\.all\(jobs\)/.test(settings) &&
  /downloadSeedToFile\(context, gid, token, seed, useOriginal, retryCount\)[\s\S]*\.then\(async \(result: DownloadSeedResult\)[\s\S]*applyDownloadResults\(context, gid, token, \[result\]\)[\s\S]*result\.applied = true/.test(settings),
  'queue executor parallelizes downloads and applies each finished seed immediately')
ok(/private static firstSeedError\(seeds: DownloadImageSeed\[\]\): string/.test(settings) &&
  /const taskError: string = DownloadQueueSettings\.firstSeedError\(task\.imageSeeds\)/.test(settings) &&
  /hasError = hasError \|\| taskError\.length > 0/.test(settings),
  'per-seed progress updates preserve existing seed errors instead of hiding them behind later successes')
ok(/let failedBatchRetries: number = 0/.test(settings) &&
  /if \(hasError\) \{[\s\S]*failedBatchRetries < connectDownloadSettings\(\)\.retryCount[\s\S]*gallery_download_batch_auto_retry[\s\S]*continue[\s\S]*failedBatchRetries = 0/.test(settings),
  'queue executor automatically retries failed batches by re-entering the pending-seed loop')
ok(/ImageResolveService\.getInstance\(\)\.resolve/.test(settings) &&
  /ImageResolveService\.getInstance\(\)\.resolveOriginal/.test(settings),
  'queue executor resolves normal images and honors the always-original policy')
ok(/resolveOriginal\(image, shouldRefreshImageUrl\)[\s\S]*catch \(error\)[\s\S]*original image unavailable[\s\S]*gallery_original_fallback[\s\S]*resolve\(image, shouldRefreshImageUrl\)/.test(settings),
  'original gallery downloads fall back to resampled images only when EH does not offer an original URL')
ok(/task\.preferOriginal\s*\|\|/.test(settings) &&
  /connectDownloadSettings\(\)\.originalMode === DownloadOriginalMode\.ALWAYS/.test(settings),
  'queue executor honors per-task original preference before the global always policy')
ok(/EhGalleryImage/.test(settings) && /image\.sUrl = seed\.imagePageUrl/.test(settings),
  'executor turns DownloadImageSeed back into an image-page resolve seed')
ok(/downloadBinaryToFileInStream\([\s\S]*imageUrl,[\s\S]*tmpPath,[\s\S]*\(loaded: number, total: number\) => \{[\s\S]*updateGalleryStreamProgress\(gid, token, seed, loaded, total\)/.test(settings) &&
  /tmpPath = `\$\{result\.filePath\}\.part`/.test(settings) &&
  /fs\.renameSync\(tmpPath, result\.filePath\)/.test(settings),
  'executor streams the resolved URL to a .part file and atomically promotes it')
ok(/activeDownloadRatio/.test(model) &&
  /updateGalleryStreamProgress\([\s\S]*gid: string,[\s\S]*token: string,[\s\S]*activeBytesWritten = loaded[\s\S]*activeBytesTotal = total/.test(settings) &&
  /visibleActiveRatio > 0/.test(queue),
  'downloads page renders transient stream progress before each file is atomically promoted')
ok(/context\.filesDir/.test(settings) && /download-gallery/.test(settings),
  'executor writes under the app sandbox download-gallery directory')
ok(/prepareGallerySeeds\(/.test(detail), 'detail download still starts through seed preparation')
ok(/galleryPreparations: Map<string, Promise<void>>/.test(settings) &&
  /static async prepareGallerySeeds[\s\S]*galleryPreparations\.get\(key\)[\s\S]*await running[\s\S]*runPrepareGallerySeeds\([\s\S]*galleryPreparations\.delete\(key\)/.test(settings),
  'seed preparation joins an in-flight gallery prepare instead of fetching duplicate preview pages')
ok(/enqueueGalleryDownloadWithPolicy/.test(detail) &&
  /DownloadOriginalMode\.ASK/.test(detail) &&
  /showAlertDialog/.test(detail) &&
  /task\.preferOriginal = preferOriginal/.test(detail),
  'detail download implements ask-mode choice before enqueueing a task')
ok(/await DownloadQueueSettings\.downloadGalleryImages\(context, gid, token\)/.test(settings),
  'seed preparation chains into the gallery image executor after preview seeds are ready')
ok(/parseSeeds/.test(settings) && /raw\.filePath/.test(settings) && /raw\.bytesWritten/.test(settings),
  'persisted queue restores downloaded file metadata')
ok(/mergePreparedSeeds/.test(settings) && /previous\.filePath\.length > 0/.test(settings) &&
  /out\.bytesWritten = previous\.bytesWritten/.test(settings),
  'seed refresh preserves existing downloaded file metadata for incremental updates')
ok(/status === DownloadGalleryTaskStatus\.PREPARING/.test(settings) &&
  /mergePreparedSeeds\([\s\S]*task\.imageSeeds,[\s\S]*seeds,[\s\S]*status === DownloadGalleryTaskStatus\.PREPARING/.test(settings) &&
  /keepExistingNotInIncoming: boolean = false/.test(settings) &&
  /if \(!keepExistingNotInIncoming\) \{[\s\S]*return merged[\s\S]*existing\.forEach/.test(settings),
  'preparing refresh keeps existing seeds instead of replacing the queue with only the first preview page')
ok(/refreshGallerySeedsFromRemote/.test(settings) &&
  /getGalleryDetail\(gid, token, isEx\)/.test(settings) &&
  /updateGalleryTaskMetadata\(context, gid, token, detail\.gallery\)/.test(settings) &&
  /prepareGallerySeeds\(context, gid, token, isEx, detail\.images, detail\.previewPageCount\)/.test(settings),
  'completed queue tasks can refresh remote seeds before the incremental downloader fills missing pages')
ok(/gallery_seed_refresh_start/.test(settings) &&
  /gallery_seed_refresh_done/.test(settings) &&
  /beforeDownloaded/.test(settings) &&
  /after !== null \? after\.downloadedCount\(\) : 0/.test(settings),
  'seed refresh emits bounded diagnostics proving downloaded files are preserved')
ok(/updateGalleryTaskMetadata/.test(settings) &&
  /const pageCount: number = gallery\.fileCountNumber\(\)/.test(settings) &&
  /task\.pageCount = pageCount/.test(settings),
  'incremental refresh normalizes EH fileCount before comparing downloaded seed progress')
ok(/private static sameSeed/.test(settings) &&
  /a\.imgkey\.length > 0 && b\.imgkey\.length > 0[\s\S]*return a\.imgkey === b\.imgkey[\s\S]*a\.page > 0 && b\.page > 0[\s\S]*return a\.page === b\.page/.test(settings) &&
  /URL fallback only covers legacy seed records[\s\S]*a\.imagePageUrl\.length > 0 && b\.imagePageUrl\.length > 0[\s\S]*return a\.imagePageUrl === b\.imagePageUrl/.test(settings),
  'incremental seed identity prefers EH imgkey and only falls back for legacy seed records')
ok(/upgradeFromGid/.test(model) &&
  /gallery\.parentGid !== task\.gid \? gallery\.parentGid : ''/.test(model) &&
  /status === DownloadGalleryTaskStatus\.READY[\s\S]*findGalleryTaskIn\([\s\S]*task\.upgradeFromGid[\s\S]*inheritDownloadedSeedsFromParent/.test(settings) &&
  /inheritDownloadedSeedsFromParent\([\s\S]*it\.imgkey === out\.imgkey[\s\S]*downloadedFileSize\(it\.filePath\)[\s\S]*copyInheritedSeedFile/.test(settings) &&
  /copyInheritedSeedFile\([\s\S]*ensureGalleryDownloadDir\(context, gid\)[\s\S]*pageFilePrefix\(seed\.page\)[\s\S]*fs\.copyFile\(src\.fd, dest\.fd\)[\s\S]*return DownloadQueueSettings\.downloadedFileSize\(targetPath\) > 0 \? targetPath : ''/.test(settings),
  'newer-version gallery downloads inherit parent files by EH imgkey by copying them into the child gallery directory')
ok(/DETAIL_SHEET_DOWNLOAD_UPGRADE/.test(detail) &&
  /canShowDownloadUpgrade\(\): boolean[\s\S]*this\.isDownloadTaskComplete\(task\)[\s\S]*this\.vm\.gallery\.newerVersions\.length > 0/.test(detail) &&
  /download_upgrade_newer/.test(detail) &&
  /DownloadUpgradeSheet/.test(detail) &&
  /ConciseListRow/.test(detail),
  'detail page exposes a standard sheet for newer-version incremental downloads only after the current gallery download is complete')
ok(/enqueueDownloadUpgrade\(version: EhGalleryVersion, preferOriginal: boolean\)/.test(detail) &&
  /EhApiService\.getInstance\(\)\.getGalleryDetail\([\s\S]*version\.gid,[\s\S]*version\.token,[\s\S]*connectSiteMode\(\)\.isEx/.test(detail) &&
  /DownloadGalleryTask\.fromGallery\([\s\S]*detail\.gallery,[\s\S]*version\.gid,[\s\S]*version\.token/.test(detail) &&
  /task\.upgradeFromGid = this\.params\.gid/.test(detail) &&
  /DownloadQueueSettings\.prepareGallerySeeds\([\s\S]*detail\.images,[\s\S]*detail\.previewPageCount/.test(detail),
  'newer-version detail action creates a child task whose parent is the current downloaded gallery')
ok(/DownloadGalleryTaskStatus\.COMPLETE/.test(repo) && /DownloadGalleryTaskStatus\.COMPLETE/.test(settings),
  'repository and legacy parser preserve complete status instead of falling back to queued')
ok(/prefer_original/.test(repo), 'repository persists per-task original preference')

ok(/downloadBinaryToFileInStream/.test(client) && /requestInStream/.test(client) &&
  /dataReceive/.test(client) && /fs\.writeSync/.test(client), 'HTTP client can stream binary response to a sandbox file')

ok(/download_file_progress/.test(queue) && /visibleDownloadedFiles/.test(queue) &&
  /download_status_complete/.test(queue), 'downloads page shows file progress and complete status')
ok(/@Monitor\('downloadQueue\.revision'\)/.test(queue) &&
  /downloadQueueTick/.test(queue) &&
  !/BasicDataSource<DownloadGalleryTask>|galleryDataSource/.test(queue) &&
  /ForEach\(\s*this\.downloadQueue\.galleryTasks,[\s\S]*ListItem\(\)\s*\{[\s\S]*DownloadGalleryTaskCardView\(\{[\s\S]*task: this\.currentGalleryTask\(task\)[\s\S]*downloadQueueRevision: this\.downloadQueueTick/.test(queue) &&
  /@ComponentV2\s+struct DownloadGalleryTaskCardView[\s\S]*@Param task: DownloadGalleryTask[\s\S]*@Param visibleDownloadedFiles: number = 0[\s\S]*@Param visibleSeededFiles: number = 0[\s\S]*@Param visibleActiveRatio: number = 0[\s\S]*private downloadedFiles\(\): number[\s\S]*return this\.visibleDownloadedFiles[\s\S]*private seededFiles\(\): number[\s\S]*return this\.visibleSeededFiles/.test(queue) &&
  !/struct DownloadGalleryTaskCardView[\s\S]*@Local downloadQueue: DownloadQueueState = connectDownloadQueue\(\)/.test(queue) &&
  /visibleStatus: this\.currentGalleryTask\(task\)\.status/.test(queue) &&
  /visibleDownloadedFiles: this\.currentGalleryTask\(task\)\.downloadedCount\(\)/.test(queue) &&
  /visibleSeededFiles: this\.currentGalleryTask\(task\)\.seededCount\(\)/.test(queue) &&
  /visibleActiveRatio: this\.currentGalleryTask\(task\)\.activeDownloadRatio\(\)/.test(queue) &&
  /private static setGalleryTasks\(state: DownloadQueueState, tasks: DownloadGalleryTask\[\]\): void \{[\s\S]*next\.push\(task\.copy\(\)\)[\s\S]*state\.galleryTasks = next[\s\S]*state\.revision = state\.revision \+ 1/.test(settings) &&
  !/private static setGalleryTasks\(state: DownloadQueueState, tasks: DownloadGalleryTask\[\]\): void \{[\s\S]*assignFrom\(task\)[\s\S]*state\.galleryTasks = next/.test(settings),
  'downloads page progress text and bar refresh through fresh task snapshots instead of stale child params')
ok(/task\.status = hasError[\s\S]*\? DownloadGalleryTaskStatus\.ERROR[\s\S]*pendingSeedCount\(task\.imageSeeds\) === 0[\s\S]*DownloadQueueSettings\.galleryDoneStatus\(task\)[\s\S]*DownloadGalleryTaskStatus\.DOWNLOADING/.test(settings) &&
  /galleryDoneStatus\(task: DownloadGalleryTask\): string[\s\S]*task\.isDownloadComplete\(\)[\s\S]*DownloadGalleryTaskStatus\.COMPLETE[\s\S]*DownloadGalleryTaskStatus\.PARTIAL/.test(settings),
  'gallery executor keeps in-flight batches downloading and only completes through the fileCount-aware done status')
ok(/refreshActiveGalleryTask/.test(queue) &&
  /MenuItem\(\{ content: \$r\('app\.string\.common_refresh'\) \}\)/.test(queue) &&
  /DownloadQueueSettings\.refreshGallerySeedsFromRemote/.test(queue) &&
  /connectSiteMode\(\)\.isEx/.test(queue), 'completed gallery task rows expose incremental refresh through the native more menu')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'download_status_downloading',
    'download_status_partial',
    'download_status_complete',
    'download_file_progress',
    'download_original_prompt',
    'download_use_regular_image',
    'download_use_original_image',
    'download_upgrade_newer',
    'download_upgrade_choose',
    'download_upgrade_untitled',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ gallery download executor contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ gallery download executor contract: bounded full-gallery image executor locked')

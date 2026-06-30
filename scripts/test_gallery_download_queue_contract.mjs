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
  'scope: detail tap enqueues one local Gallery task and Downloads renders/dedups it; Downloads owns lightweight retry/pause/remove task management, but this contract still excludes archive remote submit and a separate background agent',
  'Harmony expression: low-weight detail action row plus HDS grouped list queue rows; segmented Gallery/Archiver stays in title-bar bottomBuilder',
]

ok(grounding.length === 5, 'gallery download queue lane has five-line grounding')
ok(grounding[0].includes('slivers.dart') && grounding[0].includes('DownloadGalleryButton') &&
  grounding[0].includes('gallery_page_controller.dart') && grounding[0].includes('downloadGallery'),
  'grounding names concrete eros_fe files/components/methods')
ok(grounding[3].includes('separate background agent') && grounding[4].includes('bottomBuilder'),
  'grounding states scope boundary and Harmony expression')

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const queuePage = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
const model = read('shared/src/main/ets/model/DownloadGalleryTask.ets')
const galleryModel = read('shared/src/main/ets/model/EhGallery.ets')
const state = read('shared/src/main/ets/state/DownloadQueueState.ets')
const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const imageCache = read('shared/src/main/ets/services/CachedImageFileService.ets')
const repository = read('shared/src/main/ets/storage/DownloadQueueRepository.ets')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
const shared = read('shared/src/main/ets/Index.ets')

ok(/export class DownloadGalleryTask/.test(model) && /static fromGallery/.test(model) &&
  /pageCountText/.test(model), 'gallery download task captures display metadata from EhGallery')
ok(/static parseFileCount\(value: string\): number/.test(galleryModel) &&
  /value\.replace\(\/\[,，\\s\]\/g, ''\)/.test(galleryModel) &&
  /fileCountNumber\(\): number \{[\s\S]*EhGallery\.parseFileCount\(this\.fileCount\)/.test(galleryModel) &&
  /task\.pageCount = gallery\.fileCountNumber\(\)/.test(model) &&
  /const pageCount: number = gallery\.fileCountNumber\(\)/.test(settings),
  'download pageCount parsing handles EH thousands separators such as 1,700 instead of parseInt=1')
ok(/upgradeFromGid/.test(model) &&
  /task\.upgradeFromGid = gallery\.parentGid !== task\.gid \? gallery\.parentGid : ''/.test(model),
  'gallery download task records the parent gallery gid for newer-version incremental reuse')
ok(/DownloadGalleryTaskStatus\.QUEUED/.test(model), 'gallery task status starts as queued')
ok(/@ObservedV2\s+export class DownloadQueueState/.test(state) &&
  /@Trace galleryTasks: DownloadGalleryTask\[\] = \[\]/.test(state) &&
  /replaceGalleryTasks\(tasks: DownloadGalleryTask\[\]\): void \{[\s\S]*this\.galleryTasks = tasks[\s\S]*this\.bumpRevision\(\)/.test(state) &&
  /replaceArchiverTasks\(tasks: DownloadArchiverTask\[\]\): void \{[\s\S]*this\.archiverTasks = tasks[\s\S]*this\.bumpRevision\(\)/.test(state) &&
  /bumpRevision\(\): void \{[\s\S]*this\.revision = this\.revision \+ 1[\s\S]*publishDownloadQueueChanged\(\)/.test(state) &&
  /@ObservedV2\s+export class DownloadQueueSignalState[\s\S]*@Trace version: number = 0/.test(state) &&
  /export function connectDownloadQueueSignal\(\): DownloadQueueSignalState \{[\s\S]*return AppStorageV2\.connect\(\s*DownloadQueueSignalState/.test(state) &&
  /export function publishDownloadQueueChanged\(\): void \{[\s\S]*signal\.version = signal\.version \+ 1/.test(state) &&
  /AppStorageV2\.connect\(\s*DownloadQueueState/.test(state) &&
  /AppStorageV2\.connect\(\s*DownloadQueueSignalState/.test(state) &&
  /let sharedDownloadQueueState: DownloadQueueState \| null = null/.test(state) &&
  !/sharedDownloadQueueSignalState/.test(state) &&
  /if \(sharedDownloadQueueState === null\)/.test(state) &&
  /return sharedDownloadQueueState/.test(state),
  'download queue state is V2-only, AppStorageV2-backed, and publishes a separate live signal from inside the state class')
ok(/DOWNLOAD_GALLERY_QUEUE/.test(keys) && /download\.galleryQueue/.test(keys),
  'download queue has a centralized storage key')
ok(/class DownloadQueueSettings/.test(settings) && /static async restore/.test(settings) &&
  /static async enqueueGallery/.test(settings) && /static async removeGallery/.test(settings),
  'download queue settings owns restore/enqueue/remove')
ok(/sameGalleryTask\(it, task\.gid, task\.token, task\.preferOriginal\)/.test(settings) &&
  /return !existed/.test(settings), 'enqueue dedups by gid/token/quality and reports duplicate state')
ok(/DownloadQueueRepository\.replaceAll\(context, tasks\)/.test(settings) &&
  /DownloadQueueRepository\.replaceGalleryTask\(context, task\)/.test(settings) &&
  /DownloadQueueRepository\.load\(context\)/.test(settings),
  'queue persists through RDB repository with full writes for structure and per-task writes for progress')
ok(!/state\.revision = state\.revision \+ 1/.test(settings) &&
  /state\.replaceGalleryTasks\(next\)/.test(settings) &&
  /state\.replaceArchiverTasks\(next\)/.test(settings) &&
  /updateGalleryStreamProgress[\s\S]*const task: DownloadGalleryTask = state\.galleryTasks\[i\][\s\S]*task\.activeBytesWritten = loaded[\s\S]*publishDownloadQueueChanged\(\)/.test(settings),
  'download queue mutations publish through DownloadQueueState methods instead of external revision writes')
ok(!/store\.putSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE/.test(settings),
  'queue no longer writes the large task list to Preferences')
ok(/isDownloadComplete\(\): boolean/.test(model) &&
  /expectedFileCount\(\): number \{[\s\S]*Math\.max\(this\.pageCount, this\.seededCount\(\), this\.downloadedCount\(\)\)/.test(model) &&
  /const total: number = this\.expectedFileCount\(\)[\s\S]*return this\.seededCount\(\) >= total && downloaded >= total/.test(model) &&
  /galleryDoneStatus\(task: DownloadGalleryTask\): string/.test(settings) &&
  /task\.isDownloadComplete\(\)[\s\S]*DownloadGalleryTaskStatus\.COMPLETE[\s\S]*DownloadGalleryTaskStatus\.PARTIAL/.test(settings) &&
  /applyDownloadResults[\s\S]*DownloadQueueSettings\.galleryDoneStatus\(task\)/.test(settings) &&
  /gallery_download_incomplete_seeds/.test(settings),
  'gallery task cannot be marked complete while downloaded count is below the expected file count')
ok(/shouldRefreshIncompleteSeedList\(task: DownloadGalleryTask\): boolean/.test(settings) &&
  /task\.seededCount\(\) >= task\.pageCount/.test(settings) &&
  /pendingSeedCount\(task\.imageSeeds\) === 0/.test(settings),
  'incomplete prepared seed lists are refreshed instead of treated as complete downloads')
ok(/import \{ EhErrorText \} from '\.\.\/i18n\/EhErrorText'/.test(settings) &&
  /import \{ EhErrorKind \} from '\.\.\/network\/EhError'/.test(settings) &&
  /private static userError\(error: Object\): string \{[\s\S]*EhErrorText\.forUser\(error\)/.test(settings) &&
  /raw\.indexOf\(' login status='\) >= 0[\s\S]*EhErrorText\.message\(EhErrorKind\.LoginRequired\)/.test(settings) &&
  /raw\.indexOf\(' maybe-hidden status='\) >= 0[\s\S]*EhErrorText\.message\(EhErrorKind\.MaybeHidden\)/.test(settings) &&
  !/updateDownloadTaskStatus\([\s\S]{0,260}\(error as Error\)\.message/.test(settings) &&
  /result\.error = DownloadQueueSettings\.userError\(error as Object\)/.test(settings) &&
  /it\.error = DownloadQueueSettings\.userError\(error as Object\)/.test(settings),
  'download queue stores user-facing task errors instead of raw diagnostic messages such as detail login status')
ok(/static async refreshGallerySeedsFromRemote[\s\S]*catch \(error\) \{[\s\S]*updateDownloadTaskStatus\([\s\S]*DownloadGalleryTaskStatus\.ERROR[\s\S]*DownloadQueueSettings\.userError\(error as Object\)[\s\S]*gallery_seed_refresh_failed[\s\S]*\(error as Error\)\.message/.test(settings),
  'refreshing an incomplete gallery seed list writes a user-facing task error while logging the raw diagnostic cause')
ok(/private static async updateDownloadTaskStatus[\s\S]*let matched: boolean = false[\s\S]*let exactMatched: boolean = false[\s\S]*sameGalleryTask\(task, gid, token, preferOriginal\)[\s\S]*const exact: boolean = DownloadQueueSettings\.sameGalleryTask\(task, gid, token, preferOriginal\)[\s\S]*const gidFallback: boolean = !exactMatched && task\.gid === gid && task\.preferOriginal === preferOriginal[\s\S]*task\.token = token[\s\S]*gallery_status_update[\s\S]*matched=\$\{matched\} exact=\$\{exactMatched\}/.test(settings),
  'download task status updates log exact gid/token/quality matching and can recover old same-gid tasks with token drift')
ok(/applyDownloadResults\([\s\S]*persistGalleryTask\(context, updatedTask\)/.test(settings) &&
  /updateDownloadTaskStatus[\s\S]*persistGalleryTask\(context, updatedTask\)/.test(settings) &&
  /updatePreparedTask[\s\S]*persistGalleryTask\(context, updatedTask\)/.test(settings) &&
  /updateGalleryTaskAfterPause[\s\S]*persistGalleryTask\(context, updatedTask\)/.test(settings) &&
  !/applyDownloadResults[\s\S]*persist\(context, next\)/.test(settings),
  'download progress and status hot paths persist the changed task instead of rewriting the whole queue')
ok(/migrateLegacyPreferences/.test(settings) && /parse\(raw/.test(settings) &&
  /store\.deleteSync\(StorageKeys\.DOWNLOAD_GALLERY_QUEUE\)/.test(settings),
  'queue still imports and deletes the old Preferences JSON')
ok(/download_gallery_tasks/.test(repository) && /download_gallery_seeds/.test(repository) &&
  /SQL_UPSERT_TASK/.test(repository) && /SQL_UPSERT_SEED/.test(repository),
  'queue repository stores task metadata and image seeds in RDB tables')
ok(/DownloadQueueSettings/.test(bootstrap) && /DownloadQueueSettings\.restore\(context\)/.test(bootstrap),
  'settings bootstrap restores the queue before first paint')
ok(/DownloadGalleryTask/.test(shared) && /connectDownloadQueue/.test(shared) &&
  /DownloadQueueSignalState/.test(shared) && /connectDownloadQueueSignal/.test(shared) &&
  /DownloadQueueSettings/.test(shared), 'shared barrel exports queue model/state/settings')

ok(/@Local downloadQueue: DownloadQueueState = connectDownloadQueue\(\)/.test(detail),
  'detail page reads queue state')
ok(/@Local downloadQueueSignalState: DownloadQueueSignalState = connectDownloadQueueSignal\(\)/.test(detail) &&
  /@Local downloadChipHasTask: boolean = false/.test(detail) &&
  /@Local downloadChipStatus: string = DownloadGalleryTaskStatus\.QUEUED/.test(detail) &&
  /@Monitor\('downloadQueueSignalState\.version'\)[\s\S]*private onDownloadQueueChanged\(\): void \{[\s\S]*this\.downloadQueueTick = this\.downloadQueueTick \+ 1/.test(detail) &&
  /private onDownloadQueueChanged\(\): void \{[\s\S]*this\.syncDownloadChipState\('signal'\)/.test(detail) &&
  /private markDownloadQueueDirty\(\): void \{[\s\S]*this\.downloadQueueTick = this\.downloadQueueTick \+ 1[\s\S]*this\.syncDownloadChipState\('local'\)/.test(detail) &&
  /const inserted: boolean = await DownloadQueueSettings\.enqueueGallery\(this\.ctx\(\), task\)[\s\S]*this\.markDownloadQueueDirty\(\)[\s\S]*DownloadQueueSettings\.prepareGallerySeeds/.test(detail) &&
  /this\.syncDownloadChipState\('ready'\)/.test(detail) &&
  /this\.downloadQueueSignalState\.version < 0/.test(detail) &&
  !/@Monitor\('downloadQueue\.revision'\)/.test(detail),
  'detail page invalidates download button state from both the local enqueue action and the dedicated queue signal')
ok(/enqueueGalleryDownload/.test(detail) && /DownloadGalleryTask\.fromGallery/.test(detail) &&
  /DownloadQueueSettings\.ensureDownloadStorageReady\(this\.ctx\(\)\)/.test(detail) &&
  /DownloadQueueSettings\.enqueueGallery/.test(detail), 'detail page resolves DOWNLOAD storage before enqueueing gallery task')
ok(/detail_download/.test(detail) && /download_status_queued/.test(detail) &&
  /download_gallery_added/.test(detail) && /download_gallery_already_queued/.test(detail),
  'detail page exposes download/queued labels and toast feedback')
ok(/private downloadTask\(\): DownloadGalleryTask \| undefined/.test(detail) &&
  /let best: DownloadGalleryTask \| undefined = undefined/.test(detail) &&
  /const exact: boolean = token\.length === 0 \|\| task\.token === token/.test(detail) &&
  /task\.queuedAt > best\.queuedAt/.test(detail) &&
  /private effectiveDownloadStatus\(task: DownloadGalleryTask\): string[\s\S]*!task\.isDownloadComplete\(\)[\s\S]*DownloadGalleryTaskStatus\.PARTIAL/.test(detail) &&
  /private syncDownloadChipState\(reason: string\): void \{[\s\S]*const task: DownloadGalleryTask \| undefined = this\.downloadTask\(\)[\s\S]*this\.downloadChipStatus = this\.effectiveDownloadStatus\(task\)[\s\S]*this\.downloadChipDownloaded = task\.downloadedCount\(\)[\s\S]*detail_download_chip_sync/.test(detail) &&
  /if \(!this\.downloadChipHasTask\)[\s\S]*detail_download/.test(detail) &&
  /this\.downloadChipStatus === DownloadGalleryTaskStatus\.COMPLETE[\s\S]*download_status_complete/.test(detail) &&
  /this\.downloadChipStatus === DownloadGalleryTaskStatus\.DOWNLOADING[\s\S]*download_status_downloading/.test(detail) &&
  /this\.downloadChipStatus === DownloadGalleryTaskStatus\.ERROR[\s\S]*download_status_error/.test(detail),
  'detail page derives the visible download button status from synced local chip state')
ok(/private isDownloadChipEnabled\(\): boolean \{[\s\S]*return !this\.downloadChipHasTask \|\| this\.downloadChipComplete/.test(detail) &&
  /private DownloadActionChip\(\)[\s\S]*Text\(this\.downloadTitle\(\)\)[\s\S]*\.enabled\(this\.isDownloadChipEnabled\(\)\)[\s\S]*this\.onDownloadChipTap\(\)/.test(detail) &&
  !/this\.DetailActionChip\(\$r\('sys\.symbol\.arrow_down_to_line'\), this\.downloadTitle\(\), this\.isDownloadChipEnabled\(\)/.test(detail),
  'detail download chip reads synced local chip state and is disabled while a task is queued or downloading')
ok(/private onDownloadChipTap\(\): void[\s\S]*if \(task !== undefined\) \{[\s\S]*this\.isDownloadTaskComplete\(task\)[\s\S]*this\.openDownloadedTaskFromDetail\(task\)[\s\S]*return[\s\S]*this\.enqueueGalleryDownloadWithPolicy\(\)/.test(detail) &&
  /private openDownloadedTaskFromDetail\(task: DownloadGalleryTask\): void[\s\S]*CachedImageFileService\.displayUri\(seed\.filePath\)[\s\S]*const index: number = Math\.max\(0, Math\.min\(images\.length - 1, this\.resumeIndex\(\)\)\)[\s\S]*detail_open_local_reader[\s\S]*firstUriHash[\s\S]*new ReaderParams\(task\.gid, task\.token, index, images\.length, task\.displayTitle\(\), images, 1, images\.length\)/.test(detail),
  'detail page completed download chip opens the local file Reader at the saved reading position instead of re-enqueueing')
ok(/this\.openReader\(this\.resumeIndex\(\)\)/.test(detail),
  'detail Read action remains the primary header action')

ok(/@Local downloadQueue: DownloadQueueState = connectDownloadQueue\(\)/.test(queuePage) &&
  /@Local downloadQueueSignal: DownloadQueueSignalState = connectDownloadQueueSignal\(\)/.test(queuePage) &&
  /@Monitor\('downloadQueueSignal\.version'\)[\s\S]*private onDownloadQueueChanged\(\): void \{[\s\S]*this\.downloadQueueTick = this\.downloadQueueTick \+ 1/.test(queuePage) &&
  /this\.downloadQueueSignal\.version < 0/.test(queuePage) &&
  !/@Monitor\('downloadQueue\.revision'\)/.test(queuePage),
  'downloads page reads queue state and repaints from the dedicated queue signal')
ok(/this\.downloadView\.viewType === DownloadViewType\.GALLERY && this\.downloadQueue\.galleryTasks\.length > 0/.test(queuePage),
  'downloads page switches from empty state to real Gallery task rows by task count')
ok(/GalleryTaskSection/.test(queuePage) &&
  /ForEach\(\s*this\.downloadQueue\.galleryTasks/.test(queuePage) &&
  /this\.DownloadGalleryTaskCard\(this\.currentGalleryTask\(task\)\)/.test(queuePage) &&
  !/@ComponentV2\s+struct DownloadGalleryTaskCardView/.test(queuePage) &&
  !/@ComponentV2\s+struct DownloadArchiverTaskCardView/.test(queuePage) &&
  !/visibleStatus|visibleExpectedFiles|visibleDownloadedFiles|visibleSeededFiles|visibleActiveRatio/.test(queuePage) &&
  /@ComponentV2\s+struct DownloadGalleryTaskProgressView[\s\S]*Text\(this\.currentTask\(\)\.displayTitle\(\)\)/.test(queuePage) &&
  /@ComponentV2\s+struct DownloadGalleryTaskProgressView[\s\S]*@Local downloadQueue: DownloadQueueState = connectDownloadQueue\(\)[\s\S]*private currentTask\(\): DownloadGalleryTask/.test(queuePage) &&
  /task\.downloadedFiles/.test(queuePage) &&
  /task\.seededFiles/.test(queuePage) &&
  /task\.activeBytesWritten/.test(queuePage) &&
  /task\.activeBytesTotal/.test(queuePage) &&
  /private DownloadGalleryTaskCard\(task: DownloadGalleryTask\)[\s\S]*DownloadGalleryTaskProgressView\(\{ task: task, queueVersion: this\.downloadQueueTick \}\)/.test(queuePage) &&
  /@ComponentV2\s+struct DownloadGalleryTaskPrimaryAction[\s\S]*private canPause\(\): boolean[\s\S]*DownloadGalleryTaskStatus\.DOWNLOADING/.test(queuePage) &&
  /@ComponentV2\s+struct DownloadGalleryTaskPrimaryAction[\s\S]*private resumeActionIcon\(\): Resource[\s\S]*DownloadGalleryTaskStatus\.ERROR[\s\S]*sys\.symbol\.arrow_clockwise[\s\S]*sys\.symbol\.arrow_right/.test(queuePage) &&
  /@ComponentV2\s+struct DownloadGalleryTaskPrimaryAction[\s\S]*private resumeActionLabel\(\): Resource[\s\S]*DownloadGalleryTaskStatus\.ERROR[\s\S]*common_retry[\s\S]*download_resume/.test(queuePage) &&
  /@Monitor\('downloadQueueSignal\.version'\)[\s\S]*private onDownloadQueueChanged\(\): void/.test(queuePage) &&
  /private static setGalleryTasks\(state: DownloadQueueState, tasks: DownloadGalleryTask\[\]\): void \{[\s\S]*findExistingGalleryTask[\s\S]*existing\.assignFrom\(task\)[\s\S]*next\.push\(existing\)[\s\S]*state\.replaceGalleryTasks\(next\)/.test(settings),
  'downloads page renders real gallery task rows by stable gid/token through mounted row components and the queue signal path for live progress')
ok(/private TaskActionMenu\(\)/.test(queuePage) &&
  /removeActiveGalleryTask/.test(queuePage) &&
  /download_delete_task/.test(queuePage) &&
  /private confirmDeleteGalleryTask\(task: DownloadGalleryTask\): void[\s\S]*download_delete_confirm_message[\s\S]*fontColor: Color\.Red[\s\S]*this\.removeTask\(task\)/.test(queuePage) &&
  /DownloadQueueSettings\.removeGallery/.test(queuePage),
  'downloads page deletes local queued tasks only after an explicit destructive confirmation')
ok(!/private ReadTaskButton\(task: DownloadGalleryTask\)/.test(queuePage) &&
  /private openDownloadedTask\(task: DownloadGalleryTask\): void[\s\S]*this\.readProgress\.getIndex\(task\.gid\)[\s\S]*gallery_open_local_reader[\s\S]*firstUriHash[\s\S]*new ReaderParams\(task\.gid, task\.token, index, images\.length, task\.displayTitle\(\), images, 1, images\.length\)/.test(queuePage),
  'completed gallery tasks use the content area as the local Reader entry with saved reading progress and the full downloaded seed set')
ok(/private openTaskIfComplete\(task: DownloadGalleryTask\): void[\s\S]*this\.canReadTask\(task\)[\s\S]*this\.openDownloadedTask\(task\)/.test(queuePage) &&
  /\.onClick\(\(\) => \{[\s\S]*this\.openTaskIfComplete\(task\)/.test(queuePage),
  'completed gallery task content area opens the local Reader without duplicating a read button')
ok(/private openGalleryTaskSource\(task: DownloadGalleryTask\): void[\s\S]*gallery_open_source_from_download[\s\S]*new GalleryDetailParams/.test(queuePage) &&
  /private GalleryTaskCover\(task: DownloadGalleryTask\)[\s\S]*this\.openGalleryTaskSource\(task\)/.test(queuePage),
  'completed gallery task cover opens the original gallery detail with a diagnostic event instead of local Reader')
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
ok(!/postArchiver|downloadRemote|downloadLoacal|downloadLocal|DownloadAgentService/.test(
  `${detail}\n${queuePage}\n${settings}`,
), 'queue surface does not submit archives or introduce a separate background download agent')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'detail_download',
    'download_status_queued',
    'download_gallery_added',
    'download_gallery_already_queued',
    'download_delete_task',
    'download_delete_confirm_title',
    'download_delete_confirm_message',
    'download_delete_confirm_action',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ gallery download queue contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ gallery download queue contract: detail enqueue + real Gallery queue locked')

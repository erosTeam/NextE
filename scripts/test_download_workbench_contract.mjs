#!/usr/bin/env node
/**
 * Contract: the Downloads tab is a real queue workbench surface, not the old two-line placeholder.
 *
 * eros_fe's first-level Downloads tab is split into Gallery and Archiver queues. NextE's first
 * download lane should expose that structure through a title-bar selector without mixing
 * queue settings into the scrolling queue body.
 *
 * Run: node scripts/test_download_workbench_contract.mjs
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

const page = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
const archiveService = read('shared/src/main/ets/services/ArchiveImageService.ets')
const httpClient = read('shared/src/main/ets/network/EhHttpClient.ets')
const bar = read('entry/src/main/ets/components/DownloadTypeBar.ets')
const index = read('entry/src/main/ets/pages/Index.ets')
const state = read('shared/src/main/ets/state/DownloadViewState.ets')
const shared = read('shared/src/main/ets/Index.ets')
const queueSettings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const model = read('shared/src/main/ets/model/DownloadGalleryTask.ets')
const galleryRenderKeyBody = page.match(/private galleryRenderKey\(task: DownloadGalleryTask\): string \{([\s\S]*?)\n  \}/)?.[1] ?? ''
const archiverRenderKeyBody = page.match(/private archiverRenderKey\(task: DownloadArchiverTask\): string \{([\s\S]*?)\n  \}/)?.[1] ?? ''
const galleryStreamProgressBody =
  queueSettings.match(/private static updateGalleryStreamProgress\([\s\S]*?\n  private static updateArchiverProgress/)?.[0] ?? ''
const archiverStreamProgressBody =
  queueSettings.match(/private static updateArchiverProgress\([\s\S]*?\n  private static async updateArchiverTask/)?.[0] ?? ''

ok(/export enum DownloadViewType/.test(state) && /GALLERY = 'gallery'/.test(state) &&
  /ARCHIVER = 'archiver'/.test(state), 'download shared state defines Gallery and Archiver queue views')
ok(/@ObservedV2\s+export class DownloadViewState/.test(state) && /@Trace viewType/.test(state) &&
  /AppStorageV2\.connect\(\s*DownloadViewState/.test(state), 'download view selection is shared V2 state')
ok(/connectDownloadView/.test(shared) && /DOWNLOAD_SELECTOR_BAR_HEIGHT/.test(shared),
  'shared barrel exports download view state and title-bar height')
ok(/TabSegmentButtonV2/.test(bar) && /SegmentButtonV2Items/.test(bar) && /LengthMetrics/.test(bar),
  'download type control uses the V2-native title-bar segmented selector')
ok(/AppStrings\.get\('tab_gallery'\)/.test(bar) && /AppStrings\.get\('download_archiver'\)/.test(bar),
  'download title-bar selector labels Gallery and Archiver')
ok(/TabSegmentButtonV2\(\{[\s\S]*items: this\.segmentItems\(\)[\s\S]*selectedIndex: this\.selectedIndex\(\)[\s\S]*onItemClicked: \(index: number\) => \{[\s\S]*this\.setSelectedIndex\(index\)/.test(bar) &&
  /private setSelectedIndex\(index: number\): void[\s\S]*this\.downloadView\.viewType = next/.test(bar),
  'download title-bar selector writes the selected queue view')
ok(/DownloadTypeBarCCBuilder/.test(index) && /tab === 3[\s\S]*bottomBuilder/.test(index) &&
  /DOWNLOAD_SELECTOR_BAR_HEIGHT/.test(index), 'Index pins the download selector in title-bar bottomBuilder')
ok(/private downloadMenu\(\): Record<string, Object>/.test(index) &&
  /download_resume_all/.test(index) &&
  /download_pause_all/.test(index) &&
  /content\['menu'\] = this\.downloadMenu\(\)/.test(index),
  'Downloads tab title bar exposes current-queue batch actions instead of an empty menu')
ok(/resumeVisibleDownloads\(\)[\s\S]*DownloadQueueSettings\.resumeAllArchiverDownloads\(context\)[\s\S]*DownloadQueueSettings\.resumeAllGalleryDownloads\(context\)/.test(index) &&
  /pauseVisibleDownloads\(\)[\s\S]*DownloadQueueSettings\.pauseAllArchiverDownloads\(context\)[\s\S]*DownloadQueueSettings\.pauseAllGalleryDownloads\(context\)/.test(index),
  'Downloads tab batch actions reuse shared queue executors for the active queue type')
ok(/@Local downloadView: DownloadViewState = connectDownloadView\(\)/.test(page),
  'download page reads the shared selected queue view')
ok(!/private QueueSwitcher\(\)|SwitchButton|DOWNLOAD_VIEW_GALLERY|DOWNLOAD_VIEW_ARCHIVER/.test(page),
  'download page does not own a scrolling queue switcher')
ok(/SecondaryListScaffold/.test(page),
  'download page uses the existing list scaffold for queue content, not a centered placeholder')
ok(!/SummarySection|download_active_tasks|download_finished_tasks|selectedStatus|selectedActiveCount/.test(page),
  'download page does not put settings-like summary rows before the queue')
ok(/EmptyQueueSection/.test(page) && /selectedEmptyText/.test(page) && /selectedNextStep/.test(page),
  'download page shows per-queue empty-state guidance')
ok(/ListItem\(\)\s*\{[\s\S]*DOWNLOAD_SELECTOR_BAR_HEIGHT[\s\S]*\}\s*if \(this\.downloadView\.viewType === DownloadViewType\.GALLERY && this\.downloadQueue\.galleryTasks\.length > 0\)/.test(page),
  'download task or empty state follows the pinned selector spacer directly')
ok(!/SettingsPreviewSection|download_concurrency|download_original_images|connectDownloadSettings/.test(page),
  'download page does not mix download settings into queue content')
ok(/private DownloadGalleryTaskCard\(task: DownloadGalleryTask\)/.test(page) &&
  /private GalleryTaskCover\(task: DownloadGalleryTask\)[\s\S]*EhThumbnail\(\{[\s\S]*thumbWidth: ThemeConstants\.DOWNLOAD_TASK_COVER_WIDTH/.test(page) &&
  /radius: ThemeConstants\.DOWNLOAD_TASK_COVER_RADIUS/.test(page) &&
  /Text\(task\.displayTitle\(\)\)[\s\S]*maxLines\(2\)/.test(page),
  'gallery tasks render as readable task cards with cover and two-line title')
ok(!/BasicDataSource<DownloadGalleryTask>|BasicDataSource<DownloadArchiverTask>|galleryDataSource|archiverDataSource/.test(page) &&
  /ForEach\(\s*this\.downloadQueue\.galleryTasks,[\s\S]*ListItem\(\)\s*\{[\s\S]*this\.DownloadGalleryTaskCard\(this\.currentGalleryTask\(task\)\)/.test(page) &&
  /ForEach\(\s*this\.downloadQueue\.archiverTasks,[\s\S]*ListItem\(\)\s*\{[\s\S]*this\.DownloadArchiverTaskCard\(this\.currentArchiverTask\(task\)\)/.test(page) &&
  !/@ComponentV2\s+struct DownloadGalleryTaskCardView/.test(page) &&
  !/@ComponentV2\s+struct DownloadArchiverTaskCardView/.test(page) &&
  /private GalleryTaskProgressBar\(task: DownloadGalleryTask\)[\s\S]*this\.taskProgressRatio\([\s\S]*task\.status,[\s\S]*task\.downloadedFiles,[\s\S]*task\.seededFiles,[\s\S]*task\.activeBytesWritten,[\s\S]*task\.activeBytesTotal/.test(page) &&
  /private GalleryTaskStatusText\(task: DownloadGalleryTask\)[\s\S]*this\.taskProgressLabel\([\s\S]*task\.status,[\s\S]*task\.downloadedFiles,[\s\S]*task\.seededFiles/.test(page) &&
  /private GalleryPrimaryAction\(task: DownloadGalleryTask\)[\s\S]*this\.canPauseTask\(task\)[\s\S]*this\.canResumeTask\(task\)/.test(page) &&
  /private DownloadArchiverTaskCard\(task: DownloadArchiverTask\)/.test(page) &&
  /private ArchiverTaskStatusText\(task: DownloadArchiverTask\)[\s\S]*this\.archiverProgressLabel\(task\)/.test(page) &&
  !/initialTask|queueSignal|syncVisibleProgress/.test(page) &&
  !/visibleStatus|visibleDownloadedFiles|visibleSeededFiles|visibleActiveRatio|visibleBytesWritten|visibleProgress/.test(page) &&
  !/downloadQueueRevision/.test(page),
  'gallery download rows render through parent builders that read direct @Trace progress fields')
ok(!/renderQueueRevision|renderGalleryTasks|renderArchiverTasks/.test(page) &&
  /private safeForEachKeyPart\(value: string\): string \{[\s\S]*return value\.replace\(\/\[\^A-Za-z0-9_\]\/g, '_'\)/.test(page) &&
  /private taskKey\(task: DownloadGalleryTask\): string \{[\s\S]*task\.gid[\s\S]*task\.token[\s\S]*task\.preferOriginal \? 'original' : 'resample'/.test(page) &&
  galleryRenderKeyBody.includes('this.taskKey(task)') &&
  !galleryRenderKeyBody.includes('task.downloadedFiles') &&
  !galleryRenderKeyBody.includes('task.seededFiles') &&
  archiverRenderKeyBody.includes('task.tag') &&
  !archiverRenderKeyBody.includes('task.bytesWritten') &&
  !archiverRenderKeyBody.includes('task.progress') &&
  /ForEach\(\s*this\.downloadQueue\.galleryTasks/.test(page) &&
  /ForEach\(\s*this\.downloadQueue\.archiverTasks/.test(page) &&
  /\(task: DownloadGalleryTask\) => this\.galleryRenderKey\(task\)/.test(page) &&
  /\(task: DownloadArchiverTask\) => this\.archiverRenderKey\(task\)/.test(page) &&
  /@Monitor\('downloadQueue\.revision'\)[\s\S]*private onDownloadQueueChanged\(\): void \{[\s\S]*this\.downloadQueueTick = this\.downloadQueueTick \+ 1/.test(page) &&
  /this\.downloadQueueTick < 0/.test(page),
  'download queue page keeps stable row keys while parent builders receive a queue revision pulse')
const taskMetaTextBody = page.match(/private taskMetaText\(task: DownloadGalleryTask\): string \{([\s\S]*?)\n  \}/)?.[1] ?? ''
ok(/private GalleryQualityBadge\(task: DownloadGalleryTask\)[\s\S]*task\.preferOriginal \? 'download_use_original_image' : 'download_use_regular_image'/.test(page) &&
  /private DownloadGalleryTaskCard\(task: DownloadGalleryTask\)[\s\S]*this\.GalleryQualityBadge\(task\)/.test(page) &&
  !taskMetaTextBody.includes('download_use_original_image') &&
  !taskMetaTextBody.includes('download_use_regular_image'),
  'ordinary gallery download cards show original/resampled quality as a title-row badge')
ok(/@ObservedV2\s+export class DownloadGalleryTask/.test(model) &&
  /@ObservedV2\s+export class DownloadArchiverTask/.test(model) &&
  /@Trace status: string/.test(model) &&
  /@Trace imageSeeds: DownloadImageSeed\[\]/.test(model) &&
  /@Trace seededFiles: number/.test(model) &&
  /@Trace downloadedFiles: number/.test(model) &&
  /@Trace progress: number/.test(model),
  'download task models are V2-observed so stable ForEach rows can repaint when task fields change')
const assignFromBody = model.match(/assignFrom\(source: DownloadGalleryTask\): void \{([\s\S]*?)\n  \}/)?.[1] ?? ''
ok(/syncProgressCounts\(\): void \{[\s\S]*this\.seededFiles = this\.imageSeeds\.length[\s\S]*this\.downloadedFiles = DownloadGalleryTask\.countDownloadedSeeds/.test(model) &&
  assignFromBody.includes('this.status = source.status') &&
  assignFromBody.includes('this.imageSeeds = source.imageSeeds.map') &&
  assignFromBody.includes('this.syncProgressCounts()') &&
  /downloadedCount\(\): number \{[\s\S]*this\.imageSeeds\.length > 0[\s\S]*DownloadGalleryTask\.countDownloadedSeeds\(this\.imageSeeds\)[\s\S]*return this\.downloadedFiles/.test(model) &&
  /expectedFileCount\(\): number \{[\s\S]*return Math\.max\(this\.pageCount, this\.seededCount\(\), this\.downloadedCount\(\)\)/.test(model) &&
  /isDownloadComplete\(\): boolean \{[\s\S]*const total: number = this\.expectedFileCount\(\)[\s\S]*this\.seededCount\(\) >= total && downloaded >= total/.test(model) &&
  /applyDownloadResults[\s\S]*task\.syncProgressCounts\(\)/.test(queueSettings),
  'gallery download visible counters and completion state use the same expected seed-backed progress source')
ok(/private static setGalleryTasks\(state: DownloadQueueState, tasks: DownloadGalleryTask\[\]\): void \{[\s\S]*findExistingGalleryTask[\s\S]*existing\.assignFrom\(task\)[\s\S]*next\.push\(existing\)[\s\S]*state\.galleryTasks = next[\s\S]*state\.revision = state\.revision \+ 1/.test(queueSettings) &&
  /private static setArchiverTasks\(state: DownloadQueueState, tasks: DownloadArchiverTask\[\]\): void \{[\s\S]*findExistingArchiverTask[\s\S]*existing\.assignFrom\(task\)[\s\S]*next\.push\(existing\)[\s\S]*state\.archiverTasks = next[\s\S]*state\.revision = state\.revision \+ 1/.test(queueSettings),
  'download queue updates preserve observed task identity so mounted rows receive @Trace progress changes')
ok(/const pulseKey: string = key/.test(galleryStreamProgressBody) &&
  !/`\$\{key\}:\$\{seed\.page\}`/.test(galleryStreamProgressBody) &&
  /let updated: boolean = false/.test(galleryStreamProgressBody) &&
  /updated = true/.test(galleryStreamProgressBody) &&
  /if \(updated\) \{[\s\S]*state\.revision = state\.revision \+ 1/.test(galleryStreamProgressBody) &&
  !/persistGalleryTask/.test(galleryStreamProgressBody) &&
  !/setGalleryTasks/.test(galleryStreamProgressBody),
  'gallery stream progress publishes a throttled queue revision without persistence or row-key churn')
ok(/task\.bytesWritten = loaded/.test(archiverStreamProgressBody) &&
  /task\.bytesTotal = total/.test(archiverStreamProgressBody) &&
  /task\.progress = total > 0/.test(archiverStreamProgressBody) &&
  /task\.status = DownloadGalleryTaskStatus\.DOWNLOADING/.test(archiverStreamProgressBody) &&
  /DownloadQueueSettings\.setArchiverTasks\(state, next\)/.test(archiverStreamProgressBody) &&
  !/persistArchiverTask/.test(archiverStreamProgressBody) &&
  !archiverRenderKeyBody.includes('task.bytesWritten') &&
  !archiverRenderKeyBody.includes('task.progress'),
  'archiver stream progress republishes live bytes through stable task rows without persistence or row-key churn')
ok(/expectedFileCount\(\): number \{[\s\S]*return Math\.max\(this\.pageCount, this\.seededCount\(\), this\.downloadedCount\(\)\)/.test(model) &&
  /private effectiveGalleryStatus\(status: string, downloadedFiles: number, pageCount: number\): string/.test(page) &&
  /status === DownloadGalleryTaskStatus\.COMPLETE && pageCount > 0 && downloadedFiles < pageCount/.test(page) &&
  /private shouldShowGalleryProgress\([\s\S]*status: string,[\s\S]*downloadedFiles: number,[\s\S]*seededFiles: number,[\s\S]*activeBytesWritten: number,[\s\S]*activeBytesTotal: number/.test(page) &&
  /private taskProgressLabel\([\s\S]*status: string,[\s\S]*downloadedFiles: number,[\s\S]*seededFiles: number,[\s\S]*prepareError: string/.test(page) &&
  /private taskProgressRatio\([\s\S]*status: string,[\s\S]*downloadedFiles: number,[\s\S]*activeBytesWritten: number,[\s\S]*activeBytesTotal: number/.test(page) &&
  /const active: number = this\.activeDownloadRatio\(activeBytesWritten, activeBytesTotal\)/.test(page) &&
  /private GalleryTaskProgressBar\(task: DownloadGalleryTask\)[\s\S]*this\.taskProgressRatio\([\s\S]*task\.status,[\s\S]*task\.downloadedFiles,[\s\S]*task\.seededFiles,[\s\S]*task\.activeBytesWritten,[\s\S]*task\.activeBytesTotal/.test(page) &&
  /private GalleryTaskStatusText\(task: DownloadGalleryTask\)[\s\S]*this\.taskProgressLabel\([\s\S]*task\.status,[\s\S]*task\.downloadedFiles,[\s\S]*task\.seededFiles/.test(page) &&
  !/@Param renderProgressLabel|@Param renderProgressRatio|@Param renderShowProgress/.test(page) &&
  /download_file_progress/.test(page) &&
  /download_seed_progress/.test(page),
  'gallery task progress text and bar read direct @Trace fields on each queue revision')
ok(/private taskProgressLabel\([\s\S]*const effectiveStatus: string = this\.effectiveGalleryStatus\(status, downloadedFiles, total\)[\s\S]*if \(effectiveStatus === DownloadGalleryTaskStatus\.COMPLETE\) \{[\s\S]*return this\.statusText\(effectiveStatus\)[\s\S]*\}[\s\S]*const downloadProgress: string = this\.progressText\(downloadedFiles, total\)/.test(page),
  'completed gallery downloads show only the completed status instead of a redundant downloaded/total ratio')
ok(/if \(status === DownloadGalleryTaskStatus\.ERROR\) \{[\s\S]*downloadProgress\.length > 0[\s\S]*download_file_progress/.test(page) &&
  !/private taskProgressLabel[\s\S]*task\.downloadProgressText\(\)/.test(page),
  'gallery download failures keep visible downloaded progress instead of hiding mismatched counts behind a generic error')
ok(/private GalleryTaskActionColumn\(task: DownloadGalleryTask\)/.test(page) &&
  /private GalleryPrimaryAction\(task: DownloadGalleryTask\)/.test(page) &&
  /private GalleryTaskMoreButton\(task: DownloadGalleryTask\)/.test(page) &&
  /sys\.symbol\.dot_grid_2x2/.test(page) &&
  !/sys\.symbol\.line_3_horizontal/.test(page) &&
  /private TaskActionMenu\(\)/.test(page) &&
  /MenuItem\(\{ content: \$r\('app\.string\.download_delete_task'\) \}\)/.test(page) &&
  /private confirmDeleteGalleryTask\(task: DownloadGalleryTask\): void[\s\S]*download_delete_confirm_title[\s\S]*download_delete_confirm_message[\s\S]*fontColor: Color\.Red[\s\S]*this\.removeTask\(task\)/.test(page) &&
  /private confirmDeleteArchiverTask\(task: DownloadArchiverTask\): void[\s\S]*download_delete_confirm_title[\s\S]*download_delete_confirm_message[\s\S]*fontColor: Color\.Red[\s\S]*this\.removeArchiverTask\(task\)/.test(page) &&
  !/private TaskActions\(task: DownloadGalleryTask\)/.test(page) &&
  !/DOWNLOAD_TASK_CARD_HEIGHT/.test(page),
  'task cards expose one state action plus a native more menu, with destructive deletion behind explicit confirmation')
ok(/private ResumeTaskButton\(task: DownloadGalleryTask\)/.test(page) &&
  /private galleryResumeActionIcon\(task: DownloadGalleryTask\): Resource[\s\S]*DownloadGalleryTaskStatus\.ERROR[\s\S]*sys\.symbol\.arrow_clockwise[\s\S]*sys\.symbol\.arrow_right/.test(page) &&
  /private galleryResumeActionLabel\(task: DownloadGalleryTask\): Resource[\s\S]*DownloadGalleryTaskStatus\.ERROR[\s\S]*common_retry[\s\S]*download_resume/.test(page) &&
  /this\.TaskIconButton\(this\.galleryResumeActionIcon\(task\), this\.galleryResumeActionLabel\(task\)/.test(page) &&
  /DownloadQueueSettings\.downloadGalleryImages\(this\.ctx\(\), task\.gid, task\.token, task\.preferOriginal\)/.test(page) &&
  /common_retry/.test(page) && /download_resume/.test(page),
  'gallery retry and continue actions use distinct icon/label semantics while sharing the image executor')
ok(/private PauseTaskButton\(task: DownloadGalleryTask\)/.test(page) &&
  /sys\.symbol\.pause/.test(page) &&
  /DownloadQueueSettings\.pauseGalleryDownload\(this\.ctx\(\), task\.gid, task\.token, task\.preferOriginal\)/.test(page) &&
  /common_pause/.test(page) &&
  /private canPauseTask\(task: DownloadGalleryTask\)[\s\S]*DownloadGalleryTaskStatus\.DOWNLOADING/.test(page),
  'running gallery tasks expose one compact pause action wired to the shared queue')
ok(/status === DownloadGalleryTaskStatus\.PAUSED[\s\S]*download_status_paused/.test(page) &&
  /private canResumeTask\(task: DownloadGalleryTask\)[\s\S]*DownloadGalleryTaskStatus\.QUEUED[\s\S]*DownloadGalleryTaskStatus\.PAUSED/.test(page),
  'queued and paused gallery tasks show a low-weight resume action')
ok(/private ArchiverTaskSection\(\)/.test(page) &&
  /this\.downloadQueue\.archiverTasks/.test(page) &&
  /private DownloadArchiverTaskCard\(task: DownloadArchiverTask\)/.test(page),
  'archiver queue renders real archive task cards')
ok(/DownloadQueueSettings\.downloadArchiver/.test(page) &&
  /DownloadQueueSettings\.removeArchiver/.test(page),
  'archiver task cards wire retry and remove to the archiver queue executor')
ok(/private activeArchiverCanSwitchToBot\(\): boolean/.test(page) &&
  /DownloadSettings\.archiveBotReady\(\)/.test(page) &&
  /task\.parseSource === DownloadArchiverParseSource\.BOT/.test(page) &&
  /task\.dltype === 'org' \|\| resolution\.includes\('original'\)/.test(page) &&
  /download_archiver_use_bot/.test(page) &&
  /DownloadQueueSettings\.switchArchiverToBot/.test(page),
  'archiver task menu can switch a resumable original archive task to the configured archive bot source')
ok(/private TaskActionMenu\(\)[\s\S]*this\.actionMenuKey\.startsWith\('archiver:'\)[\s\S]*this\.activeArchiverCanSwitchToBot\(\)[\s\S]*download_archiver_use_bot[\s\S]*this\.switchActiveArchiverToBot\(\)/.test(page) &&
  /private switchActiveArchiverToBot\(\): void[\s\S]*DownloadQueueSettings\.switchArchiverToBot\(this\.ctx\(\), task\.tag\)/.test(page),
  'rendered archiver task menu exposes the archive bot parse-source switch from the parent action menu')
ok(/private PauseArchiverTaskButton\(task: DownloadArchiverTask\)/.test(page) &&
  /sys\.symbol\.pause/.test(page) &&
  /DownloadQueueSettings\.pauseArchiverDownload/.test(page) &&
  /private canPauseArchiverTask\(task: DownloadArchiverTask\): boolean[\s\S]*task\.status === DownloadGalleryTaskStatus\.DOWNLOADING/.test(page),
  'running archiver tasks expose a low-weight pause action wired to the shared queue')
ok(/private canResumeArchiverTask\(task: DownloadArchiverTask\): boolean[\s\S]*DownloadGalleryTaskStatus\.PAUSED/.test(page) &&
  /private archiverResumeActionIcon\(task: DownloadArchiverTask\): Resource[\s\S]*DownloadGalleryTaskStatus\.ERROR[\s\S]*sys\.symbol\.arrow_clockwise[\s\S]*sys\.symbol\.arrow_right/.test(page) &&
  /private archiverResumeActionLabel\(task: DownloadArchiverTask\): Resource[\s\S]*DownloadGalleryTaskStatus\.ERROR[\s\S]*common_retry[\s\S]*download_resume/.test(page),
  'paused archiver tasks can resume')
ok(/private archiverProgressLabel\(task: DownloadArchiverTask\): string[\s\S]*task\.status === DownloadGalleryTaskStatus\.ERROR[\s\S]*task\.error\.length > 0[\s\S]*`\$\{this\.statusText\(task\.status\)\} · \$\{task\.error\}`/.test(page),
  'archiver task cards show stored failure reason in the existing status subtitle')
ok(/ARCHIVER_ACCEPT: string = 'application\/zip,application\/octet-stream,\*\/\*'/.test(queueSettings) &&
  /downloadBinaryToFileInStream\([\s\S]*ARCHIVER_ACCEPT,[\s\S]*attempts/.test(queueSettings),
  'archiver executor requests archive bytes with a zip/octet-stream Accept header and configured retries')
ok(/archiverDownloads: Map<string, Promise<void>>/.test(queueSettings) &&
  /static async downloadArchiver[\s\S]*archiverDownloads\.get\(tag\)[\s\S]*await running[\s\S]*runArchiverDownload\(context, tag\)[\s\S]*archiverDownloads\.delete\(tag\)/.test(queueSettings),
  'archiver executor joins an in-flight archive download instead of starting duplicate workers')
ok(/archiver_download_start/.test(queueSettings) &&
  /archiver_download_done/.test(queueSettings) &&
  /archiver_download_failed/.test(queueSettings),
  'archiver executor emits redacted start/done/failure diagnostics for real archive QA')
ok(/const IMAGE_ACCEPT: string = 'image\/avif,image\/webp,image\/apng,image\/\*,\*\/\*;q=0\.8'/.test(httpClient) &&
  /accept: string = IMAGE_ACCEPT/.test(httpClient) &&
  /maxAttempts: number = MAX_RETRIES/.test(httpClient),
  'stream binary download keeps image Accept and default retry behavior for Reader image cache')
ok(/const written: number = await EhHttpClient\.writeArrayBuffer\(filePath, bytes\)[\s\S]*if \(written <= 0\) \{[\s\S]*EhHttpClient\.deleteFileQuietly\(filePath\)[\s\S]*throw new Error\('binary response is empty'\)/.test(httpClient) &&
  /let shouldDeleteFile: boolean = false[\s\S]*if \(code >= 500 && attempt < attempts - 1\) \{[\s\S]*shouldDeleteFile = true[\s\S]*else if \(written <= 0\) \{[\s\S]*shouldDeleteFile = true[\s\S]*catch \(error\) \{[\s\S]*shouldDeleteFile = openedTarget[\s\S]*finally \{[\s\S]*if \(shouldDeleteFile\) \{[\s\S]*EhHttpClient\.deleteFileQuietly\(filePath\)/.test(httpClient) &&
  /private static deleteFileQuietly\(filePath: string\): void/.test(httpClient),
  'binary downloads reject and clean up empty or failed responses instead of persisting unreadable files')
ok(/private canReadArchiverTask\(task: DownloadArchiverTask\)/.test(page) &&
  /task\.status === DownloadGalleryTaskStatus\.COMPLETE[\s\S]*task\.filePath\.length > 0/.test(page) &&
  !/private ReadArchiverTaskButton\(task: DownloadArchiverTask\)/.test(page),
  'completed archiver tasks do not duplicate the content-area Reader action with another read button')
ok(/private openArchiverTaskIfComplete\(task: DownloadArchiverTask\): void[\s\S]*this\.canReadArchiverTask\(task\)[\s\S]*this\.openArchiverTask\(task\)/.test(page) &&
  /\.onClick\(\(\) => \{[\s\S]*this\.openArchiverTaskIfComplete\(task\)/.test(page),
  'completed archiver task content area opens the extracted local Reader path without duplicating read controls')
ok(/private openGalleryTaskSource\(task: DownloadGalleryTask\): void[\s\S]*new GalleryDetailParams/.test(page) &&
  /private GalleryTaskCover\(task: DownloadGalleryTask\)[\s\S]*this\.openGalleryTaskSource\(task\)/.test(page),
  'gallery task cover opens the original gallery detail instead of duplicating local Reader')
ok(/private openArchiverTaskSource\(task: DownloadArchiverTask\): void[\s\S]*task\.token\.length === 0[\s\S]*new GalleryDetailParams/.test(page) &&
  /archiver_open_source_from_download/.test(page) &&
  /new GalleryDetailParams\(task\.gid, task\.token, task\.thumbUrl, task\.displayTitle\(\)\)/.test(page) &&
  /private ArchiverTaskCover\(task: DownloadArchiverTask\)[\s\S]*task\.thumbUrl\.length > 0[\s\S]*EhThumbnail\(\{[\s\S]*url: task\.thumbUrl[\s\S]*this\.openArchiverTaskSource\(task\)[\s\S]*sys\.symbol\.arrow_down_to_line/.test(page),
  'archiver task stores token-backed source navigation, preserves the cover seed, and logs source opens')
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
ok(/RADIUS_CARD: number = 24/.test(theme) &&
  /SPACE_SM: number = 8/.test(theme) &&
  /DOWNLOAD_TASK_CARD_RADIUS: number = ThemeConstants\.RADIUS_CARD/.test(theme) &&
  /DOWNLOAD_TASK_CARD_PADDING: number = ThemeConstants\.SPACE_SM/.test(read('shared/src/main/ets/theme/ThemeConstants.ets')) &&
  /DOWNLOAD_TASK_COVER_RADIUS: number =[\s\S]*ThemeConstants\.DOWNLOAD_TASK_CARD_RADIUS - ThemeConstants\.DOWNLOAD_TASK_CARD_PADDING/.test(theme) &&
  /padding\(\{ left: ThemeConstants\.DOWNLOAD_TASK_CARD_PADDING, right: ThemeConstants\.DOWNLOAD_TASK_CARD_PADDING,[\s\S]*top: ThemeConstants\.DOWNLOAD_TASK_CARD_PADDING, bottom: ThemeConstants\.DOWNLOAD_TASK_CARD_PADDING \}\)/.test(page) &&
  /private DownloadGalleryTaskCard\(task: DownloadGalleryTask\)[\s\S]*borderRadius\(ThemeConstants\.DOWNLOAD_TASK_CARD_RADIUS\)/.test(page) &&
  /private DownloadArchiverTaskCard\(task: DownloadArchiverTask\)[\s\S]*borderRadius\(ThemeConstants\.DOWNLOAD_TASK_CARD_RADIUS\)/.test(page) &&
  /private ArchiverTaskCover\(task: DownloadArchiverTask\)[\s\S]*borderRadius\(ThemeConstants\.DOWNLOAD_TASK_COVER_RADIUS\)/.test(page),
  'download task cover radius follows the concentric-corner formula: card radius minus inset padding')
ok(/ArchiveImageService\.imagesForTask\(this\.ctx\(\), task\)/.test(page) &&
  /const index: number = Math\.max\(0, Math\.min\(images\.length - 1, this\.readProgress\.getIndex\(task\.gid\)\)\)/.test(page) &&
  /archiver_open_local_reader/.test(page) &&
  /new ReaderParams\(task\.gid, '', index, images\.length, task\.displayTitle\(\), images, 1, images\.length\)/.test(page),
  'completed archiver tasks unzip into local Reader seed images at the saved reading position with a diagnostic open event')
ok(/openingArchiverTag/.test(page) &&
  /private ArchiverOpeningButton\(_task: DownloadArchiverTask\)[\s\S]*LoadingTaskIconButton\(\$r\('app\.string\.reader_loading_resolving'\)/.test(page) &&
  /private LoadingTaskIconButton\(label: Resource\)[\s\S]*LoadingProgress\(\)/.test(page),
  'archiver Reader action has an opening state while extracting')
ok(/export class ArchiveImageService/.test(archiveService) &&
  /parallel: zlib\.ParallelStrategy\.PARALLEL_STRATEGY_PARALLEL_DECOMPRESSION/.test(archiveService) &&
  /pathSeparatorStrategy: zlib\.PathSeparatorStrategy\.PATH_SEPARATOR_STRATEGY_REPLACE_BACKSLASH/.test(archiveService) &&
  /archive_extract_start/.test(archiveService) &&
  /archive_extract_done/.test(archiveService) &&
  /zlib\.decompressFile\(task\.filePath, outDir, options\)/.test(archiveService) &&
  /fileIo\.listFileSync\(dir\)/.test(archiveService) &&
  /image\.sUrl = `archive:\/\/\$\{task\.tag\}\/\$\{page\}`/.test(archiveService) &&
  /image\.imageUrl = CachedImageFileService\.displayUri\(paths\[i\]\)/.test(archiveService),
  'ArchiveImageService uses platform zip extraction options and produces file:// Reader images')
ok(/try \{[\s\S]*await zlib\.decompressFile\(task\.filePath, outDir, options\)[\s\S]*\} catch \(error\) \{[\s\S]*ArchiveImageService\.deletePath\(outDir\)[\s\S]*throw error as Error/.test(archiveService) &&
  /if \(paths\.length === 0\) \{[\s\S]*ArchiveImageService\.deletePath\(outDir\)[\s\S]*throw new Error\('archive has no readable images'\)/.test(archiveService) &&
  /private static deletePath\(path: string\): void[\s\S]*fileIo\.rmdirSync\(path\)/.test(archiveService),
  'ArchiveImageService deletes failed or unreadable extraction output instead of reusing partial archive images')
ok(/paths\.sort\(\(a: string, b: string\) => ArchiveImageService\.naturalPathCompare\(a, b\)\)/.test(archiveService) &&
  /private static naturalPathCompare\(left: string, right: string\): number/.test(archiveService) &&
  /Number\.parseInt\(a\.substring\(aStart, ai\), 10\)/.test(archiveService) &&
  /private static isDigit\(code: number\): boolean/.test(archiveService) &&
  !/fileName\(a\)\.localeCompare\(ArchiveImageService\.fileName\(b\)\)/.test(archiveService),
  'ArchiveImageService uses natural numeric path ordering for archive pages')
ok(!/ConciseListRow\(\{[\s\S]*title: task\.displayTitle\(\)/.test(page) &&
  !/Button\(\$r\('app\.string\.common_remove'\)\)/.test(page) &&
  !/ReadTaskButton/.test(page) &&
  !/Button\(\{ type: ButtonType\.Circle \}\)/.test(page),
  'gallery task rows do not regress to shallow rows, duplicated read buttons, or right-side circle stacks')
ok(!/queue · resume · archiver · offline read \(M4\)/.test(page) && !/Text\('Downloads'\)/.test(page),
  'old literal placeholder copy is gone')
ok(!/postArchiver|downloadRemote|downloadLoacal|downloadLocal|DownloadAgentService/.test(page),
  'this lane does not submit archive requests or start background downloads')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'download_archiver',
    'download_gallery_queue',
    'download_archiver_queue',
    'download_active_tasks',
    'download_finished_tasks',
    'download_status_empty',
    'download_status_paused',
    'download_resume',
    'download_delete_task',
    'download_delete_confirm_title',
    'download_delete_confirm_message',
    'download_delete_confirm_action',
    'download_resume_all',
    'download_pause_all',
    'download_gallery_empty',
    'download_archiver_empty',
    'download_gallery_next_step',
    'download_archiver_next_step',
    'download_archiver_already_queued',
    'download_concurrency',
    'download_original_images',
    'download_not_configured',
    'common_pause',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ download workbench contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ download workbench contract: Gallery/Archiver queue surface and i18n locked')

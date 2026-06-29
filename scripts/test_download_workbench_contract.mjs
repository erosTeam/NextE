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
  /ForEach\(\s*this\.downloadQueue\.galleryTasks,[\s\S]*ListItem\(\)\s*\{[\s\S]*DownloadGalleryTaskCardView\(\{[\s\S]*task: this\.currentGalleryTask\(task\)[\s\S]*downloadQueueRevision: this\.downloadQueueTick/.test(page) &&
  /ForEach\(\s*this\.downloadQueue\.archiverTasks,[\s\S]*ListItem\(\)\s*\{[\s\S]*DownloadArchiverTaskCardView\(\{[\s\S]*task: this\.currentArchiverTask\(task\)[\s\S]*downloadQueueRevision: this\.downloadQueueTick/.test(page) &&
  /@ComponentV2\s+struct DownloadGalleryTaskCardView[\s\S]*@Param task: DownloadGalleryTask/.test(page) &&
  /@ComponentV2\s+struct DownloadArchiverTaskCardView[\s\S]*@Param task: DownloadArchiverTask/.test(page) &&
  /struct DownloadGalleryTaskCardView[\s\S]*private currentTask\(\): DownloadGalleryTask \{[\s\S]*return this\.task[\s\S]*\}/.test(page) &&
  /struct DownloadArchiverTaskCardView[\s\S]*private currentTask\(\): DownloadArchiverTask \{[\s\S]*return this\.task[\s\S]*\}/.test(page) &&
  !/struct DownloadGalleryTaskCardView[\s\S]*@Local downloadQueue: DownloadQueueState = connectDownloadQueue\(\)/.test(page) &&
  !/struct DownloadArchiverTaskCardView[\s\S]*@Local downloadQueue: DownloadQueueState = connectDownloadQueue\(\)/.test(page) &&
  !/initialTask|queueSignal|syncVisibleProgress/.test(page) &&
  /visibleStatus: this\.currentGalleryTask\(task\)\.status/.test(page) &&
  /visibleDownloadedFiles: this\.currentGalleryTask\(task\)\.downloadedCount\(\)/.test(page) &&
  /visibleSeededFiles: this\.currentGalleryTask\(task\)\.seededCount\(\)/.test(page) &&
  /visibleActiveRatio: this\.currentGalleryTask\(task\)\.activeDownloadRatio\(\)/.test(page) &&
  /visibleBytesWritten: this\.currentArchiverTask\(task\)\.bytesWritten/.test(page) &&
  /visibleProgress: this\.currentArchiverTask\(task\)\.progress/.test(page),
  'download task rows render stable task actions while live progress is driven by explicit visible params')
ok(!/renderQueueRevision|renderGalleryTasks|renderArchiverTasks/.test(page) &&
  /private safeForEachKeyPart\(value: string\): string \{[\s\S]*return value\.replace\(\/\[\^A-Za-z0-9_\]\/g, '_'\)/.test(page) &&
  galleryRenderKeyBody.includes('task.gid') &&
  galleryRenderKeyBody.includes('task.token') &&
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
  /downloadQueueRevision/.test(page),
  'download queue page keeps stable row keys while rows receive a parent revision pulse')
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
  /isDownloadComplete\(\): boolean \{[\s\S]*this\.seededCount\(\) >= this\.pageCount && downloaded >= this\.pageCount/.test(model) &&
  /applyDownloadResults[\s\S]*task\.syncProgressCounts\(\)/.test(queueSettings),
  'gallery download visible counters and completion state use the same seed-backed progress source')
ok(/private static setGalleryTasks\(state: DownloadQueueState, tasks: DownloadGalleryTask\[\]\): void \{[\s\S]*next\.push\(task\.copy\(\)\)[\s\S]*state\.galleryTasks = next[\s\S]*state\.revision = state\.revision \+ 1/.test(queueSettings) &&
  /private static setArchiverTasks\(state: DownloadQueueState, tasks: DownloadArchiverTask\[\]\): void \{[\s\S]*next\.push\(task\.copy\(\)\)[\s\S]*state\.archiverTasks = next[\s\S]*state\.revision = state\.revision \+ 1/.test(queueSettings) &&
  !/private static setGalleryTasks\(state: DownloadQueueState, tasks: DownloadGalleryTask\[\]\): void \{[\s\S]*assignFrom\(task\)[\s\S]*state\.galleryTasks = next/.test(queueSettings) &&
  !/private static setArchiverTasks\(state: DownloadQueueState, tasks: DownloadArchiverTask\[\]\): void \{[\s\S]*assignFrom\(task\)[\s\S]*state\.archiverTasks = next/.test(queueSettings),
  'download queue updates publish fresh task snapshots so mounted rows receive live progress params')
ok(/private effectiveGalleryStatus\(status: string, downloadedFiles: number, pageCount: number\): string/.test(page) &&
  /status === DownloadGalleryTaskStatus\.COMPLETE && pageCount > 0 && downloadedFiles < pageCount/.test(page) &&
  /private shouldShowGalleryProgress\(status: string, downloadedFiles: number, seededFiles: number\)/.test(page) &&
  /const effectiveStatus: string = this\.effectiveGalleryStatus\(status, downloadedFiles, this\.visiblePageCount\)/.test(page) &&
  /@Param visibleDownloadedFiles: number = 0/.test(page) &&
  /@Param visibleSeededFiles: number = 0/.test(page) &&
  /@Param visibleActiveRatio: number = 0/.test(page) &&
  /private downloadedFiles\(\): number \{[\s\S]*return this\.visibleDownloadedFiles/.test(page) &&
  /private seededFiles\(\): number \{[\s\S]*return this\.visibleSeededFiles/.test(page) &&
  /private TaskProgressBar\(status: string, downloadedFiles: number, seededFiles: number, pageCount: number\)/.test(page) &&
  /taskProgressRatio\(status, downloadedFiles, seededFiles, pageCount\)/.test(page) &&
  /this\.TaskStatusText\([\s\S]*this\.taskProgressLabel\([\s\S]*this\.visibleStatus,[\s\S]*this\.downloadedFiles\(\),[\s\S]*this\.seededFiles\(\)/.test(page) &&
  /download_file_progress/.test(page) &&
  /download_seed_progress/.test(page),
  'gallery task progress text and bar refresh from the same seed-backed visible counters')
ok(/if \(effectiveStatus === DownloadGalleryTaskStatus\.ERROR\) \{[\s\S]*downloadProgress\.length > 0[\s\S]*download_file_progress/.test(page),
  'gallery download failures keep visible downloaded progress instead of hiding mismatched counts behind a generic error')
ok(/private GalleryTaskActionColumn\(status: string\)/.test(page) &&
  /private GalleryPrimaryAction\(status: string\)/.test(page) &&
  /private GalleryTaskMoreButton\(\)/.test(page) &&
  /sys\.symbol\.dot_grid_2x2/.test(page) &&
  !/sys\.symbol\.line_3_horizontal/.test(page) &&
  /private TaskActionMenu\(\)/.test(page) &&
  /MenuItem\(\{ content: \$r\('app\.string\.common_remove'\) \}\)/.test(page) &&
  !/private TaskActions\(task: DownloadGalleryTask\)/.test(page) &&
  !/DOWNLOAD_TASK_CARD_HEIGHT/.test(page),
  'task cards expose one state action plus a native more menu instead of a fixed-height bottom action bar')
ok(/private ResumeTaskButton\(\)/.test(page) &&
  /sys\.symbol\.arrow_clockwise/.test(page) &&
  /DownloadQueueSettings\.downloadGalleryImages/.test(page) &&
  /common_retry/.test(page),
  'retry/resume action is a compact icon action wired to the gallery image executor')
ok(/private PauseTaskButton\(\)/.test(page) &&
  /sys\.symbol\.pause/.test(page) &&
  /DownloadQueueSettings\.pauseGalleryDownload/.test(page) &&
  /common_pause/.test(page) &&
  /private canPauseTask\(status: string\)[\s\S]*DownloadGalleryTaskStatus\.DOWNLOADING/.test(page),
  'running gallery tasks expose one compact pause action wired to the shared queue')
ok(/status === DownloadGalleryTaskStatus\.PAUSED[\s\S]*download_status_paused/.test(page) &&
  /private canResumeTask\(status: string\)[\s\S]*DownloadGalleryTaskStatus\.QUEUED[\s\S]*DownloadGalleryTaskStatus\.PAUSED/.test(page),
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
ok(/struct DownloadArchiverTaskCardView[\s\S]*@Event onSwitchToBot\?: \(task: DownloadArchiverTask\) => void/.test(page) &&
  /private canSwitchToBot\(\): boolean[\s\S]*DownloadSettings\.archiveBotReady\(\)[\s\S]*task\.parseSource === DownloadArchiverParseSource\.BOT[\s\S]*this\.visibleStatus === DownloadGalleryTaskStatus\.COMPLETE[\s\S]*this\.visibleStatus === DownloadGalleryTaskStatus\.DOWNLOADING[\s\S]*task\.dltype === 'org' \|\| resolution\.includes\('original'\)/.test(page) &&
  /struct DownloadArchiverTaskCardView[\s\S]*private TaskActionMenu\(\)[\s\S]*download_archiver_use_bot[\s\S]*this\.switchToBot\(\)/.test(page) &&
  /onSwitchToBot: \(selected: DownloadArchiverTask\) => \{[\s\S]*DownloadQueueSettings\.switchArchiverToBot\(this\.ctx\(\), selected\.tag\)/.test(page),
  'rendered archiver task card exposes the archive bot parse-source switch, not only the parent menu helper')
ok(/private PauseArchiverTaskButton\(\)/.test(page) &&
  /sys\.symbol\.pause/.test(page) &&
  /DownloadQueueSettings\.pauseArchiverDownload/.test(page) &&
  /private canPauseArchiverTask\(\): boolean[\s\S]*this\.visibleStatus === DownloadGalleryTaskStatus\.DOWNLOADING/.test(page),
  'running archiver tasks expose a low-weight pause action wired to the shared queue')
ok(/private canResumeArchiverTask\(\): boolean[\s\S]*DownloadGalleryTaskStatus\.PAUSED/.test(page),
  'paused archiver tasks can resume')
ok(/private archiverProgressLabel\(\): string[\s\S]*this\.visibleStatus === DownloadGalleryTaskStatus\.ERROR[\s\S]*this\.visibleError\.length > 0[\s\S]*`\$\{this\.statusText\(this\.visibleStatus\)\} · \$\{this\.visibleError\}`/.test(page),
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
  /private ArchiverTaskCover\(task: DownloadArchiverTask\)[\s\S]*task\.thumbUrl\.length > 0[\s\S]*EhThumbnail\(\{[\s\S]*url: task\.thumbUrl[\s\S]*this\.openArchiverTaskSource\(task\)[\s\S]*sys\.symbol\.arrow_down_to_line/.test(page),
  'archiver task stores token-backed source navigation and renders the gallery cover when available')
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
  /new ReaderParams\(task\.gid, '', index, images\.length, task\.displayTitle\(\), images, 1, images\.length\)/.test(page),
  'completed archiver tasks unzip into local Reader seed images at the saved reading position')
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

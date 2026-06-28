#!/usr/bin/env node
/**
 * Contract: the Downloads tab is a real queue workbench surface, not the old two-line placeholder.
 *
 * eros_fe's first-level Downloads tab is split into Gallery and Archiver queues. NextE's first
 * download lane should expose that structure through a title-bar segmented control without mixing
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
const bar = read('entry/src/main/ets/components/DownloadTypeBar.ets')
const index = read('entry/src/main/ets/pages/Index.ets')
const state = read('shared/src/main/ets/state/DownloadViewState.ets')
const shared = read('shared/src/main/ets/Index.ets')

ok(/export enum DownloadViewType/.test(state) && /GALLERY = 'gallery'/.test(state) &&
  /ARCHIVER = 'archiver'/.test(state), 'download shared state defines Gallery and Archiver queue views')
ok(/@ObservedV2\s+export class DownloadViewState/.test(state) && /@Trace viewType/.test(state) &&
  /AppStorageV2\.connect\(\s*DownloadViewState/.test(state), 'download view selection is shared V2 state')
ok(/connectDownloadView/.test(shared) && /DOWNLOAD_SELECTOR_BAR_HEIGHT/.test(shared),
  'shared barrel exports download view state and title-bar height')
ok(/TabSegmentButtonV2/.test(bar) && /SegmentButtonV2Items/.test(bar),
  'download type control uses a V2-native segmented button')
ok(/AppStrings\.get\('tab_gallery'\)/.test(bar) && /AppStrings\.get\('download_archiver'\)/.test(bar),
  'download segmented control labels Gallery and Archiver')
ok(/this\.downloadView\.viewType\s*=[\s\S]*DownloadViewType\.ARCHIVER/.test(bar),
  'download segmented control writes the selected queue view')
ok(/DownloadTypeBarCCBuilder/.test(index) && /tab === 3[\s\S]*bottomBuilder/.test(index) &&
  /DOWNLOAD_SELECTOR_BAR_HEIGHT/.test(index), 'Index pins the download segmented control in title-bar bottomBuilder')
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
  /EhThumbnail\(\{[\s\S]*thumbWidth: ThemeConstants\.DOWNLOAD_TASK_COVER_WIDTH/.test(page) &&
  /Text\(task\.displayTitle\(\)\)[\s\S]*maxLines\(2\)/.test(page),
  'gallery tasks render as readable task cards with cover and two-line title')
ok(/private TaskProgressBar\(task: DownloadGalleryTask\)/.test(page) &&
  /taskProgressRatio\(task\)/.test(page) &&
  /download_file_progress/.test(page) &&
  /download_seed_progress/.test(page),
  'gallery task card promotes seed/download progress as task state')
ok(/Button\(\{ type: ButtonType\.Circle \}\)[\s\S]*sys\.symbol\.trash[\s\S]*common_remove/.test(page),
  'remove action is a low-weight icon action rather than a wide text button')
ok(/private ResumeTaskButton\(task: DownloadGalleryTask\)/.test(page) &&
  /sys\.symbol\.arrow_clockwise/.test(page) &&
  /DownloadQueueSettings\.downloadGalleryImages/.test(page) &&
  /common_retry/.test(page),
  'retry/resume action is a low-weight icon action wired to the gallery image executor')
ok(/private ArchiverTaskSection\(\)/.test(page) &&
  /this\.downloadQueue\.archiverTasks/.test(page) &&
  /private DownloadArchiverTaskCard\(task: DownloadArchiverTask\)/.test(page),
  'archiver queue renders real archive task cards')
ok(/DownloadQueueSettings\.downloadArchiver/.test(page) &&
  /DownloadQueueSettings\.removeArchiver/.test(page),
  'archiver task cards wire retry and remove to the archiver queue executor')
ok(!/ConciseListRow\(\{[\s\S]*title: task\.displayTitle\(\)/.test(page) &&
  !/Button\(\$r\('app\.string\.common_remove'\)\)/.test(page),
  'gallery task rows do not regress to shallow ConciseListRow plus large remove button')
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
    'download_gallery_empty',
    'download_archiver_empty',
    'download_gallery_next_step',
    'download_archiver_next_step',
    'download_archiver_already_queued',
    'download_concurrency',
    'download_original_images',
    'download_not_configured',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ download workbench contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ download workbench contract: Gallery/Archiver queue surface and i18n locked')

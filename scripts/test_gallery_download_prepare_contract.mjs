#!/usr/bin/env node
/**
 * Contract: Gallery download tasks prepare EH image-page seeds (`/s/` URLs) before any downloader
 * tries to resolve full image URLs. This keeps the chain aligned with eros_fe.
 *
 * Run: node scripts/test_gallery_download_prepare_contract.mjs
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
  'eros_fe: lib/common/controller/download_controller.dart downloadGallery() / _addGalleryTask(groupCount: firstPageImage.length); lib/common/controller/download/image_download_processor.dart fetchFirstPageCount() / fetchImageList()',
  'primary information: Downloads task row shows image-page seed preparation state and progress, not only a queued shell',
  'primary action: detail Read remains primary; Download remains secondary; queue row foregrounds preparation status while Remove is secondary',
  'scope: save first detail preview /s/ imagePageUrl seeds and fetch later preview pages via ?p=; no full-image URL resolve, file writes, background downloader, pause/resume engine, or archiver submit',
  'Harmony expression: HDS grouped list task row, subtitle status/progress, secondary Remove suffix; existing title-bar segmented control stays the queue switcher',
]

ok(grounding.length === 5, 'download prepare lane has five-line grounding')
ok(grounding[0].includes('download_controller.dart') && grounding[0].includes('image_download_processor.dart') &&
  grounding[0].includes('fetchImageList'), 'grounding names concrete eros_fe files and methods')
ok(grounding[3].includes('/s/ imagePageUrl') && grounding[3].includes('no full-image URL resolve'),
  'grounding states EH image-page boundary and non-scope')

const model = read('shared/src/main/ets/model/DownloadGalleryTask.ets')
const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const queue = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
const shared = read('shared/src/main/ets/Index.ets')

ok(/export class DownloadImageSeed/.test(model) && /imagePageUrl: string = ''/.test(model) &&
  /static fromGalleryImage/.test(model) && /seed\.imagePageUrl = image\.sUrl/.test(model),
  'download model stores EH /s/ image-page URLs as seeds')
ok(/imageSeeds: DownloadImageSeed\[\] = \[\]/.test(model) && /firstPageCount: number/.test(model) &&
  /previewPageCount: number/.test(model), 'gallery task tracks seed list and preview-page metadata')
ok(/PREPARING: string = 'preparing'/.test(model) && /READY: string = 'ready'/.test(model) &&
  /ERROR: string = 'error'/.test(model), 'gallery task has preparation statuses')
ok(/seedProgressText/.test(model) && /seededCount/.test(model),
  'gallery task exposes seed progress for the queue row')
ok(/DownloadImageSeed/.test(shared), 'shared barrel exports the seed model')

ok(/prepareGallerySeeds/.test(settings) && /EhApiService\.getInstance\(\)\.getPreviewImages/.test(settings),
  'single writer prepares later preview pages through EhApiService.getPreviewImages')
ok(/gallery_prepare_start/.test(settings) && /gallery_prepare_done/.test(settings) &&
  /gallery_prepare_failed/.test(settings),
  'seed preparation writes explicit start/done/failure diagnostics')
ok(/if \(seedImages\.length === 0\) \{[\s\S]*EhApiService\.getInstance\(\)\.getGalleryDetail\(gid, token, isEx\)[\s\S]*gallery_prepare_detail_seed_loaded/.test(settings),
  'empty detail image lists are reseeded from gallery detail before preview-page pagination')
ok(/let seedImages: EhGalleryImage\[\] = firstPageImages\.map/.test(settings) &&
  /const initialSeeds: DownloadImageSeed\[\] = DownloadQueueSettings\.imagesToSeeds\(seedImages\)/.test(settings) &&
  /const firstPageCount: number = Math\.max\(1, initialSeeds\.length > 0 \? initialSeeds\.length : seedImages\.length\)/.test(settings),
  'preview-page estimation uses the resolved first page seed list, not an empty detail placeholder')
ok(/for \(let p = 1; p < totalPreviewPages; p\+\+\)/.test(settings),
  'preparation starts after the first detail preview page and pages through ?p=')
ok(/expectedPreviewPageCount/.test(settings) &&
  /Math\.ceil\(pageCount \/ firstPageCount\)/.test(settings) &&
  /const totalPreviewPages: number = DownloadQueueSettings\.expectedPreviewPageCount/.test(settings),
  'preparation estimates preview pages from fileCount/first-page count when EH ptt only exposes a window')
ok(/imagesToSeeds/.test(settings) && /DownloadImageSeed\.fromGalleryImage/.test(settings),
  'preparation converts parsed preview images into image-page seeds')
ok(/catch \(error\) \{\s*await DownloadQueueSettings\.updateDownloadTaskStatus\(/.test(settings) &&
  /DownloadGalleryTaskStatus\.ERROR,\s*DownloadQueueSettings\.userError\(error as Object\),\s*\)/.test(settings) &&
  !/catch \(error\) \{\s*await DownloadQueueSettings\.updatePreparedTask\(/.test(settings),
  'preparation failure keeps existing seed records and stores a user-facing error instead of replacing them with only the first page')
ok(/mergeSeeds/.test(settings) && /it\.page === seed\.page \|\| it\.imagePageUrl === seed\.imagePageUrl/.test(settings),
  'preparation dedups seeds by page or image-page URL')
ok(/inheritDownloadedSeedsFromParent/.test(settings) &&
  /parent\.imageSeeds\.find\(\(it: DownloadImageSeed\) => \{[\s\S]*it\.imgkey === out\.imgkey[\s\S]*downloadedFileSize\(it\.filePath\) > 0/.test(settings) &&
  /copyInheritedSeedFile\(context, gid, out, previous\)/.test(settings) &&
  /fs\.copyFile\(src\.fd, dest\.fd\)/.test(settings) &&
  /gallery_incremental_copy_failed/.test(settings),
  'newer-version downloads reuse parent gallery files by matching stable EH image keys')
ok(/parseSeeds/.test(settings) && /typeof raw\.imagePageUrl === 'string'/.test(settings),
  'persisted queue defensively restores nested seed records')
ok(/refreshed\.imageSeeds = it\.imageSeeds/.test(settings) && /refreshed\.status = it\.status/.test(settings),
  'duplicate enqueue preserves existing preparation state')

ok(/prepareGallerySeeds\(/.test(detail) && /this\.vm\.images/.test(detail) &&
  /this\.vm\.previewPageCount/.test(detail), 'detail enqueue starts seed preparation from parsed preview data')
ok(/DownloadQueueSettings\.prepareGallerySeeds\([\s\S]*this\.vm\.images,[\s\S]*this\.vm\.previewPageCount,[\s\S]*\)\.catch\(\(error: Error\) => \{[\s\S]*detail_prepare_failed/.test(detail),
  'detail fire-and-forget preparation logs failures instead of silently swallowing them')
ok(/download_status_preparing/.test(queue) && /download_status_ready/.test(queue) &&
  /download_status_error/.test(queue), 'downloads page renders preparation statuses')
ok(/download_seed_progress/.test(queue) &&
  /private taskProgressLabel\([\s\S]*seededFiles: number,[\s\S]*pageCount: number,[\s\S]*prepareError: string/.test(queue) &&
  /const seedProgress: string = this\.progressText\(seededFiles, total\)/.test(queue),
  'downloads page shows seed progress in task subtitle')
ok(/taskStatusText/.test(queue) && /download_status_error/.test(queue) &&
  /if \(seedProgress\.length > 0\) \{[\s\S]*effectiveStatus === DownloadGalleryTaskStatus\.PREPARING[\s\S]*parts\.push\(this\.statusText\(effectiveStatus\)\)[\s\S]*return parts\.join\(' · '\)/.test(queue),
  'downloads page keeps preparation and error states visible in the task subtitle')
ok(/if \(status === DownloadGalleryTaskStatus\.ERROR\) \{[\s\S]*prepareError\.length > 0[\s\S]*`\$\{this\.statusText\(effectiveStatus\)\} · \$\{prepareError\}`/.test(queue),
  'downloads page shows stored gallery failure reason in the existing status subtitle')
ok(/seedProgress\.length > 0[\s\S]*return parts\.join\(' · '\)/.test(queue),
  'downloads page keeps seed progress subtitle focused instead of crowding it with lower-priority metadata')
ok(!/Text\(this\.taskStatus\(task\)\)/.test(queue),
  'downloads page does not duplicate row status in the suffix and squeeze the progress subtitle')
ok(!/trailingText:\s*this\.taskStatus/.test(queue),
  'downloads page does not pass hidden task status through a suffix-overridden trailingText')
ok(!/fullimg|DownloadAgentService|downloadToPath/.test(
  `${settings}\n${detail}\n${queue}`,
), 'seed preparation still avoids original-image expansion and the full background downloader')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'download_status_active',
    'download_status_preparing',
    'download_status_ready',
    'download_status_error',
    'download_seed_progress',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ gallery download prepare contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ gallery download prepare contract: /s/ seed preparation locked')

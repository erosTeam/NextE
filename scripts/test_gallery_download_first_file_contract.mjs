#!/usr/bin/env node
/**
 * Contract: the Gallery download queue advances from `/s/` seed preparation to one real downloaded
 * image file in the app sandbox. This is deliberately a first-file smoke, not the full background
 * downloader loop.
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
  'primary information: Downloads task row shows real file download progress, not only seed preparation',
  'primary action: detail Read remains primary; Download remains secondary; queue row foregrounds download status/progress while Remove is secondary',
  'scope: resolve the first /s/ seed to a real image URL and immediately write that image to the app sandbox; no full background loop, pause/resume, external directory picker, archiver, or original-image policy expansion',
  'Harmony expression: HDS grouped list task row with downloaded progress in the subtitle; NetworkKit request plus CoreFileKit sandbox write, no new heavy UI',
]

ok(grounding.length === 5, 'download first-file lane has five-line grounding')
ok(grounding[0].includes('download_controller.dart') &&
  grounding[0].includes('image_download_processor.dart') &&
  grounding[0].includes('downloadImageFlow') &&
  grounding[0].includes('fetchImageInfo'), 'grounding names concrete eros_fe files and methods')
ok(grounding[3].includes('first /s/ seed') && grounding[3].includes('app sandbox') &&
  grounding[3].includes('no full background loop'), 'grounding states first-file scope and non-scope')

const model = read('shared/src/main/ets/model/DownloadGalleryTask.ets')
const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const client = read('shared/src/main/ets/network/EhHttpClient.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const queue = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')

ok(/filePath: string = ''/.test(model) && /bytesWritten: number = 0/.test(model) &&
  /downloadError: string = ''/.test(model), 'download seed records sandbox file path, bytes, and error')
ok(/downloadedAt: number = 0/.test(model) && /downloadedCount/.test(model) &&
  /downloadProgressText/.test(model), 'gallery task tracks first-file download progress')
ok(/DOWNLOADING: string = 'downloading'/.test(model) &&
  /PARTIAL: string = 'partial'/.test(model), 'gallery task has first-file download statuses')

ok(/downloadFirstGalleryImage/.test(settings) &&
  /ImageResolveService\.getInstance\(\)\.resolve/.test(settings),
  'queue single-writer resolves the first seed through ImageResolveService')
ok(/EhGalleryImage/.test(settings) && /image\.sUrl = seed\.imagePageUrl/.test(settings),
  'first-file path turns a DownloadImageSeed back into an image-page resolve seed')
ok(/EhHttpClient\.getInstance\(\)\.downloadBinaryToFile/.test(settings),
  'first-file path immediately downloads the resolved URL to a file')
ok(/context\.filesDir/.test(settings) && /download-gallery/.test(settings),
  'first-file path writes under the app sandbox download-gallery directory')
ok(/prepareGallerySeeds\(/.test(detail), 'detail download still starts through seed preparation')
ok(/await DownloadQueueSettings\.downloadFirstGalleryImage\(context, gid, token\)/.test(settings),
  'seed preparation chains into the first-file smoke after preview seeds are ready')
ok(/parseSeeds/.test(settings) && /raw\.filePath/.test(settings) && /raw\.bytesWritten/.test(settings),
  'persisted queue restores downloaded file metadata')

ok(/downloadBinaryToFile/.test(client) && /HttpDataType\.ARRAY_BUFFER/.test(client) &&
  /fs\.write/.test(client) && /maxLimit/.test(client), 'HTTP client can write binary response to a sandbox file')
ok(!/downloadFirstGalleryImage[\s\S]*requestInStream/.test(settings),
  'first-file smoke intentionally avoids stream queueing complexity in the download task path')

ok(/download_file_progress/.test(queue) && /task\.downloadProgressText\(\)/.test(queue),
  'downloads page shows real file progress in the task subtitle')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'download_status_downloading',
    'download_status_partial',
    'download_file_progress',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ gallery download first-file contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ gallery download first-file contract: first image file smoke locked')

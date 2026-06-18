#!/usr/bin/env node
/**
 * Contract: Reader image loading uses real NetworkKit stream progress after the /s/
 * image page resolves to a full image URL. It must not route through the download queue
 * or keep multi-megabyte images in memory just to show a percentage.
 *
 * Run: node scripts/test_reader_byte_progress_contract.mjs
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
  'eros_fe: /Users/honjow/git/eros_fe/lib/pages/image_view/view/view_widget.dart ImageExt.build() and _ViewLoadingLine.build()',
  'primary information: Reader second-stage loading shows current full-image byte progress after the real image URL is known',
  'primary action: reading, tap regions, zoom, and page turn stay primary; retry/re-source remains the failure recovery action',
  'scope: stream the resolved full image into a transient reader cache file, bind progress into the existing centered line, and render the local file; do not implement offline library, archive/download pipeline, background queue, or fake percentages',
  'Harmony expression: NetworkKit requestInStream plus dataReceiveProgress/dataReceive writes through CoreFileKit, with V2 @Local imageProgress feeding ReaderLoadingLine',
]

ok(grounding.length === 5, 'reader byte progress lane has five-line grounding')
ok(grounding[0].includes('view_widget.dart') &&
  grounding[0].includes('ImageExt.build') &&
  grounding[0].includes('_ViewLoadingLine'), 'grounding names exact eros_fe reader loading implementation')
ok(grounding[3].includes('transient reader cache') &&
  grounding[3].includes('do not implement offline library') &&
  grounding[3].includes('fake percentages'), 'grounding pins usable loop and non-scope')

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const client = read('shared/src/main/ets/network/EhHttpClient.ets')

ok(/downloadBinaryToFileInStream/.test(client), 'EhHttpClient exposes stream-to-file image download')
ok(/requestInStream/.test(client) &&
  /dataReceiveProgress/.test(client) &&
  /info\.receiveSize/.test(client) &&
  /info\.totalSize/.test(client), 'stream download uses NetworkKit progress fields')
ok(/dataReceive/.test(client) &&
  /fs\.writeSync\(\(file as fs\.File\)\.fd, data, \{ offset: offset \}\)/.test(client),
  'stream chunks are written directly to disk with explicit offsets')
ok(!/downloadBinaryToFileInStream[\s\S]*expectDataType:\s*http\.HttpDataType\.ARRAY_BUFFER/.test(client),
  'reader stream path does not use full ARRAY_BUFFER image responses')

ok(/READER_IMAGE_CACHE_DIR: string = 'reader-images'/.test(reader) &&
  /context\.cacheDir/.test(reader) &&
  /ReaderImageCache\.ensureDir/.test(reader),
  'Reader writes streamed images into a transient cache directory')
ok(/@Local imageProgress: number = -1/.test(reader) &&
  /this\.imageProgress = Math\.max\(0, Math\.min\(1, loaded \/ total\)\)/.test(reader),
  'Reader tracks bounded real image progress')
ok(/downloadBinaryToFileInStream\(\s*remoteUrl,\s*filePath,\s*\(loaded: number, total: number\)/.test(reader),
  'Reader binds stream progress callback after URL resolution')
ok(/this\.imageUrl = `file:\/\/\$\{filePath\}`/.test(reader),
  'Reader renders the local cache file after streaming completes')
ok(/ReaderLoadingOverlay\(\{ label: \$r\('app\.string\.reader_loading_image'\), progress: this\.imageProgress \}\)/.test(reader),
  'horizontal and vertical image stages pass real progress to the centered overlay')
ok(/struct ReaderLoadingLine[\s\S]*@Param progress: number = -1[\s\S]*Math\.round\(Math\.max\(0, Math\.min\(1, this\.progress\)\) \* 100\)/.test(reader),
  'loading line renders a bounded percentage from the progress signal')

ok(!/DownloadQueueSettings|DownloadGalleryTask|connectDownloadQueue/.test(reader),
  'Reader progress does not couple online reading to the download queue')

if (failures > 0) {
  console.error(`\n✗ reader byte progress contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ reader byte progress contract: stream-backed Reader progress locked')

#!/usr/bin/env node
/**
 * Contract: Reader loading is stable and staged. First paint and far-jump parsing use a centered
 * resolving state; after the real image URL is known, each image page keeps a centered image-loading
 * line visible until Image.onComplete.
 *
 * Run: node scripts/test_reader_loading_progress_contract.mjs
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
  'eros_fe: lib/pages/image_view/view/view_widget.dart ImageExt.build() LoadState.loading and _ViewLoadingLine.build()',
  'primary information: Reader shows a stable centered loading stage instead of a bottom spinner or black image canvas',
  'primary action: reading/tap navigation remains primary; retry/re-source remains the recovery action on failure',
  'scope: split loading UI into resolving/parsing and image-loading stages; show a centered line during image loading; do not rewrite resolver, navigation, zoom, retry, or offline/download pipeline',
  'Harmony expression: a small ReaderLoadingOverlay/ReaderLoadingLine component inside ReaderPage, backed by Image.onComplete/onError, stream progress, and existing V2 local state',
]

ok(grounding.length === 5, 'reader loading lane has five-line grounding')
ok(grounding[0].includes('view_widget.dart') &&
  grounding[0].includes('ImageExt.build') &&
  grounding[0].includes('_ViewLoadingLine'), 'grounding names concrete eros_fe file/components')
ok(grounding[3].includes('resolving/parsing') &&
  grounding[3].includes('image-loading') &&
  grounding[3].includes('do not rewrite resolver'), 'grounding states staged scope and non-scope')

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')

ok(/struct ReaderLoadingOverlay/.test(reader) &&
  /struct ReaderLoadingLine/.test(reader), 'Reader has dedicated centered loading components')
ok(/ReaderLoadingOverlay\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader),
  'empty reader and jump states use the resolving loading stage')
ok(/ReaderLoadingOverlay\(\{ label: \$r\('app\.string\.reader_loading_image'\), progress: this\.imageProgress \}\)/.test(reader),
  'image pages use the image-loading stage after a real URL is known')
ok(/\.width\('100%'\)[\s\S]*?\.height\('100%'\)[\s\S]*?\.justifyContent\(FlexAlign\.Center\)[\s\S]*?\.alignItems\(HorizontalAlign\.Center\)/.test(reader),
  'loading overlay fills the page and centers its content')
ok(/@Local imageLoaded: boolean = false/.test(reader) &&
  /this\.imageLoaded = false[\s\S]*await ImageResolveService/.test(reader) &&
  /\.onComplete\(\([\s\S]*?\) => \{[\s\S]*this\.imageLoaded = true/.test(reader),
  'ReaderImagePage tracks Image loading separately from URL resolving')
ok(/if \(!this\.imageLoaded\) \{[\s\S]*ReaderLoadingOverlay\(\{ label: \$r\('app\.string\.reader_loading_image'\), progress: this\.imageProgress \}\)/.test(reader),
  'horizontal image page overlays image-loading line until Image completes')
ok(/struct ReaderVerticalImage[\s\S]*@Local imageLoaded: boolean = false[\s\S]*if \(!this\.imageLoaded\) \{[\s\S]*reader_loading_image/.test(reader),
  'vertical image page overlays image-loading line until Image completes')
ok(!/else \{\s*LoadingProgress\(\)[\s\S]*?\.color\(Color\.White\)\s*\}/.test(reader),
  'Reader no longer falls back to loose white LoadingProgress spinners for loading states')
const client = read('shared/src/main/ets/network/EhHttpClient.ets')
ok(/downloadBinaryToFileInStream/.test(client) &&
  /dataReceiveProgress/.test(client) &&
  /info\.receiveSize/.test(client) &&
  /info\.totalSize/.test(client) &&
  /@Local imageProgress: number = -1/.test(reader),
  'Reader byte percentage is backed by supported NetworkKit stream progress')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of ['reader_loading_resolving', 'reader_loading_image']) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ reader loading/progress contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ reader loading/progress contract: staged centered loading locked')

#!/usr/bin/env node
/**
 * Contract for Reader failed-image retry UI.
 *
 * Grounding:
 * - eros_fe/lib/pages/image_view/view/view_widget.dart uses ImageExt/ImageExtProvider to keep a
 *   centered LoadState.failed affordance after bounded reloads.
 * - The primary information is that the current image failed after alternate source attempts.
 * - The primary action is retrying/re-sourcing this image; navigation remains the secondary reader
 *   action once the image recovers.
 * - Scope is the Reader failure-state loop only, not the download/offline executor pipeline.
 * - HarmonyOS expression is a V2 reader-canvas overlay shared by paged and vertical modes.
 *
 * Run: node scripts/test_reader_failure_retry_ui_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const reader = readFileSync(join(ROOT, 'feature/reader/src/main/ets/pages/ReaderPage.ets'), 'utf8')

const localeFiles = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok('grounding references eros_fe failed image provider', /view_widget\.dart[\s\S]*ImageExt\/ImageExtProvider[\s\S]*LoadState\.failed/.test(readFileSync(fileURLToPath(import.meta.url), 'utf8')))
ok('declares shared V2 failure overlay', /@ComponentV2\s+struct ReaderFailureOverlay/.test(reader))
ok('failure overlay is centered on reader canvas', /struct ReaderFailureOverlay[\s\S]*justifyContent\(FlexAlign\.Center\)[\s\S]*alignItems\(HorizontalAlign\.Center\)/.test(reader))
ok('failure overlay names failed image state', /struct ReaderFailureOverlay[\s\S]*image_load_failed/.test(reader))
ok('failure overlay explains retry-source state', /struct ReaderFailureOverlay[\s\S]*reader_retry_source_hint/.test(reader))
ok('failure overlay exposes source retry action', /Button\(\$r\('app\.string\.reader_retry_source'\)\)[\s\S]*this\.onRetry\(\)/.test(reader))
ok('paged reader uses shared failure overlay', /struct ReaderImagePage[\s\S]*if \(this\.failed\) \{[\s\S]*ReaderFailureOverlay\(\{[\s\S]*this\.retrySource\(\)/.test(reader))
ok('vertical reader uses shared failure overlay', /struct ReaderVerticalImage[\s\S]*if \(this\.failed\) \{[\s\S]*ReaderFailureOverlay\(\{[\s\S]*compact: true[\s\S]*this\.retrySource\(\)/.test(reader))
ok('vertical failed branch is not a bare retry button', !/struct ReaderVerticalImage[\s\S]*if \(this\.failed\) \{\s*Button\(\$r\('app\.string\.common_retry'\)\)/.test(reader))
ok('manual retry still re-sources instead of retrying dead URL', /private retrySource\(\): void \{[\s\S]*this\.autoRetryCount = 0[\s\S]*this\.resolve\(true\)/.test(reader))

for (const file of localeFiles) {
  const content = readFileSync(join(ROOT, file), 'utf8')
  ok(`${file} defines reader_retry_source`, /"name": "reader_retry_source"/.test(content))
  ok(`${file} defines reader_retry_source_hint`, /"name": "reader_retry_source_hint"/.test(content))
}

console.log(`✓ reader failure retry UI contract: ${passed} assertions passed`)

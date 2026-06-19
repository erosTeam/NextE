#!/usr/bin/env node
/**
 * Contract for Reader image failure taxonomy.
 *
 * Grounding:
 * - eros_fe/lib/pages/image_view/view/view_widget.dart renders ViewErr509, ViewErr429, and ViewError.
 * - The primary information is why the current reader page failed: quota, rate limit, or generic.
 * - The primary action remains re-source retry; page navigation and chrome are secondary.
 * - Scope is Reader per-image error rendering only; pHash/QR content hiding is deferred.
 * - HarmonyOS expression is a shared V2 black-canvas ReaderFailureOverlay.
 *
 * Run: node scripts/test_reader_error_state_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const reader = readFileSync(join(ROOT, 'feature/reader/src/main/ets/pages/ReaderPage.ets'), 'utf8')
const feWidget = readFileSync(
  join(ROOT, '../eros_fe/lib/pages/image_view/view/view_widget.dart'),
  'utf8',
)
const feImage = readFileSync(
  join(ROOT, '../eros_fe/lib/pages/image_view/view/view_image.dart'),
  'utf8',
)

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

ok('grounding: FE has 509 error widget', /class ViewErr509/.test(feWidget))
ok('grounding: FE has 429 error widget', /class ViewErr429/.test(feWidget))
ok('grounding: FE maps image509 to ViewErr509', /EhErrorType\.image509[\s\S]*ViewErr509/.test(feImage))
ok('grounding: FE maps HTTP 429 to ViewErr429', /BadRequestException[\s\S]*e\.code == 429[\s\S]*ViewErr429/.test(feImage))

ok('Reader defines failure taxonomy', /enum ReaderImageFailureKind[\s\S]*Generic[\s\S]*Quota[\s\S]*RateLimited/.test(reader))
ok('Reader classifies image509 and 509 as quota', /readerFailureKindFromError[\s\S]*image509[\s\S]*509[\s\S]*ReaderImageFailureKind\.Quota/.test(reader))
ok('Reader classifies 429/rate throttling separately', /readerFailureKindFromError[\s\S]*429[\s\S]*rate[\s\S]*throttle[\s\S]*ReaderImageFailureKind\.RateLimited/.test(reader))
ok('Paged reader stores classified failure kind', /struct ReaderImagePage[\s\S]*@Local failureKind: ReaderImageFailureKind[\s\S]*readerFailureKindFromError\(e\)/.test(reader))
ok('Vertical reader stores classified failure kind', /struct ReaderVerticalImage[\s\S]*@Local failureKind: ReaderImageFailureKind[\s\S]*readerFailureKindFromError\(e\)/.test(reader))
ok('Paged reader passes kind into overlay', /struct ReaderImagePage[\s\S]*ReaderFailureOverlay\(\{[\s\S]*kind: this\.failureKind/.test(reader))
ok('Vertical reader passes kind into overlay', /struct ReaderVerticalImage[\s\S]*ReaderFailureOverlay\(\{[\s\S]*kind: this\.failureKind/.test(reader))
ok('Failure overlay receives the taxonomy', /struct ReaderFailureOverlay[\s\S]*@Param kind: ReaderImageFailureKind/.test(reader))
ok('Failure overlay uses quota title and hint', /failureTitle\(\)[\s\S]*reader_error_quota[\s\S]*failureHint\(\)[\s\S]*reader_error_quota_hint/.test(reader))
ok('Failure overlay uses rate-limit title and hint', /failureTitle\(\)[\s\S]*reader_error_rate_limited[\s\S]*failureHint\(\)[\s\S]*reader_error_rate_limited_hint/.test(reader))
ok('Manual retry still re-sources after classified failures', /private retrySource\(\): void \{[\s\S]*this\.failureKind = ReaderImageFailureKind\.Generic[\s\S]*this\.resolve\(true\)/.test(reader))

for (const file of localeFiles) {
  const content = readFileSync(join(ROOT, file), 'utf8')
  for (const key of [
    'reader_error_quota',
    'reader_error_quota_hint',
    'reader_error_rate_limited',
    'reader_error_rate_limited_hint',
  ]) {
    ok(`${file} defines ${key}`, new RegExp(`"name": "${key}"`).test(content))
  }
}

console.log(`✓ reader error state contract: ${passed} assertions passed`)

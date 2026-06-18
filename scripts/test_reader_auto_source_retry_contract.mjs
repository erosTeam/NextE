#!/usr/bin/env node
/**
 * Contract for Reader image auto re-source retry.
 *
 * Bug class: EH full-image URLs are one-shot/host-sensitive. A resolved URL can fail in the Image
 * component or the /s/ resolve can hit a bad/509 source. The reader should automatically retry a
 * bounded number of times with changeSource=true, then keep the manual retry affordance.
 *
 * Run: node scripts/test_reader_auto_source_retry_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = readFileSync(join(ROOT, 'feature/reader/src/main/ets/pages/ReaderPage.ets'), 'utf8')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}
const eq = (name, got, expected) => {
  assert.deepStrictEqual(got, expected, name)
  passed++
}

function retryStep(count, limit) {
  if (count < limit) {
    return { count: count + 1, failed: false, changeSource: true }
  }
  return { count, failed: true, changeSource: false }
}

{
  let state = { count: 0, failed: false, changeSource: false }
  state = retryStep(state.count, 3)
  eq('first failure auto retries with changeSource', state, { count: 1, failed: false, changeSource: true })
  state = retryStep(state.count, 3)
  state = retryStep(state.count, 3)
  eq('third failure is still an automatic retry', state, { count: 3, failed: false, changeSource: true })
  state = retryStep(state.count, 3)
  eq('after limit, reader shows failure UI', state, { count: 3, failed: true, changeSource: false })
}

ok('declares bounded auto retry limit', /const IMAGE_AUTO_RETRY_LIMIT: number = 3/.test(src))
ok('horizontal reader tracks auto retry count', /struct ReaderImagePage[\s\S]*private autoRetryCount: number = 0/.test(src))
ok('vertical reader tracks auto retry count', /struct ReaderVerticalImage[\s\S]*private autoRetryCount: number = 0/.test(src))
ok('resolve failure auto re-sources instead of immediate failed UI', /catch \(err\) \{[\s\S]*resolve_failed[\s\S]*this\.retrySourceAutomatically\(\)/.test(src))
ok('Image load failure auto re-sources', /\.onError\(\(\) => \{[\s\S]*image_load_failed[\s\S]*this\.retrySourceAutomatically\(\)/.test(src))
ok('auto retry calls resolve with changeSource=true', /private retrySourceAutomatically\(\): void \{[\s\S]*this\.autoRetryCount\+\+[\s\S]*this\.resolve\(true\)/.test(src))
ok('auto retry eventually shows failed UI', /private retrySourceAutomatically\(\): void \{[\s\S]*this\.failed = true/.test(src))
ok('manual retry resets retry count', /private retrySource\(\): void \{[\s\S]*this\.autoRetryCount = 0[\s\S]*this\.resolve\(true\)/.test(src))
ok('successful Image load resets retry count', /\.onComplete\(\([^)]*\) => \{[\s\S]*this\.autoRetryCount = 0/.test(src))

console.log(`✓ reader auto source retry contract: ${passed} assertions passed`)

#!/usr/bin/env node
/**
 * Contract: Reader loading/progress enhancement is parked during P0 core recovery.
 *
 * The recovery goal is to restore the basic reading canvas and gestures first. The
 * previous centered ReaderLoadingOverlay/ReaderLoadingLine stack is intentionally not
 * allowed in ReaderPage because it could remain above ready images and disturb hit testing.
 *
 * Run: node scripts/test_reader_loading_progress_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')

ok('Reader root uses the pre-overlay bottom stack baseline',
  /Stack\(\{ alignContent: Alignment\.Bottom \}\)/.test(reader))
ok('root empty and jump loading use plain LoadingProgress',
  /else \{[\s\S]*LoadingProgress\(\)[\s\S]*ThemeConstants\.LOADING_SIZE_LARGE/.test(reader) &&
  /if \(this\.vm\.jumping\) \{[\s\S]*LoadingProgress\(\)[\s\S]*ThemeConstants\.LOADING_SIZE_LARGE/.test(reader))
ok('horizontal image resolving uses plain LoadingProgress',
  /struct ReaderImagePage[\s\S]*else \{[\s\S]*LoadingProgress\(\)[\s\S]*ThemeConstants\.LOADING_SIZE_LARGE/.test(reader))
ok('vertical image resolving uses plain LoadingProgress',
  /struct ReaderVerticalImage[\s\S]*else \{[\s\S]*LoadingProgress\(\)[\s\S]*ThemeConstants\.LOADING_SIZE/.test(reader))
ok('ReaderLoadingOverlay is not present in ReaderPage',
  !/ReaderLoadingOverlay|ReaderLoadingLine/.test(reader))
ok('ready image branch does not overlay loading UI',
  !/if \(!this\.imageLoaded\) \{[\s\S]*LoadingProgress|if \(!this\.imageLoaded\) \{[\s\S]*ReaderLoading/.test(reader))
ok('bottom chrome is not re-anchored against a centered root',
  !/ReaderBottomBar\(\)[\s\S]*\.align\(Alignment\.Bottom\)/.test(reader))

console.log(`✓ reader loading recovery contract: ${passed} assertions passed`)

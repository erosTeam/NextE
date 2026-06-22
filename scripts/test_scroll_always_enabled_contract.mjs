#!/usr/bin/env node
/**
 * Contract: page-level list containers must still respond to drag gestures when
 * their content is shorter than the viewport, so title chrome and pull refresh
 * are usable on sparse pages.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const files = [
  'shared/src/main/ets/components/PullRefreshListScaffold.ets',
  'shared/src/main/ets/components/PullRefreshGridScaffold.ets',
  'shared/src/main/ets/components/PullRefreshWaterFlowScaffold.ets',
  'shared/src/main/ets/components/SecondaryListScaffold.ets',
]

let passed = 0
for (const file of files) {
  const src = readFileSync(join(ROOT, file), 'utf8')
  assert.match(
    src,
    /\.edgeEffect\(EdgeEffect\.Spring,\s*\{\s*alwaysEnabled:\s*true\s*\}\)/,
    `${file} must keep sparse content scrollable`,
  )
  passed++
}

console.log(`✓ scroll always-enabled contract: ${passed} scaffold(s) checked`)

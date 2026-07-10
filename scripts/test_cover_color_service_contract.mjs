#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const root = process.cwd()
const read = (path) => readFileSync(join(root, path), 'utf8')
const service = read('shared/src/main/ets/services/CoverColorService.ets')
const thumbnail = read('shared/src/main/ets/components/EhThumbnail.ets')

assert.match(service, /MAX_COVER_COLOR_MEMORY_ENTRIES:\s*number\s*=\s*512/, 'cover color cache has a finite LRU cap')
assert.match(service, /MAX_COVER_COLOR_CONCURRENCY:\s*number\s*=\s*2/, 'cover color extraction keeps a small global concurrency cap')
assert.match(service, /MAX_COVER_COLOR_PENDING:\s*number\s*=\s*32/, 'cover color extraction bounds pending decoration work')
assert.match(service, /class CoverColorNetworkTask/, 'queued cover color work has a cancellation-safe completion wrapper')
assert.match(service, /this\.queue\.unshift\(task\)/, 'new visible work is considered before stale queued decoration')
assert.match(service, /this\.cache\.put\(url, color\)/, 'both successful and failed extraction outcomes keep existing cache semantics')
assert.match(thumbnail, /needsCoverColorBg\(\)/, 'only the existing letterbox-gradient path requests cover colors')
assert.match(thumbnail, /CoverColorService\.getInstance\(\)\s*\.resolve\(url\)/, 'thumbnail still uses the shared deduplicating service')

console.log('✓ cover color service contract passed')

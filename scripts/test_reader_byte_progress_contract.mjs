#!/usr/bin/env node
/**
 * Contract: streamed Reader byte-progress is parked during P0 core recovery.
 *
 * Online reading must not route every image through a transient file-cache/progress
 * overlay until the Reader layout and gesture stack are accepted again.
 *
 * Run: node scripts/test_reader_byte_progress_contract.mjs
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

ok('ReaderPage does not import CoreFileKit file IO', !/fileIo as fs/.test(reader))
ok('ReaderPage does not import EhHttpClient', !/EhHttpClient/.test(reader))
ok('ReaderPage does not define a reader image cache directory', !/READER_IMAGE_CACHE_DIR/.test(reader))
ok('ReaderImageCache helper is not present', !/class ReaderImageCache/.test(reader))
ok('ReaderPage does not call stream-to-file download', !/downloadBinaryToFileInStream/.test(reader))
ok('ReaderPage renders resolved remote image URLs directly',
  /this\.imageUrl = this\.image\.imageUrl/.test(reader) &&
  /this\.imageUrl = await ImageResolveService\.getInstance\(\)\.resolve/.test(reader))
ok('ReaderPage has no byte progress state or percentage label',
  !/imageProgress|dataReceiveProgress|Math\.round\(Math\.max\(0, Math\.min\(1, this\.progress/.test(reader))

console.log(`✓ reader byte-progress parked contract: ${passed} assertions passed`)

import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import test from 'node:test'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

// Architecture record 6.1 requires NextE to distinguish "cancel a queued request"
// from "cancel an in-flight transfer". This exercises the real scheduler that
// implements that boundary rather than restating the source shape.
const source = fs.readFileSync(
  path.join(root, 'shared/src/main/ets/services/ReaderImageFileCacheService.ets'), 'utf8')
const start = source.indexOf('export class ReaderImagePriorityTask')
const end = source.indexOf('export class ReaderImageFileCacheService')
assert.ok(start >= 0 && end > start, 'priority scheduler section must exist')
const schedulerSource = source.slice(start, end)

const exports = {}
vm.runInNewContext(ts.transpileModule(schedulerSource, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
} }).outputText, {
  exports,
  require: () => { throw new Error('unexpected dependency') },
  EH_IMAGE_PRIORITY_LOW: 2,
  // Module-level constants the scheduler reads; mirror the real declarations.
  MAX_LOW_PRIORITY_DOWNLOADS: Number(/MAX_LOW_PRIORITY_DOWNLOADS: number = (\d+)/.exec(source)[1]),
  CACHE_DIR_NAME: 'reader-image-file-cache',
})
const { ReaderImagePriorityTask, ReaderImagePriorityScheduler } = exports

// Real values from ImagePipelineTypes: HIGH=0, MEDIUM=1, LOW=2.
const LOW = 2
const VISIBLE = 0

function task(starts, label, priority = LOW) {
  return new ReaderImagePriorityTask('key', priority, () => { starts.push(label) })
}

test('a low-priority warmer waits for the single slot and is cancellable while queued', () => {
  const starts = []
  const scheduler = new ReaderImagePriorityScheduler()
  const first = task(starts, 'first')
  const second = task(starts, 'second')
  scheduler.schedule(first)
  scheduler.schedule(second)
  assert.deepEqual(starts, ['first'], 'only one low-priority download runs at a time')
  assert.equal(scheduler.cancel(second), true, 'a queued request can be dropped')
  scheduler.complete(first)
  assert.deepEqual(starts, ['first'], 'the cancelled request never starts')
})

test('a running transfer is not cancelled, matching the transport boundary', () => {
  const starts = []
  const scheduler = new ReaderImagePriorityScheduler()
  const running = task(starts, 'running')
  scheduler.schedule(running)
  assert.deepEqual(starts, ['running'])
  assert.equal(scheduler.cancel(running), false, 'a started stream must not be aborted')
})

test('a visible request promotes a queued warmer without scheduling a duplicate download', () => {
  const starts = []
  const scheduler = new ReaderImagePriorityScheduler()
  const warmer = task(starts, 'warmer')
  const visible = task(starts, 'visible', VISIBLE)
  scheduler.schedule(warmer)
  scheduler.schedule(visible)
  assert.deepEqual(starts, ['warmer', 'visible'], 'the visible request starts immediately alongside the warmer')
  // Promoting the already started warmer must not start it a second time.
  scheduler.promote(warmer, VISIBLE)
  assert.deepEqual(starts, ['warmer', 'visible'])
  scheduler.complete(warmer)
  assert.deepEqual(starts, ['warmer', 'visible'])
})

test('promoting a queued warmer starts it once and releases the low slot on completion', () => {
  const starts = []
  const scheduler = new ReaderImagePriorityScheduler()
  const first = task(starts, 'first')
  const queued = task(starts, 'queued')
  scheduler.schedule(first)
  scheduler.schedule(queued)
  assert.deepEqual(starts, ['first'])
  scheduler.promote(queued, VISIBLE)
  assert.deepEqual(starts, ['first', 'queued'], 'the promoted queued request starts exactly once')
  scheduler.complete(first)
  scheduler.complete(queued)
  assert.deepEqual(starts, ['first', 'queued'])
})

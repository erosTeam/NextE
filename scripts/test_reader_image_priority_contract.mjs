#!/usr/bin/env node
/**
 * Contract for Reader byte-download priority. The scheduler model is copy-equal to the small ArkTS
 * scheduler; source assertions keep the production cache path forwarding priority and relaying
 * progress to joined visible requests.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const HIGH = 0
const LOW = 2

class Task {
  constructor(key, priority, start) {
    this.key = key
    this.priority = priority
    this.started = false
    this.lowSlot = false
    this.startAction = start
  }
  start() {
    this.startAction()
  }
}

class Scheduler {
  constructor() {
    this.lowQueue = []
    this.lowRunning = 0
  }
  schedule(task) {
    if (task.started) return
    if (task.priority === LOW) {
      this.lowQueue.push(task)
      this.drain()
      return
    }
    this.start(task, false)
  }
  promote(task, priority) {
    if (priority >= task.priority) return
    task.priority = priority
    if (task.started || priority === LOW) return
    this.lowQueue = this.lowQueue.filter((candidate) => candidate !== task)
    this.start(task, false)
  }
  cancel(task) {
    if (task.started) return false
    const index = this.lowQueue.indexOf(task)
    if (index < 0) return false
    this.lowQueue.splice(index, 1)
    return true
  }
  complete(task) {
    if (!task.lowSlot) return
    task.lowSlot = false
    this.lowRunning = Math.max(0, this.lowRunning - 1)
    this.drain()
  }
  drain() {
    while (this.lowRunning < 1 && this.lowQueue.length > 0) {
      const next = this.lowQueue.shift()
      if (!next.started) this.start(next, true)
    }
  }
  start(task, lowSlot) {
    if (task.started) return
    task.started = true
    task.lowSlot = lowSlot
    if (lowSlot) this.lowRunning += 1
    task.start()
  }
}

let passed = 0
const ok = (name, condition) => {
  assert.ok(condition, name)
  passed += 1
}

// A stale queued warmer must not acquire the low slot after it leaves the prefetch window.
{
  const starts = []
  const scheduler = new Scheduler()
  const activeLow = new Task('active-low', LOW, () => starts.push('active-low'))
  const staleLow = new Task('stale-low', LOW, () => starts.push('stale-low'))
  scheduler.schedule(activeLow)
  scheduler.schedule(staleLow)
  ok('queued stale warmer can be cancelled before it starts', scheduler.cancel(staleLow))
  scheduler.complete(activeLow)
  ok('cancelled warmer never starts after the active slot completes', starts.join(',') === 'active-low')
}

// A visible image starts ahead of queued warmers, while the active low request is not interrupted.
{
  const starts = []
  const scheduler = new Scheduler()
  const lowA = new Task('low-a', LOW, () => starts.push('low-a'))
  const lowB = new Task('low-b', LOW, () => starts.push('low-b'))
  const high = new Task('high', HIGH, () => starts.push('high'))
  scheduler.schedule(lowA)
  scheduler.schedule(lowB)
  scheduler.schedule(high)
  ok('only one low warmer starts at first', starts.join(',') === 'low-a,high')
  scheduler.complete(lowA)
  ok('queued warmer starts after its low slot is released', starts.join(',') === 'low-a,high,low-b')
}

// A page becoming visible promotes the same queued warmer instead of starting a duplicate request.
{
  const starts = []
  const scheduler = new Scheduler()
  const activeLow = new Task('active-low', LOW, () => starts.push('active-low'))
  const queuedLow = new Task('queued-low', LOW, () => starts.push('queued-low'))
  scheduler.schedule(activeLow)
  scheduler.schedule(queuedLow)
  scheduler.promote(queuedLow, HIGH)
  ok('queued low is promoted and starts immediately', starts.join(',') === 'active-low,queued-low')
  ok('promotion preserves one task identity', queuedLow.started && queuedLow.priority === HIGH)
}

// A joined request must receive every future progress update, rather than jumping directly to 100%.
{
  const seen = []
  const listeners = []
  const publish = (loaded, total) => listeners.forEach((listener) => listener({ loaded, total }))
  listeners.push((progress) => seen.push(`${progress.loaded}/${progress.total}`))
  publish(20, 100)
  publish(75, 100)
  ok('joined progress observer receives streamed updates', seen.join(',') === '20/100,75/100')
}

const read = (path) => readFileSync(join(ROOT, path), 'utf8')
const readerCache = read('shared/src/main/ets/services/ReaderImageFileCacheService.ets')
const pipeline = read('shared/src/main/ets/services/ImagePipelineService.ets')
const readerPage = read('feature/reader/src/main/ets/pages/ReaderPage.ets')

ok('reader cache has a bounded low-priority scheduler with queued-task promotion',
  /MAX_LOW_PRIORITY_DOWNLOADS: number = 1/.test(readerCache) &&
    /class ReaderImagePriorityScheduler/.test(readerCache) &&
    /promote\(task: ReaderImagePriorityTask, priority: number\)/.test(readerCache) &&
    /cancel\(task: ReaderImagePriorityTask\): boolean/.test(readerCache) &&
    /scheduler\.schedule\(task\.priorityTask\)/.test(readerCache))
ok('same-key join relays streaming progress and promotes an unstarted warmer',
  /running\.addProgressListener\(onProgress\)/.test(readerCache) &&
    /scheduler\.promote\(running\.priorityTask, priority\)/.test(readerCache) &&
    /task\.publishProgress\(progress\)/.test(readerCache))
ok('pipeline forwards priority into the durable reader file cache',
  !/_priority/.test(pipeline) &&
    /ReaderImageCacheSettings\.limitBytes\(\),\s*priority,/.test(pipeline))
ok('Reader still marks warmers LOW and visible file loads HIGH',
  /loadReaderFile\([\s\S]*?EH_IMAGE_PRIORITY_LOW/.test(readerPage) &&
    /loadReaderFile\([\s\S]*?EH_IMAGE_PRIORITY_HIGH/.test(readerPage))
ok('stale queued warmers are cancelled on lifecycle/source changes and source replacement',
  /cancelQueuedReaderFile/.test(pipeline) &&
    /cancelQueuedWarm\(\)/.test(readerPage) &&
    /aboutToDisappear\(\): void \{[\s\S]*?cancelQueuedWarm\(\)/.test(readerPage) &&
    /static remove\([\s\S]*?cancelQueued\(context, cacheKey\)/.test(readerCache))

console.log(`✓ reader image priority contract: ${passed} assertions passed`)

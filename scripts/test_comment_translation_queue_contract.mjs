#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const MAX = 2
const PENDING_MAX = 32
const INTERACTIVE = 0
const AUTO = 1
const EVICTED = 'comment_translation_queue_evicted'
const FULL = 'comment_translation_queue_full'

class Task {
  constructor(key, priority, startAction, discardAction = () => {}) {
    this.key = key
    this.priority = priority
    this.started = false
    this.active = false
    this.discarded = false
    this.startAction = startAction
    this.discardAction = discardAction
  }
  start() {
    this.startAction()
  }
  discard(error) {
    if (this.started || this.discarded) return
    this.discarded = true
    this.discardAction(error)
  }
}

class Scheduler {
  constructor() {
    this.queue = []
    this.running = 0
  }
  schedule(task) {
    if (task.started || task.discarded) return
    if (!this.makeRoom(task)) return
    this.enqueue(task)
    this.drain()
  }
  promote(task, priority) {
    if (task.discarded || priority >= task.priority) return
    task.priority = priority
    if (task.started || !this.removeQueued(task)) return
    this.enqueue(task)
    this.drain()
  }
  complete(task) {
    if (!task.active) return
    task.active = false
    this.running = Math.max(0, this.running - 1)
    this.drain()
  }
  pendingCount() {
    return this.queue.length
  }
  drain() {
    while (this.running < MAX && this.queue.length > 0) {
      const next = this.queue.shift()
      if (!next || next.started || next.discarded) continue
      next.started = true
      next.active = true
      this.running += 1
      next.start()
    }
  }
  enqueue(task) {
    const index = this.queue.findIndex((candidate) => task.priority < candidate.priority)
    if (index < 0) this.queue.push(task)
    else this.queue.splice(index, 0, task)
  }
  makeRoom(task) {
    if (this.queue.length < PENDING_MAX) return true
    const discarded = this.discardOldestAuto()
    if (discarded) {
      discarded.discard(new Error(EVICTED))
      return true
    }
    task.discard(new Error(FULL))
    return false
  }
  discardOldestAuto() {
    const index = this.queue.findIndex((candidate) => candidate.priority === AUTO)
    if (index < 0) return undefined
    return this.queue.splice(index, 1)[0]
  }
  removeQueued(task) {
    const index = this.queue.indexOf(task)
    if (index < 0) return false
    this.queue.splice(index, 1)
    return true
  }
}

let passed = 0
const ok = (name, condition) => {
  assert.ok(condition, name)
  passed += 1
}

{
  const starts = []
  const scheduler = new Scheduler()
  const first = new Task('first', AUTO, () => starts.push('first'))
  const second = new Task('second', AUTO, () => starts.push('second'))
  const third = new Task('third', AUTO, () => starts.push('third'))
  const interactive = new Task('interactive', INTERACTIVE, () => starts.push('interactive'))
  scheduler.schedule(first)
  scheduler.schedule(second)
  scheduler.schedule(third)
  scheduler.schedule(interactive)
  ok('only two distinct translations enter the provider at once', starts.join(',') === 'first,second')
  scheduler.complete(first)
  ok('interactive work starts before queued auto translations after a slot is released', starts.join(',') === 'first,second,interactive')
  scheduler.complete(second)
  ok('auto translations retain FIFO order behind interactive work', starts.join(',') === 'first,second,interactive,third')
  scheduler.complete(interactive)
  scheduler.complete(third)
  ok('completed slots are released exactly once', !third.active)
}

{
  const starts = []
  const discarded = []
  const scheduler = new Scheduler()
  const activeA = new Task('active-a', AUTO, () => starts.push('active-a'))
  const activeB = new Task('active-b', AUTO, () => starts.push('active-b'))
  scheduler.schedule(activeA)
  scheduler.schedule(activeB)
  const queued = []
  for (let i = 0; i < PENDING_MAX; i += 1) {
    const task = new Task(`auto-${i}`, AUTO, () => starts.push(`auto-${i}`), (error) => discarded.push(error.message))
    queued.push(task)
    scheduler.schedule(task)
  }
  ok('waiting work has a fixed upper bound', scheduler.pendingCount() === PENDING_MAX)
  const latestAuto = new Task('latest-auto', AUTO, () => starts.push('latest-auto'))
  scheduler.schedule(latestAuto)
  ok('a new visible auto translation replaces the oldest queued auto task',
    queued[0].discarded && !latestAuto.discarded && scheduler.pendingCount() === PENDING_MAX)
  const interactive = new Task('interactive', INTERACTIVE, () => starts.push('interactive'))
  scheduler.schedule(interactive)
  scheduler.complete(activeA)
  ok('interactive work replaces stale automatic work and runs at the next slot',
    queued[1].discarded && starts.join(',') === 'active-a,active-b,interactive')
  ok('evicted automatic work reports a dedicated error for silent UI cleanup',
    discarded.join(',') === `${EVICTED},${EVICTED}`)

  const interactiveOnly = new Scheduler()
  interactiveOnly.schedule(new Task('running-a', AUTO, () => {}))
  interactiveOnly.schedule(new Task('running-b', AUTO, () => {}))
  for (let i = 0; i < PENDING_MAX; i += 1) {
    interactiveOnly.schedule(new Task(`manual-${i}`, INTERACTIVE, () => {}))
  }
  const rejectedInteractive = new Task('manual-overflow', INTERACTIVE, () => {})
  interactiveOnly.schedule(rejectedInteractive)
  ok('a full interactive queue rejects only new interactive work instead of exceeding the cap',
    rejectedInteractive.discarded && interactiveOnly.pendingCount() === PENDING_MAX)
}

{
  const starts = []
  const scheduler = new Scheduler()
  const activeA = new Task('active-a', AUTO, () => starts.push('active-a'))
  const activeB = new Task('active-b', AUTO, () => starts.push('active-b'))
  const queuedAuto = new Task('queued-auto', AUTO, () => starts.push('queued-auto'))
  const queuedOther = new Task('queued-other', AUTO, () => starts.push('queued-other'))
  scheduler.schedule(activeA)
  scheduler.schedule(activeB)
  scheduler.schedule(queuedAuto)
  scheduler.schedule(queuedOther)
  scheduler.promote(queuedAuto, INTERACTIVE)
  scheduler.complete(activeA)
  ok('a same-key user action promotes its queued auto translation without duplicating it',
    starts.join(',') === 'active-a,active-b,queued-auto' && queuedAuto.priority === INTERACTIVE)
}

const read = (path) => readFileSync(join(ROOT, path), 'utf8')
const service = read('shared/src/main/ets/services/CommentTranslationService.ets')
const index = read('shared/src/main/ets/Index.ets')

ok('comment translations use fixed running and pending budgets with automatic-work eviction',
  /MAX_CONCURRENT_COMMENT_TRANSLATIONS: number = 2/.test(service) &&
    /MAX_PENDING_COMMENT_TRANSLATIONS: number = 32/.test(service) &&
    /COMMENT_TRANSLATION_PRIORITY_INTERACTIVE: number = 0/.test(service) &&
    /COMMENT_TRANSLATION_PRIORITY_AUTO: number = 1/.test(service) &&
    /class CommentTranslationQueueScheduler/.test(service) &&
    /promote\(task: CommentTranslationQueueTask, priority: number\)/.test(service) &&
    /discardOldestAuto\(\)/.test(service) &&
    /while \(this\.running < MAX_CONCURRENT_COMMENT_TRANSLATIONS/.test(service))
ok('cache hits stay outside the remote queue while distinct misses are queued, settled keys rebuild, and same keys can promote',
  /const cached: string = await CommentTranslationService\.getCached/.test(service) &&
    /const inFlight: CommentTranslationNetworkTask \| undefined = CommentTranslationService\.inflight\.get\(key\)/.test(service) &&
    /inFlight !== undefined && !inFlight\.isSettled\(\)/.test(service) &&
    /scheduler\.promote\(inFlight\.queueTask, priority\)/.test(service) &&
    /setDiscardCleanup/.test(service) &&
    /new CommentTranslationNetworkTask\([\s\S]*?translateAndCache/.test(service) &&
    /scheduler\.schedule\(queuedTask\.queueTask\)/.test(service))
ok('the production scheduler is exported for deterministic device testing',
  /COMMENT_TRANSLATION_PRIORITY_AUTO/.test(index) &&
    /COMMENT_TRANSLATION_PRIORITY_INTERACTIVE/.test(index) &&
    /MAX_PENDING_COMMENT_TRANSLATIONS/.test(index) &&
    /CommentTranslationQueueScheduler/.test(index) &&
    /CommentTranslationQueueTask/.test(index))

console.log(`✓ comment translation queue contract: ${passed} assertions passed`)

import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhHttpClient } from '../network/EhHttpClient'
import {
  CachedImageFileResult,
  CachedImageFileService,
  CachedImageProgress,
} from './CachedImageFileService'
import { CacheStat } from './CacheStat'
import { EH_IMAGE_PRIORITY_LOW } from './ImagePipelineTypes'

const CACHE_DIR_NAME: string = 'reader-image-file-cache'
const CACHE_FILE_EXTENSION: string = 'img'
const READER_IMAGE_CONNECT_TIMEOUT_MS: number = 6000
const READER_IMAGE_NO_PROGRESS_TIMEOUT_MS: number = 10000
const MAX_CACHE_FILE_COUNT: number = 4096
const MAX_LOW_PRIORITY_DOWNLOADS: number = 1

class ReaderImageCacheEntry {
  path: string = ''
  bytes: number = 0
  mtime: number = 0

  constructor(path: string, bytes: number, mtime: number) {
    this.path = path
    this.bytes = bytes
    this.mtime = mtime
  }
}

/** A small, deterministic scheduler for Reader byte downloads (separate from ImageKnife decoding). */
export class ReaderImagePriorityTask {
  key: string = ''
  priority: number = EH_IMAGE_PRIORITY_LOW
  started: boolean = false
  lowSlot: boolean = false
  private startAction: () => void = () => {}

  constructor(key: string, priority: number, startAction: () => void) {
    this.key = key
    this.priority = priority
    this.startAction = startAction
  }

  start(): void {
    this.startAction()
  }
}

/**
 * Low-priority warmers use one network slot. Any visible (non-low) request starts immediately and
 * can promote the same queued warmer without duplicating its download; running requests are not
 * aborted because NetworkKit does not expose safe stream-priority mutation.
 */
export class ReaderImagePriorityScheduler {
  private lowQueue: ReaderImagePriorityTask[] = []
  private lowRunning: number = 0

  schedule(task: ReaderImagePriorityTask): void {
    if (task.started) {
      return
    }
    if (this.isLowPriority(task.priority)) {
      this.lowQueue.push(task)
      this.drainLowQueue()
      return
    }
    this.start(task, false)
  }

  promote(task: ReaderImagePriorityTask, priority: number): void {
    if (priority >= task.priority) {
      return
    }
    task.priority = priority
    if (task.started || this.isLowPriority(priority)) {
      return
    }
    this.removeQueued(task)
    this.start(task, false)
  }

  /**
   * Drop a request that has not acquired a network slot yet. Running requests are deliberately left
   * alone: NetworkKit cannot safely abort their stream without risking a partial-cache race.
   */
  cancel(task: ReaderImagePriorityTask): boolean {
    if (task.started) {
      return false
    }
    return this.removeQueued(task)
  }

  complete(task: ReaderImagePriorityTask): void {
    if (!task.lowSlot) {
      return
    }
    task.lowSlot = false
    if (this.lowRunning > 0) {
      this.lowRunning--
    }
    this.drainLowQueue()
  }

  private drainLowQueue(): void {
    while (this.lowRunning < MAX_LOW_PRIORITY_DOWNLOADS && this.lowQueue.length > 0) {
      const next: ReaderImagePriorityTask | undefined = this.lowQueue.shift()
      if (next !== undefined && !next.started) {
        this.start(next, true)
      }
    }
  }

  private start(task: ReaderImagePriorityTask, useLowSlot: boolean): void {
    if (task.started) {
      return
    }
    task.started = true
    task.lowSlot = useLowSlot
    if (useLowSlot) {
      this.lowRunning++
    }
    task.start()
  }

  private removeQueued(task: ReaderImagePriorityTask): boolean {
    for (let i: number = 0; i < this.lowQueue.length; i++) {
      if (this.lowQueue[i] === task) {
        this.lowQueue.splice(i, 1)
        return true
      }
    }
    return false
  }

  private isLowPriority(priority: number): boolean {
    return priority === EH_IMAGE_PRIORITY_LOW
  }
}

class ReaderImageLoadTask {
  context: common.UIAbilityContext
  url: string
  cacheKey: string
  filePath: string
  limitBytes: number
  priorityTask: ReaderImagePriorityTask
  private progressListeners: Array<(progress: CachedImageProgress) => void> = []
  private lastProgress: CachedImageProgress = { loaded: 0, total: 0 }
  private hasProgress: boolean = false
  private completion: Promise<void> = Promise.resolve()
  private releaseCompletion: () => void = () => {}
  private finished: boolean = false
  private result: CachedImageFileResult | null = null
  private failureMessage: string = ''

  constructor(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    filePath: string,
    limitBytes: number,
    priority: number,
  ) {
    this.context = context
    this.url = url
    this.cacheKey = cacheKey
    this.filePath = filePath
    this.limitBytes = limitBytes
    this.priorityTask = new ReaderImagePriorityTask(filePath, priority, () => {
      ReaderImageFileCacheService.startDownload(this)
    })
    this.completion = new Promise<void>((resolve: () => void): void => {
      this.releaseCompletion = resolve
    })
  }

  addProgressListener(listener: (progress: CachedImageProgress) => void): void {
    this.progressListeners.push(listener)
    if (this.hasProgress) {
      this.notifyListener(listener, this.lastProgress)
    }
  }

  publishProgress(progress: CachedImageProgress): void {
    this.hasProgress = true
    this.lastProgress = { loaded: progress.loaded, total: progress.total }
    this.progressListeners.forEach((listener: (progress: CachedImageProgress) => void) => {
      this.notifyListener(listener, this.lastProgress)
    })
  }

  complete(result: CachedImageFileResult): void {
    if (this.finished) {
      return
    }
    this.finished = true
    this.result = result
    this.publishProgress({ loaded: result.bytes, total: result.bytes })
    this.releaseCompletion()
  }

  fail(error: Error): void {
    if (this.finished) {
      return
    }
    this.finished = true
    this.failureMessage = error.message.length > 0 ? error.message : 'reader image download failed'
    this.releaseCompletion()
  }

  async waitForResult(): Promise<CachedImageFileResult> {
    await this.completion
    if (this.failureMessage.length > 0) {
      throw new Error(this.failureMessage)
    }
    if (this.result === null) {
      throw new Error('reader image download finished without a result')
    }
    return this.result
  }

  private notifyListener(
    listener: (progress: CachedImageProgress) => void,
    progress: CachedImageProgress,
  ): void {
    try {
      listener({ loaded: progress.loaded, total: progress.total })
    } catch (_error) {}
  }
}

/**
 * App-owned Reader image-byte cache.
 *
 * The key is the gallery page identity, not EH's resolved CDN URL. This lets a cached page survive
 * process restarts, /s/ re-resolution, and image-host changes. ImageKnifePro still decodes the local
 * file and owns its memory cache; this service owns only durable Reader image bytes and LRU eviction.
 */
export class ReaderImageFileCacheService {
  private static inFlight: Map<string, ReaderImageLoadTask> = new Map<
    string,
    ReaderImageLoadTask
  >()
  private static readonly scheduler: ReaderImagePriorityScheduler = new ReaderImagePriorityScheduler()
  private static pruneChain: Promise<void> = Promise.resolve()

  static cacheKey(gid: string, token: string, page: number, original: boolean): string {
    return `reader:v1:${gid}:${token}:${page}:${original ? 'original' : 'resampled'}`
  }

  static cached(
    context: common.UIAbilityContext,
    cacheKey: string,
  ): CachedImageFileResult | null {
    if (cacheKey.length === 0) {
      return null
    }
    const filePath: string = ReaderImageFileCacheService.filePath(context, cacheKey)
    const bytes: number = ReaderImageFileCacheService.fileSize(filePath)
    if (bytes <= 0) {
      return null
    }
    ReaderImageFileCacheService.touch(filePath)
    DiagnosticLogger.info(
      'image-cache',
      'reader_disk_hit',
      `bytes=${bytes} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
    )
    return {
      filePath,
      displayUri: CachedImageFileService.displayUri(filePath),
      bytes,
      fromCache: true,
    }
  }

  static async load(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    limitBytes: number,
    priority: number,
    onProgress: (progress: CachedImageProgress) => void,
  ): Promise<CachedImageFileResult> {
    if (url.length === 0) {
      throw new Error('image URL is empty')
    }
    const localPath: string = ReaderImageFileCacheService.localFilePath(url)
    if (localPath.length > 0) {
      const localBytes: number = ReaderImageFileCacheService.fileSize(localPath)
      if (localBytes <= 0) {
        throw new Error('local image file missing')
      }
      onProgress({ loaded: localBytes, total: localBytes })
      return {
        filePath: localPath,
        displayUri: CachedImageFileService.displayUri(localPath),
        bytes: localBytes,
        fromCache: true,
      }
    }

    const cached: CachedImageFileResult | null = ReaderImageFileCacheService.cached(context, cacheKey)
    if (cached !== null) {
      onProgress({ loaded: cached.bytes, total: cached.bytes })
      return cached
    }

    const filePath: string = ReaderImageFileCacheService.filePath(context, cacheKey)
    const running: ReaderImageLoadTask | undefined =
      ReaderImageFileCacheService.inFlight.get(filePath)
    if (running !== undefined) {
      // A queued warmer is still safe to replace. This matters when a Reader retry re-resolves the
      // same page identity to a fresh CDN URL: promoting the old queued URL would silently defeat
      // the retry. Existing waiters are released with a controlled failure below.
      if (!running.priorityTask.started && running.url !== url) {
        ReaderImageFileCacheService.cancelQueuedTask(running, 'reader image source superseded')
      } else {
        running.addProgressListener(onProgress)
        const wasQueued: boolean = !running.priorityTask.started
        if (priority < running.priorityTask.priority) {
          ReaderImageFileCacheService.scheduler.promote(running.priorityTask, priority)
          if (wasQueued && running.priorityTask.started) {
            DiagnosticLogger.info(
              'image-cache',
              'reader_disk_promoted',
              `priority=${priority} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
            )
          }
        }
        const result: CachedImageFileResult = await running.waitForResult()
        DiagnosticLogger.info(
          'image-cache',
          'reader_disk_join',
          `bytes=${result.bytes} priority=${priority} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
        )
        return result
      }
    }

    DiagnosticLogger.info(
      'image-cache',
      'reader_disk_miss',
      `urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
    )
    const task: ReaderImageLoadTask = new ReaderImageLoadTask(
      context,
      url,
      cacheKey,
      filePath,
      limitBytes,
      priority,
    )
    task.addProgressListener(onProgress)
    ReaderImageFileCacheService.inFlight.set(filePath, task)
    ReaderImageFileCacheService.scheduler.schedule(task.priorityTask)
    return await task.waitForResult()
  }

  // ReaderImageLoadTask owns the deferred start callback, so ArkTS requires this same-file entry
  // point to be callable by the task object rather than marking it private.
  static startDownload(task: ReaderImageLoadTask): void {
    ReaderImageFileCacheService.downloadAndStore(
      task.context,
      task.url,
      task.cacheKey,
      task.filePath,
      task.limitBytes,
      task.priorityTask.priority,
      (progress: CachedImageProgress) => task.publishProgress(progress),
    ).then(
      (result: CachedImageFileResult): void => {
        task.complete(result)
        ReaderImageFileCacheService.settleTask(task)
      },
      (error: Error): void => {
        task.fail(error)
        ReaderImageFileCacheService.settleTask(task)
      },
    )
  }

  private static settleTask(task: ReaderImageLoadTask): void {
    const active: ReaderImageLoadTask | undefined = ReaderImageFileCacheService.inFlight.get(task.filePath)
    if (active === task) {
      ReaderImageFileCacheService.inFlight.delete(task.filePath)
    }
    ReaderImageFileCacheService.scheduler.complete(task.priorityTask)
  }

  static cancelQueued(context: common.UIAbilityContext, cacheKey: string): boolean {
    if (cacheKey.length === 0) {
      return false
    }
    const filePath: string = ReaderImageFileCacheService.filePath(context, cacheKey)
    const task: ReaderImageLoadTask | undefined = ReaderImageFileCacheService.inFlight.get(filePath)
    if (task === undefined) {
      return false
    }
    return ReaderImageFileCacheService.cancelQueuedTask(task, 'reader image request cancelled')
  }

  private static cancelQueuedTask(task: ReaderImageLoadTask, reason: string): boolean {
    if (!ReaderImageFileCacheService.scheduler.cancel(task.priorityTask)) {
      return false
    }
    const active: ReaderImageLoadTask | undefined = ReaderImageFileCacheService.inFlight.get(task.filePath)
    if (active === task) {
      ReaderImageFileCacheService.inFlight.delete(task.filePath)
    }
    task.fail(new Error(reason))
    DiagnosticLogger.info(
      'image-cache',
      'reader_disk_queued_cancelled',
      `cacheKeyHash=${DiagnosticLogger.ownerHash(task.cacheKey)}`,
    )
    return true
  }

  private static async downloadAndStore(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    filePath: string,
    limitBytes: number,
    priority: number,
    onProgress: (progress: CachedImageProgress) => void,
  ): Promise<CachedImageFileResult> {
    const tmpPath: string = `${filePath}.part`
    ReaderImageFileCacheService.removeIfExists(tmpPath)
    let lastLoggedPercent: number = -20
    let loggedUnknownTotal: boolean = false
    try {
      DiagnosticLogger.info(
        'image-cache',
        'reader_network_start',
        `priority=${priority} urlHash=${DiagnosticLogger.ownerHash(url)} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
      )
      const bytes: number = await EhHttpClient.getInstance().downloadBinaryToFileInStream(
        url,
        tmpPath,
        (loaded: number, total: number) => {
          if (total <= 0) {
            if (!loggedUnknownTotal) {
              loggedUnknownTotal = true
              DiagnosticLogger.info(
                'image-cache',
                'reader_stream_progress',
                `loaded=${loaded} total=${total} percent=? cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
              )
            }
            onProgress({ loaded, total })
            return
          }
          const percent: number = Math.floor(Math.max(0, Math.min(100, loaded * 100 / total)))
          if (percent > lastLoggedPercent && (percent >= 100 || percent - lastLoggedPercent >= 20)) {
            lastLoggedPercent = percent
            DiagnosticLogger.info(
              'image-cache',
              'reader_stream_progress',
              `loaded=${loaded} total=${total} percent=${percent} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
            )
          }
          onProgress({ loaded, total })
        },
        READER_IMAGE_CONNECT_TIMEOUT_MS,
        READER_IMAGE_NO_PROGRESS_TIMEOUT_MS,
      )
      ReaderImageFileCacheService.removeIfExists(filePath)
      fileIo.renameSync(tmpPath, filePath)
      const finalBytes: number = bytes > 0 ? bytes : ReaderImageFileCacheService.fileSize(filePath)
      if (finalBytes <= 0) {
        ReaderImageFileCacheService.removeIfExists(filePath)
        throw new Error('downloaded image file is empty')
      }
      onProgress({ loaded: finalBytes, total: finalBytes })
      DiagnosticLogger.info(
        'image-cache',
        'reader_disk_stored',
        `bytes=${finalBytes} cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
      )
      await ReaderImageFileCacheService.pruneToLimit(context, limitBytes)
      return {
        filePath,
        displayUri: CachedImageFileService.displayUri(filePath),
        bytes: finalBytes,
        fromCache: false,
      }
    } catch (error) {
      ReaderImageFileCacheService.removeIfExists(tmpPath)
      throw error as Error
    }
  }

  static remove(context: common.UIAbilityContext, cacheKey: string): void {
    if (cacheKey.length === 0) {
      return
    }
    ReaderImageFileCacheService.cancelQueued(context, cacheKey)
    ReaderImageFileCacheService.removeIfExists(ReaderImageFileCacheService.filePath(context, cacheKey))
    DiagnosticLogger.info(
      'image-cache',
      'reader_disk_removed',
      `cacheKeyHash=${DiagnosticLogger.ownerHash(cacheKey)}`,
    )
  }

  static async stat(context: common.UIAbilityContext): Promise<CacheStat> {
    const out: CacheStat = new CacheStat()
    const entries: ReaderImageCacheEntry[] = ReaderImageFileCacheService.entries(context)
    out.count = entries.length
    for (let i: number = 0; i < entries.length; i++) {
      out.bytes += entries[i].bytes
    }
    return out
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    const dir: string = ReaderImageFileCacheService.cacheDir(context)
    try {
      if (!fileIo.accessSync(dir)) {
        return
      }
      const names: string[] = fileIo.listFileSync(dir)
      for (let i: number = 0; i < names.length; i++) {
        ReaderImageFileCacheService.removeIfExists(`${dir}/${names[i]}`)
      }
    } catch (error) {
      DiagnosticLogger.warn('image-cache', 'reader_disk_clear_failed', (error as Error).message)
    }
  }

  static pruneToLimit(context: common.UIAbilityContext, limitBytes: number): Promise<void> {
    const next: Promise<void> = ReaderImageFileCacheService.pruneChain.then(
      (): Promise<void> => ReaderImageFileCacheService.pruneNow(context, limitBytes),
      (): Promise<void> => ReaderImageFileCacheService.pruneNow(context, limitBytes),
    )
    ReaderImageFileCacheService.pruneChain = next
    return next
  }

  private static async pruneNow(context: common.UIAbilityContext, limitBytes: number): Promise<void> {
    const entries: ReaderImageCacheEntry[] = ReaderImageFileCacheService.entries(context)
    if (entries.length === 0) {
      return
    }
    entries.sort((a: ReaderImageCacheEntry, b: ReaderImageCacheEntry): number => a.mtime - b.mtime)
    let totalBytes: number = 0
    for (let i: number = 0; i < entries.length; i++) {
      totalBytes += entries[i].bytes
    }
    const normalizedLimit: number = limitBytes > 0 ? limitBytes : 1
    let remaining: number = entries.length
    let removed: number = 0
    for (let i: number = 0; i < entries.length; i++) {
      if ((totalBytes <= normalizedLimit && remaining <= MAX_CACHE_FILE_COUNT) || remaining <= 1) {
        break
      }
      ReaderImageFileCacheService.removeIfExists(entries[i].path)
      totalBytes -= entries[i].bytes
      remaining--
      removed++
    }
    if (removed > 0) {
      DiagnosticLogger.info(
        'image-cache',
        'reader_disk_pruned',
        `removed=${removed} remaining=${remaining} bytes=${totalBytes} limit=${normalizedLimit}`,
      )
    }
  }

  private static entries(context: common.UIAbilityContext): ReaderImageCacheEntry[] {
    const out: ReaderImageCacheEntry[] = []
    const dir: string = ReaderImageFileCacheService.cacheDir(context)
    try {
      if (!fileIo.accessSync(dir)) {
        return out
      }
      const names: string[] = fileIo.listFileSync(dir)
      for (let i: number = 0; i < names.length; i++) {
        if (names[i].endsWith('.part')) {
          continue
        }
        const path: string = `${dir}/${names[i]}`
        try {
          const stat = fileIo.statSync(path)
          if (stat.size > 0) {
            out.push(new ReaderImageCacheEntry(path, stat.size, stat.mtime))
          } else {
            ReaderImageFileCacheService.removeIfExists(path)
          }
        } catch (_error) {}
      }
    } catch (error) {
      DiagnosticLogger.warn('image-cache', 'reader_disk_scan_failed', (error as Error).message)
    }
    return out
  }

  private static filePath(context: common.UIAbilityContext, cacheKey: string): string {
    const dir: string = ReaderImageFileCacheService.cacheDir(context)
    ReaderImageFileCacheService.ensureDir(dir)
    return `${dir}/${ReaderImageFileCacheService.hashKey(cacheKey)}.${CACHE_FILE_EXTENSION}`
  }

  private static cacheDir(context: common.UIAbilityContext): string {
    return `${context.cacheDir}/${CACHE_DIR_NAME}`
  }

  private static localFilePath(url: string): string {
    return url.startsWith('file://') ? url.substring('file://'.length) : ''
  }

  private static ensureDir(dir: string): void {
    try {
      fileIo.mkdirSync(dir, true)
    } catch (error) {
      if (!fileIo.accessSync(dir)) {
        throw error as Error
      }
    }
  }

  private static touch(path: string): void {
    try {
      fileIo.utimes(path, Date.now())
    } catch (_error) {}
  }

  private static fileSize(path: string): number {
    try {
      return fileIo.statSync(path).size
    } catch (_error) {
      return 0
    }
  }

  private static removeIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_error) {}
  }

  private static hashKey(value: string): string {
    let first: number = 5381
    let second: number = 2166136261
    for (let i: number = 0; i < value.length; i++) {
      const code: number = value.charCodeAt(i)
      first = ((first << 5) + first + code) >>> 0
      second = (code + (second << 6) + (second << 16) - second) >>> 0
    }
    return `${first.toString(16)}-${second.toString(16)}`
  }
}

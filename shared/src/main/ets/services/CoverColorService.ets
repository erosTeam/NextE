import { taskpool } from '@kit.ArkTS'
import { image } from '@kit.ImageKit'
import { effectKit } from '@kit.ArkGraphics2D'
import axios, { AxiosRequestConfig, AxiosResponse } from '@ohos/axios'

const MAX_COVER_COLOR_MEMORY_ENTRIES: number = 512
const MAX_COVER_COLOR_CONCURRENCY: number = 2
const MAX_COVER_COLOR_PENDING: number = 32

// Decode the thumbnail to a tiny bitmap purely for color sampling — far cheaper than decoding the full
// cover, and plenty for a dominant-color read (effectKit scales to ~1px internally anyway).
/**
 * Off-UI-thread cover dominant-color extraction. Fetches the public-CDN thumbnail bytes, decodes a small
 * downsampled bitmap, and reads the main color via effectKit. Returns a packed 0xAARRGGBB number (opaque)
 * usable directly as an ArkUI ResourceColor, or 0 on any failure so the caller can fall back to no gradient.
 *
 * The whole pipeline runs inside the worker so the PixelMap never crosses threads (avoids the 501
 * cross-thread-handle invalidation); only a primitive number is marshalled back. PixelMap/ImageSource are
 * released in finally to keep decode memory off the heap.
 */
@Concurrent
async function extractCoverColor(url: string): Promise<number> {
  const decodeSize: number = 32
  const timeoutMs: number = 15000
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    const config: AxiosRequestConfig<string> = {
      url: url,
      method: 'GET',
      responseType: 'array_buffer',
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      timeout: timeoutMs,
    }
    const resp: AxiosResponse<ArrayBuffer, string> =
      await axios.request<ArrayBuffer, AxiosResponse<ArrayBuffer, string>, string>(config)
    if (resp.status !== 200 || !(resp.data instanceof ArrayBuffer)) {
      return 0
    }
    source = image.createImageSource(resp.data)
    const options: image.DecodingOptions = {
      editable: false,
      desiredSize: { width: decodeSize, height: decodeSize },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    }
    pixelMap = await source.createPixelMap(options)
    const picker: effectKit.ColorPicker = await effectKit.createColorPicker(pixelMap)
    const color: effectKit.Color = picker.getMainColorSync()
    // Pack opaque ARGB; >>> 0 yields an unsigned 0xAARRGGBB (a signed << 24 would read negative).
    return ((0xff << 24) | (color.red << 16) | (color.green << 8) | color.blue) >>> 0
  } catch (error) {
    return 0
  } finally {
    if (pixelMap !== undefined) {
      await pixelMap.release()
    }
    if (source !== undefined) {
      await source.release()
    }
  }
}

/**
 * A bounded LRU cache for the decorative cover-color layer. It intentionally keeps failed extraction as 0:
 * that preserves the existing no-retry-storm behavior, while eviction only lets a later visible card try again.
 */
export class CoverColorMemoryCache {
  private readonly maxEntries: number
  private entries: Map<string, number> = new Map()

  constructor(maxEntries: number = MAX_COVER_COLOR_MEMORY_ENTRIES) {
    this.maxEntries = maxEntries > 0 ? maxEntries : 1
  }

  get(url: string): number | undefined {
    const color: number | undefined = this.entries.get(url)
    if (color === undefined) {
      return undefined
    }
    this.entries.delete(url)
    this.entries.set(url, color)
    return color
  }

  put(url: string, color: number): void {
    if (url.length === 0) {
      return
    }
    this.entries.delete(url)
    this.entries.set(url, color)
    this.trim()
  }

  size(): number {
    return this.entries.size
  }

  private trim(): void {
    while (this.entries.size > this.maxEntries) {
      let found: boolean = false
      let oldest: string = ''
      this.entries.forEach((_color: number, url: string): void => {
        if (!found) {
          found = true
          oldest = url
        }
      })
      if (!found) {
        return
      }
      this.entries.delete(oldest)
    }
  }
}

/** A waiting extraction is decorative work and can be dropped if a rapid scroll makes it stale. */
export class CoverColorQueueTask {
  key: string = ''
  started: boolean = false
  active: boolean = false
  private startAction: () => void = () => {}
  private cancelAction: () => void = () => {}

  constructor(key: string, startAction: () => void, cancelAction: () => void = () => {}) {
    this.key = key
    this.startAction = startAction
    this.cancelAction = cancelAction
  }

  start(): void {
    this.startAction()
  }

  cancel(): void {
    this.cancelAction()
  }
}

/**
 * Protects the shared TaskPool from list-scroll bursts. New appearances run before stale queued decoration;
 * active work is never interrupted. A dropped pending request resolves to 0, so the image still paints and
 * simply falls back to its normal no-gradient state.
 */
export class CoverColorQueueScheduler {
  private queue: CoverColorQueueTask[] = []
  private running: number = 0
  private readonly maxConcurrent: number
  private readonly maxPending: number

  constructor(
    maxConcurrent: number = MAX_COVER_COLOR_CONCURRENCY,
    maxPending: number = MAX_COVER_COLOR_PENDING,
  ) {
    this.maxConcurrent = maxConcurrent > 0 ? Math.floor(maxConcurrent) : 1
    this.maxPending = maxPending > 0 ? Math.floor(maxPending) : 1
  }

  schedule(task: CoverColorQueueTask): void {
    if (task.started) {
      return
    }
    this.queue.unshift(task)
    this.trimPending()
    this.drain()
  }

  complete(task: CoverColorQueueTask): void {
    if (!task.active) {
      return
    }
    task.active = false
    if (this.running > 0) {
      this.running--
    }
    this.drain()
  }

  activeCount(): number {
    return this.running
  }

  pendingCount(): number {
    return this.queue.length
  }

  private trimPending(): void {
    while (this.queue.length > this.maxPending) {
      const stale: CoverColorQueueTask | undefined = this.queue.pop()
      if (stale !== undefined && !stale.started) {
        stale.cancel()
      }
    }
  }

  private drain(): void {
    while (this.running < this.maxConcurrent && this.queue.length > 0) {
      const next: CoverColorQueueTask | undefined = this.queue.shift()
      if (next === undefined || next.started) {
        continue
      }
      next.started = true
      next.active = true
      this.running++
      next.start()
    }
  }
}

class CoverColorNetworkTask {
  queueTask: CoverColorQueueTask
  private readonly work: () => Promise<number>
  private readonly scheduler: CoverColorQueueScheduler
  private completion: Promise<number> = Promise.resolve(0)
  private resolveCompletion: (color: number) => void = (_color: number): void => {}
  private settled: boolean = false

  constructor(key: string, work: () => Promise<number>, scheduler: CoverColorQueueScheduler) {
    this.work = work
    this.scheduler = scheduler
    this.queueTask = new CoverColorQueueTask(
      key,
      (): void => this.start(),
      (): void => this.cancel(),
    )
    this.completion = new Promise<number>((resolve: (color: number) => void): void => {
      this.resolveCompletion = resolve
    })
  }

  schedule(): Promise<number> {
    this.scheduler.schedule(this.queueTask)
    return this.completion
  }

  private start(): void {
    try {
      this.work().then(
        (color: number): void => {
          this.settle(color)
          this.scheduler.complete(this.queueTask)
        },
        (): void => {
          this.settle(0)
          this.scheduler.complete(this.queueTask)
        },
      )
    } catch (_error) {
      this.settle(0)
      this.scheduler.complete(this.queueTask)
    }
  }

  private cancel(): void {
    this.settle(0)
  }

  private settle(color: number): void {
    if (this.settled) {
      return
    }
    this.settled = true
    this.resolveCompletion(color)
  }
}

/**
 * In-memory cover dominant-color cache + in-flight dedup. EhThumbnail asks for a thumb URL's color and gets
 * a packed 0xAARRGGBB number once extraction resolves (0 while pending or on failure). Recent results are
 * retained across recycled rows, while a small global queue prevents decorative decodes from competing with
 * the actual thumbnail pipeline during a fast scroll.
 */
export class CoverColorService {
  private static instance: CoverColorService | null = null
  private cache: CoverColorMemoryCache = new CoverColorMemoryCache()
  private inFlight: Map<string, Promise<number>> = new Map()
  private readonly scheduler: CoverColorQueueScheduler = new CoverColorQueueScheduler()

  static getInstance(): CoverColorService {
    if (CoverColorService.instance === null) {
      CoverColorService.instance = new CoverColorService()
    }
    return CoverColorService.instance
  }

  // Synchronous cache peek so a recycled row can paint a known color immediately, with no flash or task.
  cached(url: string): number {
    const hit: number | undefined = this.cache.get(url)
    return hit === undefined ? 0 : hit
  }

  // Returns the cached color, joins an in-flight extraction, or starts one. Resolves to 0 on failure.
  resolve(url: string): Promise<number> {
    if (url.length === 0) {
      return Promise.resolve(0)
    }
    const hit: number | undefined = this.cache.get(url)
    if (hit !== undefined) {
      return Promise.resolve(hit)
    }
    const pending: Promise<number> | undefined = this.inFlight.get(url)
    if (pending !== undefined) {
      return pending
    }
    const task: CoverColorNetworkTask = new CoverColorNetworkTask(
      url,
      (): Promise<number> => this.extract(url),
      this.scheduler,
    )
    const completion: Promise<number> = task.schedule()
    this.inFlight.set(url, completion)
    completion.then((): void => {
      if (this.inFlight.get(url) === completion) {
        this.inFlight.delete(url)
      }
    })
    return completion
  }

  private async extract(url: string): Promise<number> {
    let color: number = 0
    try {
      color = await taskpool.execute<[string], number>(extractCoverColor, url)
    } catch (error) {
      color = 0
    }
    this.cache.put(url, color)
    return color
  }
}

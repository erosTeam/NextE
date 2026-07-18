import { common } from '@kit.AbilityKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  connectReadMode,
  READER_SUPER_RESOLUTION_MAX_SOURCE_HEIGHT,
  ReaderSuperResolutionBackend,
  ReaderSuperResolutionModel,
} from '../state/ReadModeState'
import { CacheStat } from './CacheStat'
import {
  ReaderNativeBackendPreference,
  ReaderNativeSuperResolution,
  ReaderNativeSuperResolutionCapabilities,
  ReaderNativeSuperResolutionConfig,
  ReaderNativeSuperResolutionResult,
} from './ReaderNativeSuperResolution'
import {
  ReaderSuperResolutionModelPaths,
  ReaderSuperResolutionModelService,
} from './ReaderSuperResolutionModelService'
import {
  ReaderSuperResolutionModelDefinition,
  ReaderSuperResolutionModelRegistry,
} from './ReaderSuperResolutionModelRegistry'

const CACHE_DIR_NAME: string = 'reader-super-resolution-cache'
const OUTPUT_SCALE: number = 2
// Keep the execution budget aligned with the largest height exposed by settings. For ordinary
// portrait reader images, every source at or below that height must be eligible for 2x processing.
const MAX_OUTPUT_EDGE: number = READER_SUPER_RESOLUTION_MAX_SOURCE_HEIGHT * OUTPUT_SCALE
const MAX_OUTPUT_PIXELS: number = MAX_OUTPUT_EDGE * MAX_OUTPUT_EDGE
const MAX_OUTPUT_PIXEL_BYTES: number = MAX_OUTPUT_PIXELS * 4
const MAX_CACHE_FILE_COUNT: number = 64
const MAX_CACHE_BYTES: number = 256 * 1024 * 1024
const HASH_CHUNK_BYTES: number = 256 * 1024
const SUPER_RESOLUTION_SUPERSEDED_ERROR: string = 'super-resolution request superseded'
const NATIVE_PIPELINE_VERSION: string = 'vulkan-gpu-prepost-tile128-fp16a-yield1-v7'

class ReaderSuperResolutionCacheEntry {
  path: string = ''
  bytes: number = 0
  mtime: number = 0

  constructor(path: string, bytes: number, mtime: number) {
    this.path = path
    this.bytes = bytes
    this.mtime = mtime
  }
}

export class ReaderSuperResolutionResult {
  filePath: string = ''
  displayUri: string = ''
  applied: boolean = false
  sourceWidth: number = 0
  sourceHeight: number = 0
  outputWidth: number = 0
  outputHeight: number = 0
  elapsedMs: number = 0
  backend: string = ''
  reason: string = ''
}

export enum ReaderSuperResolutionTaskState {
  QUEUED = 'queued',
  PROCESSING = 'processing',
}

export enum ReaderSuperResolutionTaskPriority {
  CURRENT = 0,
  PREFETCH = 1,
}

class ReaderSuperResolutionInFlightTask {
  promise: Promise<ReaderSuperResolutionResult> = Promise.resolve(new ReaderSuperResolutionResult())
  state: ReaderSuperResolutionTaskState = ReaderSuperResolutionTaskState.QUEUED
  requestId: number = 0
  priority: number = ReaderSuperResolutionTaskPriority.CURRENT
  enqueueOrder: number = 0
  sourcePath: string = ''
  owners: Set<string> = new Set<string>()
  observers: Array<(state: ReaderSuperResolutionTaskState) => void> = []
  uncancellable: boolean = false
  superseded: boolean = false
  startAction: () => Promise<ReaderSuperResolutionResult> =
    (): Promise<ReaderSuperResolutionResult> => Promise.resolve(new ReaderSuperResolutionResult())
  resolveTask: (result: ReaderSuperResolutionResult) => void =
    (_result: ReaderSuperResolutionResult): void => {}
  rejectTask: (error: Error) => void = (_error: Error): void => {}
}

export class ReaderSuperResolutionCapabilities {
  vulkanAvailable: boolean = false
  gpuName: string = ''
  ncnnVersion: string = ''
}

/**
 * On-device reader image enhancement. The original image remains the display fallback and only the
 * active/visible reader page asks this service to generate a 2x cached derivative.
 */
export class ReaderSuperResolutionService {
  private static inFlight: Map<string, ReaderSuperResolutionInFlightTask> = new Map<
    string,
    ReaderSuperResolutionInFlightTask
  >()
  private static ownerTasks: Map<string, ReaderSuperResolutionInFlightTask> = new Map<
    string,
    ReaderSuperResolutionInFlightTask
  >()
  private static requestSequence: number = 0
  private static enqueueSequence: number = 0
  private static pendingTasks: ReaderSuperResolutionInFlightTask[] = []
  private static activeTask: ReaderSuperResolutionInFlightTask | null = null
  private static pruneChain: Promise<void> = Promise.resolve()

  static capabilities(): ReaderSuperResolutionCapabilities {
    const native: ReaderNativeSuperResolutionCapabilities =
      ReaderNativeSuperResolution.capabilities()
    const result: ReaderSuperResolutionCapabilities = new ReaderSuperResolutionCapabilities()
    result.vulkanAvailable = native.vulkanAvailable
    result.gpuName = native.gpuName
    result.ncnnVersion = native.ncnnVersion
    return result
  }

  static async stat(context: common.UIAbilityContext): Promise<CacheStat> {
    const result: CacheStat = new CacheStat()
    const entries: ReaderSuperResolutionCacheEntry[] = ReaderSuperResolutionService.cacheEntries(context)
    result.count = entries.length
    for (let i: number = 0; i < entries.length; i++) {
      result.bytes += entries[i].bytes
    }
    return result
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    await ReaderSuperResolutionService.waitForIdle()
    const entries: ReaderSuperResolutionCacheEntry[] = ReaderSuperResolutionService.cacheEntries(context)
    for (let i: number = 0; i < entries.length; i++) {
      ReaderSuperResolutionService.removeIfExists(entries[i].path)
      ReaderSuperResolutionService.removeIfExists(
        ReaderSuperResolutionService.backendMetadataPath(entries[i].path),
      )
    }
  }

  static async process(
    context: common.UIAbilityContext,
    sourcePath: string,
    sourceKey: string,
    onTaskState: (state: ReaderSuperResolutionTaskState) => void = (_state: ReaderSuperResolutionTaskState) => {},
    ownerKey: string = '',
    priority: number = ReaderSuperResolutionTaskPriority.CURRENT,
  ): Promise<ReaderSuperResolutionResult> {
    if (!connectReadMode().superResolutionEnabled) {
      ReaderSuperResolutionService.releaseOwner(ownerKey)
      return ReaderSuperResolutionService.originalResult(sourcePath, 'disabled')
    }
    const model: string = connectReadMode().superResolutionModel
    if (model === ReaderSuperResolutionModel.NONE) {
      ReaderSuperResolutionService.releaseOwner(ownerKey)
      return ReaderSuperResolutionService.originalResult(sourcePath, 'model_not_selected')
    }
    if (ReaderSuperResolutionModelRegistry.find(model) === null) {
      ReaderSuperResolutionService.releaseOwner(ownerKey)
      return ReaderSuperResolutionService.originalResult(sourcePath, 'backend_unavailable')
    }
    const backendPreference: string = connectReadMode().superResolutionBackend

    const sourceStat: fileIo.Stat | null = ReaderSuperResolutionService.fileStat(sourcePath)
    if (sourceStat === null || sourceStat.size <= 0) {
      ReaderSuperResolutionService.releaseOwner(ownerKey)
      return ReaderSuperResolutionService.originalResult(sourcePath, 'source_missing')
    }
    const maxHeight: number = connectReadMode().superResolutionMaxHeight
    let sourceDigest: string = ''
    try {
      sourceDigest = ReaderSuperResolutionService.hashFile(sourcePath)
    } catch (error) {
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'source_hash_failed',
        `message=${(error as Error).message} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      ReaderSuperResolutionService.releaseOwner(ownerKey)
      return ReaderSuperResolutionService.originalResult(sourcePath, 'source_hash_failed')
    }
    const cacheIdentity: string =
      `${ReaderSuperResolutionService.pipelineVersion(model)}|${model}|${sourceKey}|` +
        `${sourceStat.size}|${sourceDigest}|maxHeight=${maxHeight}|backend=${backendPreference}`
    let outputPath: string = ''
    try {
      outputPath = ReaderSuperResolutionService.outputPath(context, cacheIdentity)
    } catch (error) {
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'cache_prepare_failed',
        `message=${(error as Error).message} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      ReaderSuperResolutionService.releaseOwner(ownerKey)
      return ReaderSuperResolutionService.originalResult(sourcePath, 'cache_unavailable')
    }
    const cachedBytes: number = ReaderSuperResolutionService.fileSize(outputPath)
    if (cachedBytes > 0) {
      ReaderSuperResolutionService.releaseOwner(ownerKey)
      ReaderSuperResolutionService.touch(outputPath)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'cache_hit',
        `bytes=${cachedBytes} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      const cachedResult: ReaderSuperResolutionResult = new ReaderSuperResolutionResult()
      cachedResult.filePath = outputPath
      cachedResult.displayUri = ReaderSuperResolutionService.displayUri(outputPath)
      cachedResult.applied = true
      cachedResult.backend = ReaderSuperResolutionService.readBackendMetadata(outputPath)
      cachedResult.reason = cachedResult.backend.length > 0
        ? `cache_hit:${cachedResult.backend}`
        : 'cache_hit'
      return cachedResult
    }

    const existing: ReaderSuperResolutionInFlightTask | undefined =
      ReaderSuperResolutionService.inFlight.get(outputPath)
    if (existing !== undefined) {
      ReaderSuperResolutionService.claimOwner(ownerKey, existing, onTaskState)
      ReaderSuperResolutionService.promote(existing, priority, sourceKey)
      onTaskState(existing.state)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'queue_join',
        `state=${existing.state} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      return await existing.promise
    }
    const inFlight: ReaderSuperResolutionInFlightTask = new ReaderSuperResolutionInFlightTask()
    ReaderSuperResolutionService.requestSequence += 1
    inFlight.requestId = ReaderSuperResolutionService.requestSequence
    ReaderSuperResolutionService.enqueueSequence += 1
    inFlight.enqueueOrder = ReaderSuperResolutionService.enqueueSequence
    inFlight.priority = priority
    inFlight.sourcePath = sourcePath
    ReaderSuperResolutionService.claimOwner(ownerKey, inFlight, onTaskState)
    const task: Promise<ReaderSuperResolutionResult> =
      new Promise<ReaderSuperResolutionResult>(
        (
          resolve: (result: ReaderSuperResolutionResult) => void,
          reject: (error: Error) => void,
        ): void => {
          inFlight.resolveTask = resolve
          inFlight.rejectTask = reject
        },
      )
    inFlight.promise = task
    inFlight.startAction = (): Promise<ReaderSuperResolutionResult> =>
      ReaderSuperResolutionService.processNow(
        context,
        sourcePath,
        sourceKey,
        outputPath,
        maxHeight,
        model,
        backendPreference,
        inFlight,
    )
    ReaderSuperResolutionService.inFlight.set(outputPath, inFlight)
    onTaskState(ReaderSuperResolutionTaskState.QUEUED)
    DiagnosticLogger.info(
      'reader-super-resolution',
      'queue_enqueue',
      `priority=${priority} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
    )
    ReaderSuperResolutionService.enqueue(inFlight, sourceKey)
    try {
      return await task
    } finally {
      ReaderSuperResolutionService.cleanupTask(outputPath, inFlight)
    }
  }

  static releaseOwner(ownerKey: string): void {
    if (ownerKey.length <= 0) {
      return
    }
    const task: ReaderSuperResolutionInFlightTask | undefined =
      ReaderSuperResolutionService.ownerTasks.get(ownerKey)
    if (task === undefined) {
      return
    }
    ReaderSuperResolutionService.ownerTasks.delete(ownerKey)
    task.owners.delete(ownerKey)
    if (task.owners.size <= 0) {
      ReaderNativeSuperResolution.setRequestActive(task.requestId, false)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'queue_release',
        `request=${task.requestId} state=${task.state}`,
      )
    }
  }

  static setInteractionPaused(paused: boolean): void {
    ReaderNativeSuperResolution.setInteractionPaused(paused)
  }

  private static claimOwner(
    ownerKey: string,
    task: ReaderSuperResolutionInFlightTask,
    observer: (state: ReaderSuperResolutionTaskState) => void,
  ): void {
    task.observers.push(observer)
    if (ownerKey.length <= 0) {
      task.uncancellable = true
      ReaderNativeSuperResolution.setRequestActive(task.requestId, true)
      return
    }
    const previous: ReaderSuperResolutionInFlightTask | undefined =
      ReaderSuperResolutionService.ownerTasks.get(ownerKey)
    if (previous !== undefined && previous !== task) {
      ReaderSuperResolutionService.releaseOwner(ownerKey)
    }
    task.owners.add(ownerKey)
    ReaderSuperResolutionService.ownerTasks.set(ownerKey, task)
    ReaderNativeSuperResolution.setRequestActive(task.requestId, true)
  }

  private static hasActiveOwner(task: ReaderSuperResolutionInFlightTask): boolean {
    return !task.superseded && (task.uncancellable || task.owners.size > 0)
  }

  private static ensureTaskActive(task: ReaderSuperResolutionInFlightTask): void {
    if (ReaderSuperResolutionService.hasActiveOwner(task)) {
      return
    }
    ReaderNativeSuperResolution.setRequestActive(task.requestId, false)
    throw new Error(SUPER_RESOLUTION_SUPERSEDED_ERROR)
  }

  private static notifyProcessing(task: ReaderSuperResolutionInFlightTask): void {
    task.state = ReaderSuperResolutionTaskState.PROCESSING
    for (let i: number = 0; i < task.observers.length; i++) {
      task.observers[i](ReaderSuperResolutionTaskState.PROCESSING)
    }
  }

  private static cleanupTask(
    outputPath: string,
    task: ReaderSuperResolutionInFlightTask,
  ): void {
    if (ReaderSuperResolutionService.inFlight.get(outputPath) === task) {
      ReaderSuperResolutionService.inFlight.delete(outputPath)
    }
    task.owners.forEach((ownerKey: string): void => {
      if (ReaderSuperResolutionService.ownerTasks.get(ownerKey) === task) {
        ReaderSuperResolutionService.ownerTasks.delete(ownerKey)
      }
    })
    task.owners.clear()
    ReaderNativeSuperResolution.setRequestActive(task.requestId, true)
  }

  private static enqueue(
    inFlight: ReaderSuperResolutionInFlightTask,
    sourceKey: string,
  ): void {
    ReaderSuperResolutionService.pendingTasks.push(inFlight)
    ReaderSuperResolutionService.sortPendingTasks()
    if (inFlight.priority === ReaderSuperResolutionTaskPriority.CURRENT) {
      ReaderSuperResolutionService.preemptActivePrefetch(sourceKey)
    }
    ReaderSuperResolutionService.drainQueue()
  }

  private static promote(
    task: ReaderSuperResolutionInFlightTask,
    priority: number,
    sourceKey: string,
  ): void {
    if (priority >= task.priority) {
      return
    }
    task.priority = priority
    ReaderSuperResolutionService.sortPendingTasks()
    if (priority === ReaderSuperResolutionTaskPriority.CURRENT) {
      ReaderSuperResolutionService.preemptActivePrefetch(sourceKey)
    }
    DiagnosticLogger.info(
      'reader-super-resolution',
      'queue_promote',
      `request=${task.requestId} priority=${priority} state=${task.state} ` +
        `keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
    )
  }

  private static sortPendingTasks(): void {
    ReaderSuperResolutionService.pendingTasks.sort(
      (
        left: ReaderSuperResolutionInFlightTask,
        right: ReaderSuperResolutionInFlightTask,
      ): number => {
        if (left.priority !== right.priority) {
          return left.priority - right.priority
        }
        return left.enqueueOrder - right.enqueueOrder
      },
    )
  }

  private static preemptActivePrefetch(sourceKey: string): void {
    const active: ReaderSuperResolutionInFlightTask | null =
      ReaderSuperResolutionService.activeTask
    if (active === null ||
      active.priority === ReaderSuperResolutionTaskPriority.CURRENT || active.superseded) {
      return
    }
    active.superseded = true
    ReaderNativeSuperResolution.setRequestActive(active.requestId, false)
    DiagnosticLogger.info(
      'reader-super-resolution',
      'queue_preempt',
      `request=${active.requestId} byKeyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
    )
  }

  private static drainQueue(): void {
    if (ReaderSuperResolutionService.activeTask !== null) {
      return
    }
    while (ReaderSuperResolutionService.pendingTasks.length > 0) {
      const next: ReaderSuperResolutionInFlightTask | undefined =
        ReaderSuperResolutionService.pendingTasks.shift()
      if (next === undefined) {
        return
      }
      if (!ReaderSuperResolutionService.hasActiveOwner(next)) {
        next.resolveTask(
          ReaderSuperResolutionService.originalResult(next.sourcePath, 'superseded'),
        )
        continue
      }
      ReaderSuperResolutionService.activeTask = next
      ReaderSuperResolutionService.notifyProcessing(next)
      next.startAction()
        .then((result: ReaderSuperResolutionResult): void => {
          next.resolveTask(result)
        })
        .catch((error: Error): void => {
          next.rejectTask(error)
        })
        .finally((): void => {
          if (ReaderSuperResolutionService.activeTask === next) {
            ReaderSuperResolutionService.activeTask = null
          }
          ReaderSuperResolutionService.drainQueue()
        })
      return
    }
  }

  private static async waitForIdle(): Promise<void> {
    while (ReaderSuperResolutionService.activeTask !== null ||
      ReaderSuperResolutionService.pendingTasks.length > 0) {
      await new Promise<void>((resolve: () => void): void => {
        setTimeout((): void => resolve(), 20)
      })
    }
  }

  private static async processNow(
    context: common.UIAbilityContext,
    sourcePath: string,
    sourceKey: string,
    outputPath: string,
    maxHeight: number,
    model: string,
    backendPreference: string,
    inFlight: ReaderSuperResolutionInFlightTask,
  ): Promise<ReaderSuperResolutionResult> {
    const startedAt: number = Date.now()
    let source: image.ImageSource | undefined = undefined
    let sourcePixelMap: image.PixelMap | undefined = undefined
    let outputPixelMap: image.PixelMap | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    let outputFile: fileIo.File | null = null
    let actualBackend: string = ''
    const tmpPath: string = `${outputPath}.part`
    let sourceWidth: number = 0
    let sourceHeight: number = 0
    try {
      ReaderSuperResolutionService.ensureTaskActive(inFlight)
      source = image.createImageSource(sourcePath)
      const sourceInfo: image.ImageInfo = await source.getImageInfo()
      ReaderSuperResolutionService.ensureTaskActive(inFlight)
      sourceWidth = sourceInfo.size.width
      sourceHeight = sourceInfo.size.height
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        return ReaderSuperResolutionService.skipResult(
          sourcePath,
          sourceWidth,
          sourceHeight,
          startedAt,
          'invalid_dimensions',
        )
      }
      if (sourceHeight > maxHeight) {
        return ReaderSuperResolutionService.skipResult(
          sourcePath,
          sourceWidth,
          sourceHeight,
          startedAt,
          'height_limit',
        )
      }
      const outputWidth: number = sourceWidth * OUTPUT_SCALE
      const outputHeight: number = sourceHeight * OUTPUT_SCALE
      const outputPixels: number = outputWidth * outputHeight
      if (outputWidth > MAX_OUTPUT_EDGE || outputHeight > MAX_OUTPUT_EDGE ||
        outputPixels > MAX_OUTPUT_PIXELS) {
        return ReaderSuperResolutionService.skipResult(
          sourcePath,
          sourceWidth,
          sourceHeight,
          startedAt,
          'device_size_limit',
        )
      }
      const outputPixelBytes: number = outputWidth * outputHeight * 4
      if (outputPixelBytes > MAX_OUTPUT_PIXEL_BYTES) {
        return ReaderSuperResolutionService.skipResult(
          sourcePath,
          sourceWidth,
          sourceHeight,
          startedAt,
          'memory_limit',
        )
      }

      DiagnosticLogger.info(
        'reader-super-resolution',
        'process_start',
        `model=${model} source=${sourceWidth}x${sourceHeight} output=${outputWidth}x${outputHeight} ` +
          `keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      const decodingOptions: image.DecodingOptions = {
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      }
      sourcePixelMap = await source.createPixelMap(decodingOptions)
      ReaderSuperResolutionService.ensureTaskActive(inFlight)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'source_decoded',
        `source=${sourceWidth}x${sourceHeight} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      const modelPaths: ReaderSuperResolutionModelPaths | null =
        await ReaderSuperResolutionModelService.pathsIfReady(context, model)
      ReaderSuperResolutionService.ensureTaskActive(inFlight)
      if (modelPaths === null) {
        return ReaderSuperResolutionService.skipResult(
          sourcePath,
          sourceWidth,
          sourceHeight,
          startedAt,
          'model_not_installed',
        )
      }
      const decodedInfo: image.ImageInfo = await sourcePixelMap.getImageInfo()
      const inputBuffer: ArrayBuffer = new ArrayBuffer(sourcePixelMap.getPixelBytesNumber())
      await sourcePixelMap.readPixelsToBuffer(inputBuffer)
      ReaderSuperResolutionService.ensureTaskActive(inFlight)
      const nativeResult: ReaderNativeSuperResolutionResult =
        await ReaderNativeSuperResolution.upscaleRgba(
          inputBuffer,
          sourceWidth,
          sourceHeight,
          Math.max(Math.floor(decodedInfo.stride), sourceWidth * 4),
          modelPaths.paramPath,
          modelPaths.modelPath,
          ReaderSuperResolutionService.nativeConfig(model, backendPreference),
          inFlight.requestId,
        )
      ReaderSuperResolutionService.ensureTaskActive(inFlight)
      actualBackend = nativeResult.backend
      const initializationOptions: image.InitializationOptions = {
        size: { width: outputWidth, height: outputHeight },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false,
      }
      outputPixelMap = await image.createPixelMap(nativeResult.pixels, initializationOptions)
      ReaderSuperResolutionService.ensureTaskActive(inFlight)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'model_inference_done',
        `model=${model} backend=${actualBackend} output=${outputWidth}x${outputHeight} ` +
          `modelLoadMs=${nativeResult.modelLoadMs} inferenceMs=${nativeResult.inferenceMs} ` +
          `keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )

      ReaderSuperResolutionService.removeIfExists(tmpPath)
      outputFile = fileIo.openSync(
        tmpPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      packer = image.createImagePacker()
      const packOptions: image.PackingOption = { format: 'image/jpeg', quality: 98 }
      await packer.packToFile(outputPixelMap, outputFile.fd, packOptions)
      ReaderSuperResolutionService.ensureTaskActive(inFlight)
      fileIo.closeSync(outputFile)
      outputFile = null
      ReaderSuperResolutionService.removeIfExists(outputPath)
      ReaderSuperResolutionService.removeIfExists(
        ReaderSuperResolutionService.backendMetadataPath(outputPath),
      )
      fileIo.renameSync(tmpPath, outputPath)
      ReaderSuperResolutionService.writeBackendMetadata(outputPath, actualBackend)
      const outputBytes: number = ReaderSuperResolutionService.fileSize(outputPath)
      if (outputBytes <= 0) {
        throw new Error('enhanced image file is empty')
      }
      ReaderSuperResolutionService.touch(outputPath)
      const elapsedMs: number = Date.now() - startedAt
      DiagnosticLogger.info(
        'reader-super-resolution',
        'process_success',
        `model=${model} source=${sourceWidth}x${sourceHeight} output=${outputWidth}x${outputHeight} ` +
          `backend=${actualBackend} bytes=${outputBytes} elapsedMs=${elapsedMs} ` +
            `keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      await ReaderSuperResolutionService.pruneToLimit(context, outputPath)
      const result: ReaderSuperResolutionResult = new ReaderSuperResolutionResult()
      result.filePath = outputPath
      result.displayUri = ReaderSuperResolutionService.displayUri(outputPath)
      result.applied = true
      result.sourceWidth = sourceWidth
      result.sourceHeight = sourceHeight
      result.outputWidth = outputWidth
      result.outputHeight = outputHeight
      result.elapsedMs = elapsedMs
      result.backend = actualBackend
      result.reason = `processed:${actualBackend}`
      return result
    } catch (error) {
      ReaderSuperResolutionService.removeIfExists(tmpPath)
      const message: string = (error as Error).message
      if (message === SUPER_RESOLUTION_SUPERSEDED_ERROR ||
        !ReaderSuperResolutionService.hasActiveOwner(inFlight)) {
        DiagnosticLogger.info(
          'reader-super-resolution',
          'process_superseded',
          `request=${inFlight.requestId} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
        )
        return ReaderSuperResolutionService.skipResult(
          sourcePath,
          sourceWidth,
          sourceHeight,
          startedAt,
          'superseded',
        )
      }
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'process_failed',
        `message=${message} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      return ReaderSuperResolutionService.originalResult(sourcePath, 'processing_failed')
    } finally {
      if (outputFile !== null) {
        try {
          fileIo.closeSync(outputFile)
        } catch (_error) {}
      }
      if (packer !== undefined) {
        await packer.release()
      }
      if (outputPixelMap !== undefined) {
        await outputPixelMap.release()
      }
      if (sourcePixelMap !== undefined) {
        await sourcePixelMap.release()
      }
      if (source !== undefined) {
        await source.release()
      }
    }
  }

  private static pipelineVersion(model: string): string {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(model)
    return definition === null
      ? 'unsupported'
      : `${definition.pipelineVersion}|runtime=${NATIVE_PIPELINE_VERSION}`
  }

  private static nativeConfig(
    model: string,
    backendPreference: string,
  ): ReaderNativeSuperResolutionConfig {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(model)
    const config: ReaderNativeSuperResolutionConfig = definition === null
      ? new ReaderNativeSuperResolutionConfig()
      : definition.nativeConfig()
    if (backendPreference === ReaderSuperResolutionBackend.VULKAN) {
      config.backendPreference = ReaderNativeBackendPreference.VULKAN
    } else if (backendPreference === ReaderSuperResolutionBackend.CPU) {
      config.backendPreference = ReaderNativeBackendPreference.CPU
    }
    return config
  }

  private static skipResult(
    sourcePath: string,
    width: number,
    height: number,
    startedAt: number,
    reason: string,
  ): ReaderSuperResolutionResult {
    const result: ReaderSuperResolutionResult = ReaderSuperResolutionService.originalResult(sourcePath, reason)
    result.sourceWidth = width
    result.sourceHeight = height
    result.elapsedMs = Date.now() - startedAt
    DiagnosticLogger.info(
      'reader-super-resolution',
      'process_skipped',
      `source=${width}x${height} reason=${reason}`,
    )
    return result
  }

  private static originalResult(sourcePath: string, reason: string): ReaderSuperResolutionResult {
    const result: ReaderSuperResolutionResult = new ReaderSuperResolutionResult()
    result.filePath = sourcePath
    result.displayUri = ReaderSuperResolutionService.displayUri(sourcePath)
    result.reason = reason
    return result
  }

  private static pruneToLimit(
    context: common.UIAbilityContext,
    protectedPath: string,
  ): Promise<void> {
    const task: Promise<void> = ReaderSuperResolutionService.pruneChain.then(
      (): Promise<void> => ReaderSuperResolutionService.pruneNow(context, protectedPath),
      (): Promise<void> => ReaderSuperResolutionService.pruneNow(context, protectedPath),
    )
    ReaderSuperResolutionService.pruneChain = task
    return task
  }

  private static async pruneNow(
    context: common.UIAbilityContext,
    protectedPath: string,
  ): Promise<void> {
    const entries: ReaderSuperResolutionCacheEntry[] = ReaderSuperResolutionService.cacheEntries(context)
    entries.sort(
      (left: ReaderSuperResolutionCacheEntry, right: ReaderSuperResolutionCacheEntry): number =>
        left.mtime - right.mtime,
    )
    let totalBytes: number = 0
    for (let i: number = 0; i < entries.length; i++) {
      totalBytes += entries[i].bytes
    }
    let remaining: number = entries.length
    for (let i: number = 0; i < entries.length; i++) {
      if ((totalBytes <= MAX_CACHE_BYTES && remaining <= MAX_CACHE_FILE_COUNT) || remaining <= 1) {
        break
      }
      if (entries[i].path === protectedPath) {
        continue
      }
      ReaderSuperResolutionService.removeIfExists(entries[i].path)
      ReaderSuperResolutionService.removeIfExists(
        ReaderSuperResolutionService.backendMetadataPath(entries[i].path),
      )
      totalBytes -= entries[i].bytes
      remaining--
    }
  }

  private static cacheEntries(context: common.UIAbilityContext): ReaderSuperResolutionCacheEntry[] {
    const entries: ReaderSuperResolutionCacheEntry[] = []
    const dir: string = ReaderSuperResolutionService.cacheDir(context)
    try {
      if (!fileIo.accessSync(dir)) {
        return entries
      }
      const names: string[] = fileIo.listFileSync(dir)
      for (let i: number = 0; i < names.length; i++) {
        const path: string = `${dir}/${names[i]}`
        if (names[i].endsWith('.part')) {
          ReaderSuperResolutionService.removeIfExists(path)
          continue
        }
        if (!names[i].endsWith('.jpg')) {
          continue
        }
        const stat: fileIo.Stat | null = ReaderSuperResolutionService.fileStat(path)
        if (stat !== null && stat.size > 0) {
          entries.push(new ReaderSuperResolutionCacheEntry(path, stat.size, stat.mtime))
        }
      }
    } catch (error) {
      DiagnosticLogger.warn('reader-super-resolution', 'cache_scan_failed', (error as Error).message)
    }
    return entries
  }

  private static outputPath(context: common.UIAbilityContext, identity: string): string {
    const dir: string = ReaderSuperResolutionService.cacheDir(context)
    ReaderSuperResolutionService.ensureDir(dir)
    return `${dir}/${ReaderSuperResolutionService.hashKey(identity)}.jpg`
  }

  private static cacheDir(context: common.UIAbilityContext): string {
    return `${context.cacheDir}/${CACHE_DIR_NAME}`
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

  private static fileStat(path: string): fileIo.Stat | null {
    try {
      return fileIo.statSync(path)
    } catch (_error) {
      return null
    }
  }

  private static fileSize(path: string): number {
    const stat: fileIo.Stat | null = ReaderSuperResolutionService.fileStat(path)
    return stat === null ? 0 : stat.size
  }

  private static touch(path: string): void {
    try {
      fileIo.utimes(path, Date.now())
    } catch (_error) {}
  }

  private static removeIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_error) {}
  }

  private static backendMetadataPath(outputPath: string): string {
    return `${outputPath}.backend`
  }

  private static writeBackendMetadata(outputPath: string, backend: string): void {
    if (backend !== 'vulkan' && backend !== 'cpu') {
      return
    }
    const path: string = ReaderSuperResolutionService.backendMetadataPath(outputPath)
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      fileIo.writeSync(file.fd, backend)
    } catch (error) {
      ReaderSuperResolutionService.removeIfExists(path)
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'cache_backend_write_failed',
        (error as Error).message,
      )
    } finally {
      if (file !== null) {
        try {
          fileIo.closeSync(file)
        } catch (_error) {}
      }
    }
  }

  private static readBackendMetadata(outputPath: string): string {
    try {
      const value: string = fileIo.readTextSync(
        ReaderSuperResolutionService.backendMetadataPath(outputPath),
      ).trim()
      return value === 'vulkan' || value === 'cpu' ? value : ''
    } catch (_error) {
      return ''
    }
  }

  private static displayUri(path: string): string {
    if (path.startsWith('file://')) {
      return path
    }
    if (path.startsWith('/')) {
      return `file://${path}`
    }
    return `file:///${path}`
  }

  private static hashKey(value: string): string {
    let hash: number = 5381
    for (let i: number = 0; i < value.length; i++) {
      hash = ((hash << 5) + hash + value.charCodeAt(i)) >>> 0
    }
    return hash.toString(16)
  }

  private static hashFile(path: string): string {
    const md = cryptoFramework.createMd('SHA256')
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      while (true) {
        const buffer: ArrayBuffer = new ArrayBuffer(HASH_CHUNK_BYTES)
        const read: number = fileIo.readSync(file.fd, buffer, { length: HASH_CHUNK_BYTES })
        if (read <= 0) {
          break
        }
        md.updateSync({ data: new Uint8Array(buffer, 0, read) })
      }
      return ReaderSuperResolutionService.toHex(md.digestSync().data)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static toHex(bytes: Uint8Array): string {
    const parts: string[] = []
    for (let i: number = 0; i < bytes.length; i++) {
      parts.push(bytes[i].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}

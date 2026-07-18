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

class ReaderSuperResolutionInFlightTask {
  promise: Promise<ReaderSuperResolutionResult> = Promise.resolve(new ReaderSuperResolutionResult())
  state: ReaderSuperResolutionTaskState = ReaderSuperResolutionTaskState.QUEUED
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
  private static processingChain: Promise<void> = Promise.resolve()
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
    await ReaderSuperResolutionService.processingChain
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
  ): Promise<ReaderSuperResolutionResult> {
    if (!connectReadMode().superResolutionEnabled) {
      return ReaderSuperResolutionService.originalResult(sourcePath, 'disabled')
    }
    const model: string = connectReadMode().superResolutionModel
    if (model === ReaderSuperResolutionModel.NONE) {
      return ReaderSuperResolutionService.originalResult(sourcePath, 'model_not_selected')
    }
    if (ReaderSuperResolutionModelRegistry.find(model) === null) {
      return ReaderSuperResolutionService.originalResult(sourcePath, 'backend_unavailable')
    }
    const backendPreference: string = connectReadMode().superResolutionBackend

    const sourceStat: fileIo.Stat | null = ReaderSuperResolutionService.fileStat(sourcePath)
    if (sourceStat === null || sourceStat.size <= 0) {
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
      return ReaderSuperResolutionService.originalResult(sourcePath, 'cache_unavailable')
    }
    const cachedBytes: number = ReaderSuperResolutionService.fileSize(outputPath)
    if (cachedBytes > 0) {
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
      onTaskState(existing.state)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'queue_join',
        `state=${existing.state} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      return await existing.promise
    }
    const inFlight: ReaderSuperResolutionInFlightTask = new ReaderSuperResolutionInFlightTask()
    const task: Promise<ReaderSuperResolutionResult> = ReaderSuperResolutionService.enqueue(
      context,
      sourcePath,
      sourceKey,
      outputPath,
      maxHeight,
      model,
      backendPreference,
      (): void => {
        inFlight.state = ReaderSuperResolutionTaskState.PROCESSING
        onTaskState(ReaderSuperResolutionTaskState.PROCESSING)
      },
    )
    inFlight.promise = task
    ReaderSuperResolutionService.inFlight.set(outputPath, inFlight)
    onTaskState(ReaderSuperResolutionTaskState.QUEUED)
    DiagnosticLogger.info(
      'reader-super-resolution',
      'queue_enqueue',
      `keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
    )
    try {
      return await task
    } finally {
      if (ReaderSuperResolutionService.inFlight.get(outputPath) === inFlight) {
        ReaderSuperResolutionService.inFlight.delete(outputPath)
      }
    }
  }

  private static enqueue(
    context: common.UIAbilityContext,
    sourcePath: string,
    sourceKey: string,
    outputPath: string,
    maxHeight: number,
    model: string,
    backendPreference: string,
    onProcessStart: () => void,
  ): Promise<ReaderSuperResolutionResult> {
    const task: Promise<ReaderSuperResolutionResult> = ReaderSuperResolutionService.processingChain.then(
      (): Promise<ReaderSuperResolutionResult> => {
        onProcessStart()
        return ReaderSuperResolutionService.processNow(
          context,
          sourcePath,
          sourceKey,
          outputPath,
          maxHeight,
          model,
          backendPreference,
        )
      },
      (): Promise<ReaderSuperResolutionResult> => {
        onProcessStart()
        return ReaderSuperResolutionService.processNow(
          context,
          sourcePath,
          sourceKey,
          outputPath,
          maxHeight,
          model,
          backendPreference,
        )
      },
    )
    ReaderSuperResolutionService.processingChain = task.then(
      (): void => {},
      (): void => {},
    )
    return task
  }

  private static async processNow(
    context: common.UIAbilityContext,
    sourcePath: string,
    sourceKey: string,
    outputPath: string,
    maxHeight: number,
    model: string,
    backendPreference: string,
  ): Promise<ReaderSuperResolutionResult> {
    const startedAt: number = Date.now()
    let source: image.ImageSource | undefined = undefined
    let sourcePixelMap: image.PixelMap | undefined = undefined
    let outputPixelMap: image.PixelMap | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    let outputFile: fileIo.File | null = null
    let actualBackend: string = ''
    const tmpPath: string = `${outputPath}.part`
    try {
      source = image.createImageSource(sourcePath)
      const sourceInfo: image.ImageInfo = await source.getImageInfo()
      const sourceWidth: number = sourceInfo.size.width
      const sourceHeight: number = sourceInfo.size.height
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
      DiagnosticLogger.info(
        'reader-super-resolution',
        'source_decoded',
        `source=${sourceWidth}x${sourceHeight} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
      )
      const modelPaths: ReaderSuperResolutionModelPaths | null =
        await ReaderSuperResolutionModelService.pathsIfReady(context, model)
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
      const nativeResult: ReaderNativeSuperResolutionResult =
        await ReaderNativeSuperResolution.upscaleRgba(
          inputBuffer,
          sourceWidth,
          sourceHeight,
          Math.max(Math.floor(decodedInfo.stride), sourceWidth * 4),
          modelPaths.paramPath,
          modelPaths.modelPath,
          ReaderSuperResolutionService.nativeConfig(model, backendPreference),
        )
      actualBackend = nativeResult.backend
      const initializationOptions: image.InitializationOptions = {
        size: { width: outputWidth, height: outputHeight },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false,
      }
      outputPixelMap = await image.createPixelMap(nativeResult.pixels, initializationOptions)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'model_inference_done',
        `model=${model} backend=${actualBackend} output=${outputWidth}x${outputHeight} ` +
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
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'process_failed',
        `message=${(error as Error).message} keyHash=${DiagnosticLogger.ownerHash(sourceKey)}`,
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
    return definition === null ? 'unsupported' : definition.pipelineVersion
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

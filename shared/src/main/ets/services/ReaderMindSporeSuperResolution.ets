import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS'
import { mindSporeLite } from '@kit.MindSporeLiteKit'
import { ReaderNativeSuperResolution } from './ReaderNativeSuperResolution'

const SCALE: number = 2
const TILE_SIZE: number = 160
const BACKEND_NAME: string = 'nnrt'

interface ReaderMindSporeWorkerRequest {
  kind: string
  requestId: number
  modelPath: string
  tensor: ArrayBuffer
}

interface ReaderMindSporeWorkerResponse {
  kind: string
  requestId: number
  tensor: ArrayBuffer
  modelLoadMs: number
  inferenceMs: number
  message: string
}

class ReaderMindSporePendingRequest {
  resolve: (response: ReaderMindSporeWorkerResponse) => void
  reject: (error: Error) => void

  constructor(
    resolve: (response: ReaderMindSporeWorkerResponse) => void,
    reject: (error: Error) => void,
  ) {
    this.resolve = resolve
    this.reject = reject
  }
}

export interface ReaderMindSporeSuperResolutionWorkerFactory {
  create(): worker.ThreadWorker
}

class ReaderMindSporeWorkerClient {
  private static instance: worker.ThreadWorker | null = null
  private static factory: ReaderMindSporeSuperResolutionWorkerFactory | null = null
  private static nextRequestId: number = 1
  private static pending: Map<number, ReaderMindSporePendingRequest> = new Map()

  static configure(factory: ReaderMindSporeSuperResolutionWorkerFactory): void {
    ReaderMindSporeWorkerClient.factory = factory
  }

  static async prepare(modelPath: string): Promise<ReaderMindSporeWorkerResponse> {
    return await ReaderMindSporeWorkerClient.request('prepare', modelPath, new ArrayBuffer(0))
  }

  static async predict(
    modelPath: string,
    tensor: ArrayBuffer,
  ): Promise<ReaderMindSporeWorkerResponse> {
    return await ReaderMindSporeWorkerClient.request('predict', modelPath, tensor, true)
  }

  private static request(
    kind: string,
    modelPath: string,
    tensor: ArrayBuffer,
    transferTensor: boolean = false,
  ): Promise<ReaderMindSporeWorkerResponse> {
    const requestId: number = ReaderMindSporeWorkerClient.nextRequestId++
    const request: ReaderMindSporeWorkerRequest = {
      kind: kind,
      requestId: requestId,
      modelPath: modelPath,
      tensor: tensor,
    }
    return new Promise<ReaderMindSporeWorkerResponse>(
      (
        resolve: (response: ReaderMindSporeWorkerResponse) => void,
        reject: (error: Error) => void,
      ): void => {
        ReaderMindSporeWorkerClient.pending.set(
          requestId,
          new ReaderMindSporePendingRequest(resolve, reject),
        )
        try {
          const instance: worker.ThreadWorker = ReaderMindSporeWorkerClient.ensureWorker()
          if (transferTensor) {
            instance.postMessage(request, [tensor])
          } else {
            instance.postMessage(request)
          }
        } catch (error) {
          ReaderMindSporeWorkerClient.pending.delete(requestId)
          reject(error as Error)
        }
      },
    )
  }

  private static ensureWorker(): worker.ThreadWorker {
    if (ReaderMindSporeWorkerClient.instance !== null) {
      return ReaderMindSporeWorkerClient.instance
    }
    const factory: ReaderMindSporeSuperResolutionWorkerFactory | null =
      ReaderMindSporeWorkerClient.factory
    if (factory === null) {
      throw new Error('NNRT worker factory is not configured')
    }
    const instance: worker.ThreadWorker = factory.create()
    instance.onmessage = (event: MessageEvents): void => {
      const response: ReaderMindSporeWorkerResponse =
        event.data as ReaderMindSporeWorkerResponse
      const pending: ReaderMindSporePendingRequest | undefined =
        ReaderMindSporeWorkerClient.pending.get(response.requestId)
      if (pending === undefined) {
        return
      }
      ReaderMindSporeWorkerClient.pending.delete(response.requestId)
      if (response.kind === 'failure') {
        pending.reject(new Error(response.message))
        return
      }
      pending.resolve(response)
    }
    instance.onerror = (error: ErrorEvent): void => {
      ReaderMindSporeWorkerClient.reset(new Error(error.message))
    }
    instance.onexit = (code: number): void => {
      if (code !== 0) {
        ReaderMindSporeWorkerClient.reset(
          new Error('NNRT worker exited with code ' + code),
        )
      } else {
        ReaderMindSporeWorkerClient.instance = null
      }
    }
    ReaderMindSporeWorkerClient.instance = instance
    return instance
  }

  private static reset(error: Error): void {
    const instance: worker.ThreadWorker | null = ReaderMindSporeWorkerClient.instance
    ReaderMindSporeWorkerClient.instance = null
    if (instance !== null) {
      instance.terminate()
    }
    ReaderMindSporeWorkerClient.pending.forEach(
      (pending: ReaderMindSporePendingRequest): void => pending.reject(error),
    )
    ReaderMindSporeWorkerClient.pending.clear()
  }
}

export class ReaderMindSporeSuperResolutionPrepareResult {
  backend: string = BACKEND_NAME
  modelLoadMs: number = 0
}

export class ReaderMindSporeSuperResolutionResult {
  pixels: ArrayBuffer = new ArrayBuffer(0)
  backend: string = BACKEND_NAME
  modelLoadMs: number = 0
  inferenceMs: number = 0
  tileCount: number = 0
}

class ReaderMindSporeAccelerator {
  deviceID: bigint
  deviceName: string

  constructor(deviceID: bigint, deviceName: string) {
    this.deviceID = deviceID
    this.deviceName = deviceName
  }
}

/**
 * Fixed-shape Real-ESRGAN x2plus runner for HarmonyOS NNRT accelerators.
 *
 * Model prediction lives on a persistent low-priority Worker because MindSpore's Promise-based predict API still
 * occupies the calling ArkTS event loop while the NPU is running. Native preprocessing and stitching stay as short
 * per-tile operations on the caller and yield before the next tile.
 */
export class ReaderMindSporeSuperResolution {
  private static acceleratorResolved: boolean = false
  private static cachedAccelerator: ReaderMindSporeAccelerator | null = null

  static acceleratorAvailable(): boolean {
    return ReaderMindSporeSuperResolution.acceleratorDevice() !== null
  }

  static configureWorkerFactory(
    factory: ReaderMindSporeSuperResolutionWorkerFactory,
  ): void {
    ReaderMindSporeWorkerClient.configure(factory)
  }

  static async prepareModel(
    modelPath: string,
  ): Promise<ReaderMindSporeSuperResolutionPrepareResult> {
    const response: ReaderMindSporeWorkerResponse =
      await ReaderMindSporeWorkerClient.prepare(modelPath)
    const result: ReaderMindSporeSuperResolutionPrepareResult =
      new ReaderMindSporeSuperResolutionPrepareResult()
    result.modelLoadMs = response.modelLoadMs
    return result
  }

  static async upscaleRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    modelPath: string,
    waitUntilAllowed: () => Promise<void>,
  ): Promise<ReaderMindSporeSuperResolutionResult> {
    if (width <= 0 || height <= 0 || stride < width * 4 ||
      pixels.byteLength < stride * height) {
      throw new Error('invalid NNRT super-resolution image buffer')
    }
    const outputWidth: number = width * SCALE
    const outputHeight: number = height * SCALE
    const outputBuffer: ArrayBuffer = new ArrayBuffer(outputWidth * outputHeight * 4)
    const xTiles: number = Math.ceil(width / TILE_SIZE)
    const yTiles: number = Math.ceil(height / TILE_SIZE)
    let modelLoadMs: number = 0
    let inferenceMs: number = 0
    let tileCount: number = 0

    for (let tileY: number = 0; tileY < yTiles; tileY++) {
      const inputY: number = tileY * TILE_SIZE
      const tileHeight: number = Math.min(TILE_SIZE, height - inputY)
      for (let tileX: number = 0; tileX < xTiles; tileX++) {
        await waitUntilAllowed()
        const inputX: number = tileX * TILE_SIZE
        const tileWidth: number = Math.min(TILE_SIZE, width - inputX)
        const inputTile: ArrayBuffer = ReaderNativeSuperResolution.prepareNnrtTileRgba(
          pixels,
          width,
          height,
          stride,
          inputX,
          inputY,
        )
        const response: ReaderMindSporeWorkerResponse =
          await ReaderMindSporeWorkerClient.predict(modelPath, inputTile)
        ReaderNativeSuperResolution.writeNnrtTileRgba(
          outputBuffer,
          outputWidth,
          outputHeight,
          response.tensor,
          inputX,
          inputY,
          tileWidth,
          tileHeight,
        )
        modelLoadMs += response.modelLoadMs
        inferenceMs += response.inferenceMs
        tileCount += 1
        await ReaderMindSporeSuperResolution.yieldToUi()
      }
    }
    const result: ReaderMindSporeSuperResolutionResult =
      new ReaderMindSporeSuperResolutionResult()
    result.pixels = outputBuffer
    result.modelLoadMs = modelLoadMs
    result.inferenceMs = inferenceMs
    result.tileCount = tileCount
    return result
  }

  private static acceleratorDevice(): ReaderMindSporeAccelerator | null {
    if (ReaderMindSporeSuperResolution.acceleratorResolved) {
      return ReaderMindSporeSuperResolution.cachedAccelerator
    }
    const devices: mindSporeLite.NNRTDeviceDescription[] =
      mindSporeLite.getAllNNRTDeviceDescriptions()
    let fallback: ReaderMindSporeAccelerator | null = null
    for (let index: number = 0; index < devices.length; index++) {
      const device: mindSporeLite.NNRTDeviceDescription = devices[index]
      if (device.deviceType() !== mindSporeLite.NNRTDeviceType.NNRTDEVICE_ACCELERATOR) {
        continue
      }
      const accelerator: ReaderMindSporeAccelerator = new ReaderMindSporeAccelerator(
        device.deviceID(),
        device.deviceName(),
      )
      if (fallback === null) {
        fallback = accelerator
      }
      if (accelerator.deviceName.startsWith('NPU_')) {
        ReaderMindSporeSuperResolution.acceleratorResolved = true
        ReaderMindSporeSuperResolution.cachedAccelerator = accelerator
        return accelerator
      }
    }
    ReaderMindSporeSuperResolution.acceleratorResolved = true
    ReaderMindSporeSuperResolution.cachedAccelerator = fallback
    return fallback
  }

  private static yieldToUi(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0)
    })
  }
}

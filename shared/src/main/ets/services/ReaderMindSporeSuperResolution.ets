import { mindSporeLite } from '@kit.MindSporeLiteKit'
import { ReaderNativeSuperResolution } from './ReaderNativeSuperResolution'

const BACKEND_NAME: string = 'nnrt'

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
 * Model loading, tile prediction, preprocessing, and stitching run in one native background task. This keeps the
 * ArkTS event loop responsive while preserving per-request cancellation and interaction-pause checks.
 */
export class ReaderMindSporeSuperResolution {
  private static acceleratorResolved: boolean = false
  private static cachedAccelerator: ReaderMindSporeAccelerator | null = null

  static acceleratorAvailable(): boolean {
    return ReaderMindSporeSuperResolution.acceleratorDevice() !== null
  }

  static async prepareModel(
    modelPath: string,
  ): Promise<ReaderMindSporeSuperResolutionPrepareResult> {
    const native = await ReaderNativeSuperResolution.prepareMindSporeModel(modelPath)
    const result: ReaderMindSporeSuperResolutionPrepareResult =
      new ReaderMindSporeSuperResolutionPrepareResult()
    result.backend = native.backend
    result.modelLoadMs = native.modelLoadMs
    return result
  }

  static async upscaleRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    modelPath: string,
    requestId: number,
  ): Promise<ReaderMindSporeSuperResolutionResult> {
    if (width <= 0 || height <= 0 || stride < width * 4 ||
      pixels.byteLength < stride * height) {
      throw new Error('invalid NNRT super-resolution image buffer')
    }
    const native = await ReaderNativeSuperResolution.upscaleMindSporeRgba(
      pixels,
      width,
      height,
      stride,
      modelPath,
      requestId,
    )
    const result: ReaderMindSporeSuperResolutionResult =
      new ReaderMindSporeSuperResolutionResult()
    result.pixels = native.pixels
    result.backend = native.backend
    result.modelLoadMs = native.modelLoadMs
    result.inferenceMs = native.inferenceMs
    result.tileCount = native.tileCount
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
}

import nativeSuperResolution from 'libnexte_super_resolution.so'

interface NativeSuperResolutionModule {
  prepareModel(
    paramPath: string,
    modelPath: string,
    modelKind: number,
    backendPreference: number,
    tileSize: number,
    prepadding: number,
    threads: number,
    inputName: string,
    outputName: string,
  ): Promise<NativeSuperResolutionPrepareResult>

  upscaleRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    modelKind: number,
    backendPreference: number,
    tileSize: number,
    prepadding: number,
    threads: number,
    inputName: string,
    outputName: string,
    requestId: number,
  ): Promise<NativeSuperResolutionResult>

  prepareNnrtTileRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    inputX: number,
    inputY: number,
  ): ArrayBuffer

  writeNnrtTileRgba(
    pixels: ArrayBuffer,
    outputWidth: number,
    outputHeight: number,
    tensor: ArrayBuffer,
    inputX: number,
    inputY: number,
    tileWidth: number,
    tileHeight: number,
  ): void

  setRequestActive(requestId: number, active: boolean): void

  setInteractionPaused(paused: boolean): void

  getCapabilities(): NativeSuperResolutionCapabilities
}

interface NativeSuperResolutionPrepareResult {
  backend: string
  modelLoadMs: number
}

interface NativeSuperResolutionResult {
  pixels: ArrayBuffer
  backend: string
  modelLoadMs: number
  inferenceMs: number
}

interface NativeSuperResolutionCapabilities {
  vulkanAvailable: boolean
  gpuCount: number
  gpuName: string
  ncnnVersion: string
}

export enum ReaderNativeModelKind {
  WAIFU2X = 0,
  REAL_ESRGAN = 1,
  LUMINANCE = 2,
}

export enum ReaderNativeBackendPreference {
  AUTO = 0,
  VULKAN = 1,
  CPU = 2,
}

export class ReaderNativeSuperResolutionConfig {
  modelKind: number = ReaderNativeModelKind.WAIFU2X
  backendPreference: number = ReaderNativeBackendPreference.AUTO
  tileSize: number = 142
  prepadding: number = 7
  threads: number = 2
  inputName: string = 'Input1'
  outputName: string = 'Eltwise4'
}

export class ReaderNativeSuperResolutionResult {
  pixels: ArrayBuffer = new ArrayBuffer(0)
  backend: string = ''
  modelLoadMs: number = 0
  inferenceMs: number = 0
}

export class ReaderNativeSuperResolutionPrepareResult {
  backend: string = ''
  modelLoadMs: number = 0
}

export class ReaderNativeSuperResolutionCapabilities {
  vulkanAvailable: boolean = false
  gpuCount: number = 0
  gpuName: string = ''
  ncnnVersion: string = ''
}

const nativeRuntime: NativeSuperResolutionModule =
  nativeSuperResolution as NativeSuperResolutionModule

/** Typed ArkTS boundary for the asynchronous ncnn NAPI worker. */
export class ReaderNativeSuperResolution {
  static capabilities(): ReaderNativeSuperResolutionCapabilities {
    const native: NativeSuperResolutionCapabilities = nativeRuntime.getCapabilities()
    const result: ReaderNativeSuperResolutionCapabilities =
      new ReaderNativeSuperResolutionCapabilities()
    result.vulkanAvailable = native.vulkanAvailable
    result.gpuCount = native.gpuCount
    result.gpuName = native.gpuName
    result.ncnnVersion = native.ncnnVersion
    return result
  }

  static async prepareModel(
    paramPath: string,
    modelPath: string,
    config: ReaderNativeSuperResolutionConfig,
  ): Promise<ReaderNativeSuperResolutionPrepareResult> {
    const native: NativeSuperResolutionPrepareResult = await nativeRuntime.prepareModel(
      paramPath,
      modelPath,
      config.modelKind,
      config.backendPreference,
      config.tileSize,
      config.prepadding,
      config.threads,
      config.inputName,
      config.outputName,
    )
    const result: ReaderNativeSuperResolutionPrepareResult =
      new ReaderNativeSuperResolutionPrepareResult()
    result.backend = native.backend
    result.modelLoadMs = native.modelLoadMs
    return result
  }

  static async upscaleRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    config: ReaderNativeSuperResolutionConfig,
    requestId: number,
  ): Promise<ReaderNativeSuperResolutionResult> {
    const native: NativeSuperResolutionResult = await nativeRuntime.upscaleRgba(
      pixels,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      config.modelKind,
      config.backendPreference,
      config.tileSize,
      config.prepadding,
      config.threads,
      config.inputName,
      config.outputName,
      requestId,
    )
    const result: ReaderNativeSuperResolutionResult = new ReaderNativeSuperResolutionResult()
    result.pixels = native.pixels
    result.backend = native.backend
    result.modelLoadMs = native.modelLoadMs
    result.inferenceMs = native.inferenceMs
    return result
  }

  static prepareNnrtTileRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    inputX: number,
    inputY: number,
  ): ArrayBuffer {
    return nativeRuntime.prepareNnrtTileRgba(
      pixels,
      width,
      height,
      stride,
      inputX,
      inputY,
    )
  }

  static writeNnrtTileRgba(
    pixels: ArrayBuffer,
    outputWidth: number,
    outputHeight: number,
    tensor: ArrayBuffer,
    inputX: number,
    inputY: number,
    tileWidth: number,
    tileHeight: number,
  ): void {
    nativeRuntime.writeNnrtTileRgba(
      pixels,
      outputWidth,
      outputHeight,
      tensor,
      inputX,
      inputY,
      tileWidth,
      tileHeight,
    )
  }

  static setRequestActive(requestId: number, active: boolean): void {
    if (requestId <= 0) {
      return
    }
    nativeRuntime.setRequestActive(requestId, active)
  }

  static setInteractionPaused(paused: boolean): void {
    nativeRuntime.setInteractionPaused(paused)
  }
}

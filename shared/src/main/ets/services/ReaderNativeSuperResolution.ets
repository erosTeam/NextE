import nativeSuperResolution from 'libnexte_super_resolution.so'

interface NativeSuperResolutionModule {
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
  ): Promise<NativeSuperResolutionResult>

  getCapabilities(): NativeSuperResolutionCapabilities
}

interface NativeSuperResolutionResult {
  pixels: ArrayBuffer
  backend: string
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

  static async upscaleRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    config: ReaderNativeSuperResolutionConfig,
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
    )
    const result: ReaderNativeSuperResolutionResult = new ReaderNativeSuperResolutionResult()
    result.pixels = native.pixels
    result.backend = native.backend
    return result
  }
}

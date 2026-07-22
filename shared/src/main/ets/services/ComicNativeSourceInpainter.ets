import nativeVision from 'libnexte_super_resolution.so'

interface NativeComicInpaintingResult {
  pixels: ArrayBuffer
  backend: string
  modelLoadMs: number
  inferenceMs: number
  inferenceWidth: number
  inferenceHeight: number
}

interface NativeComicInpainterModule {
  inpaintComicRegion(
    pixels: ArrayBuffer,
    mask: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    threads: number,
    inputBgra: boolean,
  ): Promise<NativeComicInpaintingResult>
}

export class ComicNativeInpaintingResult {
  pixels: ArrayBuffer = new ArrayBuffer(0)
  backend: string = ''
  modelLoadMs: number = 0
  inferenceMs: number = 0
  inferenceWidth: number = 0
  inferenceHeight: number = 0
}

export interface ComicLocalSourceInpainter {
  profileId(): string
  revision(): number
  inpaint(
    pixels: ArrayBuffer,
    mask: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
  ): Promise<ComicNativeInpaintingResult>
}

const nativeRuntime: NativeComicInpainterModule = nativeVision as NativeComicInpainterModule

/** Typed ArkTS boundary for bounded local AOT manga background repair. */
export class ComicNativeSourceInpainter {
  private static async inpaint(
    pixels: ArrayBuffer,
    mask: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    threads: number,
    inputBgra: boolean,
  ): Promise<ComicNativeInpaintingResult> {
    if (width <= 1 || height <= 1 || width > 1024 || height > 1024 ||
      stride < width * 4 || pixels.byteLength < stride * height ||
      mask.byteLength < width * height) {
      throw new Error('invalid native comic inpainter input')
    }
    if (paramPath.trim().length <= 0 || modelPath.trim().length <= 0 ||
      threads < 1 || threads > 8) {
      throw new Error('invalid native comic inpainter configuration')
    }
    const native: NativeComicInpaintingResult = await nativeRuntime.inpaintComicRegion(
      pixels,
      mask,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      threads,
      inputBgra,
    )
    if (native.pixels.byteLength !== stride * height || native.backend.length <= 0 ||
      native.modelLoadMs < 0 || native.inferenceMs < 0 ||
      native.inferenceWidth < 0 || native.inferenceWidth > 256 ||
      native.inferenceHeight < 0 || native.inferenceHeight > 256) {
      throw new Error('invalid native comic inpainter result')
    }
    const result: ComicNativeInpaintingResult = new ComicNativeInpaintingResult()
    result.pixels = native.pixels
    result.backend = native.backend
    result.modelLoadMs = native.modelLoadMs
    result.inferenceMs = native.inferenceMs
    result.inferenceWidth = native.inferenceWidth
    result.inferenceHeight = native.inferenceHeight
    return result
  }

  static async inpaintRgba(
    pixels: ArrayBuffer,
    mask: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    threads: number = 2,
  ): Promise<ComicNativeInpaintingResult> {
    return ComicNativeSourceInpainter.inpaint(
      pixels,
      mask,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      threads,
      false,
    )
  }

  static async inpaintBgra(
    pixels: ArrayBuffer,
    mask: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    threads: number = 2,
  ): Promise<ComicNativeInpaintingResult> {
    return ComicNativeSourceInpainter.inpaint(
      pixels,
      mask,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      threads,
      true,
    )
  }
}

/** File-backed optional source inpainter; model installation remains outside the HAP. */
export class ComicNcnnLocalSourceInpainter implements ComicLocalSourceInpainter {
  private readonly paramPath: string
  private readonly modelPath: string
  private readonly threads: number

  constructor(paramPath: string, modelPath: string, threads: number = 2) {
    this.paramPath = paramPath
    this.modelPath = modelPath
    this.threads = threads
  }

  profileId(): string {
    return 'aot-manga-256-ncnn-fp32-v4'
  }

  revision(): number {
    return 4
  }

  async inpaint(
    pixels: ArrayBuffer,
    mask: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
  ): Promise<ComicNativeInpaintingResult> {
    // PixelMap.readPixels exposes BGRA_8888 bytes on HarmonyOS.
    return ComicNativeSourceInpainter.inpaintBgra(
      pixels,
      mask,
      width,
      height,
      stride,
      this.paramPath,
      this.modelPath,
      this.threads,
    )
  }
}

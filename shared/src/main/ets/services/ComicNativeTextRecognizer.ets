import nativeVision from 'libnexte_super_resolution.so'
import { image } from '@kit.ImageKit'

const COMIC_NATIVE_MAX_TEXT_CHARS: number = 512

interface NativeComicTextRecognitionResult {
  text: string
  score: number
  backend: string
  modelLoadMs: number
  preprocessingMs: number
  inferenceMs: number
  decodingMs: number
}

interface NativeComicTextRecognizerModule {
  recognizeComicText(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    dictionaryPath: string,
    rotateCounterClockwise: boolean,
    threads: number,
  ): Promise<NativeComicTextRecognitionResult>
}

export class ComicNativeTextRecognitionResult {
  text: string = ''
  score: number = 0
  backend: string = ''
  modelLoadMs: number = 0
  preprocessingMs: number = 0
  inferenceMs: number = 0
  decodingMs: number = 0
  pixelMapReadMs: number = 0
  nativeCallMs: number = 0
  regionCropReadMs: number = 0
  regionPixelMapCreateMs: number = 0
  regionPixelMapReleaseMs: number = 0
}

export interface ComicLocalTextRecognizer {
  profileId(): string
  revision(): number
  recognize(
    pixelMap: image.PixelMap,
    rotateCounterClockwise: boolean,
  ): Promise<ComicNativeTextRecognitionResult>
}

const nativeRuntime: NativeComicTextRecognizerModule =
  nativeVision as NativeComicTextRecognizerModule

/** Typed ArkTS boundary for the optional PP-OCRv5 ncnn line recognizer. */
export class ComicNativeTextRecognizer {
  static async recognizeRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    dictionaryPath: string,
    rotateCounterClockwise: boolean = false,
    threads: number = 2,
  ): Promise<ComicNativeTextRecognitionResult> {
    if (width <= 0 || height <= 0 || stride < width * 4 ||
      pixels.byteLength < stride * height) {
      throw new Error('invalid native comic text recognizer RGBA input')
    }
    if (paramPath.trim().length <= 0 || modelPath.trim().length <= 0 ||
      dictionaryPath.trim().length <= 0 || threads < 1 || threads > 8) {
      throw new Error('invalid native comic text recognizer configuration')
    }
    const native: NativeComicTextRecognitionResult = await nativeRuntime.recognizeComicText(
      pixels,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      dictionaryPath,
      rotateCounterClockwise,
      threads,
    )
    if (native.text.length > COMIC_NATIVE_MAX_TEXT_CHARS ||
      !Number.isFinite(native.score) || native.score < 0 || native.score > 1 ||
      native.backend.length <= 0 || native.modelLoadMs < 0 || native.preprocessingMs < 0 ||
      native.inferenceMs < 0 || native.decodingMs < 0) {
      throw new Error('invalid native comic text recognizer result')
    }
    const result: ComicNativeTextRecognitionResult = new ComicNativeTextRecognitionResult()
    result.text = native.text
    result.score = native.score
    result.backend = native.backend
    result.modelLoadMs = native.modelLoadMs
    result.preprocessingMs = native.preprocessingMs
    result.inferenceMs = native.inferenceMs
    result.decodingMs = native.decodingMs
    return result
  }
}

/** File-backed optional recognizer; model installation remains outside the HAP. */
export class ComicNcnnLocalTextRecognizer implements ComicLocalTextRecognizer {
  private readonly paramPath: string
  private readonly modelPath: string
  private readonly dictionaryPath: string
  private readonly threads: number

  constructor(
    paramPath: string,
    modelPath: string,
    dictionaryPath: string,
    threads: number = 2,
  ) {
    this.paramPath = paramPath
    this.modelPath = modelPath
    this.dictionaryPath = dictionaryPath
    this.threads = threads
  }

  profileId(): string {
    return 'pp-ocrv5-mobile-rec-ncnn-fp32-v1'
  }

  revision(): number {
    return 1
  }

  async recognize(
    pixelMap: image.PixelMap,
    rotateCounterClockwise: boolean,
  ): Promise<ComicNativeTextRecognitionResult> {
    const info: image.ImageInfo = await pixelMap.getImageInfo()
    const width: number = Math.floor(info.size.width)
    const height: number = Math.floor(info.size.height)
    const pixels: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
    const pixelMapReadStartedAt: number = Date.now()
    await pixelMap.readPixelsToBuffer(pixels)
    const pixelMapReadMs: number = Date.now() - pixelMapReadStartedAt
    const stride: number = Math.floor(pixels.byteLength / Math.max(1, height))
    const nativeCallStartedAt: number = Date.now()
    const result: ComicNativeTextRecognitionResult =
      await ComicNativeTextRecognizer.recognizeRgba(
        pixels,
        width,
        height,
        stride,
        this.paramPath,
        this.modelPath,
        this.dictionaryPath,
        rotateCounterClockwise,
        this.threads,
      )
    result.pixelMapReadMs = pixelMapReadMs
    result.nativeCallMs = Date.now() - nativeCallStartedAt
    return result
  }
}

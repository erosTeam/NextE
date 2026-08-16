import nativeVision from 'libreader_enhancement.so'

const COMIC_BUBBLE_MASK_MAX_PIXELS: number = 16 * 1024 * 1024
const COMIC_BUBBLE_MASK_MAX_DETECTIONS: number = 64

interface NativeComicBubbleMaskDetection {
  left: number
  top: number
  right: number
  bottom: number
  score: number
}

interface NativeComicBubbleMaskResult {
  mask: ArrayBuffer
  detections: NativeComicBubbleMaskDetection[]
  backend: string
  modelLoadMs: number
  inferenceMs: number
  postprocessingMs: number
  maskedPixels: number
}

interface NativeComicBubbleMaskModule {
  inferComicBubbleMask(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    confidenceThreshold: number,
    maskThreshold: number,
    threads: number,
  ): Promise<NativeComicBubbleMaskResult>
}

export class ComicNativeBubbleMaskDetection {
  left: number = 0
  top: number = 0
  right: number = 0
  bottom: number = 0
  score: number = 0
}

export class ComicNativeBubbleMaskResult {
  mask: ArrayBuffer = new ArrayBuffer(0)
  detections: ComicNativeBubbleMaskDetection[] = []
  backend: string = ''
  modelLoadMs: number = 0
  inferenceMs: number = 0
  postprocessingMs: number = 0
  maskedPixels: number = 0
}

const nativeRuntime: NativeComicBubbleMaskModule = nativeVision as NativeComicBubbleMaskModule

/**
 * Typed boundary for semantic speech-bubble instance masks. This is deliberately separate from
 * text-region OBB detection: callers receive a raster mask and may not promote a bounding box to
 * a bubble boundary.
 */
export class ComicNativeBubbleMasker {
  static async inferRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    confidenceThreshold: number = 0.5,
    maskThreshold: number = 0.5,
    threads: number = 2,
  ): Promise<ComicNativeBubbleMaskResult> {
    if (width <= 1 || height <= 1 || width * height > COMIC_BUBBLE_MASK_MAX_PIXELS ||
      stride < width * 4 || pixels.byteLength < stride * height) {
      throw new Error('invalid native comic bubble mask input')
    }
    if (paramPath.trim().length <= 0 || modelPath.trim().length <= 0 ||
      confidenceThreshold <= 0 || confidenceThreshold >= 1 ||
      maskThreshold <= 0 || maskThreshold >= 1 || threads < 1 || threads > 8) {
      throw new Error('invalid native comic bubble mask configuration')
    }
    const native: NativeComicBubbleMaskResult = await nativeRuntime.inferComicBubbleMask(
      pixels,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      confidenceThreshold,
      maskThreshold,
      threads,
    )
    if (native.mask.byteLength !== width * height ||
      native.detections.length > COMIC_BUBBLE_MASK_MAX_DETECTIONS ||
      native.backend.length <= 0 || native.modelLoadMs < 0 || native.inferenceMs < 0 ||
      native.postprocessingMs < 0 || native.maskedPixels < 0 ||
      native.maskedPixels > width * height || Math.floor(native.maskedPixels) !== native.maskedPixels) {
      throw new Error('invalid native comic bubble mask result')
    }
    const result: ComicNativeBubbleMaskResult = new ComicNativeBubbleMaskResult()
    result.mask = native.mask
    result.backend = native.backend
    result.modelLoadMs = native.modelLoadMs
    result.inferenceMs = native.inferenceMs
    result.postprocessingMs = native.postprocessingMs
    result.maskedPixels = native.maskedPixels
    for (let index: number = 0; index < native.detections.length; index++) {
      const source: NativeComicBubbleMaskDetection = native.detections[index]
      if (!Number.isFinite(source.left) || !Number.isFinite(source.top) ||
        !Number.isFinite(source.right) || !Number.isFinite(source.bottom) ||
        !Number.isFinite(source.score) || source.left < 0 || source.top < 0 ||
        source.right > width || source.bottom > height || source.right <= source.left ||
        source.bottom <= source.top || source.score <= 0 || source.score > 1) {
        throw new Error('native comic bubble mask returned an invalid detection')
      }
      const detection: ComicNativeBubbleMaskDetection = new ComicNativeBubbleMaskDetection()
      detection.left = source.left
      detection.top = source.top
      detection.right = source.right
      detection.bottom = source.bottom
      detection.score = source.score
      result.detections.push(detection)
    }
    return result
  }
}

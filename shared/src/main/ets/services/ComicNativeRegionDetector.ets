import nativeVision from 'libnexte_super_resolution.so'
import { image } from '@kit.ImageKit'

const COMIC_NATIVE_MAX_REGIONS: number = 512
const COMIC_NATIVE_POINT_VALUES: number = 8

interface NativeComicRegionDetection {
  points: number[]
  score: number
  classId: number
  label: string
}

interface NativeComicRegionDetectionResult {
  regions: NativeComicRegionDetection[]
  backend: string
  modelLoadMs: number
  inferenceMs: number
}

interface NativeComicRegionDetectorModule {
  detectComicRegions(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    confidenceThreshold: number,
    threads: number,
  ): Promise<NativeComicRegionDetectionResult>
}

export class ComicNativeRegionPoint {
  x: number = 0
  y: number = 0

  constructor(x: number = 0, y: number = 0) {
    this.x = x
    this.y = y
  }
}

export class ComicNativeDetectedRegion {
  points: ComicNativeRegionPoint[] = []
  score: number = 0
  classId: number = 0
  label: string = ''
  proposalOccupiedCells: number = 0
}

export class ComicNativeRegionDetectionResult {
  regions: ComicNativeDetectedRegion[] = []
  backend: string = ''
  modelLoadMs: number = 0
  inferenceMs: number = 0
  pixelMapReadMs: number = 0
  nativeCallMs: number = 0
}

export interface ComicLocalRegionDetector {
  profileId(): string
  revision(): number
  detect(pixelMap: image.PixelMap): Promise<ComicNativeRegionDetectionResult>
}

const nativeRuntime: NativeComicRegionDetectorModule =
  nativeVision as NativeComicRegionDetectorModule

/** Typed ArkTS boundary for the optional ncnn manga balloon/region detector. */
export class ComicNativeRegionDetector {
  static async detectRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    confidenceThreshold: number = 0.5,
    threads: number = 2,
  ): Promise<ComicNativeRegionDetectionResult> {
    if (width <= 0 || height <= 0 || stride < width * 4 ||
      pixels.byteLength < stride * height) {
      throw new Error('invalid native comic detector RGBA input')
    }
    if (paramPath.trim().length <= 0 || modelPath.trim().length <= 0 ||
      confidenceThreshold <= 0 || confidenceThreshold >= 1 ||
      threads < 1 || threads > 8) {
      throw new Error('invalid native comic detector configuration')
    }
    const native: NativeComicRegionDetectionResult = await nativeRuntime.detectComicRegions(
      pixels,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      confidenceThreshold,
      threads,
    )
    if (native.regions.length > COMIC_NATIVE_MAX_REGIONS ||
      native.backend.length <= 0 || native.modelLoadMs < 0 || native.inferenceMs < 0) {
      throw new Error('invalid native comic detector result')
    }
    const result: ComicNativeRegionDetectionResult = new ComicNativeRegionDetectionResult()
    result.backend = native.backend
    result.modelLoadMs = native.modelLoadMs
    result.inferenceMs = native.inferenceMs
    for (let index: number = 0; index < native.regions.length; index++) {
      const source: NativeComicRegionDetection = native.regions[index]
      if (source.points.length !== COMIC_NATIVE_POINT_VALUES ||
        !Number.isFinite(source.score) || source.score <= 0 || source.score > 1 ||
        source.classId < 0 || source.classId > 4 || source.label.length <= 0) {
        throw new Error('invalid native comic detector region')
      }
      const region: ComicNativeDetectedRegion = new ComicNativeDetectedRegion()
      region.score = source.score
      region.classId = source.classId
      region.label = source.label
      for (let coordinate: number = 0;
        coordinate < source.points.length; coordinate += 2) {
        const x: number = source.points[coordinate]
        const y: number = source.points[coordinate + 1]
        if (!Number.isFinite(x) || !Number.isFinite(y) ||
          x < 0 || x > width || y < 0 || y > height) {
          throw new Error('native comic detector returned an out-of-bounds point')
        }
        region.points.push(new ComicNativeRegionPoint(x, y))
      }
      result.regions.push(region)
    }
    return result
  }
}

/** File-backed optional detector; model installation remains outside the HAP. */
export class ComicNcnnLocalRegionDetector implements ComicLocalRegionDetector {
  private readonly paramPath: string
  private readonly modelPath: string
  private readonly confidenceThreshold: number
  private readonly threads: number

  constructor(
    paramPath: string,
    modelPath: string,
    confidenceThreshold: number = 0.5,
    threads: number = 2,
  ) {
    this.paramPath = paramPath
    this.modelPath = modelPath
    this.confidenceThreshold = confidenceThreshold
    this.threads = threads
  }

  profileId(): string {
    return 'ysgyolo-1.2-os1-ncnn-fp32-tiled-v2'
  }

  revision(): number {
    return 2
  }

  async detect(pixelMap: image.PixelMap): Promise<ComicNativeRegionDetectionResult> {
    const info: image.ImageInfo = await pixelMap.getImageInfo()
    const width: number = Math.floor(info.size.width)
    const height: number = Math.floor(info.size.height)
    const stride: number = Math.max(Math.floor(info.stride), width * 4)
    const pixels: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
    const pixelMapReadStartedAt: number = Date.now()
    await pixelMap.readPixelsToBuffer(pixels)
    const pixelMapReadMs: number = Date.now() - pixelMapReadStartedAt
    const nativeCallStartedAt: number = Date.now()
    const result: ComicNativeRegionDetectionResult =
      await ComicNativeRegionDetector.detectRgba(
        pixels,
        width,
        height,
        stride,
        this.paramPath,
        this.modelPath,
        this.confidenceThreshold,
        this.threads,
      )
    result.pixelMapReadMs = pixelMapReadMs
    result.nativeCallMs = Date.now() - nativeCallStartedAt
    return result
  }
}

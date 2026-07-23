import nativeVision from 'libnexte_super_resolution.so'
import { image } from '@kit.ImageKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const COMIC_TEXT_MASK_TILE_EDGE: number = 2048
const COMIC_TEXT_MASK_TILE_OVERLAP: number = 256
const COMIC_TEXT_MASK_MAX_TILES: number = 64
const COMIC_TEXT_MASK_MAX_PIXELS: number = 16 * 1024 * 1024

interface NativeComicTextMaskResult {
  mask: ArrayBuffer
  secondaryMask?: ArrayBuffer
  backend: string
  modelLoadMs: number
  preprocessingMs: number
  inferenceMs: number
  postprocessingMs: number
  resultMarshallingMs: number
  maskedPixels: number
  secondaryMaskedPixels: number
}

interface NativeComicTextMaskModule {
  inferComicTextMask(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    threshold: number,
    threads: number,
    inputBgra: boolean,
    secondaryThreshold: number,
  ): Promise<NativeComicTextMaskResult>
}

class ComicTextMaskTile {
  x: number = 0
  y: number = 0
  width: number = 0
  height: number = 0
}

export class ComicNativeTextMaskResult {
  mask: ArrayBuffer = new ArrayBuffer(0)
  secondaryMask: ArrayBuffer = new ArrayBuffer(0)
  backend: string = ''
  modelLoadMs: number = 0
  preprocessingMs: number = 0
  inferenceMs: number = 0
  postprocessingMs: number = 0
  resultMarshallingMs: number = 0
  tileCount: number = 1
  maskedPixels: number = 0
  secondaryMaskedPixels: number = 0
  pixelMapReadMs: number = 0
  nativeCallMs: number = 0
  wrapperTotalMs: number = 0
}

export interface ComicLocalTextMasker {
  profileId(): string
  revision(): number
  mask(pixelMap: image.PixelMap): Promise<ComicNativeTextMaskResult>
}

const nativeRuntime: NativeComicTextMaskModule = nativeVision as NativeComicTextMaskModule

/** Typed ArkTS boundary for CTD's pixel-level text segmentation output. */
export class ComicNativeTextMasker {
  private static async infer(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    threshold: number,
    threads: number,
    inputBgra: boolean,
    secondaryThreshold: number,
  ): Promise<ComicNativeTextMaskResult> {
    if (width <= 1 || height <= 1 || width > COMIC_TEXT_MASK_TILE_EDGE ||
      height > COMIC_TEXT_MASK_TILE_EDGE || stride < width * 4 ||
      pixels.byteLength < stride * height) {
      throw new Error('invalid native comic text mask input')
    }
    if (paramPath.trim().length <= 0 || modelPath.trim().length <= 0 ||
      threshold <= 0 || threshold >= 1 || threads < 1 || threads > 8 ||
      secondaryThreshold < 0 || secondaryThreshold >= 1 ||
      (secondaryThreshold > 0 && secondaryThreshold <= threshold)) {
      throw new Error('invalid native comic text mask configuration')
    }
    const native: NativeComicTextMaskResult = await nativeRuntime.inferComicTextMask(
      pixels,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      threshold,
      threads,
      inputBgra,
      secondaryThreshold,
    )
    if (native.mask.byteLength !== width * height || native.backend.length <= 0 ||
      native.modelLoadMs < 0 || native.preprocessingMs < 0 ||
      native.inferenceMs < 0 || native.postprocessingMs < 0 ||
      native.resultMarshallingMs < 0 ||
      native.maskedPixels < 0 || native.maskedPixels > width * height ||
      native.secondaryMaskedPixels < 0 ||
      native.secondaryMaskedPixels > width * height ||
      Math.floor(native.maskedPixels) !== native.maskedPixels ||
      Math.floor(native.secondaryMaskedPixels) !== native.secondaryMaskedPixels ||
      (secondaryThreshold > 0 && native.secondaryMask === undefined) ||
      (native.secondaryMask !== undefined &&
        native.secondaryMask.byteLength !== width * height)) {
      throw new Error('invalid native comic text mask result')
    }
    const result: ComicNativeTextMaskResult = new ComicNativeTextMaskResult()
    result.mask = native.mask
    if (native.secondaryMask !== undefined) {
      result.secondaryMask = native.secondaryMask
    }
    result.backend = native.backend
    result.modelLoadMs = native.modelLoadMs
    result.preprocessingMs = native.preprocessingMs
    result.inferenceMs = native.inferenceMs
    result.postprocessingMs = native.postprocessingMs
    result.resultMarshallingMs = native.resultMarshallingMs
    result.maskedPixels = native.maskedPixels
    result.secondaryMaskedPixels = native.secondaryMaskedPixels
    return result
  }

  static async inferRgba(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    threshold: number = 0.3,
    threads: number = 4,
    secondaryThreshold: number = 0,
  ): Promise<ComicNativeTextMaskResult> {
    return ComicNativeTextMasker.infer(
      pixels,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      threshold,
      threads,
      false,
      secondaryThreshold,
    )
  }

  static async inferBgra(
    pixels: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    paramPath: string,
    modelPath: string,
    threshold: number = 0.3,
    threads: number = 4,
    secondaryThreshold: number = 0,
  ): Promise<ComicNativeTextMaskResult> {
    return ComicNativeTextMasker.infer(
      pixels,
      width,
      height,
      stride,
      paramPath,
      modelPath,
      threshold,
      threads,
      true,
      secondaryThreshold,
    )
  }
}

/** File-backed tiled CTD masker; model installation remains outside the HAP. */
export class ComicNcnnLocalTextMasker implements ComicLocalTextMasker {
  private readonly paramPath: string
  private readonly modelPath: string
  private readonly threshold: number
  private readonly threads: number
  private readonly secondaryThreshold: number

  constructor(
    paramPath: string,
    modelPath: string,
    threshold: number = 0.3,
    threads: number = 4,
    secondaryThreshold: number = 0,
  ) {
    this.paramPath = paramPath
    this.modelPath = modelPath
    this.threshold = threshold
    this.threads = threads
    this.secondaryThreshold = secondaryThreshold
  }

  profileId(): string {
    return 'ctd-seg-1024-ncnn-fp16-tiled-v3'
  }

  revision(): number {
    return 3
  }

  async mask(pixelMap: image.PixelMap): Promise<ComicNativeTextMaskResult> {
    const wrapperStartedAt: number = Date.now()
    const info: image.ImageInfo = await pixelMap.getImageInfo()
    const width: number = Math.floor(info.size.width)
    const height: number = Math.floor(info.size.height)
    if (width <= 1 || height <= 1 || width * height > COMIC_TEXT_MASK_MAX_PIXELS) {
      throw new Error('comic text mask page exceeds the on-device pixel boundary')
    }
    const tiles: ComicTextMaskTile[] = ComicNcnnLocalTextMasker.tiles(width, height)
    if (tiles.length <= 0 || tiles.length > COMIC_TEXT_MASK_MAX_TILES) {
      throw new Error('comic text mask page exceeds the on-device tile boundary')
    }
    const firstTile: ComicTextMaskTile = tiles[0]
    if (tiles.length === 1 && firstTile.x === 0 && firstTile.y === 0 &&
      firstTile.width === width && firstTile.height === height) {
      const result: ComicNativeTextMaskResult = await this.inferTile(pixelMap, firstTile)
      result.tileCount = 1
      result.wrapperTotalMs = Date.now() - wrapperStartedAt
      ComicNcnnLocalTextMasker.logResult(result, width, height)
      return result
    }
    const mergedBuffer: ArrayBuffer = new ArrayBuffer(width * height)
    const merged: Uint8Array = new Uint8Array(mergedBuffer)
    const secondaryMergedBuffer: ArrayBuffer = this.secondaryThreshold > 0 ?
      new ArrayBuffer(width * height) : new ArrayBuffer(0)
    const secondaryMerged: Uint8Array = new Uint8Array(secondaryMergedBuffer)
    const aggregate: ComicNativeTextMaskResult = new ComicNativeTextMaskResult()
    aggregate.mask = mergedBuffer
    aggregate.secondaryMask = secondaryMergedBuffer
    aggregate.tileCount = tiles.length
    const coveredRightByRow: Int32Array = new Int32Array(height)
    for (let tileIndex: number = 0; tileIndex < tiles.length; tileIndex++) {
      const tile: ComicTextMaskTile = tiles[tileIndex]
      const result: ComicNativeTextMaskResult = await this.inferTile(pixelMap, tile)
      aggregate.backend = result.backend
      aggregate.modelLoadMs = aggregate.modelLoadMs + result.modelLoadMs
      aggregate.preprocessingMs = aggregate.preprocessingMs + result.preprocessingMs
      aggregate.inferenceMs = aggregate.inferenceMs + result.inferenceMs
      aggregate.postprocessingMs = aggregate.postprocessingMs + result.postprocessingMs
      aggregate.resultMarshallingMs =
        aggregate.resultMarshallingMs + result.resultMarshallingMs
      aggregate.pixelMapReadMs = aggregate.pixelMapReadMs + result.pixelMapReadMs
      aggregate.nativeCallMs = aggregate.nativeCallMs + result.nativeCallMs
      aggregate.maskedPixels = aggregate.maskedPixels + result.maskedPixels
      aggregate.secondaryMaskedPixels =
        aggregate.secondaryMaskedPixels + result.secondaryMaskedPixels
      const tileMask: Uint8Array = new Uint8Array(result.mask)
      const secondaryTileMask: Uint8Array = new Uint8Array(result.secondaryMask)
      for (let y: number = 0; y < tile.height; y++) {
        const sourceRow: number = y * tile.width
        const targetY: number = tile.y + y
        const targetRow: number = targetY * width + tile.x
        const coveredRight: number = coveredRightByRow[targetY]
        const overlapWidth: number = Math.max(
          0,
          Math.min(tile.width, coveredRight - tile.x),
        )
        for (let x: number = 0; x < overlapWidth; x++) {
          if (tileMask[sourceRow + x] !== 0) {
            if (merged[targetRow + x] !== 0) {
              aggregate.maskedPixels = aggregate.maskedPixels - 1
            }
            merged[targetRow + x] = 1
          }
          if (secondaryTileMask.length > 0 && secondaryTileMask[sourceRow + x] !== 0) {
            if (secondaryMerged[targetRow + x] !== 0) {
              aggregate.secondaryMaskedPixels =
                aggregate.secondaryMaskedPixels - 1
            }
            secondaryMerged[targetRow + x] = 1
          }
        }
        if (overlapWidth < tile.width) {
          merged.set(
            tileMask.subarray(sourceRow + overlapWidth, sourceRow + tile.width),
            targetRow + overlapWidth,
          )
          if (secondaryTileMask.length > 0) {
            secondaryMerged.set(
              secondaryTileMask.subarray(
                sourceRow + overlapWidth,
                sourceRow + tile.width,
              ),
              targetRow + overlapWidth,
            )
          }
        }
        coveredRightByRow[targetY] = Math.max(coveredRight, tile.x + tile.width)
      }
    }
    aggregate.wrapperTotalMs = Date.now() - wrapperStartedAt
    ComicNcnnLocalTextMasker.logResult(aggregate, width, height)
    return aggregate
  }

  private async inferTile(
    pixelMap: image.PixelMap,
    tile: ComicTextMaskTile,
  ): Promise<ComicNativeTextMaskResult> {
    const stride: number = tile.width * 4
    const pixels: ArrayBuffer = new ArrayBuffer(stride * tile.height)
    const area: image.PositionArea = {
      pixels: pixels,
      offset: 0,
      stride: stride,
      region: {
        x: tile.x,
        y: tile.y,
        size: { width: tile.width, height: tile.height },
      },
    }
    const pixelMapReadStartedAt: number = Date.now()
    await pixelMap.readPixels(area)
    const pixelMapReadMs: number = Date.now() - pixelMapReadStartedAt
    // PixelMap.readPixels exposes BGRA_8888 bytes on HarmonyOS.
    const nativeCallStartedAt: number = Date.now()
    const result: ComicNativeTextMaskResult =
      await ComicNativeTextMasker.inferBgra(
        pixels,
        tile.width,
        tile.height,
        stride,
        this.paramPath,
        this.modelPath,
        this.threshold,
        this.threads,
        this.secondaryThreshold,
      )
    result.pixelMapReadMs = pixelMapReadMs
    result.nativeCallMs = Date.now() - nativeCallStartedAt
    return result
  }

  private static logResult(
    result: ComicNativeTextMaskResult,
    width: number,
    height: number,
  ): void {
    DiagnosticLogger.info(
      'comic-translation',
      'local_text_mask_inferred',
      `backend=${result.backend} page=${width}x${height} tiles=${result.tileCount} ` +
      `masked=${result.maskedPixels} secondary=${result.secondaryMaskedPixels} ` +
      `load=${result.modelLoadMs}ms ` +
      `inference=${result.inferenceMs}ms`,
    )
    DiagnosticLogger.info(
      'comic-translation',
      'local_text_mask_timings',
      `total=${result.wrapperTotalMs}ms pixelRead=${result.pixelMapReadMs}ms ` +
        `nativeCall=${result.nativeCallMs}ms nativeBridge=${Math.max(
          0,
          result.nativeCallMs - result.modelLoadMs - result.preprocessingMs -
            result.inferenceMs - result.postprocessingMs -
            result.resultMarshallingMs,
        )}ms load=${result.modelLoadMs}ms preprocess=${result.preprocessingMs}ms ` +
        `inference=${result.inferenceMs}ms postprocess=${result.postprocessingMs}ms ` +
        `marshal=${result.resultMarshallingMs}ms`,
    )
  }

  private static tiles(width: number, height: number): ComicTextMaskTile[] {
    const xStarts: number[] = ComicNcnnLocalTextMasker.tileStarts(width)
    const yStarts: number[] = ComicNcnnLocalTextMasker.tileStarts(height)
    const output: ComicTextMaskTile[] = []
    for (let yIndex: number = 0; yIndex < yStarts.length; yIndex++) {
      for (let xIndex: number = 0; xIndex < xStarts.length; xIndex++) {
        const tile: ComicTextMaskTile = new ComicTextMaskTile()
        tile.x = xStarts[xIndex]
        tile.y = yStarts[yIndex]
        tile.width = Math.min(COMIC_TEXT_MASK_TILE_EDGE, width - tile.x)
        tile.height = Math.min(COMIC_TEXT_MASK_TILE_EDGE, height - tile.y)
        output.push(tile)
      }
    }
    return output
  }

  private static tileStarts(length: number): number[] {
    if (length <= COMIC_TEXT_MASK_TILE_EDGE) {
      return [0]
    }
    const output: number[] = []
    const step: number = COMIC_TEXT_MASK_TILE_EDGE - COMIC_TEXT_MASK_TILE_OVERLAP
    let start: number = 0
    while (true) {
      output.push(start)
      if (start + COMIC_TEXT_MASK_TILE_EDGE >= length) {
        break
      }
      const next: number = Math.min(length - COMIC_TEXT_MASK_TILE_EDGE, start + step)
      if (next <= start) {
        break
      }
      start = next
    }
    return output
  }
}

import { image } from '@kit.ImageKit'
import { util } from '@kit.ArkTS'
import { ComicPoint, ComicTextBlock } from '../model/ComicTranslation'
import { ComicTextTranslationRequest } from './ComicVisualTranslationBackend'

const MAX_COMIC_REGION_CROPS: number = 16
const MAX_COMIC_REGION_CROP_BYTES: number = 1536 * 1024
const MAX_COMIC_REGION_CROP_TOTAL_BYTES: number = 8 * 1024 * 1024
const COMIC_REGION_CROP_LONG_EDGE: number = 1024
const COMIC_REGION_CROP_MAX_SCALE: number = 4

class ComicRegionCropCandidate {
  blockIndex: number = 0
  readingOrder: number = 0
  area: number = 0
}

class ComicRegionCropRect {
  x: number = 0
  y: number = 0
  width: number = 0
  height: number = 0
}

export class ComicResponsesRegionImage {
  blockId: string = ''
  dataUrl: string = ''
  width: number = 0
  height: number = 0
  byteLength: number = 0
}

/** Produces bounded, enlarged close-ups so the vision model can verify OCR inside known regions. */
export class ComicResponsesRegionImagePayload {
  static async build(request: ComicTextTranslationRequest): Promise<ComicResponsesRegionImage[]> {
    const candidates: ComicRegionCropCandidate[] =
      ComicResponsesRegionImagePayload.candidates(request)
    if (candidates.length <= 0) {
      return []
    }
    let source: image.ImageSource | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    const results: ComicResponsesRegionImage[] = []
    let totalBytes: number = 0
    try {
      source = image.createImageSource(request.source.imageFilePath)
      const sourceInfo: image.ImageInfo = await source.getImageInfo()
      if (sourceInfo.size.width !== request.source.imageWidth ||
        sourceInfo.size.height !== request.source.imageHeight) {
        throw new Error('Comic region crop source dimensions do not match the request')
      }
      packer = image.createImagePacker()
      for (let index: number = 0; index < candidates.length; index++) {
        const block: ComicTextBlock = request.document.blocks[candidates[index].blockIndex]
        const rect: ComicRegionCropRect = ComicResponsesRegionImagePayload.rect(
          block.polygon,
          request.source.imageWidth,
          request.source.imageHeight,
        )
        const desired = ComicResponsesRegionImagePayload.desiredSize(rect)
        let pixelMap: image.PixelMap | undefined = undefined
        try {
          const options: image.DecodingOptions = {
            editable: false,
            desiredRegion: {
              x: rect.x,
              y: rect.y,
              size: { width: rect.width, height: rect.height },
            },
            desiredSize: desired,
            cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
          }
          pixelMap = await source.createPixelMap(options)
          const packed: ArrayBuffer = await packer.packToData(pixelMap, {
            format: 'image/jpeg',
            quality: 95,
          })
          const bytes: Uint8Array = new Uint8Array(packed)
          if (bytes.byteLength <= 0 || bytes.byteLength > MAX_COMIC_REGION_CROP_BYTES ||
            totalBytes + bytes.byteLength > MAX_COMIC_REGION_CROP_TOTAL_BYTES) {
            throw new Error('Comic region crop payload exceeds its size boundary')
          }
          totalBytes += bytes.byteLength
          const result: ComicResponsesRegionImage = new ComicResponsesRegionImage()
          result.blockId = block.blockId
          result.dataUrl = 'data:image/jpeg;base64,' +
            new util.Base64Helper().encodeToStringSync(bytes)
          result.width = desired.width
          result.height = desired.height
          result.byteLength = bytes.byteLength
          results.push(result)
        } finally {
          if (pixelMap !== undefined) {
            await pixelMap.release()
          }
        }
      }
      return results
    } finally {
      if (packer !== undefined) {
        await packer.release()
      }
      if (source !== undefined) {
        await source.release()
      }
    }
  }

  private static candidates(request: ComicTextTranslationRequest): ComicRegionCropCandidate[] {
    const values: ComicRegionCropCandidate[] = []
    for (let blockIndex: number = 0; blockIndex < request.document.blocks.length; blockIndex++) {
      const block: ComicTextBlock = request.document.blocks[blockIndex]
      const bounds: ComicRegionCropRect = ComicResponsesRegionImagePayload.tightRect(block.polygon)
      const candidate: ComicRegionCropCandidate = new ComicRegionCropCandidate()
      candidate.blockIndex = blockIndex
      candidate.readingOrder = block.readingOrder
      candidate.area = bounds.width * bounds.height
      values.push(candidate)
    }
    values.sort((left: ComicRegionCropCandidate, right: ComicRegionCropCandidate): number => {
      if (left.area !== right.area) {
        return left.area - right.area
      }
      return left.readingOrder - right.readingOrder
    })
    const selected: ComicRegionCropCandidate[] = values.slice(0, MAX_COMIC_REGION_CROPS)
    selected.sort((left: ComicRegionCropCandidate, right: ComicRegionCropCandidate): number =>
      left.readingOrder - right.readingOrder)
    return selected
  }

  private static tightRect(polygon: ComicPoint[]): ComicRegionCropRect {
    let minX: number = polygon[0].x
    let minY: number = polygon[0].y
    let maxX: number = polygon[0].x
    let maxY: number = polygon[0].y
    for (let index: number = 1; index < polygon.length; index++) {
      minX = Math.min(minX, polygon[index].x)
      minY = Math.min(minY, polygon[index].y)
      maxX = Math.max(maxX, polygon[index].x)
      maxY = Math.max(maxY, polygon[index].y)
    }
    const result: ComicRegionCropRect = new ComicRegionCropRect()
    result.x = Math.floor(minX)
    result.y = Math.floor(minY)
    result.width = Math.max(1, Math.ceil(maxX) - result.x)
    result.height = Math.max(1, Math.ceil(maxY) - result.y)
    return result
  }

  private static rect(
    polygon: ComicPoint[],
    sourceWidth: number,
    sourceHeight: number,
  ): ComicRegionCropRect {
    const tight: ComicRegionCropRect = ComicResponsesRegionImagePayload.tightRect(polygon)
    const paddingX: number = Math.max(24, Math.floor(tight.width * 0.5))
    const paddingY: number = Math.max(24, Math.floor(tight.height * 0.35))
    const left: number = Math.max(0, tight.x - paddingX)
    const top: number = Math.max(0, tight.y - paddingY)
    const right: number = Math.min(sourceWidth, tight.x + tight.width + paddingX)
    const bottom: number = Math.min(sourceHeight, tight.y + tight.height + paddingY)
    const result: ComicRegionCropRect = new ComicRegionCropRect()
    result.x = left
    result.y = top
    result.width = Math.max(1, right - left)
    result.height = Math.max(1, bottom - top)
    return result
  }

  private static desiredSize(rect: ComicRegionCropRect): image.Size {
    const longEdge: number = Math.max(rect.width, rect.height)
    const scale: number = Math.max(1, Math.min(
      COMIC_REGION_CROP_MAX_SCALE,
      COMIC_REGION_CROP_LONG_EDGE / longEdge,
    ))
    return {
      width: Math.max(1, Math.floor(rect.width * scale)),
      height: Math.max(1, Math.floor(rect.height * scale)),
    }
  }
}

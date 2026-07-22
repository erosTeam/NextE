import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { common2D, drawing } from '@kit.ArkGraphics2D'
import { image } from '@kit.ImageKit'
import {
  ComicAnalysisState,
  ComicPageDocument,
  ComicPoint,
  ComicQualitySeverity,
  ComicQualitySignal,
  ComicRenderState,
  ComicSourceOrigin,
  ComicTextBlock,
  ComicTextKind,
  ComicTranslationState,
} from '../model/ComicTranslation'
import {
  ComicBackendTemplate,
  ComicRenderedPage,
  ComicRegionAnalysisResult,
} from '../model/ComicVisualTranslation'
import {
  ComicRegionAnalysisRequest,
  ComicRegionRenderBackend,
  ComicRegionRenderRequest,
} from './ComicVisualTranslationBackend'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'
import {
  ComicLocalOcrEngine,
  ComicLocalOcrLine,
  ComicLocalOcrPoint,
  ComicLocalOcrResult,
  HarmonyComicLocalOcrEngine,
} from './ComicHarmonyOcrService'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  ComicLocalRegionDetector,
  ComicNativeDetectedRegion,
  ComicNativeRegionDetectionResult,
  ComicNativeRegionPoint,
} from './ComicNativeRegionDetector'
import {
  ComicLocalTextRecognizer,
  ComicNativeTextRecognitionResult,
} from './ComicNativeTextRecognizer'

const LOCAL_VISUAL_BACKEND_ID: string = 'harmony-local-comic-visual'
const LOCAL_VISUAL_PROFILE_ID: string = 'core-vision-ocr-bubble-group-v14'
const LOCAL_VISUAL_PROTOCOL_REVISION: number = 14
const LOCAL_TEMPLATE_MIME: string = 'application/vnd.nexte.comic-local-template+json'
const LOCAL_RENDER_CACHE_DIR: string = 'comic-translated-pages'
const LOCAL_OCR_TILE_EDGE: number = 2048
const LOCAL_OCR_TILE_OVERLAP: number = 128
const LOCAL_DETECTOR_TILE_EDGE: number = 2048
const LOCAL_DETECTOR_TILE_OVERLAP: number = 256
const LOCAL_DETECTOR_MAX_TILES: number = 64
const LOCAL_DETECTOR_MAX_REGIONS: number = 512
const LOCAL_DETECTOR_DUPLICATE_IOU: number = 0.3
const LOCAL_DETECTOR_DUPLICATE_CENTER_DISTANCE: number = 10
const LOCAL_MAX_BLOCKS: number = 512
const LOCAL_MAX_SOURCE_TEXT_CHARS: number = 8192
const LOCAL_HASH_CHUNK_BYTES: number = 256 * 1024
const LOCAL_MAX_RENDERED_BYTES: number = 80 * 1024 * 1024
const LOCAL_MAX_RENDER_PIXELS: number = 16 * 1024 * 1024
const LOCAL_SUPPLEMENTAL_OCR_MAX_REGIONS: number = 16
const LOCAL_SUPPLEMENTAL_OCR_MAX_REGION_PIXELS: number = 2 * 1024 * 1024
const LOCAL_SUPPLEMENTAL_OCR_MIN_CONFIDENCE: number = 0.85
const LOCAL_SUPPLEMENTAL_OCR_MAX_TEXT_CHARS: number = 96
const LOCAL_MIN_FONT_SIZE: number = 8
const LOCAL_MAX_FONT_SIZE: number = 42
const LOCAL_VERTICAL_STYLE_HINT: string = 'vertical-rl'
const LOCAL_HORIZONTAL_STYLE_HINT: string = 'horizontal-ltr'

class LocalOcrTile {
  x: number = 0
  y: number = 0
  width: number = 0
  height: number = 0
}

class LocalMappedLine {
  text: string = ''
  polygon: ComicPoint[] = []
  tileIndex: number = 0
  blockIndex: number = 0
  lineIndex: number = 0
  detectorRegionIndex: number = -1
}

class LocalMappedBlock {
  text: string = ''
  polygon: ComicPoint[] = []
  styleHint: string = LOCAL_HORIZONTAL_STYLE_HINT
  tileIndex: number = 0
  detectorRegionIndex: number = -1
}

class LocalTemplatePoint {
  x: number = 0
  y: number = 0
}

class LocalTemplateBlock {
  blockId: string = ''
  polygon: LocalTemplatePoint[] = []
}

class LocalTemplateEnvelope {
  schemaVersion: number = 1
  backendId: string = LOCAL_VISUAL_BACKEND_ID
  profileId: string = LOCAL_VISUAL_PROFILE_ID
  sourceImageHash: string = ''
  width: number = 0
  height: number = 0
  blocks: LocalTemplateBlock[] = []
}

class LocalRenderRect {
  left: number = 0
  top: number = 0
  right: number = 0
  bottom: number = 0

  width(): number {
    return this.right - this.left
  }

  height(): number {
    return this.bottom - this.top
  }
}

class LocalTextLayout {
  fontSize: number = 0
  lines: string[] = []
}

class LocalVerticalTextLayout {
  fontSize: number = 0
  columns: string[] = []
}

class LocalFillStyle {
  red: number = 255
  green: number = 255
  blue: number = 255
  textRed: number = 24
  textGreen: number = 24
  textBlue: number = 24
}

class LocalColorSample {
  red: number = 0
  green: number = 0
  blue: number = 0
  luminance: number = 0
}

/** Endpoint-free visual backend with system OCR and optional manga-specific local models. */
export class ComicLocalVisualBackend implements ComicRegionRenderBackend {
  private readonly context: common.UIAbilityContext
  private readonly ocr: ComicLocalOcrEngine
  private readonly detector: ComicLocalRegionDetector | null
  private readonly supplementalRecognizer: ComicLocalTextRecognizer | null
  private readonly resolvedProfileId: string

  constructor(
    context: common.UIAbilityContext,
    ocr: ComicLocalOcrEngine = new HarmonyComicLocalOcrEngine(),
    detector: ComicLocalRegionDetector | null = null,
    supplementalRecognizer: ComicLocalTextRecognizer | null = null,
  ) {
    this.context = context
    this.ocr = ocr
    this.detector = detector
    this.supplementalRecognizer = supplementalRecognizer
    this.resolvedProfileId = LOCAL_VISUAL_PROFILE_ID +
      (detector === null ? '' : `-${detector.profileId()}`) +
      (supplementalRecognizer === null ? '' : `-${supplementalRecognizer.profileId()}`)
  }

  backendId(): string {
    return LOCAL_VISUAL_BACKEND_ID
  }

  profileId(): string {
    return this.resolvedProfileId
  }

  protocolRevision(): number {
    return LOCAL_VISUAL_PROTOCOL_REVISION +
      (this.detector === null ? 0 : this.detector.revision()) +
      (this.supplementalRecognizer === null ? 0 : this.supplementalRecognizer.revision())
  }

  async analyze(request: ComicRegionAnalysisRequest): Promise<ComicRegionAnalysisResult> {
    ComicVisualTranslationContract.validateRegionAnalysisRequest(request)
    let source: image.ImageSource | undefined = undefined
    try {
      source = image.createImageSource(request.source.imageFilePath)
      const info: image.ImageInfo = await source.getImageInfo()
      if (Math.floor(info.size.width) !== request.source.imageWidth ||
        Math.floor(info.size.height) !== request.source.imageHeight) {
        throw new Error('Local comic OCR source dimensions do not match the request')
      }
      const detection: ComicNativeRegionDetectionResult | null =
        await this.detectRegions(
          source,
          request.source.imageWidth,
          request.source.imageHeight,
        )
      const tiles: LocalOcrTile[] = ComicLocalVisualBackend.tiles(
        request.source.imageWidth,
        request.source.imageHeight,
      )
      const mapped: LocalMappedLine[] = []
      for (let tileIndex: number = 0; tileIndex < tiles.length; tileIndex++) {
        const tile: LocalOcrTile = tiles[tileIndex]
        let pixelMap: image.PixelMap | undefined = undefined
        try {
          pixelMap = await source.createPixelMap({
            editable: false,
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
            desiredRegion: {
              x: tile.x,
              y: tile.y,
              size: { width: tile.width, height: tile.height },
            },
            cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
          })
          const recognized: ComicLocalOcrResult = await this.ocr.recognize(pixelMap)
          ComicLocalVisualBackend.appendMappedLines(
            mapped,
            recognized.lines,
            tile,
            tileIndex,
            request.source.imageWidth,
            request.source.imageHeight,
          )
        } finally {
          if (pixelMap !== undefined) {
            await pixelMap.release()
          }
        }
      }
      const lines: LocalMappedLine[] = ComicLocalVisualBackend.suppressFurigana(
        ComicLocalVisualBackend.deduplicate(mapped),
      )
      ComicLocalVisualBackend.assignDetectorRegions(lines, detection)
      const supplementalCount: number = await this.supplementMissedRegions(
        source,
        lines,
        detection,
        request.source.imageWidth,
        request.source.imageHeight,
      )
      const blocks: LocalMappedBlock[] = ComicLocalVisualBackend.groupLines(lines)
      const result: ComicRegionAnalysisResult = new ComicRegionAnalysisResult()
      result.backendId = this.backendId()
      result.profileId = this.profileId()
      result.regionRevision = request.requestedRegionRevision
      result.document = ComicLocalVisualBackend.document(
        request,
        blocks,
        tiles.length,
        this.profileId(),
        detection !== null,
        supplementalCount,
      )
      result.adapterTemplate = ComicLocalVisualBackend.template(
        request,
        result.document,
        this.profileId(),
        this.protocolRevision(),
      )
      ComicVisualTranslationContract.validateRegionAnalysisResult(
        request,
        result.backendId,
        result.profileId,
        result.regionRevision,
        result.document,
        result.adapterTemplate,
      )
      return result
    } finally {
      if (source !== undefined) {
        await source.release()
      }
    }
  }

  async render(request: ComicRegionRenderRequest): Promise<ComicRenderedPage> {
    ComicVisualTranslationContract.validateStagedRenderRequest(request)
    this.validateTemplate(request)
    if (request.source.imageWidth * request.source.imageHeight > LOCAL_MAX_RENDER_PIXELS) {
      throw new Error('Local comic rendered page exceeds the on-device pixel boundary')
    }
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    let outputFile: fileIo.File | null = null
    const identityHash: string = ComicLocalVisualBackend.sha256Text(request.identity.cacheKey())
    const dir: string = `${this.context.cacheDir}/${LOCAL_RENDER_CACHE_DIR}`
    ComicLocalVisualBackend.ensureDir(dir)
    const partial: string = `${dir}/${identityHash}.part-${util.generateRandomUUID(true)}`
    try {
      source = image.createImageSource(request.source.imageFilePath)
      pixelMap = await source.createPixelMap({
        editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      })
      const translations: Map<string, string> = new Map<string, string>()
      for (let index: number = 0; index < request.translations.blocks.length; index++) {
        translations.set(
          request.translations.blocks[index].blockId,
          request.translations.blocks[index].translatedText,
        )
      }
      const fillStyles: LocalFillStyle[] = []
      for (let index: number = 0; index < request.document.blocks.length; index++) {
        const block: ComicTextBlock = request.document.blocks[index]
        const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
        const treatment: LocalRenderRect = ComicLocalVisualBackend.sourceTreatmentRect(
          raw,
          request.source.imageWidth,
          request.source.imageHeight,
          block.styleHint,
        )
        fillStyles.push(await ComicLocalVisualBackend.sampleFillStyle(
          pixelMap,
          request.source.imageWidth,
          request.source.imageHeight,
          treatment,
        ))
      }
      for (let index: number = 0; index < request.document.blocks.length; index++) {
        const block: ComicTextBlock = request.document.blocks[index]
        const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
        const treatment: LocalRenderRect = ComicLocalVisualBackend.sourceTreatmentRect(
          raw,
          request.source.imageWidth,
          request.source.imageHeight,
          block.styleHint,
        )
        await ComicLocalVisualBackend.eraseSourceRegion(
          pixelMap,
          request.source.imageWidth,
          request.source.imageHeight,
          raw,
          treatment,
          fillStyles[index],
          block.styleHint,
        )
      }
      const verticalFontCap: number = ComicLocalVisualBackend.verticalPageFontCap(
        request.document,
        translations,
        request.source.imageWidth,
        request.source.imageHeight,
      )
      const canvas: drawing.Canvas = new drawing.Canvas(pixelMap)
      for (let index: number = 0; index < request.document.blocks.length; index++) {
        const block: ComicTextBlock = request.document.blocks[index]
        const translated: string | undefined = translations.get(block.blockId)
        if (translated === undefined || translated.trim().length <= 0) {
          throw new Error('Local comic renderer is missing a translated block')
        }
        ComicLocalVisualBackend.drawBlock(
          canvas,
          block,
          translated.trim(),
          request.source.imageWidth,
          request.source.imageHeight,
          fillStyles[index],
          verticalFontCap,
        )
      }
      packer = image.createImagePacker()
      outputFile = fileIo.openSync(
        partial,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      await packer.packToFile(pixelMap, outputFile.fd, { format: 'image/png', quality: 100 })
      fileIo.closeSync(outputFile)
      outputFile = null
      const stat: fileIo.Stat = fileIo.statSync(partial)
      if (!stat.isFile() || stat.size <= 0 || stat.size > LOCAL_MAX_RENDERED_BYTES) {
        throw new Error('Local comic rendered page size is invalid')
      }
      const artifactHash: string = ComicLocalVisualBackend.sha256File(partial)
      const path: string = `${dir}/${identityHash}-${artifactHash}.png`
      ComicLocalVisualBackend.removeFile(path)
      fileIo.renameSync(partial, path)
      const now: number = Date.now()
      const page: ComicRenderedPage = new ComicRenderedPage()
      page.identity = request.identity.copy()
      page.artifactHash = artifactHash
      page.mimeType = 'image/png'
      page.width = request.source.imageWidth
      page.height = request.source.imageHeight
      page.byteLength = Math.floor(stat.size)
      page.localFilePath = path
      page.createdAt = now
      page.lastAccessAt = now
      ComicVisualTranslationContract.validateRenderedPage(request.identity, page)
      return page
    } catch (error) {
      ComicLocalVisualBackend.removeFile(partial)
      throw error as Error
    } finally {
      if (outputFile !== null) {
        fileIo.closeSync(outputFile)
      }
      if (packer !== undefined) {
        await packer.release()
      }
      if (pixelMap !== undefined) {
        await pixelMap.release()
      }
      if (source !== undefined) {
        await source.release()
      }
    }
  }

  private async detectRegions(
    source: image.ImageSource,
    width: number,
    height: number,
  ): Promise<ComicNativeRegionDetectionResult | null> {
    if (this.detector === null) {
      return null
    }
    const tiles: LocalOcrTile[] = ComicLocalVisualBackend.detectorTiles(width, height)
    if (tiles.length > LOCAL_DETECTOR_MAX_TILES) {
      DiagnosticLogger.warn(
        'comic-translation',
        'local_region_detector_fallback',
        `profile=${this.detector.profileId()} tiles=${tiles.length} limit=${LOCAL_DETECTOR_MAX_TILES}`,
      )
      return null
    }
    try {
      const combined: ComicNativeRegionDetectionResult = new ComicNativeRegionDetectionResult()
      for (let tileIndex: number = 0; tileIndex < tiles.length; tileIndex++) {
        const tile: LocalOcrTile = tiles[tileIndex]
        let pixelMap: image.PixelMap | undefined = undefined
        try {
          pixelMap = await source.createPixelMap({
            editable: false,
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
            desiredRegion: {
              x: tile.x,
              y: tile.y,
              size: { width: tile.width, height: tile.height },
            },
            cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
          })
          const detected: ComicNativeRegionDetectionResult = await this.detector.detect(pixelMap)
          if (combined.backend.length <= 0) {
            combined.backend = detected.backend
          }
          combined.modelLoadMs = combined.modelLoadMs + detected.modelLoadMs
          combined.inferenceMs = combined.inferenceMs + detected.inferenceMs
          ComicLocalVisualBackend.appendDetectedRegions(
            combined.regions,
            detected.regions,
            tile,
            width,
            height,
          )
        } finally {
          if (pixelMap !== undefined) {
            await pixelMap.release()
          }
        }
      }
      combined.regions = ComicLocalVisualBackend.deduplicateDetectedRegions(combined.regions)
      DiagnosticLogger.info(
        'comic-translation',
        'local_region_detector_success',
        `profile=${this.detector.profileId()} tiles=${tiles.length} ` +
          `regions=${combined.regions.length} loadMs=${combined.modelLoadMs} ` +
          `inferenceMs=${combined.inferenceMs}`,
      )
      return combined
    } catch (error) {
      DiagnosticLogger.warn(
        'comic-translation',
        'local_region_detector_fallback',
        `profile=${this.detector.profileId()} message=${(error as Error).message}`,
      )
      return null
    }
  }

  private async supplementMissedRegions(
    source: image.ImageSource,
    lines: LocalMappedLine[],
    detection: ComicNativeRegionDetectionResult | null,
    sourceWidth: number,
    sourceHeight: number,
  ): Promise<number> {
    if (this.supplementalRecognizer === null || detection === null) {
      return 0
    }
    const covered: Set<number> = new Set<number>()
    for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex++) {
      if (lines[lineIndex].detectorRegionIndex >= 0) {
        covered.add(lines[lineIndex].detectorRegionIndex)
      }
    }
    let attempted: number = 0
    let accepted: number = 0
    let inferenceMs: number = 0
    let modelLoadMs: number = 0
    for (let regionIndex: number = 0;
      regionIndex < detection.regions.length &&
      attempted < LOCAL_SUPPLEMENTAL_OCR_MAX_REGIONS; regionIndex++) {
      if (covered.has(regionIndex)) {
        continue
      }
      const region: ComicNativeDetectedRegion = detection.regions[regionIndex]
      const rect: LocalRenderRect = ComicLocalVisualBackend.detectedRegionBounds(
        region,
        sourceWidth,
        sourceHeight,
      )
      if (rect.width() < 8 || rect.height() < 8 ||
        rect.width() * rect.height() > LOCAL_SUPPLEMENTAL_OCR_MAX_REGION_PIXELS) {
        continue
      }
      attempted = attempted + 1
      let pixelMap: image.PixelMap | undefined = undefined
      try {
        pixelMap = await source.createPixelMap({
          editable: false,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredRegion: {
            x: Math.floor(rect.left),
            y: Math.floor(rect.top),
            size: {
              width: Math.ceil(rect.width()),
              height: Math.ceil(rect.height()),
            },
          },
          cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
        })
        const recognized: ComicNativeTextRecognitionResult =
          await this.supplementalRecognizer.recognize(
            pixelMap,
            rect.height() > rect.width() * 1.2,
          )
        modelLoadMs = modelLoadMs + recognized.modelLoadMs
        inferenceMs = inferenceMs + recognized.inferenceMs
        const text: string = recognized.text.trim()
        if (recognized.score < LOCAL_SUPPLEMENTAL_OCR_MIN_CONFIDENCE ||
          text.length < 2 || text.length > LOCAL_SUPPLEMENTAL_OCR_MAX_TEXT_CHARS ||
          /[\u0000-\u001f]/.test(text)) {
          continue
        }
        const line: LocalMappedLine = new LocalMappedLine()
        line.text = text
        line.tileIndex = LOCAL_MAX_BLOCKS + regionIndex
        line.blockIndex = regionIndex
        line.lineIndex = 0
        line.detectorRegionIndex = regionIndex
        for (let pointIndex: number = 0; pointIndex < region.points.length; pointIndex++) {
          line.polygon.push(new ComicPoint(
            Math.max(0, Math.min(sourceWidth, region.points[pointIndex].x)),
            Math.max(0, Math.min(sourceHeight, region.points[pointIndex].y)),
          ))
        }
        lines.push(line)
        accepted = accepted + 1
      } catch (error) {
        DiagnosticLogger.warn(
          'comic-translation',
          'local_text_recognizer_region_skipped',
          `profile=${this.supplementalRecognizer.profileId()} message=${(error as Error).message}`,
        )
      } finally {
        if (pixelMap !== undefined) {
          await pixelMap.release()
        }
      }
    }
    DiagnosticLogger.info(
      'comic-translation',
      'local_text_recognizer_complete',
      `profile=${this.supplementalRecognizer.profileId()} attempted=${attempted} ` +
        `accepted=${accepted} loadMs=${modelLoadMs} inferenceMs=${inferenceMs}`,
    )
    return accepted
  }

  private static tiles(width: number, height: number): LocalOcrTile[] {
    return ComicLocalVisualBackend.overlappingTiles(
      width,
      height,
      LOCAL_OCR_TILE_EDGE,
      LOCAL_OCR_TILE_OVERLAP,
    )
  }

  private static detectorTiles(width: number, height: number): LocalOcrTile[] {
    return ComicLocalVisualBackend.overlappingTiles(
      width,
      height,
      LOCAL_DETECTOR_TILE_EDGE,
      LOCAL_DETECTOR_TILE_OVERLAP,
    )
  }

  private static overlappingTiles(
    width: number,
    height: number,
    edge: number,
    overlap: number,
  ): LocalOcrTile[] {
    const values: LocalOcrTile[] = []
    const step: number = edge - overlap
    for (let y: number = 0; y < height; y += step) {
      const tileHeight: number = Math.min(edge, height - y)
      for (let x: number = 0; x < width; x += step) {
        const tile: LocalOcrTile = new LocalOcrTile()
        tile.x = x
        tile.y = y
        tile.width = Math.min(edge, width - x)
        tile.height = tileHeight
        values.push(tile)
        if (x + tile.width >= width) {
          break
        }
      }
      if (y + tileHeight >= height) {
        break
      }
    }
    return values
  }

  private static appendDetectedRegions(
    output: ComicNativeDetectedRegion[],
    regions: ComicNativeDetectedRegion[],
    tile: LocalOcrTile,
    sourceWidth: number,
    sourceHeight: number,
  ): void {
    for (let regionIndex: number = 0; regionIndex < regions.length; regionIndex++) {
      const source: ComicNativeDetectedRegion = regions[regionIndex]
      const mapped: ComicNativeDetectedRegion = new ComicNativeDetectedRegion()
      mapped.score = source.score
      mapped.classId = source.classId
      mapped.label = source.label
      for (let pointIndex: number = 0; pointIndex < source.points.length; pointIndex++) {
        mapped.points.push(new ComicNativeRegionPoint(
          Math.max(0, Math.min(sourceWidth, source.points[pointIndex].x + tile.x)),
          Math.max(0, Math.min(sourceHeight, source.points[pointIndex].y + tile.y)),
        ))
      }
      output.push(mapped)
    }
  }

  private static deduplicateDetectedRegions(
    regions: ComicNativeDetectedRegion[],
  ): ComicNativeDetectedRegion[] {
    const sorted: ComicNativeDetectedRegion[] = regions.slice().sort(
      (left: ComicNativeDetectedRegion, right: ComicNativeDetectedRegion): number =>
        right.score - left.score,
    )
    const accepted: ComicNativeDetectedRegion[] = []
    for (let candidateIndex: number = 0; candidateIndex < sorted.length; candidateIndex++) {
      const candidate: ComicNativeDetectedRegion = sorted[candidateIndex]
      let duplicate: boolean = false
      for (let acceptedIndex: number = 0; acceptedIndex < accepted.length; acceptedIndex++) {
        const existing: ComicNativeDetectedRegion = accepted[acceptedIndex]
        if ((candidate.classId === existing.classId &&
          ComicLocalVisualBackend.detectedRegionCenterDistance(candidate, existing) <
            LOCAL_DETECTOR_DUPLICATE_CENTER_DISTANCE) ||
          ComicLocalVisualBackend.detectedRegionAxisIou(candidate, existing) >
            LOCAL_DETECTOR_DUPLICATE_IOU) {
          duplicate = true
          break
        }
      }
      if (!duplicate) {
        accepted.push(candidate)
        if (accepted.length >= LOCAL_DETECTOR_MAX_REGIONS) {
          break
        }
      }
    }
    return accepted
  }

  private static detectedRegionCenterDistance(
    left: ComicNativeDetectedRegion,
    right: ComicNativeDetectedRegion,
  ): number {
    const leftBounds: LocalRenderRect = ComicLocalVisualBackend.detectedRegionBounds(
      left,
      Number.MAX_SAFE_INTEGER,
      Number.MAX_SAFE_INTEGER,
    )
    const rightBounds: LocalRenderRect = ComicLocalVisualBackend.detectedRegionBounds(
      right,
      Number.MAX_SAFE_INTEGER,
      Number.MAX_SAFE_INTEGER,
    )
    return Math.hypot(
      (leftBounds.left + leftBounds.right - rightBounds.left - rightBounds.right) / 2,
      (leftBounds.top + leftBounds.bottom - rightBounds.top - rightBounds.bottom) / 2,
    )
  }

  private static detectedRegionAxisIou(
    left: ComicNativeDetectedRegion,
    right: ComicNativeDetectedRegion,
  ): number {
    const leftBounds: LocalRenderRect = ComicLocalVisualBackend.detectedRegionBounds(
      left,
      Number.MAX_SAFE_INTEGER,
      Number.MAX_SAFE_INTEGER,
    )
    const rightBounds: LocalRenderRect = ComicLocalVisualBackend.detectedRegionBounds(
      right,
      Number.MAX_SAFE_INTEGER,
      Number.MAX_SAFE_INTEGER,
    )
    const intersectionWidth: number = Math.max(
      0,
      Math.min(leftBounds.right, rightBounds.right) -
        Math.max(leftBounds.left, rightBounds.left),
    )
    const intersectionHeight: number = Math.max(
      0,
      Math.min(leftBounds.bottom, rightBounds.bottom) -
        Math.max(leftBounds.top, rightBounds.top),
    )
    const intersection: number = intersectionWidth * intersectionHeight
    const union: number = leftBounds.width() * leftBounds.height() +
      rightBounds.width() * rightBounds.height() - intersection
    return union > 0 ? intersection / union : 0
  }

  private static appendMappedLines(
    output: LocalMappedLine[],
    lines: ComicLocalOcrLine[],
    tile: LocalOcrTile,
    tileIndex: number,
    sourceWidth: number,
    sourceHeight: number,
  ): void {
    for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex++) {
      if (output.length >= LOCAL_MAX_BLOCKS * 2) {
        throw new Error('Local comic OCR candidate count exceeds its boundary')
      }
      const source: ComicLocalOcrLine = lines[lineIndex]
      const text: string = source.text.trim()
      // A single glyph from system OCR is usually a furigana/SFX fragment or a false positive.
      // Until the manga detector can classify these regions, leaving the artwork untouched is
      // safer than covering a large area with a low-confidence translation.
      if (text.length < 2 || text.length > LOCAL_MAX_SOURCE_TEXT_CHARS ||
        source.polygon.length < 3 || source.polygon.length > 64) {
        continue
      }
      const mapped: LocalMappedLine = new LocalMappedLine()
      mapped.text = text
      mapped.tileIndex = tileIndex
      mapped.blockIndex = source.blockIndex
      mapped.lineIndex = source.lineIndex
      for (let pointIndex: number = 0; pointIndex < source.polygon.length; pointIndex++) {
        const point: ComicLocalOcrPoint = source.polygon[pointIndex]
        const x: number = Math.max(0, Math.min(sourceWidth, point.x + tile.x))
        const y: number = Math.max(0, Math.min(sourceHeight, point.y + tile.y))
        mapped.polygon.push(new ComicPoint(x, y))
      }
      output.push(mapped)
    }
  }

  private static deduplicate(values: LocalMappedLine[]): LocalMappedLine[] {
    const output: LocalMappedLine[] = []
    for (let index: number = 0; index < values.length; index++) {
      const candidate: LocalMappedLine = values[index]
      let duplicate: boolean = false
      for (let acceptedIndex: number = 0; acceptedIndex < output.length; acceptedIndex++) {
        if (ComicLocalVisualBackend.sameLine(candidate, output[acceptedIndex])) {
          duplicate = true
          break
        }
      }
      if (!duplicate) {
        output.push(candidate)
      }
      if (output.length > LOCAL_MAX_BLOCKS) {
        throw new Error('Local comic OCR block count exceeds its boundary')
      }
    }
    output.sort((left: LocalMappedLine, right: LocalMappedLine): number => {
      const leftRect: LocalRenderRect = ComicLocalVisualBackend.bounds(left.polygon)
      const rightRect: LocalRenderRect = ComicLocalVisualBackend.bounds(right.polygon)
      const verticalDelta: number = leftRect.top - rightRect.top
      if (Math.abs(verticalDelta) > 12) {
        return verticalDelta
      }
      return rightRect.right - leftRect.right
    })
    return output
  }

  private static sameLine(left: LocalMappedLine, right: LocalMappedLine): boolean {
    if (left.text.replace(/\s+/g, '') !== right.text.replace(/\s+/g, '')) {
      return false
    }
    const leftRect: LocalRenderRect = ComicLocalVisualBackend.bounds(left.polygon)
    const rightRect: LocalRenderRect = ComicLocalVisualBackend.bounds(right.polygon)
    const leftCenterX: number = (leftRect.left + leftRect.right) / 2
    const leftCenterY: number = (leftRect.top + leftRect.bottom) / 2
    const rightCenterX: number = (rightRect.left + rightRect.right) / 2
    const rightCenterY: number = (rightRect.top + rightRect.bottom) / 2
    return Math.abs(leftCenterX - rightCenterX) <= LOCAL_OCR_TILE_OVERLAP &&
      Math.abs(leftCenterY - rightCenterY) <= LOCAL_OCR_TILE_OVERLAP
  }

  private static suppressFurigana(values: LocalMappedLine[]): LocalMappedLine[] {
    const output: LocalMappedLine[] = []
    for (let index: number = 0; index < values.length; index++) {
      const candidate: LocalMappedLine = values[index]
      if (!ComicLocalVisualBackend.isFurigana(candidate, values, index)) {
        output.push(candidate)
      }
    }
    return output
  }

  private static assignDetectorRegions(
    values: LocalMappedLine[],
    detection: ComicNativeRegionDetectionResult | null,
  ): void {
    if (detection === null) {
      return
    }
    for (let lineIndex: number = 0; lineIndex < values.length; lineIndex++) {
      const rect: LocalRenderRect = ComicLocalVisualBackend.bounds(values[lineIndex].polygon)
      const centerX: number = (rect.left + rect.right) / 2
      const centerY: number = (rect.top + rect.bottom) / 2
      let selected: number = -1
      let selectedArea: number = Number.POSITIVE_INFINITY
      for (let regionIndex: number = 0;
        regionIndex < detection.regions.length; regionIndex++) {
        const region: ComicNativeDetectedRegion = detection.regions[regionIndex]
        if (!ComicLocalVisualBackend.regionContains(region, centerX, centerY)) {
          continue
        }
        const area: number = ComicLocalVisualBackend.regionArea(region)
        if (area < selectedArea) {
          selected = regionIndex
          selectedArea = area
        }
      }
      values[lineIndex].detectorRegionIndex = selected
    }
  }

  private static regionContains(
    region: ComicNativeDetectedRegion,
    x: number,
    y: number,
  ): boolean {
    if (region.points.length < 3) {
      return false
    }
    let inside: boolean = false
    for (let current: number = 0, previous: number = region.points.length - 1;
      current < region.points.length; previous = current++) {
      const currentPoint = region.points[current]
      const previousPoint = region.points[previous]
      const crosses: boolean = (currentPoint.y > y) !== (previousPoint.y > y) &&
        x < (previousPoint.x - currentPoint.x) * (y - currentPoint.y) /
          (previousPoint.y - currentPoint.y) + currentPoint.x
      if (crosses) {
        inside = !inside
      }
    }
    return inside
  }

  private static regionArea(region: ComicNativeDetectedRegion): number {
    let doubled: number = 0
    for (let index: number = 0; index < region.points.length; index++) {
      const next: number = (index + 1) % region.points.length
      doubled += region.points[index].x * region.points[next].y -
        region.points[next].x * region.points[index].y
    }
    return Math.max(1, Math.abs(doubled) / 2)
  }

  private static detectedRegionBounds(
    region: ComicNativeDetectedRegion,
    sourceWidth: number,
    sourceHeight: number,
  ): LocalRenderRect {
    const rect: LocalRenderRect = new LocalRenderRect()
    rect.left = sourceWidth
    rect.top = sourceHeight
    rect.right = 0
    rect.bottom = 0
    for (let index: number = 0; index < region.points.length; index++) {
      rect.left = Math.min(rect.left, region.points[index].x)
      rect.top = Math.min(rect.top, region.points[index].y)
      rect.right = Math.max(rect.right, region.points[index].x)
      rect.bottom = Math.max(rect.bottom, region.points[index].y)
    }
    rect.left = Math.max(0, Math.floor(rect.left))
    rect.top = Math.max(0, Math.floor(rect.top))
    rect.right = Math.min(sourceWidth, Math.ceil(rect.right))
    rect.bottom = Math.min(sourceHeight, Math.ceil(rect.bottom))
    return rect
  }

  private static isFurigana(
    candidate: LocalMappedLine,
    values: LocalMappedLine[],
    candidateIndex: number,
  ): boolean {
    if (candidate.text.length > 4 || !/^[\u3041-\u3096ー]+$/.test(candidate.text)) {
      return false
    }
    const candidateRect: LocalRenderRect = ComicLocalVisualBackend.bounds(candidate.polygon)
    const candidateArea: number = candidateRect.width() * candidateRect.height()
    const candidateCenterX: number = (candidateRect.left + candidateRect.right) / 2
    const candidateCenterY: number = (candidateRect.top + candidateRect.bottom) / 2
    for (let index: number = 0; index < values.length; index++) {
      if (index === candidateIndex || values[index].tileIndex !== candidate.tileIndex) {
        continue
      }
      const neighborRect: LocalRenderRect = ComicLocalVisualBackend.bounds(values[index].polygon)
      const neighborArea: number = neighborRect.width() * neighborRect.height()
      const neighborCenterX: number = (neighborRect.left + neighborRect.right) / 2
      const neighborCenterY: number = (neighborRect.top + neighborRect.bottom) / 2
      const nearX: boolean = Math.abs(candidateCenterX - neighborCenterX) <=
        Math.max(28, neighborRect.width() * 0.9)
      const nearY: boolean = Math.abs(candidateCenterY - neighborCenterY) <=
        Math.max(32, neighborRect.height() * 0.7)
      if (neighborArea >= candidateArea * 2.8 && nearX && nearY) {
        return true
      }
    }
    return false
  }

  private static groupLines(values: LocalMappedLine[]): LocalMappedBlock[] {
    const groups: LocalMappedLine[][] = []
    const tileIndexes: number[] = []
    const blockIndexes: number[] = []
    const detectorRegionIndexes: number[] = []
    for (let index: number = 0; index < values.length; index++) {
      const value: LocalMappedLine = values[index]
      let groupIndex: number = -1
      for (let candidateIndex: number = 0; candidateIndex < groups.length; candidateIndex++) {
        const sameDetectorRegion: boolean = value.detectorRegionIndex >= 0 &&
          detectorRegionIndexes[candidateIndex] === value.detectorRegionIndex
        const sameOcrBlock: boolean = value.detectorRegionIndex < 0 &&
          detectorRegionIndexes[candidateIndex] < 0 &&
          tileIndexes[candidateIndex] === value.tileIndex &&
          blockIndexes[candidateIndex] === value.blockIndex
        if (sameDetectorRegion || sameOcrBlock) {
          groupIndex = candidateIndex
          break
        }
      }
      if (groupIndex < 0) {
        groups.push([])
        tileIndexes.push(value.tileIndex)
        blockIndexes.push(value.blockIndex)
        detectorRegionIndexes.push(value.detectorRegionIndex)
        groupIndex = groups.length - 1
      }
      groups[groupIndex].push(value)
    }
    const grouped: LocalMappedBlock[] = []
    for (let index: number = 0; index < groups.length; index++) {
      if (groups[index].length <= 0) {
        continue
      }
      grouped.push(ComicLocalVisualBackend.group(groups[index]))
    }
    const verticalMerged: LocalMappedBlock[] =
      ComicLocalVisualBackend.mergeAdjacentVerticalBlocks(grouped)
    const output: LocalMappedBlock[] =
      ComicLocalVisualBackend.mergeAdjacentHorizontalBlocks(verticalMerged)
    output.sort((left: LocalMappedBlock, right: LocalMappedBlock): number => {
      const leftRect: LocalRenderRect = ComicLocalVisualBackend.bounds(left.polygon)
      const rightRect: LocalRenderRect = ComicLocalVisualBackend.bounds(right.polygon)
      const verticalDelta: number = leftRect.top - rightRect.top
      if (Math.abs(verticalDelta) > 12) {
        return verticalDelta
      }
      return rightRect.right - leftRect.right
    })
    return output
  }

  private static group(lines: LocalMappedLine[]): LocalMappedBlock {
    let verticalVotes: number = 0
    for (let index: number = 0; index < lines.length; index++) {
      const rect: LocalRenderRect = ComicLocalVisualBackend.bounds(lines[index].polygon)
      if (rect.height() > rect.width() * 1.15) {
        verticalVotes = verticalVotes + 1
      }
    }
    const vertical: boolean = verticalVotes * 2 >= lines.length
    lines.sort((left: LocalMappedLine, right: LocalMappedLine): number => {
      const leftRect: LocalRenderRect = ComicLocalVisualBackend.bounds(left.polygon)
      const rightRect: LocalRenderRect = ComicLocalVisualBackend.bounds(right.polygon)
      if (vertical) {
        const horizontalDelta: number = rightRect.right - leftRect.right
        if (Math.abs(horizontalDelta) > 8) {
          return horizontalDelta
        }
        return leftRect.top - rightRect.top
      }
      const verticalDelta: number = leftRect.top - rightRect.top
      if (Math.abs(verticalDelta) > 8) {
        return verticalDelta
      }
      return leftRect.left - rightRect.left
    })
    const block: LocalMappedBlock = new LocalMappedBlock()
    block.styleHint = vertical ? LOCAL_VERTICAL_STYLE_HINT : LOCAL_HORIZONTAL_STYLE_HINT
    block.tileIndex = lines[0].tileIndex
    block.detectorRegionIndex = lines[0].detectorRegionIndex
    const textParts: string[] = []
    let left: number = Number.POSITIVE_INFINITY
    let top: number = Number.POSITIVE_INFINITY
    let right: number = Number.NEGATIVE_INFINITY
    let bottom: number = Number.NEGATIVE_INFINITY
    for (let index: number = 0; index < lines.length; index++) {
      const rect: LocalRenderRect = ComicLocalVisualBackend.bounds(lines[index].polygon)
      left = Math.min(left, rect.left)
      top = Math.min(top, rect.top)
      right = Math.max(right, rect.right)
      bottom = Math.max(bottom, rect.bottom)
      textParts.push(lines[index].text)
    }
    block.text = textParts.join(vertical ? '' : '\n')
    block.polygon.push(new ComicPoint(left, top))
    block.polygon.push(new ComicPoint(right, top))
    block.polygon.push(new ComicPoint(right, bottom))
    block.polygon.push(new ComicPoint(left, bottom))
    return block
  }

  private static mergeAdjacentVerticalBlocks(values: LocalMappedBlock[]): LocalMappedBlock[] {
    const working: LocalMappedBlock[] = values.slice()
    let changed: boolean = true
    while (changed) {
      changed = false
      for (let leftIndex: number = 0; leftIndex < working.length; leftIndex++) {
        for (let rightIndex: number = leftIndex + 1; rightIndex < working.length; rightIndex++) {
          if (!ComicLocalVisualBackend.shouldMergeVerticalBlocks(
            working[leftIndex],
            working[rightIndex],
          )) {
            continue
          }
          working[leftIndex] = ComicLocalVisualBackend.mergeVerticalBlocks(
            working[leftIndex],
            working[rightIndex],
          )
          working.splice(rightIndex, 1)
          changed = true
          break
        }
        if (changed) {
          break
        }
      }
    }
    return working
  }

  private static shouldMergeVerticalBlocks(
    first: LocalMappedBlock,
    second: LocalMappedBlock,
  ): boolean {
    if (first.styleHint !== LOCAL_VERTICAL_STYLE_HINT ||
      second.styleHint !== LOCAL_VERTICAL_STYLE_HINT || first.tileIndex !== second.tileIndex) {
      return false
    }
    if (first.detectorRegionIndex !== second.detectorRegionIndex &&
      (first.detectorRegionIndex >= 0 || second.detectorRegionIndex >= 0)) {
      return false
    }
    const firstRect: LocalRenderRect = ComicLocalVisualBackend.bounds(first.polygon)
    const secondRect: LocalRenderRect = ComicLocalVisualBackend.bounds(second.polygon)
    const rightRect: LocalRenderRect = firstRect.left >= secondRect.left ? firstRect : secondRect
    const leftRect: LocalRenderRect = firstRect.left >= secondRect.left ? secondRect : firstRect
    const horizontalGap: number = rightRect.left - leftRect.right
    const maximumGap: number = Math.max(firstRect.width(), secondRect.width()) * 0.55
    if (horizontalGap < -Math.min(firstRect.width(), secondRect.width()) * 0.28 ||
      horizontalGap > maximumGap) {
      return false
    }
    const overlap: number = Math.min(firstRect.bottom, secondRect.bottom) -
      Math.max(firstRect.top, secondRect.top)
    const overlapRatio: number = overlap / Math.max(
      1,
      Math.min(firstRect.height(), secondRect.height()),
    )
    const firstCenterY: number = (firstRect.top + firstRect.bottom) / 2
    const secondCenterY: number = (secondRect.top + secondRect.bottom) / 2
    const topAligned: boolean = Math.abs(firstRect.top - secondRect.top) <= Math.max(
      12,
      Math.min(firstRect.height(), secondRect.height()) * 0.2,
    )
    const centerAligned: boolean = Math.abs(firstCenterY - secondCenterY) <=
      Math.max(firstRect.height(), secondRect.height()) * 0.32
    return overlapRatio >= 0.62 && (topAligned || centerAligned)
  }

  private static mergeVerticalBlocks(
    first: LocalMappedBlock,
    second: LocalMappedBlock,
  ): LocalMappedBlock {
    const firstRect: LocalRenderRect = ComicLocalVisualBackend.bounds(first.polygon)
    const secondRect: LocalRenderRect = ComicLocalVisualBackend.bounds(second.polygon)
    const right: LocalMappedBlock = firstRect.left >= secondRect.left ? first : second
    const left: LocalMappedBlock = firstRect.left >= secondRect.left ? second : first
    const block: LocalMappedBlock = new LocalMappedBlock()
    block.text = right.text + left.text
    block.styleHint = LOCAL_VERTICAL_STYLE_HINT
    block.tileIndex = first.tileIndex
    block.detectorRegionIndex = first.detectorRegionIndex
    const leftEdge: number = Math.min(firstRect.left, secondRect.left)
    const topEdge: number = Math.min(firstRect.top, secondRect.top)
    const rightEdge: number = Math.max(firstRect.right, secondRect.right)
    const bottomEdge: number = Math.max(firstRect.bottom, secondRect.bottom)
    block.polygon.push(new ComicPoint(leftEdge, topEdge))
    block.polygon.push(new ComicPoint(rightEdge, topEdge))
    block.polygon.push(new ComicPoint(rightEdge, bottomEdge))
    block.polygon.push(new ComicPoint(leftEdge, bottomEdge))
    return block
  }

  private static mergeAdjacentHorizontalBlocks(values: LocalMappedBlock[]): LocalMappedBlock[] {
    const working: LocalMappedBlock[] = values.slice()
    let changed: boolean = true
    while (changed) {
      changed = false
      for (let firstIndex: number = 0; firstIndex < working.length; firstIndex++) {
        for (let secondIndex: number = firstIndex + 1;
          secondIndex < working.length; secondIndex++) {
          if (!ComicLocalVisualBackend.shouldMergeHorizontalBlocks(
            working[firstIndex],
            working[secondIndex],
          )) {
            continue
          }
          working[firstIndex] = ComicLocalVisualBackend.mergeHorizontalBlocks(
            working[firstIndex],
            working[secondIndex],
          )
          working.splice(secondIndex, 1)
          changed = true
          break
        }
        if (changed) {
          break
        }
      }
    }
    return working
  }

  private static shouldMergeHorizontalBlocks(
    first: LocalMappedBlock,
    second: LocalMappedBlock,
  ): boolean {
    if (first.styleHint !== LOCAL_HORIZONTAL_STYLE_HINT ||
      second.styleHint !== LOCAL_HORIZONTAL_STYLE_HINT || first.tileIndex !== second.tileIndex) {
      return false
    }
    if (first.detectorRegionIndex !== second.detectorRegionIndex &&
      (first.detectorRegionIndex >= 0 || second.detectorRegionIndex >= 0)) {
      return false
    }
    const firstRect: LocalRenderRect = ComicLocalVisualBackend.bounds(first.polygon)
    const secondRect: LocalRenderRect = ComicLocalVisualBackend.bounds(second.polygon)
    const upperRect: LocalRenderRect = firstRect.top <= secondRect.top ? firstRect : secondRect
    const lowerRect: LocalRenderRect = firstRect.top <= secondRect.top ? secondRect : firstRect
    const verticalGap: number = lowerRect.top - upperRect.bottom
    if (verticalGap < -Math.min(firstRect.height(), secondRect.height()) * 0.28 ||
      verticalGap > Math.max(firstRect.height(), secondRect.height()) * 0.55) {
      return false
    }
    const overlap: number = Math.min(firstRect.right, secondRect.right) -
      Math.max(firstRect.left, secondRect.left)
    const overlapRatio: number = overlap / Math.max(
      1,
      Math.min(firstRect.width(), secondRect.width()),
    )
    const firstCenterX: number = (firstRect.left + firstRect.right) / 2
    const secondCenterX: number = (secondRect.left + secondRect.right) / 2
    return overlapRatio >= 0.62 && Math.abs(firstCenterX - secondCenterX) <=
      Math.max(firstRect.width(), secondRect.width()) * 0.36
  }

  private static mergeHorizontalBlocks(
    first: LocalMappedBlock,
    second: LocalMappedBlock,
  ): LocalMappedBlock {
    const firstRect: LocalRenderRect = ComicLocalVisualBackend.bounds(first.polygon)
    const secondRect: LocalRenderRect = ComicLocalVisualBackend.bounds(second.polygon)
    const upper: LocalMappedBlock = firstRect.top <= secondRect.top ? first : second
    const lower: LocalMappedBlock = firstRect.top <= secondRect.top ? second : first
    const block: LocalMappedBlock = new LocalMappedBlock()
    block.text = upper.text + '\n' + lower.text
    block.styleHint = LOCAL_HORIZONTAL_STYLE_HINT
    block.tileIndex = first.tileIndex
    block.detectorRegionIndex = first.detectorRegionIndex
    const leftEdge: number = Math.min(firstRect.left, secondRect.left)
    const topEdge: number = Math.min(firstRect.top, secondRect.top)
    const rightEdge: number = Math.max(firstRect.right, secondRect.right)
    const bottomEdge: number = Math.max(firstRect.bottom, secondRect.bottom)
    block.polygon.push(new ComicPoint(leftEdge, topEdge))
    block.polygon.push(new ComicPoint(rightEdge, topEdge))
    block.polygon.push(new ComicPoint(rightEdge, bottomEdge))
    block.polygon.push(new ComicPoint(leftEdge, bottomEdge))
    return block
  }

  private static document(
    request: ComicRegionAnalysisRequest,
    lines: LocalMappedBlock[],
    tileCount: number,
    profileId: string,
    detectorUsed: boolean,
    supplementalCount: number,
  ): ComicPageDocument {
    const document: ComicPageDocument = new ComicPageDocument()
    document.projectId = request.source.projectId
    document.pageIndex = request.source.pageIndex
    document.imageHash = request.source.imageHash
    document.imageWidth = request.source.imageWidth
    document.imageHeight = request.source.imageHeight
    document.imagePreparationProfile.profileId = profileId
    document.imagePreparationProfile.mimeType = 'image/rgba8888'
    document.imagePreparationProfile.preparedWidth = request.source.imageWidth
    document.imagePreparationProfile.preparedHeight = request.source.imageHeight
    document.imagePreparationProfile.tileCount = tileCount
    document.analysisRevision = request.requestedDocumentRevision
    document.translationRevision = 0
    document.renderRevision = 0
    document.analysisState = ComicAnalysisState.READY
    document.translationState = ComicTranslationState.MISSING
    document.renderState = ComicRenderState.UNAVAILABLE
    document.hasText = lines.length > 0
    for (let index: number = 0; index < lines.length; index++) {
      const block: ComicTextBlock = new ComicTextBlock()
      block.blockId = `p${request.source.pageIndex}-local-${index + 1}`
      block.readingOrder = index
      block.kind = ComicTextKind.OTHER
      block.sourceText = lines[index].text
      block.normalizedSourceText = lines[index].text.replace(/\s+/g, ' ').trim()
      block.polygon = lines[index].polygon
      block.styleHint = lines[index].styleHint
      block.sourceOrigin = ComicSourceOrigin.OCR
      block.sourceRevision = request.requestedDocumentRevision
      document.blocks.push(block)
    }
    const signal: ComicQualitySignal = new ComicQualitySignal()
    signal.code = 'local_system_ocr_requires_visual_review'
    signal.severity = ComicQualitySeverity.WARNING
    signal.message = 'System OCR can miss stylized text; local output requires visual review.'
    document.qualitySignals.push(signal)
    if (detectorUsed) {
      const detectorSignal: ComicQualitySignal = new ComicQualitySignal()
      detectorSignal.code = 'local_manga_region_detector_active'
      detectorSignal.severity = ComicQualitySeverity.INFO
      detectorSignal.message = 'Manga region detection grouped OCR lines before translation.'
      document.qualitySignals.push(detectorSignal)
    }
    if (supplementalCount > 0) {
      const recognizerSignal: ComicQualitySignal = new ComicQualitySignal()
      recognizerSignal.code = 'local_manga_text_recognizer_supplemented'
      recognizerSignal.severity = ComicQualitySeverity.INFO
      recognizerSignal.message =
        `Manga text recognition recovered ${supplementalCount} system OCR miss(es).`
      document.qualitySignals.push(recognizerSignal)
    }
    return document
  }

  private static template(
    request: ComicRegionAnalysisRequest,
    document: ComicPageDocument,
    profileId: string,
    protocolRevision: number,
  ): ComicBackendTemplate {
    const envelope: LocalTemplateEnvelope = new LocalTemplateEnvelope()
    envelope.sourceImageHash = request.source.imageHash
    envelope.profileId = profileId
    envelope.width = request.source.imageWidth
    envelope.height = request.source.imageHeight
    for (let index: number = 0; index < document.blocks.length; index++) {
      const source: ComicTextBlock = document.blocks[index]
      const block: LocalTemplateBlock = new LocalTemplateBlock()
      block.blockId = source.blockId
      for (let pointIndex: number = 0; pointIndex < source.polygon.length; pointIndex++) {
        const point: LocalTemplatePoint = new LocalTemplatePoint()
        point.x = source.polygon[pointIndex].x
        point.y = source.polygon[pointIndex].y
        block.polygon.push(point)
      }
      envelope.blocks.push(block)
    }
    const payload: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify(envelope))
    const template: ComicBackendTemplate = new ComicBackendTemplate()
    template.backendId = LOCAL_VISUAL_BACKEND_ID
    template.profileId = profileId
    template.protocolRevision = protocolRevision
    template.contentHash = ComicLocalVisualBackend.sha256(payload)
    template.mimeType = LOCAL_TEMPLATE_MIME
    template.payload = payload
    return template
  }

  private validateTemplate(request: ComicRegionRenderRequest): void {
    if (request.adapterTemplate.backendId !== LOCAL_VISUAL_BACKEND_ID ||
      request.adapterTemplate.profileId !== this.profileId() ||
      request.adapterTemplate.protocolRevision !== this.protocolRevision() ||
      request.adapterTemplate.mimeType !== LOCAL_TEMPLATE_MIME ||
      request.adapterTemplate.contentHash !==
        ComicLocalVisualBackend.sha256(request.adapterTemplate.payload)) {
      throw new Error('Local comic render template identity is invalid')
    }
    let envelope: LocalTemplateEnvelope
    try {
      envelope = JSON.parse(
        new util.TextDecoder().decodeToString(request.adapterTemplate.payload),
      ) as LocalTemplateEnvelope
    } catch (_error) {
      throw new Error('Local comic render template is invalid JSON')
    }
    if (envelope.schemaVersion !== 1 || envelope.backendId !== LOCAL_VISUAL_BACKEND_ID ||
      envelope.profileId !== this.profileId() ||
      envelope.sourceImageHash !== request.source.imageHash ||
      envelope.width !== request.source.imageWidth ||
      envelope.height !== request.source.imageHeight ||
      envelope.blocks.length !== request.document.blocks.length) {
      throw new Error('Local comic render template does not match the request')
    }
    for (let index: number = 0; index < envelope.blocks.length; index++) {
      if (envelope.blocks[index].blockId !== request.document.blocks[index].blockId) {
        throw new Error('Local comic render template block order is invalid')
      }
    }
  }

  private static drawBlock(
    canvas: drawing.Canvas,
    block: ComicTextBlock,
    translatedText: string,
    imageWidth: number,
    imageHeight: number,
    fill: LocalFillStyle,
    verticalFontCap: number,
  ): void {
    const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
    const rect: LocalRenderRect = ComicLocalVisualBackend.sourceTreatmentRect(
      raw,
      imageWidth,
      imageHeight,
      block.styleHint,
    )
    const horizontalPadding: number = Math.max(4, Math.min(12, rect.width() * 0.08))
    const verticalPadding: number = Math.max(4, Math.min(10, rect.height() * 0.08))
    const contentWidth: number = Math.max(1, rect.width() - horizontalPadding * 2)
    const contentHeight: number = Math.max(1, rect.height() - verticalPadding * 2)
    const font: drawing.Font = new drawing.Font()
    font.enableSubpixel(true)
    const textBrush: drawing.Brush = new drawing.Brush()
    textBrush.setColor(255, fill.textRed, fill.textGreen, fill.textBlue)
    canvas.attachBrush(textBrush)
    if (block.styleHint === LOCAL_VERTICAL_STYLE_HINT) {
      ComicLocalVisualBackend.drawVerticalText(
        canvas,
        translatedText,
        rect,
        horizontalPadding,
        verticalPadding,
        contentWidth,
        contentHeight,
        font,
        verticalFontCap,
      )
      canvas.detachBrush()
      return
    }
    const layout: LocalTextLayout = ComicLocalVisualBackend.layout(
      translatedText,
      contentWidth,
      contentHeight,
      font,
    )
    font.setSize(layout.fontSize)
    const lineHeight: number = layout.fontSize * 1.18
    const totalHeight: number = layout.lines.length * lineHeight
    const metrics: drawing.FontMetrics = font.getMetrics()
    let baseline: number = rect.top + verticalPadding +
      Math.max(0, (contentHeight - totalHeight) / 2) - metrics.ascent
    for (let index: number = 0; index < layout.lines.length; index++) {
      const line: string = layout.lines[index]
      const width: number = font.measureText(line, drawing.TextEncoding.TEXT_ENCODING_UTF8)
      const x: number = rect.left + horizontalPadding + Math.max(0, (contentWidth - width) / 2)
      canvas.drawTextBlob(drawing.TextBlob.makeFromString(line, font), x, baseline)
      baseline += lineHeight
    }
    canvas.detachBrush()
  }

  private static verticalPageFontCap(
    document: ComicPageDocument,
    translations: Map<string, string>,
    imageWidth: number,
    imageHeight: number,
  ): number {
    const fittedSizes: number[] = []
    const font: drawing.Font = new drawing.Font()
    font.enableSubpixel(true)
    for (let index: number = 0; index < document.blocks.length; index++) {
      const block: ComicTextBlock = document.blocks[index]
      if (block.styleHint !== LOCAL_VERTICAL_STYLE_HINT) {
        continue
      }
      const translated: string | undefined = translations.get(block.blockId)
      if (translated === undefined || translated.trim().length <= 0) {
        continue
      }
      const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
      const rect: LocalRenderRect = ComicLocalVisualBackend.sourceTreatmentRect(
        raw,
        imageWidth,
        imageHeight,
        block.styleHint,
      )
      const horizontalPadding: number = Math.max(4, Math.min(12, rect.width() * 0.08))
      const verticalPadding: number = Math.max(4, Math.min(10, rect.height() * 0.08))
      const contentWidth: number = Math.max(1, rect.width() - horizontalPadding * 2)
      const contentHeight: number = Math.max(1, rect.height() - verticalPadding * 2)
      const layout: LocalVerticalTextLayout = ComicLocalVisualBackend.verticalLayout(
        translated.trim(),
        contentWidth,
        contentHeight,
        font,
        LOCAL_MAX_FONT_SIZE,
      )
      fittedSizes.push(layout.fontSize)
    }
    if (fittedSizes.length <= 1) {
      return LOCAL_MAX_FONT_SIZE
    }
    fittedSizes.sort((left: number, right: number): number => left - right)
    return fittedSizes[Math.floor((fittedSizes.length - 1) / 2)]
  }

  private static sourceTreatmentRect(
    raw: LocalRenderRect,
    imageWidth: number,
    imageHeight: number,
    styleHint: string,
  ): LocalRenderRect {
    const rawWidth: number = Math.max(1, raw.width())
    const rawHeight: number = Math.max(1, raw.height())
    const verticalTargetWidth: number = Math.min(
      140,
      Math.max(rawWidth + 40, rawWidth * 2),
    )
    const verticalExtraWidth: number = Math.max(0, verticalTargetWidth - rawWidth)
    const horizontalTargetWidth: number = Math.min(
      360,
      Math.max(rawWidth + 40, rawWidth * 1.35),
    )
    const horizontalExtraWidth: number = Math.max(0, horizontalTargetWidth - rawWidth)
    const horizontalTargetHeight: number = Math.min(
      180,
      Math.max(rawHeight + 24, rawHeight * 1.35),
    )
    const horizontalExtraHeight: number = Math.max(0, horizontalTargetHeight - rawHeight)
    const leftPadding: number = styleHint === LOCAL_VERTICAL_STYLE_HINT ?
      verticalExtraWidth * 0.58 : horizontalExtraWidth / 2
    const rightPadding: number = styleHint === LOCAL_VERTICAL_STYLE_HINT ?
      verticalExtraWidth - leftPadding : horizontalExtraWidth / 2
    const topPadding: number = styleHint === LOCAL_VERTICAL_STYLE_HINT ?
      Math.max(2, Math.min(8, rawHeight * 0.05)) : horizontalExtraHeight / 2
    const bottomPadding: number = styleHint === LOCAL_VERTICAL_STYLE_HINT ?
      Math.max(2, Math.min(8, rawHeight * 0.05)) : horizontalExtraHeight / 2
    const rect: LocalRenderRect = new LocalRenderRect()
    rect.left = Math.max(0, raw.left - leftPadding)
    rect.top = Math.max(0, raw.top - topPadding)
    rect.right = Math.min(imageWidth, raw.right + rightPadding)
    rect.bottom = Math.min(imageHeight, raw.bottom + bottomPadding)
    return rect
  }

  private static async sampleFillStyle(
    pixelMap: image.PixelMap,
    imageWidth: number,
    imageHeight: number,
    treatment: LocalRenderRect,
  ): Promise<LocalFillStyle> {
    const samples: LocalColorSample[] = []
    const desiredWidth: number = Math.max(1, Math.ceil(treatment.width() + 8))
    const desiredHeight: number = Math.max(1, Math.ceil(treatment.height() + 8))
    const sampleWidth: number = Math.min(256, imageWidth, desiredWidth)
    const sampleHeight: number = Math.min(256, imageHeight, desiredHeight)
    const centerX: number = (treatment.left + treatment.right) / 2
    const centerY: number = (treatment.top + treatment.bottom) / 2
    const left: number = Math.max(
      0,
      Math.min(imageWidth - sampleWidth, Math.floor(centerX - sampleWidth / 2)),
    )
    const top: number = Math.max(
      0,
      Math.min(imageHeight - sampleHeight, Math.floor(centerY - sampleHeight / 2)),
    )
    const rowBytes: number = sampleWidth * 4
    const buffer: ArrayBuffer = new ArrayBuffer(rowBytes * sampleHeight)
    const area: image.PositionArea = {
      pixels: buffer,
      offset: 0,
      stride: rowBytes,
      region: {
        x: left,
        y: top,
        size: { width: sampleWidth, height: sampleHeight },
      },
    }
    await pixelMap.readPixels(area)
    const sourcePixels: Uint8Array = new Uint8Array(buffer)
    for (let y: number = 0; y < sampleHeight; y += 2) {
      for (let x: number = 0; x < sampleWidth; x += 2) {
        const offset: number = y * rowBytes + x * 4
        // PixelMap.readPixels returns BGRA_8888 regardless of the source pixel format.
        const sample: LocalColorSample = new LocalColorSample()
        sample.blue = sourcePixels[offset]
        sample.green = sourcePixels[offset + 1]
        sample.red = sourcePixels[offset + 2]
        sample.luminance = sample.red * 0.299 + sample.green * 0.587 + sample.blue * 0.114
        samples.push(sample)
      }
    }
    const style: LocalFillStyle = new LocalFillStyle()
    if (samples.length <= 0) {
      return style
    }
    samples.sort((leftValue: LocalColorSample, rightValue: LocalColorSample): number =>
      leftValue.luminance - rightValue.luminance)
    // Source glyphs are sparse inside their bounding rectangle. The upper-middle local
    // quartile rejects those dark strokes while retaining a dark fill for inverse text.
    const backgroundIndex: number = Math.min(
      samples.length - 1,
      Math.floor(samples.length * 0.72),
    )
    style.red = samples[backgroundIndex].red
    style.green = samples[backgroundIndex].green
    style.blue = samples[backgroundIndex].blue
    if (samples[backgroundIndex].luminance < 128) {
      style.textRed = 245
      style.textGreen = 245
      style.textBlue = 245
    }
    return style
  }

  private static async eraseSourceRegion(
    pixelMap: image.PixelMap,
    imageWidth: number,
    imageHeight: number,
    raw: LocalRenderRect,
    treatment: LocalRenderRect,
    background: LocalFillStyle,
    styleHint: string,
  ): Promise<void> {
    const treatmentLeft: number = Math.max(0, Math.floor(treatment.left))
    const treatmentTop: number = Math.max(0, Math.floor(treatment.top))
    const treatmentRight: number = Math.min(imageWidth, Math.ceil(treatment.right))
    const treatmentBottom: number = Math.min(imageHeight, Math.ceil(treatment.bottom))
    if (treatmentRight <= treatmentLeft || treatmentBottom <= treatmentTop) {
      return
    }
    const border: number = 6
    const outerLeft: number = Math.max(0, treatmentLeft - border)
    const outerTop: number = Math.max(0, treatmentTop - border)
    const outerRight: number = Math.min(imageWidth, treatmentRight + border)
    const outerBottom: number = Math.min(imageHeight, treatmentBottom + border)
    const width: number = outerRight - outerLeft
    const height: number = outerBottom - outerTop
    if (width <= 1 || height <= 1) {
      return
    }
    const rowBytes: number = width * 4
    const buffer: ArrayBuffer = new ArrayBuffer(rowBytes * height)
    const area: image.PositionArea = {
      pixels: buffer,
      offset: 0,
      stride: rowBytes,
      region: {
        x: outerLeft,
        y: outerTop,
        size: { width: width, height: height },
      },
    }
    await pixelMap.readPixels(area)
    const pixels: Uint8Array = new Uint8Array(buffer)
    const mask: Uint8Array = new Uint8Array(width * height)
    const rawLeft: number = Math.max(treatmentLeft, Math.floor(raw.left))
    const rawTop: number = Math.max(treatmentTop, Math.floor(raw.top))
    const rawRight: number = styleHint === LOCAL_VERTICAL_STYLE_HINT ?
      Math.min(
        treatmentRight,
        Math.ceil(raw.right + Math.max(8, Math.min(18, raw.width() * 0.25))),
      ) : Math.min(treatmentRight, Math.ceil(raw.right))
    const rawBottom: number = Math.min(treatmentBottom, Math.ceil(raw.bottom))
    const backgroundLuminance: number = background.red * 0.299 +
      background.green * 0.587 + background.blue * 0.114
    let masked: number = 0
    for (let globalY: number = rawTop; globalY < rawBottom; globalY++) {
      const y: number = globalY - outerTop
      for (let globalX: number = rawLeft; globalX < rawRight; globalX++) {
        const x: number = globalX - outerLeft
        const offset: number = y * rowBytes + x * 4
        const blue: number = pixels[offset]
        const green: number = pixels[offset + 1]
        const red: number = pixels[offset + 2]
        const luminance: number = red * 0.299 + green * 0.587 + blue * 0.114
        const colorDelta: number = Math.max(
          Math.abs(red - background.red),
          Math.abs(green - background.green),
          Math.abs(blue - background.blue),
        )
        if (Math.abs(luminance - backgroundLuminance) >= 36 && colorDelta >= 44) {
          mask[y * width + x] = 1
          masked = masked + 1
        }
      }
    }
    if (masked <= 0) {
      return
    }
    for (let dilation: number = 0; dilation < 2; dilation++) {
      const expanded: Uint8Array = new Uint8Array(mask)
      for (let y: number = 1; y < height - 1; y++) {
        const globalY: number = outerTop + y
        if (globalY < treatmentTop || globalY >= treatmentBottom) {
          continue
        }
        for (let x: number = 1; x < width - 1; x++) {
          const globalX: number = outerLeft + x
          if (globalX < treatmentLeft || globalX >= treatmentRight ||
            mask[y * width + x] === 0) {
            continue
          }
          for (let yOffset: number = -1; yOffset <= 1; yOffset++) {
            for (let xOffset: number = -1; xOffset <= 1; xOffset++) {
              const expandedX: number = x + xOffset
              const expandedY: number = y + yOffset
              const expandedGlobalX: number = outerLeft + expandedX
              const expandedGlobalY: number = outerTop + expandedY
              if (expandedGlobalX >= treatmentLeft && expandedGlobalX < treatmentRight &&
                expandedGlobalY >= treatmentTop && expandedGlobalY < treatmentBottom) {
                expanded[expandedY * width + expandedX] = 1
              }
            }
          }
        }
      }
      mask.set(expanded)
    }
    let remaining: number = 0
    for (let index: number = 0; index < mask.length; index++) {
      if (mask[index] !== 0) {
        remaining = remaining + 1
      }
    }
    const maxPasses: number = Math.min(64, Math.max(width, height))
    for (let pass: number = 0; pass < maxPasses && remaining > 0; pass++) {
      const nextPixels: Uint8Array = new Uint8Array(pixels)
      const nextMask: Uint8Array = new Uint8Array(mask)
      let filled: number = 0
      for (let y: number = 1; y < height - 1; y++) {
        for (let x: number = 1; x < width - 1; x++) {
          const index: number = y * width + x
          if (mask[index] === 0) {
            continue
          }
          let neighbors: number = 0
          let blue: number = 0
          let green: number = 0
          let red: number = 0
          for (let yOffset: number = -1; yOffset <= 1; yOffset++) {
            for (let xOffset: number = -1; xOffset <= 1; xOffset++) {
              if (xOffset === 0 && yOffset === 0) {
                continue
              }
              const neighborIndex: number = (y + yOffset) * width + x + xOffset
              if (mask[neighborIndex] !== 0) {
                continue
              }
              const neighborOffset: number = neighborIndex * 4
              blue = blue + pixels[neighborOffset]
              green = green + pixels[neighborOffset + 1]
              red = red + pixels[neighborOffset + 2]
              neighbors = neighbors + 1
            }
          }
          if (neighbors > 0) {
            const offset: number = index * 4
            nextPixels[offset] = Math.round(blue / neighbors)
            nextPixels[offset + 1] = Math.round(green / neighbors)
            nextPixels[offset + 2] = Math.round(red / neighbors)
            nextMask[index] = 0
            filled = filled + 1
          }
        }
      }
      if (filled <= 0) {
        break
      }
      pixels.set(nextPixels)
      mask.set(nextMask)
      remaining = remaining - filled
    }
    if (remaining > 0) {
      for (let index: number = 0; index < mask.length; index++) {
        if (mask[index] === 0) {
          continue
        }
        const offset: number = index * 4
        pixels[offset] = background.blue
        pixels[offset + 1] = background.green
        pixels[offset + 2] = background.red
      }
    }
    await pixelMap.writePixels(area)
  }

  private static drawVerticalText(
    canvas: drawing.Canvas,
    text: string,
    rect: LocalRenderRect,
    horizontalPadding: number,
    verticalPadding: number,
    contentWidth: number,
    contentHeight: number,
    font: drawing.Font,
    maxFontSize: number,
  ): void {
    const layout: LocalVerticalTextLayout = ComicLocalVisualBackend.verticalLayout(
      text,
      contentWidth,
      contentHeight,
      font,
      maxFontSize,
    )
    font.setSize(layout.fontSize)
    const columnWidth: number = layout.fontSize * 1.16
    const cellHeight: number = layout.fontSize * 1.12
    const totalWidth: number = layout.columns.length * columnWidth
    const right: number = rect.right - horizontalPadding -
      Math.max(0, (contentWidth - totalWidth) / 2)
    const metrics: drawing.FontMetrics = font.getMetrics()
    for (let columnIndex: number = 0; columnIndex < layout.columns.length; columnIndex++) {
      const column: string = layout.columns[columnIndex]
      const totalHeight: number = column.length * cellHeight
      const top: number = rect.top + verticalPadding +
        Math.max(0, (contentHeight - totalHeight) / 2)
      const centerX: number = right - columnWidth * (columnIndex + 0.5)
      for (let rowIndex: number = 0; rowIndex < column.length; rowIndex++) {
        const glyph: string = ComicLocalVisualBackend.verticalGlyph(column.charAt(rowIndex))
        const glyphWidth: number = font.measureText(glyph, drawing.TextEncoding.TEXT_ENCODING_UTF8)
        const x: number = centerX - glyphWidth / 2
        const baseline: number = top + rowIndex * cellHeight - metrics.ascent
        canvas.drawTextBlob(drawing.TextBlob.makeFromString(glyph, font), x, baseline)
      }
    }
  }

  private static verticalLayout(
    text: string,
    width: number,
    height: number,
    font: drawing.Font,
    maxFontSize: number,
  ): LocalVerticalTextLayout {
    const normalized: string = ComicLocalVisualBackend.normalizeVerticalText(text)
    const initialSize: number = Math.max(
      LOCAL_MIN_FONT_SIZE,
      Math.min(LOCAL_MAX_FONT_SIZE, maxFontSize, Math.floor(Math.min(width, height))),
    )
    for (let size: number = initialSize; size >= LOCAL_MIN_FONT_SIZE; size--) {
      font.setSize(size)
      const cellHeight: number = size * 1.12
      const columnWidth: number = size * 1.16
      const charsPerColumn: number = Math.max(1, Math.floor(height / cellHeight))
      const columnCount: number = Math.ceil(normalized.length / charsPerColumn)
      if (columnCount * columnWidth > width ||
        ComicLocalVisualBackend.hasInvalidVerticalBreak(normalized, charsPerColumn)) {
        continue
      }
      const result: LocalVerticalTextLayout = new LocalVerticalTextLayout()
      result.fontSize = size
      for (let start: number = 0; start < normalized.length; start += charsPerColumn) {
        result.columns.push(normalized.slice(start, start + charsPerColumn))
      }
      if (result.columns.length > 0) {
        return result
      }
    }
    throw new Error('Local vertical comic translation does not fit its detected region')
  }

  private static hasInvalidVerticalBreak(text: string, charsPerColumn: number): boolean {
    for (let start: number = charsPerColumn; start < text.length; start += charsPerColumn) {
      if ('，。！？、,.!?；：）】》」』…'.includes(text.charAt(start))) {
        return true
      }
    }
    return false
  }

  private static normalizeVerticalText(text: string): string {
    const compact: string = text.replace(/\s+/g, '')
    const trailingPunctuation: string = '。！？.!?'
    let prefixLength: number = 0
    while (prefixLength < compact.length &&
      trailingPunctuation.includes(compact.charAt(prefixLength))) {
      prefixLength = prefixLength + 1
    }
    if (prefixLength <= 0 || prefixLength >= compact.length) {
      return compact
    }
    return compact.slice(prefixLength) + compact.slice(0, prefixLength)
  }

  private static verticalGlyph(value: string): string {
    switch (value) {
      case '，':
      case ',':
        return '︐'
      case '。':
      case '.':
        return '︒'
      case '、':
        return '︑'
      case '：':
      case ':':
        return '︓'
      case '；':
      case ';':
        return '︔'
      case '！':
      case '!':
        return '︕'
      case '？':
      case '?':
        return '︖'
      case '…':
        return '︙'
      case '（':
      case '(':
        return '︵'
      case '）':
      case ')':
        return '︶'
      default:
        return value
    }
  }

  private static layout(
    text: string,
    width: number,
    height: number,
    font: drawing.Font,
  ): LocalTextLayout {
    const initialSize: number = Math.max(
      LOCAL_MIN_FONT_SIZE,
      Math.min(LOCAL_MAX_FONT_SIZE, Math.floor(height * 0.62)),
    )
    const compact: string = text.replace(/\s+/g, ' ').trim()
    if (!text.includes('\n') && compact.length <= 8) {
      for (let size: number = initialSize; size >= LOCAL_MIN_FONT_SIZE; size--) {
        font.setSize(size)
        const measured: number = font.measureText(
          compact,
          drawing.TextEncoding.TEXT_ENCODING_UTF8,
        )
        if (measured <= width && size * 1.18 <= height) {
          const result: LocalTextLayout = new LocalTextLayout()
          result.fontSize = size
          result.lines.push(compact)
          return result
        }
      }
    }
    for (let size: number = initialSize; size >= LOCAL_MIN_FONT_SIZE; size--) {
      font.setSize(size)
      const lines: string[] = ComicLocalVisualBackend.wrap(text, width, font)
      if (lines.length * size * 1.18 <= height) {
        const result: LocalTextLayout = new LocalTextLayout()
        result.fontSize = size
        result.lines = lines
        return result
      }
    }
    throw new Error('Local comic translation does not fit its detected region')
  }

  private static wrap(text: string, width: number, font: drawing.Font): string[] {
    const lines: string[] = []
    let current: string = ''
    for (let index: number = 0; index < text.length; index++) {
      const character: string = text.charAt(index)
      if (character === '\n') {
        if (current.length > 0) {
          lines.push(current)
          current = ''
        }
        continue
      }
      const candidate: string = current + character
      const measured: number = font.measureText(candidate, drawing.TextEncoding.TEXT_ENCODING_UTF8)
      if (current.length > 0 && measured > width) {
        lines.push(current)
        current = character
      } else {
        current = candidate
      }
    }
    if (current.length > 0) {
      lines.push(current)
    }
    if (lines.length === 0) {
      lines.push(text)
    }
    return lines
  }

  private static bounds(points: ComicPoint[]): LocalRenderRect {
    const rect: LocalRenderRect = new LocalRenderRect()
    rect.left = Number.POSITIVE_INFINITY
    rect.top = Number.POSITIVE_INFINITY
    rect.right = Number.NEGATIVE_INFINITY
    rect.bottom = Number.NEGATIVE_INFINITY
    for (let index: number = 0; index < points.length; index++) {
      rect.left = Math.min(rect.left, points[index].x)
      rect.top = Math.min(rect.top, points[index].y)
      rect.right = Math.max(rect.right, points[index].x)
      rect.bottom = Math.max(rect.bottom, points[index].y)
    }
    if (!Number.isFinite(rect.left) || !Number.isFinite(rect.top) ||
      !Number.isFinite(rect.right) || !Number.isFinite(rect.bottom) ||
      rect.right <= rect.left || rect.bottom <= rect.top) {
      throw new Error('Local comic OCR polygon has invalid bounds')
    }
    return rect
  }

  private static ensureDir(path: string): void {
    try {
      fileIo.mkdirSync(path, true)
    } catch (error) {
      if (!fileIo.accessSync(path)) {
        throw error as Error
      }
    }
  }

  private static removeFile(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_error) {}
  }

  private static sha256Text(value: string): string {
    return ComicLocalVisualBackend.sha256(new util.TextEncoder().encodeInto(value))
  }

  private static sha256(bytes: Uint8Array): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: bytes })
    return ComicLocalVisualBackend.toHex(md.digestSync().data)
  }

  private static sha256File(path: string): string {
    const md = cryptoFramework.createMd('SHA256')
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      while (true) {
        const buffer: ArrayBuffer = new ArrayBuffer(LOCAL_HASH_CHUNK_BYTES)
        const read: number = fileIo.readSync(file.fd, buffer, { length: buffer.byteLength })
        if (read <= 0) {
          break
        }
        md.updateSync({ data: new Uint8Array(buffer, 0, read) })
      }
      return ComicLocalVisualBackend.toHex(md.digestSync().data)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static toHex(bytes: Uint8Array): string {
    const parts: string[] = []
    for (let index: number = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}

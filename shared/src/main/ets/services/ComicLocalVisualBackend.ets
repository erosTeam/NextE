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
import {
  ComicLocalSourceInpainter,
  ComicNativeInpaintingResult,
} from './ComicNativeSourceInpainter'
import {
  ComicLocalTextMasker,
  ComicNativeTextMaskResult,
} from './ComicNativeTextMasker'

const LOCAL_VISUAL_BACKEND_ID: string = 'harmony-local-comic-visual'
const LOCAL_VISUAL_PROFILE_ID: string = 'core-vision-ocr-bubble-group-v33'
const LOCAL_VISUAL_PROTOCOL_REVISION: number = 33
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
const LOCAL_CTD_SUPPLEMENTAL_MAX_REGIONS: number = 2
const LOCAL_CTD_SUPPLEMENTAL_MAX_FALLBACK_REGIONS: number = 1
const LOCAL_SUPPLEMENTAL_OCR_MAX_REGION_PIXELS: number = 2 * 1024 * 1024
const LOCAL_SUPPLEMENTAL_OCR_MIN_CONFIDENCE: number = 0.85
const LOCAL_SUPPLEMENTAL_OCR_MAX_TEXT_CHARS: number = 96
const LOCAL_TEXT_MASK_CANDIDATE_GRID_SIZE: number = 4
const LOCAL_TEXT_MASK_CANDIDATE_DILATION_PASSES: number = 2
const LOCAL_TEXT_MASK_CANDIDATE_MIN_CELLS: number = 4
const LOCAL_TEXT_MASK_CANDIDATE_MAX_REGIONS: number = 32
const LOCAL_TEXT_MASK_KNOWN_COVERAGE_RATIO: number = 0.25
const LOCAL_CTD_SUPPLEMENTAL_MIN_OCCUPIED_CELLS: number = 64
const LOCAL_TEXT_MASK_CACHE_MAX_ENTRIES: number = 2
const LOCAL_TEXT_MASK_CACHE_MAX_BYTES: number = 16 * 1024 * 1024
const LOCAL_MIN_FONT_SIZE: number = 8
const LOCAL_MAX_FONT_SIZE: number = 42
const LOCAL_NARROW_UPRIGHT_MIN_FONT_SIZE: number = 10
const LOCAL_NARROW_UPRIGHT_MIN_ROTATED_RATIO: number = 0.75
const LOCAL_TEXT_MASK_DILATION_PASSES: number = 4
const LOCAL_UNMATCHED_SHORT_TEXT_MAX_CHARS: number = 4
const LOCAL_OBSTACLE_LAYOUT_MIN_LINES: number = 4
const LOCAL_OBSTACLE_LAYOUT_SAMPLE_STEP: number = 2
const LOCAL_OBSTACLE_LAYOUT_EDGE_THRESHOLD: number = 28
const LOCAL_FOOTER_START_RATIO: number = 0.94
const LOCAL_FOOTER_SYMBOL_FRAGMENT_MAX_CHARS: number = 12
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
  lineWidthScale: number = 1
  lineHeightScale: number = 1
}

class LocalSupplementalOcrTimings {
  sourcePixelMapCreateMs: number = 0
  regionCropReadMs: number = 0
  regionPixelMapCreateMs: number = 0
  regionPixelMapReleaseMs: number = 0
  recognizerPixelMapReadMs: number = 0
  nativeCallMs: number = 0
  modelLoadMs: number = 0
  nativePreprocessingMs: number = 0
  nativeInferenceMs: number = 0
  nativeDecodingMs: number = 0
  systemRetryMs: number = 0

  addRecognition(result: ComicNativeTextRecognitionResult): void {
    this.regionCropReadMs = this.regionCropReadMs + result.regionCropReadMs
    this.regionPixelMapCreateMs =
      this.regionPixelMapCreateMs + result.regionPixelMapCreateMs
    this.regionPixelMapReleaseMs =
      this.regionPixelMapReleaseMs + result.regionPixelMapReleaseMs
    this.recognizerPixelMapReadMs =
      this.recognizerPixelMapReadMs + result.pixelMapReadMs
    this.nativeCallMs = this.nativeCallMs + result.nativeCallMs
    this.modelLoadMs = this.modelLoadMs + result.modelLoadMs
    this.nativePreprocessingMs =
      this.nativePreprocessingMs + result.preprocessingMs
    this.nativeInferenceMs = this.nativeInferenceMs + result.inferenceMs
    this.nativeDecodingMs = this.nativeDecodingMs + result.decodingMs
  }

  nativeBridgeMs(): number {
    return Math.max(
      0,
      this.nativeCallMs - this.modelLoadMs - this.nativePreprocessingMs -
        this.nativeInferenceMs - this.nativeDecodingMs,
    )
  }
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
  shapeConstrained: boolean = false

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

class LocalTextMaskCandidate {
  rect: LocalRenderRect = new LocalRenderRect()
  occupiedCells: number = 0
}

class LocalVerticalTextLayout {
  fontSize: number = 0
  columns: string[] = []
}

class LocalHorizontalRenderLayout {
  rect: LocalRenderRect = new LocalRenderRect()
  horizontalPadding: number = 0
  verticalPadding: number = 0
  contentWidth: number = 0
  contentHeight: number = 0
  layout: LocalTextLayout = new LocalTextLayout()
  rotationDegrees: number = 0
  rotationCenterX: number = 0
  rotationCenterY: number = 0
  narrowUprightPreferred: boolean = false
}

class LocalRenderPlanBlock {
  block: ComicTextBlock = new ComicTextBlock()
  translatedText: string = ''
}

class LocalFillStyle {
  red: number = 255
  green: number = 255
  blue: number = 255
  textRed: number = 24
  textGreen: number = 24
  textBlue: number = 24
}

class LocalBubbleRenderGroup {
  plan: LocalRenderPlanBlock = new LocalRenderPlanBlock()
  textRect: LocalRenderRect = new LocalRenderRect()
  fill: LocalFillStyle = new LocalFillStyle()
  memberIndexes: number[] = []
}

class LocalSourceTreatmentTarget {
  raw: LocalRenderRect = new LocalRenderRect()
  treatment: LocalRenderRect = new LocalRenderRect()
  background: LocalFillStyle = new LocalFillStyle()
  styleHint: string = LOCAL_HORIZONTAL_STYLE_HINT
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
  private readonly sourceInpainter: ComicLocalSourceInpainter | null
  private readonly sourceMasker: ComicLocalTextMasker | null
  private readonly proposalMasker: ComicLocalTextMasker | null
  private readonly resolvedProfileId: string
  private readonly treatmentMaskCache: Map<string, Uint8Array> = new Map<string, Uint8Array>()
  private treatmentMaskCacheBytes: number = 0

  constructor(
    context: common.UIAbilityContext,
    ocr: ComicLocalOcrEngine = new HarmonyComicLocalOcrEngine(),
    detector: ComicLocalRegionDetector | null = null,
    supplementalRecognizer: ComicLocalTextRecognizer | null = null,
    sourceInpainter: ComicLocalSourceInpainter | null = null,
    sourceMasker: ComicLocalTextMasker | null = null,
    proposalMasker: ComicLocalTextMasker | null = null,
  ) {
    this.context = context
    this.ocr = ocr
    this.detector = detector
    this.supplementalRecognizer = supplementalRecognizer
    this.sourceInpainter = sourceInpainter
    this.sourceMasker = sourceMasker
    this.proposalMasker = proposalMasker === null ? sourceMasker : proposalMasker
    this.resolvedProfileId = LOCAL_VISUAL_PROFILE_ID +
      (detector === null ? '' : `-${detector.profileId()}`) +
      (supplementalRecognizer === null ? '' : `-${supplementalRecognizer.profileId()}`) +
      (sourceInpainter === null ? '' : `-${sourceInpainter.profileId()}`) +
      (sourceMasker === null ? '' : `-${sourceMasker.profileId()}`)
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
      (this.supplementalRecognizer === null ? 0 : this.supplementalRecognizer.revision()) +
      (this.sourceInpainter === null ? 0 : this.sourceInpainter.revision()) +
      (this.sourceMasker === null ? 0 : this.sourceMasker.revision()) +
      (this.proposalMasker === null || this.proposalMasker === this.sourceMasker ?
        0 : this.proposalMasker.revision())
  }

  async analyze(request: ComicRegionAnalysisRequest): Promise<ComicRegionAnalysisResult> {
    ComicVisualTranslationContract.validateRegionAnalysisRequest(request)
    const analysisStartedAt: number = Date.now()
    let detectorMs: number = 0
    let systemOcrMs: number = 0
    let proposalMaskMs: number = 0
    let supplementalOcrMs: number = 0
    let source: image.ImageSource | undefined = undefined
    try {
      source = image.createImageSource(request.source.imageFilePath)
      const info: image.ImageInfo = await source.getImageInfo()
      if (Math.floor(info.size.width) !== request.source.imageWidth ||
        Math.floor(info.size.height) !== request.source.imageHeight) {
        throw new Error('Local comic OCR source dimensions do not match the request')
      }
      let stageStartedAt: number = Date.now()
      let detection: ComicNativeRegionDetectionResult | null =
        await this.detectRegions(
          source,
          request.source.imageWidth,
          request.source.imageHeight,
        )
      detectorMs = Date.now() - stageStartedAt
      const tiles: LocalOcrTile[] = ComicLocalVisualBackend.tiles(
        request.source.imageWidth,
        request.source.imageHeight,
      )
      const mapped: LocalMappedLine[] = []
      stageStartedAt = Date.now()
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
      systemOcrMs = Date.now() - stageStartedAt
      const lines: LocalMappedLine[] = ComicLocalVisualBackend.suppressFurigana(
        ComicLocalVisualBackend.deduplicate(mapped),
      )
      // Establish trust against the manga detector before CTD proposes additional regions.
      // A short unmatched system-OCR fragment is filtered from the final document and must not
      // suppress a CTD proposal that PP-OCR could recover correctly.
      ComicLocalVisualBackend.assignDetectorRegions(lines, detection)
      const candidateCoverageLines: LocalMappedLine[] =
        ComicLocalVisualBackend.suppressUnmatchedShortText(lines, detection)
      stageStartedAt = Date.now()
      detection = await this.addTextMaskCandidates(
        source,
        candidateCoverageLines,
        detection,
        request.source.imageWidth,
        request.source.imageHeight,
        request.source.imageHash,
      )
      proposalMaskMs = Date.now() - stageStartedAt
      ComicLocalVisualBackend.assignDetectorRegions(lines, detection)
      ComicLocalVisualBackend.logDetectorCoverage(
        lines,
        detection,
        request.source.imageWidth,
        request.source.imageHeight,
      )
      stageStartedAt = Date.now()
      const supplementalCount: number = await this.supplementMissedRegions(
        source,
        lines,
        detection,
        request.source.imageWidth,
        request.source.imageHeight,
      )
      supplementalOcrMs = Date.now() - stageStartedAt
      const layoutStartedAt: number = Date.now()
      const layoutLines: LocalMappedLine[] = ComicLocalVisualBackend.suppressUnmatchedShortText(
        lines,
        detection,
      )
      const groupedBlocks: LocalMappedBlock[] = ComicLocalVisualBackend.groupLines(
        layoutLines,
        detection,
        request.source.imageWidth,
        request.source.imageHeight,
      )
      const blocks: LocalMappedBlock[] = ComicLocalVisualBackend.filterFooterArtifacts(
        groupedBlocks,
        request.source.imageHeight,
      )
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
        groupedBlocks.length - blocks.length,
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
      DiagnosticLogger.info(
        'comic-translation',
        'local_analysis_stage_timings',
        `detector=${detectorMs}ms systemOcr=${systemOcrMs}ms ` +
          `proposalMask=${proposalMaskMs}ms supplementalOcr=${supplementalOcrMs}ms ` +
          `layout=${Date.now() - layoutStartedAt}ms total=${Date.now() - analysisStartedAt}ms ` +
          `tiles=${tiles.length} blocks=${result.document.blocks.length}`,
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
    const renderStartedAt: number = Date.now()
    let decodeMs: number = 0
    let maskMs: number = 0
    let layoutMs: number = 0
    let inpaintMs: number = 0
    let drawMs: number = 0
    let encodeMs: number = 0
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
      decodeMs = Date.now() - renderStartedAt
      const maskStartedAt: number = Date.now()
      let pageTextMask: Uint8Array | null = this.takeTreatmentMask(
        request.source.imageHash,
        request.source.imageWidth,
        request.source.imageHeight,
      )
      if (pageTextMask === null && this.sourceMasker !== null) {
        const maskResult: ComicNativeTextMaskResult = await this.sourceMasker.mask(pixelMap)
        if (maskResult.mask.byteLength !== request.source.imageWidth * request.source.imageHeight) {
          throw new Error('Local comic text mask dimensions do not match the source page')
        }
        pageTextMask = new Uint8Array(maskResult.mask)
      }
      maskMs = Date.now() - maskStartedAt
      const layoutStartedAt: number = Date.now()
      const translations: Map<string, string> = new Map<string, string>()
      for (let index: number = 0; index < request.translations.blocks.length; index++) {
        translations.set(
          request.translations.blocks[index].blockId,
          request.translations.blocks[index].translatedText,
        )
      }
      const renderPlans: LocalRenderPlanBlock[] = ComicLocalVisualBackend.renderPlans(
        request.document,
        translations,
      )
      DiagnosticLogger.info(
        'comic-translation',
        'local_render_plan_ready',
        `documentBlocks=${request.document.blocks.length} plans=${renderPlans.length} ` +
          `target=${request.translations.targetLanguage}`,
      )
      const fillStyles: LocalFillStyle[] = []
      for (let index: number = 0; index < renderPlans.length; index++) {
        const block: ComicTextBlock = renderPlans[index].block
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
      // Fit every region independently, but cap outlier columns at the page median. This keeps
      // separate regions legible without allowing one narrow OCR column to become much larger
      // than its neighbours and visually overlap them.
      const verticalFontCap: number = ComicLocalVisualBackend.verticalPageFontCap(
        renderPlans,
        request.source.imageWidth,
        request.source.imageHeight,
        request.translations.targetLanguage,
      )
      const horizontalFontCap: number = ComicLocalVisualBackend.horizontalPageFontCap(
        renderPlans,
        request.source.imageWidth,
        request.source.imageHeight,
        request.translations.targetLanguage,
      )
      const textRects: LocalRenderRect[] = []
      for (let index: number = 0; index < renderPlans.length; index++) {
        textRects.push(await ComicLocalVisualBackend.resolvedRenderTextRect(
          pixelMap,
          renderPlans[index].block,
          request.source.imageWidth,
          request.source.imageHeight,
          fillStyles[index],
          request.translations.targetLanguage,
        ))
      }
      const renderGroups: LocalBubbleRenderGroup[] = ComicLocalVisualBackend.bubbleRenderGroups(
        renderPlans,
        textRects,
        fillStyles,
        request.translations.targetLanguage,
      )
      const drawableGroups: LocalBubbleRenderGroup[] = []
      const horizontalOffsets: number[] = []
      for (let index: number = 0; index < renderGroups.length; index++) {
        const group: LocalBubbleRenderGroup = renderGroups[index]
        try {
          ComicLocalVisualBackend.validateBlockLayout(
            group.plan.block,
            group.plan.translatedText,
            group.textRect,
            verticalFontCap,
            horizontalFontCap,
            request.translations.targetLanguage,
          )
          const offset: number = await ComicLocalVisualBackend.horizontalVerticalOffset(
            pixelMap,
            group.plan.block,
            group.plan.translatedText,
            group.textRect,
            request.source.imageWidth,
            request.source.imageHeight,
            horizontalFontCap,
            request.translations.targetLanguage,
          )
          drawableGroups.push(group)
          horizontalOffsets.push(offset)
        } catch (error) {
          DiagnosticLogger.warn(
            'comic-translation',
            'local_render_group_skipped',
            `members=${group.memberIndexes.join(',')} reason=${(error as Error).message}`,
          )
        }
      }
      if (drawableGroups.length <= 0) {
        throw new Error('No local comic translation fits its detected region')
      }
      DiagnosticLogger.info(
        'comic-translation',
        'local_render_groups_ready',
        `drawable=${drawableGroups.length} skipped=${renderGroups.length - drawableGroups.length}`,
      )
      layoutMs = Date.now() - layoutStartedAt
      // All geometry and text layout decisions must finish against the untouched page. Erase
      // only regions that have a drawable replacement so one pathological translation cannot
      // blank its source text or abort otherwise valid regions on the page.
      const inpaintStartedAt: number = Date.now()
      for (let index: number = 0; index < drawableGroups.length; index++) {
        const targets: LocalSourceTreatmentTarget[] = []
        for (let memberIndex: number = 0;
          memberIndex < drawableGroups[index].memberIndexes.length; memberIndex++) {
          const planIndex: number = drawableGroups[index].memberIndexes[memberIndex]
          const block: ComicTextBlock = renderPlans[planIndex].block
          const target: LocalSourceTreatmentTarget = new LocalSourceTreatmentTarget()
          target.raw = ComicLocalVisualBackend.bounds(block.polygon)
          target.treatment = ComicLocalVisualBackend.sourceTreatmentRect(
            target.raw,
            request.source.imageWidth,
            request.source.imageHeight,
            block.styleHint,
          )
          target.background = fillStyles[planIndex]
          target.styleHint = block.styleHint
          targets.push(target)
        }
        await ComicLocalVisualBackend.eraseSourceRegions(
          pixelMap,
          request.source.imageWidth,
          request.source.imageHeight,
          targets,
          this.sourceInpainter,
          pageTextMask,
        )
      }
      inpaintMs = Date.now() - inpaintStartedAt
      const drawStartedAt: number = Date.now()
      const canvas: drawing.Canvas = new drawing.Canvas(pixelMap)
      for (let index: number = 0; index < drawableGroups.length; index++) {
        const block: ComicTextBlock = drawableGroups[index].plan.block
        ComicLocalVisualBackend.drawBlock(
          canvas,
          block,
          drawableGroups[index].plan.translatedText,
          drawableGroups[index].textRect,
          drawableGroups[index].fill,
          verticalFontCap,
          horizontalFontCap,
          request.translations.targetLanguage,
          horizontalOffsets[index],
        )
      }
      drawMs = Date.now() - drawStartedAt
      const encodeStartedAt: number = Date.now()
      packer = image.createImagePacker()
      outputFile = fileIo.openSync(
        partial,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      await packer.packToFile(pixelMap, outputFile.fd, { format: 'image/png', quality: 100 })
      fileIo.closeSync(outputFile)
      outputFile = null
      encodeMs = Date.now() - encodeStartedAt
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
      DiagnosticLogger.info(
        'comic-translation',
        'local_render_stage_timings',
        `decode=${decodeMs}ms mask=${maskMs}ms layout=${layoutMs}ms ` +
          `inpaint=${inpaintMs}ms draw=${drawMs}ms encode=${encodeMs}ms ` +
          `finalize=${Date.now() - encodeStartedAt - encodeMs}ms ` +
          `total=${Date.now() - renderStartedAt}ms groups=${drawableGroups.length} ` +
          `bytes=${page.byteLength}`,
      )
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
      let sourcePixelMapCreateMs: number = 0
      let sourcePixelMapReleaseMs: number = 0
      for (let tileIndex: number = 0; tileIndex < tiles.length; tileIndex++) {
        const tile: LocalOcrTile = tiles[tileIndex]
        let pixelMap: image.PixelMap | undefined = undefined
        try {
          const pixelMapCreateStartedAt: number = Date.now()
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
          sourcePixelMapCreateMs =
            sourcePixelMapCreateMs + Date.now() - pixelMapCreateStartedAt
          const detected: ComicNativeRegionDetectionResult = await this.detector.detect(pixelMap)
          if (combined.backend.length <= 0) {
            combined.backend = detected.backend
          }
          combined.modelLoadMs = combined.modelLoadMs + detected.modelLoadMs
          combined.inferenceMs = combined.inferenceMs + detected.inferenceMs
          combined.pixelMapReadMs = combined.pixelMapReadMs + detected.pixelMapReadMs
          combined.nativeCallMs = combined.nativeCallMs + detected.nativeCallMs
          ComicLocalVisualBackend.appendDetectedRegions(
            combined.regions,
            detected.regions,
            tile,
            width,
            height,
          )
        } finally {
          if (pixelMap !== undefined) {
            const pixelMapReleaseStartedAt: number = Date.now()
            await pixelMap.release()
            sourcePixelMapReleaseMs =
              sourcePixelMapReleaseMs + Date.now() - pixelMapReleaseStartedAt
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
      DiagnosticLogger.info(
        'comic-translation',
        'local_region_detector_timings',
        `sourceMap=${sourcePixelMapCreateMs}ms sourceRelease=${sourcePixelMapReleaseMs}ms ` +
          `pixelRead=${combined.pixelMapReadMs}ms nativeCall=${combined.nativeCallMs}ms ` +
          `nativeBridge=${Math.max(
            0,
            combined.nativeCallMs - combined.modelLoadMs - combined.inferenceMs,
          )}ms load=${combined.modelLoadMs}ms inference=${combined.inferenceMs}ms`,
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
      const regionIndex: number = lines[lineIndex].detectorRegionIndex
      if (regionIndex < 0) {
        continue
      }
      const region: ComicNativeDetectedRegion = detection.regions[regionIndex]
      const compact: string = lines[lineIndex].text.replace(/\s+/g, '')
      if (region.label === 'ctd-text' &&
        compact.length <= LOCAL_UNMATCHED_SHORT_TEXT_MAX_CHARS) {
        continue
      }
      covered.add(regionIndex)
    }
    let attempted: number = 0
    let attemptedCtd: number = 0
    let accepted: number = 0
    let inferenceMs: number = 0
    let modelLoadMs: number = 0
    let fallbackRegions: number = 0
    let splitRecognitions: number = 0
    let systemRetries: number = 0
    const timings: LocalSupplementalOcrTimings = new LocalSupplementalOcrTimings()
    let recognizerSourcePixelMap: image.PixelMap | undefined = undefined
    try {
      for (let regionIndex: number = 0;
        regionIndex < detection.regions.length &&
        attempted < LOCAL_SUPPLEMENTAL_OCR_MAX_REGIONS; regionIndex++) {
        if (covered.has(regionIndex)) {
          continue
        }
        const region: ComicNativeDetectedRegion = detection.regions[regionIndex]
        if (region.label === 'ctd-text' &&
          region.proposalOccupiedCells < LOCAL_CTD_SUPPLEMENTAL_MIN_OCCUPIED_CELLS) {
          continue
        }
        if (region.label === 'ctd-text' &&
          attemptedCtd >= LOCAL_CTD_SUPPLEMENTAL_MAX_REGIONS) {
          continue
        }
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
        if (region.label === 'ctd-text') {
          attemptedCtd = attemptedCtd + 1
        }
        try {
          if (recognizerSourcePixelMap === undefined) {
            const sourcePixelMapStartedAt: number = Date.now()
            recognizerSourcePixelMap = await source.createPixelMap({
              editable: false,
              desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
            })
            timings.sourcePixelMapCreateMs =
              Date.now() - sourcePixelMapStartedAt
          }
          const recognized: ComicNativeTextRecognitionResult = await this.recognizeRegion(
            recognizerSourcePixelMap,
            rect,
          )
          timings.addRecognition(recognized)
          modelLoadMs = modelLoadMs + recognized.modelLoadMs
          inferenceMs = inferenceMs + recognized.inferenceMs
          let text: string = recognized.text.trim()
          let score: number = recognized.score
          let strategy: string = 'whole'
          let acceptedResult: boolean = ComicLocalVisualBackend.supplementalTextAccepted(
            text,
            score,
          ) && !ComicLocalVisualBackend.isPeripheralLatinLabel(
            text,
            rect,
            sourceWidth,
            sourceHeight,
            region.label,
          )
          let fallbackAllowed: boolean = false
          if (!acceptedResult && region.label === 'ctd-text' &&
            fallbackRegions < LOCAL_CTD_SUPPLEMENTAL_MAX_FALLBACK_REGIONS) {
            fallbackRegions = fallbackRegions + 1
            fallbackAllowed = true
            const splitRects: LocalRenderRect[] = ComicLocalVisualBackend.ctdLineSplitRects(rect)
            const splitTexts: string[] = []
            let splitScore: number = 1
            for (let splitIndex: number = 0; splitIndex < splitRects.length; splitIndex++) {
              splitRecognitions = splitRecognitions + 1
              const split: ComicNativeTextRecognitionResult = await this.recognizeRegion(
                recognizerSourcePixelMap,
                splitRects[splitIndex],
              )
              timings.addRecognition(split)
              modelLoadMs = modelLoadMs + split.modelLoadMs
              inferenceMs = inferenceMs + split.inferenceMs
              const splitText: string = split.text.trim()
              const splitAccepted: boolean = ComicLocalVisualBackend.supplementalTextAccepted(
                splitText,
                split.score,
              ) && !ComicLocalVisualBackend.isPeripheralLatinLabel(
                splitText,
                splitRects[splitIndex],
                sourceWidth,
                sourceHeight,
                region.label,
              )
              DiagnosticLogger.info(
                'comic-translation',
                'local_text_recognizer_split_region',
                `region=${regionIndex} split=${splitIndex} ` +
                  `bounds=${Math.floor(splitRects[splitIndex].left)},` +
                  `${Math.floor(splitRects[splitIndex].top)},` +
                  `${Math.ceil(splitRects[splitIndex].right)},` +
                  `${Math.ceil(splitRects[splitIndex].bottom)} ` +
                  `score=${split.score.toFixed(3)} chars=${splitText.length} ` +
                  `accepted=${splitAccepted ? 1 : 0}`,
              )
              if (!splitAccepted) {
                continue
              }
              splitTexts.push(splitText)
              splitScore = Math.min(splitScore, split.score)
            }
            // A partial split would publish one half's transcript against the whole source region
            // and could erase untranslated text in the rejected half. Accept split recovery only
            // when every proposed half is independently trustworthy.
            if (splitTexts.length > 0 && splitTexts.length === splitRects.length) {
              text = splitTexts.join(' ')
              score = splitScore
              strategy = `split${splitTexts.length}`
              acceptedResult = true
            }
          }
          if (!acceptedResult && fallbackAllowed &&
            ComicLocalVisualBackend.ctdSystemRetryEligible(
              rect,
              sourceWidth,
              sourceHeight,
              region.proposalOccupiedCells,
            )) {
            systemRetries = systemRetries + 1
            const systemRetryStartedAt: number = Date.now()
            const systemText: string = await this.recognizeSystemRegion(source, rect)
            timings.systemRetryMs =
              timings.systemRetryMs + Date.now() - systemRetryStartedAt
            const systemAccepted: boolean =
              ComicLocalVisualBackend.supplementalSystemTextAccepted(systemText) &&
              !ComicLocalVisualBackend.isPeripheralLatinLabel(
                systemText,
                rect,
                sourceWidth,
                sourceHeight,
                region.label,
              )
            DiagnosticLogger.info(
              'comic-translation',
              'local_system_ocr_region',
              `region=${regionIndex} bounds=${Math.floor(rect.left)},${Math.floor(rect.top)},` +
                `${Math.ceil(rect.right)},${Math.ceil(rect.bottom)} chars=${systemText.length} ` +
                `accepted=${systemAccepted ? 1 : 0}`,
            )
            if (systemAccepted) {
              text = systemText
              score = 1
              strategy = 'system-crop'
              acceptedResult = true
            }
          }
          DiagnosticLogger.info(
            'comic-translation',
            'local_text_recognizer_region',
            `region=${regionIndex} source=${region.label === 'ctd-text' ? 'ctd' : 'detector'} ` +
              `bounds=${Math.floor(rect.left)},${Math.floor(rect.top)},` +
              `${Math.ceil(rect.right)},${Math.ceil(rect.bottom)} ` +
              `score=${score.toFixed(3)} chars=${text.length} strategy=${strategy} ` +
              `accepted=${acceptedResult ? 1 : 0}`,
          )
          if (!acceptedResult) {
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
        }
      }
    } finally {
      if (recognizerSourcePixelMap !== undefined) {
        await recognizerSourcePixelMap.release()
      }
    }
    DiagnosticLogger.info(
      'comic-translation',
      'local_text_recognizer_complete',
      `profile=${this.supplementalRecognizer.profileId()} attempted=${attempted} ` +
        `attemptedCtd=${attemptedCtd} ` +
        `accepted=${accepted} fallbackRegions=${fallbackRegions} ` +
        `splitRecognitions=${splitRecognitions} systemRetries=${systemRetries} ` +
        `sourceMapMs=${timings.sourcePixelMapCreateMs} ` +
        `cropReadMs=${timings.regionCropReadMs} cropMapMs=${timings.regionPixelMapCreateMs} ` +
        `cropReleaseMs=${timings.regionPixelMapReleaseMs} ` +
        `recognizerReadMs=${timings.recognizerPixelMapReadMs} ` +
        `nativeCallMs=${timings.nativeCallMs} nativeBridgeMs=${timings.nativeBridgeMs()} ` +
        `loadMs=${modelLoadMs} preprocessMs=${timings.nativePreprocessingMs} ` +
        `inferenceMs=${inferenceMs} decodeMs=${timings.nativeDecodingMs} ` +
        `systemRetryMs=${timings.systemRetryMs}`,
    )
    DiagnosticLogger.info(
      'comic-translation',
      'local_text_recognizer_input_timings',
      `sourceMap=${timings.sourcePixelMapCreateMs}ms ` +
        `cropRead=${timings.regionCropReadMs}ms cropMap=${timings.regionPixelMapCreateMs}ms ` +
        `cropRelease=${timings.regionPixelMapReleaseMs}ms ` +
        `recognizerRead=${timings.recognizerPixelMapReadMs}ms`,
    )
    DiagnosticLogger.info(
      'comic-translation',
      'local_text_recognizer_native_timings',
      `nativeCall=${timings.nativeCallMs}ms nativeBridge=${timings.nativeBridgeMs()}ms ` +
        `load=${timings.modelLoadMs}ms preprocess=${timings.nativePreprocessingMs}ms ` +
        `inference=${timings.nativeInferenceMs}ms decode=${timings.nativeDecodingMs}ms ` +
        `systemRetry=${timings.systemRetryMs}ms`,
    )
    return accepted
  }

  private async recognizeRegion(
    sourcePixelMap: image.PixelMap,
    rect: LocalRenderRect,
  ): Promise<ComicNativeTextRecognitionResult> {
    if (this.supplementalRecognizer === null) {
      throw new Error('Local manga text recognizer is unavailable')
    }
    let pixelMap: image.PixelMap | undefined = undefined
    let result: ComicNativeTextRecognitionResult | undefined = undefined
    try {
      const width: number = Math.ceil(rect.width())
      const height: number = Math.ceil(rect.height())
      const rowBytes: number = width * 4
      const pixels: ArrayBuffer = new ArrayBuffer(rowBytes * height)
      const cropReadStartedAt: number = Date.now()
      await sourcePixelMap.readPixels({
        pixels: pixels,
        offset: 0,
        stride: rowBytes,
        region: {
          x: Math.floor(rect.left),
          y: Math.floor(rect.top),
          size: { width: width, height: height },
        },
      })
      const cropReadMs: number = Date.now() - cropReadStartedAt
      const cropPixelMapStartedAt: number = Date.now()
      pixelMap = await image.createPixelMap(pixels, {
        size: { width: width, height: height },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false,
      })
      const cropPixelMapCreateMs: number = Date.now() - cropPixelMapStartedAt
      result = await this.supplementalRecognizer.recognize(
        pixelMap,
        rect.height() > rect.width() * 1.2,
      )
      result.regionCropReadMs = cropReadMs
      result.regionPixelMapCreateMs = cropPixelMapCreateMs
      return result
    } finally {
      if (pixelMap !== undefined) {
        const releaseStartedAt: number = Date.now()
        await pixelMap.release()
        if (result !== undefined) {
          result.regionPixelMapReleaseMs = Date.now() - releaseStartedAt
        }
      }
    }
  }

  private async recognizeSystemRegion(
    source: image.ImageSource,
    rect: LocalRenderRect,
  ): Promise<string> {
    let pixelMap: image.PixelMap | undefined = undefined
    try {
      const width: number = Math.ceil(rect.width())
      const height: number = Math.ceil(rect.height())
      const scale: number = Math.min(3, Math.max(2, 512 / Math.max(width, height)))
      pixelMap = await source.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredRegion: {
          x: Math.floor(rect.left),
          y: Math.floor(rect.top),
          size: { width: width, height: height },
        },
        desiredSize: {
          width: Math.max(width, Math.round(width * scale)),
          height: Math.max(height, Math.round(height * scale)),
        },
        cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
      })
      const recognized: ComicLocalOcrResult = await this.ocr.recognize(pixelMap)
      const texts: string[] = []
      for (let index: number = 0; index < recognized.lines.length; index++) {
        const value: string = recognized.lines[index].text.trim()
        if (value.length > 0) {
          texts.push(value)
        }
      }
      return texts.join(' ')
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release()
      }
    }
  }

  private static supplementalTextAccepted(text: string, score: number): boolean {
    return score >= LOCAL_SUPPLEMENTAL_OCR_MIN_CONFIDENCE &&
      text.length >= 2 && text.length <= LOCAL_SUPPLEMENTAL_OCR_MAX_TEXT_CHARS &&
      !/[\u0000-\u001f]/.test(text)
  }

  private static supplementalSystemTextAccepted(text: string): boolean {
    if (!ComicLocalVisualBackend.supplementalTextAccepted(text, 1)) {
      return false
    }
    const compact: string = text.replace(/\s+/g, '')
    const latinDigits: string = compact.replace(/[^A-Za-z0-9]/g, '')
    const cjk: string = compact.replace(
      /[^\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/g,
      '',
    )
    // Enlarged artwork crops can make Core Vision alternate between O/0 and one kana or
    // ideograph. A false positive here would erase source artwork, so mixed short fragments
    // fail closed and remain visible for a future manga-specific recognizer.
    return !(compact.length <= 8 && latinDigits.length >= 3 && cjk.length <= 1)
  }

  private static ctdLineSplitRects(rect: LocalRenderRect): LocalRenderRect[] {
    if (rect.width() < 48 || rect.height() < 64 ||
      rect.height() < rect.width() * 0.65 || rect.height() > rect.width() * 1.8) {
      return []
    }
    const middle: number = (rect.top + rect.bottom) / 2
    const overlap: number = Math.min(12, Math.max(4, rect.height() * 0.08))
    const top: LocalRenderRect = new LocalRenderRect()
    top.left = rect.left
    top.top = rect.top
    top.right = rect.right
    top.bottom = Math.min(rect.bottom, middle + overlap)
    const bottom: LocalRenderRect = new LocalRenderRect()
    bottom.left = rect.left
    bottom.top = Math.max(rect.top, middle - overlap)
    bottom.right = rect.right
    bottom.bottom = rect.bottom
    return [top, bottom]
  }

  private static ctdSystemRetryEligible(
    rect: LocalRenderRect,
    sourceWidth: number,
    sourceHeight: number,
    occupiedCells: number,
  ): boolean {
    return occupiedCells >= LOCAL_CTD_SUPPLEMENTAL_MIN_OCCUPIED_CELLS &&
      rect.width() >= 64 && rect.height() >= 64 &&
      rect.left > sourceWidth * 0.08 && rect.right < sourceWidth * 0.92 &&
      rect.top > sourceHeight * 0.12 && rect.bottom < sourceHeight * 0.88
  }

  private static isPeripheralLatinLabel(
    text: string,
    rect: LocalRenderRect,
    sourceWidth: number,
    sourceHeight: number,
    regionLabel: string,
  ): boolean {
    const compact: string = text.replace(/\s+/g, '')
    if (regionLabel !== 'ctd-text' || compact.length <= 0 || compact.length > 6 ||
      !/^[A-Za-z0-9]+$/.test(compact)) {
      return false
    }
    return rect.left <= sourceWidth * 0.08 || rect.right >= sourceWidth * 0.92 ||
      rect.top <= sourceHeight * 0.12 || rect.bottom >= sourceHeight * 0.88
  }

  private static treatmentMaskCacheKey(
    sourceImageHash: string,
    sourceWidth: number,
    sourceHeight: number,
  ): string {
    return `${sourceImageHash}:${sourceWidth}x${sourceHeight}`
  }

  private cacheTreatmentMask(
    sourceImageHash: string,
    sourceWidth: number,
    sourceHeight: number,
    mask: ArrayBuffer,
  ): void {
    const expectedBytes: number = sourceWidth * sourceHeight
    if (this.sourceMasker === null || mask.byteLength !== expectedBytes ||
      expectedBytes <= 0 || expectedBytes > LOCAL_TEXT_MASK_CACHE_MAX_BYTES) {
      return
    }
    const key: string = ComicLocalVisualBackend.treatmentMaskCacheKey(
      sourceImageHash,
      sourceWidth,
      sourceHeight,
    )
    const replaced: Uint8Array | undefined = this.treatmentMaskCache.get(key)
    if (replaced !== undefined) {
      this.treatmentMaskCache.delete(key)
      this.treatmentMaskCacheBytes = Math.max(
        0,
        this.treatmentMaskCacheBytes - replaced.byteLength,
      )
    }
    while (this.treatmentMaskCache.size >= LOCAL_TEXT_MASK_CACHE_MAX_ENTRIES ||
      this.treatmentMaskCacheBytes + expectedBytes > LOCAL_TEXT_MASK_CACHE_MAX_BYTES) {
      const oldestKey: string | undefined = this.treatmentMaskCache.keys().next().value
      if (oldestKey === undefined) {
        break
      }
      const oldest: Uint8Array | undefined = this.treatmentMaskCache.get(oldestKey)
      this.treatmentMaskCache.delete(oldestKey)
      if (oldest !== undefined) {
        this.treatmentMaskCacheBytes = Math.max(
          0,
          this.treatmentMaskCacheBytes - oldest.byteLength,
        )
      }
    }
    const cached: Uint8Array = new Uint8Array(mask)
    this.treatmentMaskCache.set(key, cached)
    this.treatmentMaskCacheBytes = this.treatmentMaskCacheBytes + cached.byteLength
    DiagnosticLogger.info(
      'comic-translation',
      'local_text_mask_cache_stored',
      `bytes=${cached.byteLength} entries=${this.treatmentMaskCache.size} ` +
        `totalBytes=${this.treatmentMaskCacheBytes}`,
    )
  }

  private takeTreatmentMask(
    sourceImageHash: string,
    sourceWidth: number,
    sourceHeight: number,
  ): Uint8Array | null {
    const key: string = ComicLocalVisualBackend.treatmentMaskCacheKey(
      sourceImageHash,
      sourceWidth,
      sourceHeight,
    )
    const cached: Uint8Array | undefined = this.treatmentMaskCache.get(key)
    if (cached === undefined) {
      return null
    }
    this.treatmentMaskCache.delete(key)
    this.treatmentMaskCacheBytes = Math.max(
      0,
      this.treatmentMaskCacheBytes - cached.byteLength,
    )
    DiagnosticLogger.info(
      'comic-translation',
      'local_text_mask_cache_hit',
      `bytes=${cached.byteLength} entries=${this.treatmentMaskCache.size} ` +
        `totalBytes=${this.treatmentMaskCacheBytes}`,
    )
    return cached
  }

  private async addTextMaskCandidates(
    source: image.ImageSource,
    lines: LocalMappedLine[],
    detection: ComicNativeRegionDetectionResult | null,
    sourceWidth: number,
    sourceHeight: number,
    sourceImageHash: string,
  ): Promise<ComicNativeRegionDetectionResult | null> {
    if (this.proposalMasker === null || this.supplementalRecognizer === null) {
      return detection
    }
    let pixelMap: image.PixelMap | undefined = undefined
    try {
      pixelMap = await source.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      })
      const maskResult: ComicNativeTextMaskResult = await this.proposalMasker.mask(pixelMap)
      if (maskResult.mask.byteLength !== sourceWidth * sourceHeight) {
        throw new Error('Local comic analysis text mask dimensions do not match the source page')
      }
      this.cacheTreatmentMask(
        sourceImageHash,
        sourceWidth,
        sourceHeight,
        maskResult.secondaryMask,
      )
      const candidates: LocalTextMaskCandidate[] =
        ComicLocalVisualBackend.textMaskCandidates(
          new Uint8Array(maskResult.mask),
          sourceWidth,
          sourceHeight,
        )
      // Keep proposal construction transactional. If mask processing or diagnostics fails after
      // one candidate was appended, the detector result returned by the caller must remain
      // untouched rather than exposing a partially augmented region set.
      const resolved: ComicNativeRegionDetectionResult = new ComicNativeRegionDetectionResult()
      if (detection !== null) {
        resolved.backend = detection.backend
        resolved.modelLoadMs = detection.modelLoadMs
        resolved.inferenceMs = detection.inferenceMs
        for (let index: number = 0; index < detection.regions.length; index++) {
          resolved.regions.push(detection.regions[index])
        }
      }
      if (resolved.backend.length <= 0) {
        resolved.backend = maskResult.backend
      }
      let added: number = 0
      const candidateDiagnostics: string[] = []
      for (let index: number = 0; index < candidates.length; index++) {
        const coverage: number = ComicLocalVisualBackend.textMaskCandidateCoverage(
          candidates[index].rect,
          lines,
          resolved,
          sourceWidth,
          sourceHeight,
        )
        const rect: LocalRenderRect = candidates[index].rect
        if (coverage >= LOCAL_TEXT_MASK_KNOWN_COVERAGE_RATIO) {
          candidateDiagnostics.push(ComicLocalVisualBackend.textMaskCandidateDiagnostic(
            index,
            rect,
            candidates[index].occupiedCells,
            coverage,
            false,
          ))
          continue
        }
        const region: ComicNativeDetectedRegion = new ComicNativeDetectedRegion()
        region.score = 1
        region.classId = -1
        region.label = 'ctd-text'
        region.proposalOccupiedCells = candidates[index].occupiedCells
        region.points.push(new ComicNativeRegionPoint(rect.left, rect.top))
        region.points.push(new ComicNativeRegionPoint(rect.right, rect.top))
        region.points.push(new ComicNativeRegionPoint(rect.right, rect.bottom))
        region.points.push(new ComicNativeRegionPoint(rect.left, rect.bottom))
        resolved.regions.push(region)
        added = added + 1
        candidateDiagnostics.push(ComicLocalVisualBackend.textMaskCandidateDiagnostic(
          index,
          rect,
          candidates[index].occupiedCells,
          coverage,
          true,
        ))
      }
      ComicLocalVisualBackend.logTextMaskCandidateGeometry(candidateDiagnostics)
      DiagnosticLogger.info(
        'comic-translation',
        'local_text_mask_candidates',
        `profile=${this.proposalMasker.profileId()} components=${candidates.length} ` +
          `added=${added} totalRegions=${resolved.regions.length}`,
      )
      return resolved.regions.length > 0 ? resolved : detection
    } catch (error) {
      DiagnosticLogger.warn(
        'comic-translation',
        'local_text_mask_candidate_fallback',
        `profile=${this.proposalMasker.profileId()} message=${(error as Error).message}`,
      )
      return detection
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release()
      }
    }
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
      mapped.proposalOccupiedCells = source.proposalOccupiedCells
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

  private static logDetectorCoverage(
    values: LocalMappedLine[],
    detection: ComicNativeRegionDetectionResult | null,
    sourceWidth: number,
    sourceHeight: number,
  ): void {
    if (detection === null) {
      return
    }
    const counts: number[] = []
    for (let regionIndex: number = 0;
      regionIndex < detection.regions.length; regionIndex++) {
      counts.push(0)
    }
    for (let lineIndex: number = 0; lineIndex < values.length; lineIndex++) {
      const regionIndex: number = values[lineIndex].detectorRegionIndex
      if (regionIndex >= 0 && regionIndex < counts.length) {
        counts[regionIndex] = counts[regionIndex] + 1
      }
    }
    const chunkSize: number = 8
    for (let start: number = 0; start < detection.regions.length; start += chunkSize) {
      const parts: string[] = []
      const end: number = Math.min(detection.regions.length, start + chunkSize)
      for (let regionIndex: number = start; regionIndex < end; regionIndex++) {
        const rect: LocalRenderRect = ComicLocalVisualBackend.detectedRegionBounds(
          detection.regions[regionIndex],
          sourceWidth,
          sourceHeight,
        )
        parts.push(
          `r${regionIndex}=${Math.floor(rect.left)},${Math.floor(rect.top)},` +
            `${Math.ceil(rect.right)},${Math.ceil(rect.bottom)}:ocr${counts[regionIndex]}`,
        )
      }
      DiagnosticLogger.info(
        'comic-translation',
        'local_region_detector_coverage',
        `regions=${detection.regions.length} lines=${values.length} ${parts.join(';')}`,
      )
    }
  }

  private static suppressUnmatchedShortText(
    values: LocalMappedLine[],
    detection: ComicNativeRegionDetectionResult | null,
  ): LocalMappedLine[] {
    if (detection === null) {
      return values
    }
    const output: LocalMappedLine[] = []
    for (let index: number = 0; index < values.length; index++) {
      const value: LocalMappedLine = values[index]
      const compact: string = value.text.replace(/\s+/g, '')
      if (value.detectorRegionIndex < 0 &&
        compact.length <= LOCAL_UNMATCHED_SHORT_TEXT_MAX_CHARS) {
        continue
      }
      output.push(value)
    }
    return output
  }

  private static filterFooterArtifacts(
    values: LocalMappedBlock[],
    imageHeight: number,
  ): LocalMappedBlock[] {
    const output: LocalMappedBlock[] = []
    for (let index: number = 0; index < values.length; index++) {
      const value: LocalMappedBlock = values[index]
      if (!ComicLocalVisualBackend.isFooterArtifact(value, imageHeight)) {
        output.push(value)
      }
    }
    return output
  }

  private static isFooterArtifact(value: LocalMappedBlock, imageHeight: number): boolean {
    if (value.styleHint !== LOCAL_HORIZONTAL_STYLE_HINT || imageHeight <= 0) {
      return false
    }
    const rect: LocalRenderRect = ComicLocalVisualBackend.bounds(value.polygon)
    if (rect.top < imageHeight * LOCAL_FOOTER_START_RATIO) {
      return false
    }
    const normalized: string = value.text.replace(/\s+/g, ' ').trim()
    if (/(?:https?:\/\/|www\.|(?:twitter|pixiv|patreon|fantia|enty)\s*[,.]?\s*(?:com|jp)|[A-Za-z0-9_-]+\.(?:com|net|org|jp)(?:[\/\s]|$))/i.test(normalized)) {
      return true
    }
    const compact: string = normalized.replace(/\s+/g, '')
    if (compact.length <= 0 || compact.length > LOCAL_FOOTER_SYMBOL_FRAGMENT_MAX_CHARS) {
      return false
    }
    let naturalCharacters: number = 0
    for (let index: number = 0; index < compact.length; index++) {
      if (/[A-Za-z0-9\u3040-\u30ff\u3400-\u9fff]/.test(compact.charAt(index))) {
        naturalCharacters = naturalCharacters + 1
      }
    }
    return naturalCharacters * 2 < compact.length
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

  private static textMaskCandidates(
    mask: Uint8Array,
    sourceWidth: number,
    sourceHeight: number,
  ): LocalTextMaskCandidate[] {
    if (mask.length !== sourceWidth * sourceHeight || sourceWidth <= 0 || sourceHeight <= 0) {
      return []
    }
    const cellSize: number = LOCAL_TEXT_MASK_CANDIDATE_GRID_SIZE
    const gridWidth: number = Math.ceil(sourceWidth / cellSize)
    const gridHeight: number = Math.ceil(sourceHeight / cellSize)
    const occupied: Uint8Array = new Uint8Array(gridWidth * gridHeight)
    for (let y: number = 0; y < sourceHeight; y++) {
      const sourceRow: number = y * sourceWidth
      const gridRow: number = Math.floor(y / cellSize) * gridWidth
      for (let x: number = 0; x < sourceWidth; x++) {
        if (mask[sourceRow + x] !== 0) {
          occupied[gridRow + Math.floor(x / cellSize)] = 1
        }
      }
    }
    let connected: Uint8Array = new Uint8Array(occupied)
    for (let pass: number = 0;
      pass < LOCAL_TEXT_MASK_CANDIDATE_DILATION_PASSES; pass++) {
      const expanded: Uint8Array = new Uint8Array(connected)
      for (let y: number = 0; y < gridHeight; y++) {
        for (let x: number = 0; x < gridWidth; x++) {
          if (connected[y * gridWidth + x] === 0) {
            continue
          }
          const top: number = Math.max(0, y - 1)
          const bottom: number = Math.min(gridHeight - 1, y + 1)
          const left: number = Math.max(0, x - 1)
          const right: number = Math.min(gridWidth - 1, x + 1)
          for (let expandedY: number = top; expandedY <= bottom; expandedY++) {
            for (let expandedX: number = left; expandedX <= right; expandedX++) {
              expanded[expandedY * gridWidth + expandedX] = 1
            }
          }
        }
      }
      connected = expanded
    }
    const visited: Uint8Array = new Uint8Array(connected.length)
    const candidates: LocalTextMaskCandidate[] = []
    for (let start: number = 0; start < connected.length; start++) {
      if (connected[start] === 0 || visited[start] !== 0) {
        continue
      }
      const queue: number[] = [start]
      visited[start] = 1
      let cursor: number = 0
      let occupiedCells: number = 0
      let minimumX: number = gridWidth
      let minimumY: number = gridHeight
      let maximumX: number = -1
      let maximumY: number = -1
      while (cursor < queue.length) {
        const current: number = queue[cursor]
        cursor = cursor + 1
        const y: number = Math.floor(current / gridWidth)
        const x: number = current - y * gridWidth
        if (occupied[current] !== 0) {
          occupiedCells = occupiedCells + 1
          minimumX = Math.min(minimumX, x)
          minimumY = Math.min(minimumY, y)
          maximumX = Math.max(maximumX, x)
          maximumY = Math.max(maximumY, y)
        }
        const top: number = Math.max(0, y - 1)
        const bottom: number = Math.min(gridHeight - 1, y + 1)
        const left: number = Math.max(0, x - 1)
        const right: number = Math.min(gridWidth - 1, x + 1)
        for (let neighborY: number = top; neighborY <= bottom; neighborY++) {
          for (let neighborX: number = left; neighborX <= right; neighborX++) {
            const neighbor: number = neighborY * gridWidth + neighborX
            if (connected[neighbor] === 0 || visited[neighbor] !== 0) {
              continue
            }
            visited[neighbor] = 1
            queue.push(neighbor)
          }
        }
      }
      if (occupiedCells < LOCAL_TEXT_MASK_CANDIDATE_MIN_CELLS || maximumX < minimumX ||
        maximumY < minimumY) {
        continue
      }
      const padding: number = cellSize * 2
      const candidate: LocalTextMaskCandidate = new LocalTextMaskCandidate()
      candidate.rect.left = Math.max(0, minimumX * cellSize - padding)
      candidate.rect.top = Math.max(0, minimumY * cellSize - padding)
      candidate.rect.right = Math.min(sourceWidth, (maximumX + 1) * cellSize + padding)
      candidate.rect.bottom = Math.min(sourceHeight, (maximumY + 1) * cellSize + padding)
      candidate.occupiedCells = occupiedCells
      const area: number = candidate.rect.width() * candidate.rect.height()
      if (candidate.rect.width() < 8 || candidate.rect.height() < 8 ||
        area > LOCAL_SUPPLEMENTAL_OCR_MAX_REGION_PIXELS) {
        continue
      }
      candidates.push(candidate)
    }
    candidates.sort((left: LocalTextMaskCandidate, right: LocalTextMaskCandidate): number =>
      right.occupiedCells - left.occupiedCells)
    if (candidates.length <= LOCAL_TEXT_MASK_CANDIDATE_MAX_REGIONS) {
      return candidates
    }
    return candidates.slice(0, LOCAL_TEXT_MASK_CANDIDATE_MAX_REGIONS)
  }

  private static textMaskCandidateCoverage(
    candidate: LocalRenderRect,
    lines: LocalMappedLine[],
    detection: ComicNativeRegionDetectionResult,
    sourceWidth: number,
    sourceHeight: number,
  ): number {
    const cellSize: number = LOCAL_TEXT_MASK_CANDIDATE_GRID_SIZE
    const gridWidth: number = Math.max(1, Math.ceil(candidate.width() / cellSize))
    const gridHeight: number = Math.max(1, Math.ceil(candidate.height() / cellSize))
    const covered: Uint8Array = new Uint8Array(gridWidth * gridHeight)
    for (let index: number = 0; index < lines.length; index++) {
      ComicLocalVisualBackend.markTextMaskCandidateCoverage(
        candidate,
        ComicLocalVisualBackend.bounds(lines[index].polygon),
        covered,
        gridWidth,
        gridHeight,
        cellSize,
      )
    }
    for (let index: number = 0; index < detection.regions.length; index++) {
      ComicLocalVisualBackend.markTextMaskCandidateCoverage(
        candidate,
        ComicLocalVisualBackend.detectedRegionBounds(
          detection.regions[index],
          sourceWidth,
          sourceHeight,
        ),
        covered,
        gridWidth,
        gridHeight,
        cellSize,
      )
    }
    let coveredCells: number = 0
    for (let index: number = 0; index < covered.length; index++) {
      if (covered[index] !== 0) {
        coveredCells = coveredCells + 1
      }
    }
    return coveredCells / covered.length
  }

  private static markTextMaskCandidateCoverage(
    candidate: LocalRenderRect,
    known: LocalRenderRect,
    covered: Uint8Array,
    gridWidth: number,
    gridHeight: number,
    cellSize: number,
  ): void {
    const overlapLeft: number = Math.max(candidate.left, known.left)
    const overlapTop: number = Math.max(candidate.top, known.top)
    const overlapRight: number = Math.min(candidate.right, known.right)
    const overlapBottom: number = Math.min(candidate.bottom, known.bottom)
    if (overlapRight <= overlapLeft || overlapBottom <= overlapTop) {
      return
    }
    const startX: number = Math.max(0, Math.floor((overlapLeft - candidate.left) / cellSize))
    const startY: number = Math.max(0, Math.floor((overlapTop - candidate.top) / cellSize))
    const endX: number = Math.min(
      gridWidth - 1,
      Math.floor((overlapRight - candidate.left) / cellSize),
    )
    const endY: number = Math.min(
      gridHeight - 1,
      Math.floor((overlapBottom - candidate.top) / cellSize),
    )
    for (let y: number = startY; y <= endY; y++) {
      const centerY: number = Math.min(
        candidate.bottom,
        candidate.top + (y + 0.5) * cellSize,
      )
      if (centerY < known.top || centerY > known.bottom) {
        continue
      }
      for (let x: number = startX; x <= endX; x++) {
        const centerX: number = Math.min(
          candidate.right,
          candidate.left + (x + 0.5) * cellSize,
        )
        if (centerX >= known.left && centerX <= known.right) {
          covered[y * gridWidth + x] = 1
        }
      }
    }
  }

  private static textMaskCandidateDiagnostic(
    index: number,
    rect: LocalRenderRect,
    occupiedCells: number,
    coverage: number,
    added: boolean,
  ): string {
    return `c${index}=${Math.floor(rect.left)},${Math.floor(rect.top)},` +
      `${Math.ceil(rect.right)},${Math.ceil(rect.bottom)}:` +
      `cells${occupiedCells}:cov${coverage.toFixed(2)}:add${added ? 1 : 0}`
  }

  private static logTextMaskCandidateGeometry(values: string[]): void {
    const chunkSize: number = 6
    for (let start: number = 0; start < values.length; start += chunkSize) {
      DiagnosticLogger.info(
        'comic-translation',
        'local_text_mask_candidate_geometry',
        values.slice(start, Math.min(values.length, start + chunkSize)).join(';'),
      )
    }
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

  private static groupLines(
    values: LocalMappedLine[],
    detection: ComicNativeRegionDetectionResult | null,
    sourceWidth: number,
    sourceHeight: number,
  ): LocalMappedBlock[] {
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
    // Detector regions commonly describe individual source columns rather than the whole
    // paragraph. Apply their geometry first so adjacent columns can be merged into one layout
    // region instead of independently expanding translated text into each other.
    ComicLocalVisualBackend.applyDetectorRegionGeometry(
      grouped,
      detection,
      sourceWidth,
      sourceHeight,
    )
    const verticalMerged: LocalMappedBlock[] =
      ComicLocalVisualBackend.mergeAdjacentVerticalBlocks(grouped)
    const horizontalMerged: LocalMappedBlock[] =
      ComicLocalVisualBackend.mergeAdjacentHorizontalBlocks(verticalMerged)
    const output: LocalMappedBlock[] =
      ComicLocalVisualBackend.collapseContainedVerticalSourceBlocks(horizontalMerged)
    DiagnosticLogger.info(
      'comic-translation',
      'local_line_grouping_stages',
      `grouped=${ComicLocalVisualBackend.groupingGeometry(grouped)} ` +
        `vertical=${ComicLocalVisualBackend.groupingGeometry(verticalMerged)} ` +
        `horizontal=${ComicLocalVisualBackend.groupingGeometry(horizontalMerged)}`,
    )
    DiagnosticLogger.info(
      'comic-translation',
      'local_line_grouping_ready',
      `groups=${grouped.length} vertical=${verticalMerged.length} ` +
        `horizontal=${horizontalMerged.length} output=${output.length} ` +
        `geometry=${ComicLocalVisualBackend.groupingGeometry(output)}`,
    )
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

  private static collapseContainedVerticalSourceBlocks(
    values: LocalMappedBlock[],
  ): LocalMappedBlock[] {
    const suppressed: boolean[] = new Array<boolean>(values.length).fill(false)
    const candidateIndexes: number[] = []
    for (let index: number = 0; index < values.length; index++) {
      candidateIndexes.push(index)
    }
    candidateIndexes.sort((left: number, right: number): number =>
      ComicLocalVisualBackend.mappedBlockArea(values[left]) -
        ComicLocalVisualBackend.mappedBlockArea(values[right]))
    for (let orderIndex: number = 0; orderIndex < candidateIndexes.length; orderIndex++) {
      const candidateIndex: number = candidateIndexes[orderIndex]
      let ownerIndex: number = -1
      let ownerArea: number = Number.POSITIVE_INFINITY
      for (let containerIndex: number = 0; containerIndex < values.length; containerIndex++) {
        if (candidateIndex === containerIndex || suppressed[containerIndex] ||
          !ComicLocalVisualBackend.isContainedVerticalSourceFragment(
            values[candidateIndex],
            values[containerIndex],
          )) {
          continue
        }
        const area: number = ComicLocalVisualBackend.mappedBlockArea(values[containerIndex])
        if (area < ownerArea) {
          ownerIndex = containerIndex
          ownerArea = area
        }
      }
      if (ownerIndex < 0) {
        continue
      }
      const combined: string = ComicLocalVisualBackend.combinedSourceText(
        values[ownerIndex].text,
        values[candidateIndex].text,
      )
      if (combined.length > LOCAL_MAX_SOURCE_TEXT_CHARS) {
        continue
      }
      values[ownerIndex].text = combined
      suppressed[candidateIndex] = true
    }
    const output: LocalMappedBlock[] = []
    for (let index: number = 0; index < values.length; index++) {
      if (!suppressed[index]) {
        output.push(values[index])
      }
    }
    return output
  }

  private static mappedBlockArea(block: LocalMappedBlock): number {
    const rect: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
    return Math.max(1, rect.width() * rect.height())
  }

  private static isContainedVerticalSourceFragment(
    candidate: LocalMappedBlock,
    container: LocalMappedBlock,
  ): boolean {
    if (candidate.styleHint !== LOCAL_VERTICAL_STYLE_HINT ||
      container.styleHint !== LOCAL_VERTICAL_STYLE_HINT ||
      candidate.tileIndex !== container.tileIndex ||
      container.text.length < candidate.text.length * 2) {
      return false
    }
    const candidateRect: LocalRenderRect = ComicLocalVisualBackend.bounds(candidate.polygon)
    const containerRect: LocalRenderRect = ComicLocalVisualBackend.bounds(container.polygon)
    const candidateArea: number = Math.max(1, candidateRect.width() * candidateRect.height())
    const containerArea: number = Math.max(1, containerRect.width() * containerRect.height())
    if (containerArea < candidateArea * 3 ||
      containerRect.width() < candidateRect.width() * 2.4) {
      return false
    }
    const overlapWidth: number = Math.max(
      0,
      Math.min(candidateRect.right, containerRect.right) -
        Math.max(candidateRect.left, containerRect.left),
    )
    const overlapHeight: number = Math.max(
      0,
      Math.min(candidateRect.bottom, containerRect.bottom) -
        Math.max(candidateRect.top, containerRect.top),
    )
    return overlapWidth * overlapHeight / candidateArea >= 0.9
  }

  private static combinedSourceText(container: string, fragment: string): string {
    const normalizedContainer: string = ComicLocalVisualBackend.normalizedSourceText(container)
    const normalizedFragment: string = ComicLocalVisualBackend.normalizedSourceText(fragment)
    if (normalizedFragment.length <= 0 || normalizedContainer.includes(normalizedFragment)) {
      return container
    }
    return container + '\n' + fragment
  }

  private static normalizedSourceText(value: string): string {
    return value.toLowerCase()
      .replace(/[\s.,!?;:'"()\[\]{}\-–—…，。！？；：、“”‘’（）【】]+/g, '')
  }

  private static applyDetectorRegionGeometry(
    blocks: LocalMappedBlock[],
    detection: ComicNativeRegionDetectionResult | null,
    sourceWidth: number,
    sourceHeight: number,
  ): void {
    if (detection === null) {
      return
    }
    for (let index: number = 0; index < blocks.length; index++) {
      const regionIndex: number = blocks[index].detectorRegionIndex
      if (regionIndex < 0 || regionIndex >= detection.regions.length) {
        continue
      }
      const region: LocalRenderRect = ComicLocalVisualBackend.detectedRegionBounds(
        detection.regions[regionIndex],
        sourceWidth,
        sourceHeight,
      )
      if (region.width() < 8 || region.height() < 8) {
        continue
      }
      blocks[index].polygon = [
        new ComicPoint(region.left, region.top),
        new ComicPoint(region.right, region.top),
        new ComicPoint(region.right, region.bottom),
        new ComicPoint(region.left, region.bottom),
      ]
    }
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
      block.lineWidthScale = Math.max(block.lineWidthScale, rect.width())
      block.lineHeightScale = Math.max(block.lineHeightScale, rect.height())
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
    const firstRect: LocalRenderRect = ComicLocalVisualBackend.bounds(first.polygon)
    const secondRect: LocalRenderRect = ComicLocalVisualBackend.bounds(second.polygon)
    const rightRect: LocalRenderRect = firstRect.left >= secondRect.left ? firstRect : secondRect
    const leftRect: LocalRenderRect = firstRect.left >= secondRect.left ? secondRect : firstRect
    const horizontalGap: number = rightRect.left - leftRect.right
    // Keep spacing tied to an original OCR column rather than the accumulated paragraph width.
    // The latter grows after every merge and can eventually absorb the next balloon.
    const maximumGap: number = Math.max(first.lineWidthScale, second.lineWidthScale) * 0.55
    // Detector boxes for neighbouring Japanese columns can overlap by roughly one-third of a
    // glyph width because punctuation and antialiasing extend into the next box. Treat that as
    // one paragraph; larger overlap remains a likely duplicate/nested detection.
    if (horizontalGap < -Math.min(first.lineWidthScale, second.lineWidthScale) * 0.36 ||
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
    block.detectorRegionIndex = first.detectorRegionIndex === second.detectorRegionIndex ?
      first.detectorRegionIndex : -1
    block.lineWidthScale = Math.max(first.lineWidthScale, second.lineWidthScale)
    block.lineHeightScale = Math.max(first.lineHeightScale, second.lineHeightScale)
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
    const firstRect: LocalRenderRect = ComicLocalVisualBackend.bounds(first.polygon)
    const secondRect: LocalRenderRect = ComicLocalVisualBackend.bounds(second.polygon)
    const upperRect: LocalRenderRect = firstRect.top <= secondRect.top ? firstRect : secondRect
    const lowerRect: LocalRenderRect = firstRect.top <= secondRect.top ? secondRect : firstRect
    const verticalGap: number = lowerRect.top - upperRect.bottom
    const overlapScale: number = Math.min(first.lineHeightScale, second.lineHeightScale)
    const maximumGap: number = Math.max(first.lineHeightScale, second.lineHeightScale) * 0.55
    if (verticalGap < -overlapScale * 0.42 ||
      // A merged paragraph may be much taller than one line. Preserve the original line-height
      // scale so two completed paragraphs cannot bridge the gap between separate balloons.
      verticalGap > maximumGap) {
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
    block.detectorRegionIndex = first.detectorRegionIndex === second.detectorRegionIndex ?
      first.detectorRegionIndex : -1
    block.lineWidthScale = Math.max(first.lineWidthScale, second.lineWidthScale)
    block.lineHeightScale = Math.max(first.lineHeightScale, second.lineHeightScale)
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

  private static groupingGeometry(values: LocalMappedBlock[]): string {
    const parts: string[] = []
    const limit: number = Math.min(values.length, 16)
    for (let index: number = 0; index < limit; index++) {
      const rect: LocalRenderRect = ComicLocalVisualBackend.bounds(values[index].polygon)
      const direction: string = values[index].styleHint === LOCAL_VERTICAL_STYLE_HINT ? 'v' : 'h'
      parts.push(
        `${direction}:${Math.floor(rect.left)},${Math.floor(rect.top)},` +
          `${Math.ceil(rect.right)},${Math.ceil(rect.bottom)}`,
      )
    }
    if (values.length > limit) {
      parts.push(`+${values.length - limit}`)
    }
    return parts.join(';')
  }

  private static document(
    request: ComicRegionAnalysisRequest,
    lines: LocalMappedBlock[],
    tileCount: number,
    profileId: string,
    detectorUsed: boolean,
    supplementalCount: number,
    footerArtifactCount: number,
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
    if (footerArtifactCount > 0) {
      const footerSignal: ComicQualitySignal = new ComicQualitySignal()
      footerSignal.code = 'local_non_dialogue_footer_filtered'
      footerSignal.severity = ComicQualitySeverity.INFO
      footerSignal.message =
        `Ignored ${footerArtifactCount} likely non-dialogue footer artifact(s).`
      document.qualitySignals.push(footerSignal)
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
    textRect: LocalRenderRect,
    fill: LocalFillStyle,
    verticalFontCap: number,
    horizontalFontCap: number,
    targetLanguage: string,
    horizontalVerticalOffset: number,
  ): void {
    const renderStyleHint: string = ComicLocalVisualBackend.renderStyleHint(
      block.styleHint,
      targetLanguage,
    )
    const horizontalPadding: number = Math.max(4, Math.min(12, textRect.width() * 0.08))
    const verticalPadding: number = Math.max(4, Math.min(10, textRect.height() * 0.08))
    const contentWidth: number = Math.max(1, textRect.width() - horizontalPadding * 2)
    const contentHeight: number = Math.max(1, textRect.height() - verticalPadding * 2)
    const font: drawing.Font = new drawing.Font()
    font.enableSubpixel(true)
    const textBrush: drawing.Brush = new drawing.Brush()
    textBrush.setColor(255, fill.textRed, fill.textGreen, fill.textBlue)
    const textPen: drawing.Pen = new drawing.Pen()
    textPen.setColor(255, 255, 255, 255)
    textPen.setAntiAlias(true)
    if (renderStyleHint === LOCAL_VERTICAL_STYLE_HINT) {
      const layout: LocalVerticalTextLayout = ComicLocalVisualBackend.verticalLayout(
        translatedText,
        contentWidth,
        contentHeight,
        font,
        verticalFontCap,
      )
      textPen.setStrokeWidth(ComicLocalVisualBackend.outlineWidth(layout.fontSize))
      canvas.attachPen(textPen)
      ComicLocalVisualBackend.drawVerticalLayout(
        canvas,
        layout,
        textRect,
        horizontalPadding,
        verticalPadding,
        contentWidth,
        contentHeight,
        font,
      )
      canvas.detachPen()
      canvas.attachBrush(textBrush)
      ComicLocalVisualBackend.drawVerticalLayout(
        canvas,
        layout,
        textRect,
        horizontalPadding,
        verticalPadding,
        contentWidth,
        contentHeight,
        font,
      )
      canvas.detachBrush()
      return
    }
    const horizontal: LocalHorizontalRenderLayout =
      ComicLocalVisualBackend.horizontalRenderLayout(
        block,
        translatedText,
        textRect,
        horizontalFontCap,
      )
    const layout: LocalTextLayout = horizontal.layout
    textPen.setStrokeWidth(ComicLocalVisualBackend.outlineWidth(layout.fontSize))
    canvas.attachPen(textPen)
    ComicLocalVisualBackend.drawPreparedHorizontalLayout(
      canvas,
      horizontal,
      font,
      horizontalVerticalOffset,
    )
    canvas.detachPen()
    canvas.attachBrush(textBrush)
    ComicLocalVisualBackend.drawPreparedHorizontalLayout(
      canvas,
      horizontal,
      font,
      horizontalVerticalOffset,
    )
    canvas.detachBrush()
  }

  private static validateBlockLayout(
    block: ComicTextBlock,
    translatedText: string,
    textRect: LocalRenderRect,
    verticalFontCap: number,
    horizontalFontCap: number,
    targetLanguage: string,
  ): void {
    const renderStyleHint: string = ComicLocalVisualBackend.renderStyleHint(
      block.styleHint,
      targetLanguage,
    )
    if (renderStyleHint === LOCAL_VERTICAL_STYLE_HINT) {
      const horizontalPadding: number = Math.max(4, Math.min(12, textRect.width() * 0.08))
      const verticalPadding: number = Math.max(4, Math.min(10, textRect.height() * 0.08))
      const contentWidth: number = Math.max(1, textRect.width() - horizontalPadding * 2)
      const contentHeight: number = Math.max(1, textRect.height() - verticalPadding * 2)
      const font: drawing.Font = new drawing.Font()
      font.enableSubpixel(true)
      ComicLocalVisualBackend.verticalLayout(
        translatedText,
        contentWidth,
        contentHeight,
        font,
        verticalFontCap,
      )
      return
    }
    ComicLocalVisualBackend.horizontalRenderLayout(
      block,
      translatedText,
      textRect,
      horizontalFontCap,
    )
  }

  private static horizontalRenderLayout(
    block: ComicTextBlock,
    translatedText: string,
    textRect: LocalRenderRect,
    horizontalFontCap: number,
  ): LocalHorizontalRenderLayout {
    const result: LocalHorizontalRenderLayout = new LocalHorizontalRenderLayout()
    const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
    const physicalRect: LocalRenderRect = textRect.shapeConstrained ? textRect :
      ComicLocalVisualBackend.compactFallbackTextRect(raw, textRect)
    const narrowVertical: boolean = block.styleHint === LOCAL_VERTICAL_STYLE_HINT &&
      physicalRect.height() >= 120 && physicalRect.height() >= physicalRect.width() * 1.8
    if (narrowVertical) {
      result.rotationDegrees = 90
      result.rotationCenterX = (physicalRect.left + physicalRect.right) / 2
      result.rotationCenterY = (physicalRect.top + physicalRect.bottom) / 2
      result.rect.left = result.rotationCenterX - physicalRect.height() / 2
      result.rect.top = result.rotationCenterY - physicalRect.width() / 2
      result.rect.right = result.rotationCenterX + physicalRect.height() / 2
      result.rect.bottom = result.rotationCenterY + physicalRect.width() / 2
    } else {
      result.rect = textRect
    }
    result.horizontalPadding = Math.max(4, Math.min(12, result.rect.width() * 0.08))
    result.verticalPadding = Math.max(4, Math.min(10, result.rect.height() * 0.08))
    result.contentWidth = Math.max(1, result.rect.width() - result.horizontalPadding * 2)
    result.contentHeight = Math.max(1, result.rect.height() - result.verticalPadding * 2)
    const font: drawing.Font = new drawing.Font()
    font.enableSubpixel(true)
    let blockFontCap: number = block.styleHint === LOCAL_VERTICAL_STYLE_HINT ?
      horizontalFontCap : LOCAL_MAX_FONT_SIZE
    if (block.styleHint === LOCAL_VERTICAL_STYLE_HINT && result.rect.width() > 360) {
      const referenceWidth: number = 360
      const referencePadding: number = Math.max(4, Math.min(12, referenceWidth * 0.08))
      const referenceLayout: LocalTextLayout = ComicLocalVisualBackend.layout(
        translatedText,
        Math.max(1, referenceWidth - referencePadding * 2),
        result.contentHeight,
        font,
        blockFontCap,
      )
      blockFontCap = Math.min(blockFontCap, referenceLayout.fontSize)
    }
    result.layout = ComicLocalVisualBackend.layout(
      translatedText,
      result.contentWidth,
      result.contentHeight,
      font,
      blockFontCap,
    )
    if (narrowVertical) {
      const upright: LocalHorizontalRenderLayout = new LocalHorizontalRenderLayout()
      upright.rect = physicalRect
      upright.horizontalPadding = Math.max(4, Math.min(12, upright.rect.width() * 0.08))
      upright.verticalPadding = Math.max(4, Math.min(10, upright.rect.height() * 0.08))
      upright.contentWidth = Math.max(1, upright.rect.width() - upright.horizontalPadding * 2)
      upright.contentHeight = Math.max(1, upright.rect.height() - upright.verticalPadding * 2)
      const uprightLayout: LocalTextLayout | null =
        ComicLocalVisualBackend.uprightLatinLayout(
          translatedText,
          upright.contentWidth,
          upright.contentHeight,
          font,
          blockFontCap,
        )
      if (uprightLayout !== null && uprightLayout.fontSize >=
        result.layout.fontSize * LOCAL_NARROW_UPRIGHT_MIN_ROTATED_RATIO) {
        upright.layout = uprightLayout
        upright.narrowUprightPreferred = true
        return upright
      }
    }
    return result
  }

  private static uprightLatinLayout(
    text: string,
    width: number,
    height: number,
    font: drawing.Font,
    maxFontSize: number,
  ): LocalTextLayout | null {
    const initialSize: number = Math.min(
      LOCAL_MAX_FONT_SIZE,
      maxFontSize,
      Math.floor(height * 0.62),
    )
    if (initialSize < LOCAL_NARROW_UPRIGHT_MIN_FONT_SIZE) {
      return null
    }
    for (let size: number = initialSize;
      size >= LOCAL_NARROW_UPRIGHT_MIN_FONT_SIZE; size--) {
      if (!ComicLocalVisualBackend.latinWordsFit(text, width, size, font)) {
        continue
      }
      font.setSize(size)
      const lines: string[] = ComicLocalVisualBackend.wrap(text, width, font)
      if (lines.length * size * 1.18 <= height) {
        const result: LocalTextLayout = new LocalTextLayout()
        result.fontSize = size
        result.lines = lines
        return result
      }
    }
    return null
  }

  private static latinWordsFit(
    text: string,
    width: number,
    fontSize: number,
    font: drawing.Font,
  ): boolean {
    font.setSize(fontSize)
    const words: string[] = text.replace(/[\r\n]+/g, ' ').trim().split(/\s+/)
    for (let index: number = 0; index < words.length; index++) {
      const word: string = words[index]
      if (!/[A-Za-z0-9]/.test(word)) {
        continue
      }
      if (font.measureText(word, drawing.TextEncoding.TEXT_ENCODING_UTF8) > width) {
        return false
      }
    }
    return true
  }

  private static compactFallbackTextRect(
    raw: LocalRenderRect,
    fallback: LocalRenderRect,
  ): LocalRenderRect {
    const rect: LocalRenderRect = new LocalRenderRect()
    rect.left = raw.left
    rect.top = raw.top
    rect.right = raw.right
    rect.bottom = raw.bottom
    // Keep an unconfirmed narrow balloon at the original OCR scale, but retain the page-safe
    // positioning already resolved by the fallback rectangle. This prevents both the old broad
    // overflow and a rotated word touching the physical page edge.
    const inset: number = 8
    const minimumX: number = fallback.left + inset
    const maximumX: number = fallback.right - inset
    const minimumY: number = fallback.top + inset
    const maximumY: number = fallback.bottom - inset
    if (rect.left < minimumX) {
      rect.right = rect.right + (minimumX - rect.left)
      rect.left = minimumX
    }
    if (rect.right > maximumX) {
      rect.left = rect.left - (rect.right - maximumX)
      rect.right = maximumX
    }
    if (rect.top < minimumY) {
      rect.bottom = rect.bottom + (minimumY - rect.top)
      rect.top = minimumY
    }
    if (rect.bottom > maximumY) {
      rect.top = rect.top - (rect.bottom - maximumY)
      rect.bottom = maximumY
    }
    return rect
  }

  private static async horizontalVerticalOffset(
    pixelMap: image.PixelMap,
    block: ComicTextBlock,
    translatedText: string,
    textRect: LocalRenderRect,
    imageWidth: number,
    imageHeight: number,
    horizontalFontCap: number,
    targetLanguage: string,
  ): Promise<number> {
    if (block.styleHint !== LOCAL_VERTICAL_STYLE_HINT ||
      ComicLocalVisualBackend.renderStyleHint(block.styleHint, targetLanguage) !==
        LOCAL_HORIZONTAL_STYLE_HINT) {
      return -1
    }
    const prepared: LocalHorizontalRenderLayout =
      ComicLocalVisualBackend.horizontalRenderLayout(
        block,
        translatedText,
        textRect,
        horizontalFontCap,
      )
    if (prepared.narrowUprightPreferred) {
      DiagnosticLogger.info(
        'comic-translation',
        'local_horizontal_layout_upright_preferred',
        `block=${block.blockId} physical=${Math.round(prepared.rect.width())}x` +
          `${Math.round(prepared.rect.height())} font=${prepared.layout.fontSize} ` +
          `lines=${prepared.layout.lines.length}`,
      )
    }
    if (prepared.rotationDegrees !== 0) {
      DiagnosticLogger.info(
        'comic-translation',
        'local_horizontal_layout_rotated',
        `block=${block.blockId} physical=${Math.round(prepared.rect.height())}x` +
          `${Math.round(prepared.rect.width())} font=${prepared.layout.fontSize} ` +
          `lines=${prepared.layout.lines.length}`,
      )
      return -1
    }
    const lineHeight: number = prepared.layout.fontSize * 1.18
    const totalHeight: number = prepared.layout.lines.length * lineHeight
    const slack: number = Math.max(0, prepared.contentHeight - totalHeight)
    if (prepared.layout.lines.length < LOCAL_OBSTACLE_LAYOUT_MIN_LINES ||
      slack < Math.max(18, lineHeight * 1.2)) {
      return -1
    }
    const left: number = Math.max(0, Math.floor(prepared.rect.left))
    const top: number = Math.max(0, Math.floor(prepared.rect.top))
    const right: number = Math.min(imageWidth, Math.ceil(prepared.rect.right))
    const bottom: number = Math.min(imageHeight, Math.ceil(prepared.rect.bottom))
    const width: number = right - left
    const height: number = bottom - top
    if (width <= 2 || height <= 2) {
      return -1
    }
    try {
      const rowBytes: number = width * 4
      const buffer: ArrayBuffer = new ArrayBuffer(rowBytes * height)
      await pixelMap.readPixels({
        pixels: buffer,
        offset: 0,
        stride: rowBytes,
        region: {
          x: left,
          y: top,
          size: { width: width, height: height },
        },
      })
      const pixels: Uint8Array = new Uint8Array(buffer)
      const candidates: number[] = [0, slack / 2, slack]
      const centerScore: number = ComicLocalVisualBackend.horizontalObstacleScore(
        pixels,
        width,
        height,
        rowBytes,
        prepared,
        candidates[1],
      )
      let bestOffset: number = candidates[1]
      let bestScore: number = centerScore
      for (let index: number = 0; index < candidates.length; index++) {
        const candidate: number = candidates[index]
        const score: number = ComicLocalVisualBackend.horizontalObstacleScore(
          pixels,
          width,
          height,
          rowBytes,
          prepared,
          candidate,
        )
        if (score + 0.01 < bestScore) {
          bestScore = score
          bestOffset = candidate
        }
      }
      const requiredImprovement: number = Math.max(1.5, centerScore * 0.16)
      if (centerScore - bestScore < requiredImprovement) {
        return candidates[1]
      }
      DiagnosticLogger.info(
        'comic-translation',
        'local_obstacle_layout_shifted',
        `block=${block.blockId} lines=${prepared.layout.lines.length} ` +
          `center=${centerScore.toFixed(2)} selected=${bestScore.toFixed(2)} ` +
          `offset=${Math.round(bestOffset)}`,
      )
      return bestOffset
    } catch (error) {
      DiagnosticLogger.warn(
        'comic-translation',
        'local_obstacle_layout_fallback',
        `block=${block.blockId} message=${(error as Error).message}`,
      )
      return -1
    }
  }

  private static horizontalObstacleScore(
    pixels: Uint8Array,
    width: number,
    height: number,
    rowBytes: number,
    prepared: LocalHorizontalRenderLayout,
    verticalOffset: number,
  ): number {
    const font: drawing.Font = new drawing.Font()
    font.enableSubpixel(true)
    font.setSize(prepared.layout.fontSize)
    const lineHeight: number = prepared.layout.fontSize * 1.18
    const outline: number = ComicLocalVisualBackend.outlineWidth(prepared.layout.fontSize)
    const localLeft: number = prepared.rect.left - Math.floor(prepared.rect.left)
    const localTop: number = prepared.rect.top - Math.floor(prepared.rect.top)
    let edgeScore: number = 0
    let samples: number = 0
    for (let lineIndex: number = 0;
      lineIndex < prepared.layout.lines.length; lineIndex++) {
      const line: string = prepared.layout.lines[lineIndex]
      const lineWidth: number = font.measureText(line, drawing.TextEncoding.TEXT_ENCODING_UTF8)
      const lineLeft: number = localLeft + prepared.horizontalPadding +
        Math.max(0, (prepared.contentWidth - lineWidth) / 2) - outline
      const lineTop: number = localTop + prepared.verticalPadding + verticalOffset +
        lineIndex * lineHeight - outline
      const lineRight: number = lineLeft + lineWidth + outline * 2
      const lineBottom: number = lineTop + lineHeight + outline * 2
      const startX: number = Math.max(1, Math.floor(lineLeft))
      const startY: number = Math.max(1, Math.floor(lineTop))
      const endX: number = Math.min(width - 2, Math.ceil(lineRight))
      const endY: number = Math.min(height - 2, Math.ceil(lineBottom))
      for (let y: number = startY; y <= endY;
        y += LOCAL_OBSTACLE_LAYOUT_SAMPLE_STEP) {
        for (let x: number = startX; x <= endX;
          x += LOCAL_OBSTACLE_LAYOUT_SAMPLE_STEP) {
          const luminance: number = ComicLocalVisualBackend.pixelLuminance(
            pixels,
            y * rowBytes + x * 4,
          )
          const rightLuminance: number = ComicLocalVisualBackend.pixelLuminance(
            pixels,
            y * rowBytes + (x + 1) * 4,
          )
          const bottomLuminance: number = ComicLocalVisualBackend.pixelLuminance(
            pixels,
            (y + 1) * rowBytes + x * 4,
          )
          const edge: number = Math.max(
            Math.abs(luminance - rightLuminance),
            Math.abs(luminance - bottomLuminance),
          )
          if (edge >= LOCAL_OBSTACLE_LAYOUT_EDGE_THRESHOLD) {
            edgeScore = edgeScore + edge
          }
          samples = samples + 1
        }
      }
    }
    return samples > 0 ? edgeScore / samples : 0
  }

  private static pixelLuminance(pixels: Uint8Array, offset: number): number {
    return pixels[offset + 2] * 0.299 + pixels[offset + 1] * 0.587 +
      pixels[offset] * 0.114
  }

  private static drawHorizontalLayout(
    canvas: drawing.Canvas,
    layout: LocalTextLayout,
    rect: LocalRenderRect,
    horizontalPadding: number,
    verticalPadding: number,
    contentWidth: number,
    contentHeight: number,
    font: drawing.Font,
    verticalOffset: number,
  ): void {
    font.setSize(layout.fontSize)
    const lineHeight: number = layout.fontSize * 1.18
    const totalHeight: number = layout.lines.length * lineHeight
    const metrics: drawing.FontMetrics = font.getMetrics()
    const availableOffset: number = Math.max(0, contentHeight - totalHeight)
    const resolvedOffset: number = verticalOffset < 0 ? availableOffset / 2 :
      Math.max(0, Math.min(availableOffset, verticalOffset))
    let baseline: number = rect.top + verticalPadding + resolvedOffset - metrics.ascent
    for (let index: number = 0; index < layout.lines.length; index++) {
      const line: string = layout.lines[index]
      const width: number = font.measureText(line, drawing.TextEncoding.TEXT_ENCODING_UTF8)
      const x: number = rect.left + horizontalPadding + Math.max(0, (contentWidth - width) / 2)
      canvas.drawTextBlob(drawing.TextBlob.makeFromString(line, font), x, baseline)
      baseline += lineHeight
    }
  }

  private static drawPreparedHorizontalLayout(
    canvas: drawing.Canvas,
    prepared: LocalHorizontalRenderLayout,
    font: drawing.Font,
    verticalOffset: number,
  ): void {
    if (prepared.rotationDegrees === 0) {
      ComicLocalVisualBackend.drawHorizontalLayout(
        canvas,
        prepared.layout,
        prepared.rect,
        prepared.horizontalPadding,
        prepared.verticalPadding,
        prepared.contentWidth,
        prepared.contentHeight,
        font,
        verticalOffset,
      )
      return
    }
    canvas.save()
    try {
      canvas.rotate(
        prepared.rotationDegrees,
        prepared.rotationCenterX,
        prepared.rotationCenterY,
      )
      ComicLocalVisualBackend.drawHorizontalLayout(
        canvas,
        prepared.layout,
        prepared.rect,
        prepared.horizontalPadding,
        prepared.verticalPadding,
        prepared.contentWidth,
        prepared.contentHeight,
        font,
        verticalOffset,
      )
    } finally {
      canvas.restore()
    }
  }

  static outlineWidth(fontSize: number): number {
    // The fill pass covers the inner half of the pen stroke, so a 20% pen width leaves
    // roughly one normal glyph-stroke of white outline visible around the final text.
    return Math.max(2.0, Math.min(10.0, fontSize * 0.20))
  }

  private static verticalPageFontCap(
    renderPlans: LocalRenderPlanBlock[],
    imageWidth: number,
    imageHeight: number,
    targetLanguage: string,
  ): number {
    const fittedSizes: number[] = []
    const font: drawing.Font = new drawing.Font()
    font.enableSubpixel(true)
    for (let index: number = 0; index < renderPlans.length; index++) {
      const block: ComicTextBlock = renderPlans[index].block
      const renderStyleHint: string = ComicLocalVisualBackend.renderStyleHint(
        block.styleHint,
        targetLanguage,
      )
      if (renderStyleHint !== LOCAL_VERTICAL_STYLE_HINT) {
        continue
      }
      const translated: string = renderPlans[index].translatedText
      const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
      const rect: LocalRenderRect = ComicLocalVisualBackend.renderTextRect(
        raw,
        imageWidth,
        imageHeight,
        block.styleHint,
        renderStyleHint,
      )
      const horizontalPadding: number = Math.max(4, Math.min(12, rect.width() * 0.08))
      const verticalPadding: number = Math.max(4, Math.min(10, rect.height() * 0.08))
      const contentWidth: number = Math.max(1, rect.width() - horizontalPadding * 2)
      const contentHeight: number = Math.max(1, rect.height() - verticalPadding * 2)
      try {
        const layout: LocalVerticalTextLayout = ComicLocalVisualBackend.verticalLayout(
          translated.trim(),
          contentWidth,
          contentHeight,
          font,
          LOCAL_MAX_FONT_SIZE,
        )
        fittedSizes.push(layout.fontSize)
      } catch (error) {
        DiagnosticLogger.warn(
          'comic-translation',
          'local_font_cap_sample_skipped',
          `block=${block.blockId} direction=vertical reason=${(error as Error).message}`,
        )
      }
    }
    if (fittedSizes.length <= 1) {
      return LOCAL_MAX_FONT_SIZE
    }
    fittedSizes.sort((left: number, right: number): number => left - right)
    return fittedSizes[Math.floor((fittedSizes.length - 1) / 2)]
  }

  private static horizontalPageFontCap(
    renderPlans: LocalRenderPlanBlock[],
    imageWidth: number,
    imageHeight: number,
    targetLanguage: string,
  ): number {
    if (ComicLocalVisualBackend.targetUsesVerticalLayout(targetLanguage)) {
      return LOCAL_MAX_FONT_SIZE
    }
    const fittedSizes: number[] = []
    for (let index: number = 0; index < renderPlans.length; index++) {
      const block: ComicTextBlock = renderPlans[index].block
      if (block.styleHint !== LOCAL_VERTICAL_STYLE_HINT) {
        continue
      }
      const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
      const rect: LocalRenderRect = ComicLocalVisualBackend.renderTextRect(
        raw,
        imageWidth,
        imageHeight,
        block.styleHint,
        LOCAL_HORIZONTAL_STYLE_HINT,
      )
      try {
        const prepared: LocalHorizontalRenderLayout =
          ComicLocalVisualBackend.horizontalRenderLayout(
            block,
            renderPlans[index].translatedText,
            rect,
            LOCAL_MAX_FONT_SIZE,
          )
        fittedSizes.push(prepared.layout.fontSize)
      } catch (error) {
        DiagnosticLogger.warn(
          'comic-translation',
          'local_font_cap_sample_skipped',
          `block=${block.blockId} direction=horizontal reason=${(error as Error).message}`,
        )
      }
    }
    if (fittedSizes.length <= 1) {
      return LOCAL_MAX_FONT_SIZE
    }
    fittedSizes.sort((left: number, right: number): number => left - right)
    return fittedSizes[Math.floor((fittedSizes.length - 1) / 2)]
  }

  private static renderPlans(
    document: ComicPageDocument,
    translations: Map<string, string>,
  ): LocalRenderPlanBlock[] {
    const plans: LocalRenderPlanBlock[] = []
    for (let index: number = 0; index < document.blocks.length; index++) {
      const source: ComicTextBlock = document.blocks[index]
      const translated: string | undefined = translations.get(source.blockId)
      if (translated === undefined || translated.trim().length <= 0) {
        throw new Error('Local comic renderer is missing a translated block')
      }
      const plan: LocalRenderPlanBlock = new LocalRenderPlanBlock()
      plan.block = source.copy()
      plan.translatedText = translated.trim()
      plans.push(plan)
    }
    // Analysis owns semantic grouping. Render-only grouping is applied later only when the
    // pixel-derived closed-balloon boundary independently confirms that several plans share
    // one visual container; adjacency alone never changes this document boundary.
    return plans
  }

  private static bubbleRenderGroups(
    renderPlans: LocalRenderPlanBlock[],
    textRects: LocalRenderRect[],
    fillStyles: LocalFillStyle[],
    targetLanguage: string,
  ): LocalBubbleRenderGroup[] {
    const parent: number[] = []
    for (let index: number = 0; index < renderPlans.length; index++) {
      parent.push(index)
    }
    for (let firstIndex: number = 0; firstIndex < renderPlans.length; firstIndex++) {
      for (let secondIndex: number = firstIndex + 1;
        secondIndex < renderPlans.length; secondIndex++) {
        if (!ComicLocalVisualBackend.shareConfirmedBubble(
          renderPlans[firstIndex].block,
          textRects[firstIndex],
          renderPlans[secondIndex].block,
          textRects[secondIndex],
        )) {
          continue
        }
        const firstRoot: number = ComicLocalVisualBackend.renderGroupRoot(parent, firstIndex)
        const secondRoot: number = ComicLocalVisualBackend.renderGroupRoot(parent, secondIndex)
        if (firstRoot !== secondRoot) {
          parent[secondRoot] = firstRoot
        }
      }
    }
    const membersByRoot: Map<number, number[]> = new Map<number, number[]>()
    for (let index: number = 0; index < renderPlans.length; index++) {
      const root: number = ComicLocalVisualBackend.renderGroupRoot(parent, index)
      const members: number[] | undefined = membersByRoot.get(root)
      if (members === undefined) {
        membersByRoot.set(root, [index])
      } else {
        members.push(index)
      }
    }
    const groups: LocalBubbleRenderGroup[] = []
    membersByRoot.forEach((members: number[]): void => {
      const representative: number = ComicLocalVisualBackend.confirmedBubbleRepresentative(
        members,
        renderPlans,
        textRects,
      )
      if (members.length <= 1 || representative < 0) {
        for (let index: number = 0; index < members.length; index++) {
          groups.push(ComicLocalVisualBackend.singleBubbleRenderGroup(
            members[index],
            renderPlans,
            textRects,
            fillStyles,
          ))
        }
        return
      }
      groups.push(ComicLocalVisualBackend.mergedBubbleRenderGroup(
        members,
        representative,
        renderPlans,
        textRects,
        fillStyles,
        targetLanguage,
      ))
    })
    groups.sort((left: LocalBubbleRenderGroup, right: LocalBubbleRenderGroup): number =>
      left.memberIndexes[0] - right.memberIndexes[0])
    DiagnosticLogger.info(
      'comic-translation',
      'local_bubble_render_groups',
      `plans=${renderPlans.length} groups=${groups.length} ` +
        `merged=${renderPlans.length - groups.length}`,
    )
    return groups
  }

  private static renderGroupRoot(parent: number[], index: number): number {
    let root: number = index
    while (parent[root] !== root) {
      root = parent[root]
    }
    let current: number = index
    while (parent[current] !== current) {
      const next: number = parent[current]
      parent[current] = root
      current = next
    }
    return root
  }

  private static shareConfirmedBubble(
    firstBlock: ComicTextBlock,
    firstRect: LocalRenderRect,
    secondBlock: ComicTextBlock,
    secondRect: LocalRenderRect,
  ): boolean {
    if (firstBlock.styleHint !== LOCAL_VERTICAL_STYLE_HINT ||
      secondBlock.styleHint !== LOCAL_VERTICAL_STYLE_HINT) {
      return false
    }
    return (firstRect.shapeConstrained &&
      ComicLocalVisualBackend.rectContainsBlockCenter(firstRect, secondBlock)) ||
      (secondRect.shapeConstrained &&
      ComicLocalVisualBackend.rectContainsBlockCenter(secondRect, firstBlock))
  }

  private static rectContainsBlockCenter(rect: LocalRenderRect, block: ComicTextBlock): boolean {
    const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
    const centerX: number = (raw.left + raw.right) / 2
    const centerY: number = (raw.top + raw.bottom) / 2
    const tolerance: number = 2
    return centerX >= rect.left - tolerance && centerX <= rect.right + tolerance &&
      centerY >= rect.top - tolerance && centerY <= rect.bottom + tolerance
  }

  private static confirmedBubbleRepresentative(
    members: number[],
    renderPlans: LocalRenderPlanBlock[],
    textRects: LocalRenderRect[],
  ): number {
    let selected: number = -1
    let selectedArea: number = 0
    for (let memberIndex: number = 0; memberIndex < members.length; memberIndex++) {
      const candidateIndex: number = members[memberIndex]
      const candidate: LocalRenderRect = textRects[candidateIndex]
      if (!candidate.shapeConstrained) {
        continue
      }
      let containsAll: boolean = true
      for (let blockIndex: number = 0; blockIndex < members.length; blockIndex++) {
        if (!ComicLocalVisualBackend.rectContainsBlockCenter(
          candidate,
          renderPlans[members[blockIndex]].block,
        )) {
          containsAll = false
          break
        }
      }
      const area: number = candidate.width() * candidate.height()
      if (containsAll && area > selectedArea) {
        selected = candidateIndex
        selectedArea = area
      }
    }
    return selected
  }

  private static singleBubbleRenderGroup(
    index: number,
    renderPlans: LocalRenderPlanBlock[],
    textRects: LocalRenderRect[],
    fillStyles: LocalFillStyle[],
  ): LocalBubbleRenderGroup {
    const group: LocalBubbleRenderGroup = new LocalBubbleRenderGroup()
    group.plan = renderPlans[index]
    group.textRect = textRects[index]
    group.fill = fillStyles[index]
    group.memberIndexes.push(index)
    return group
  }

  private static mergedBubbleRenderGroup(
    members: number[],
    representative: number,
    renderPlans: LocalRenderPlanBlock[],
    textRects: LocalRenderRect[],
    fillStyles: LocalFillStyle[],
    targetLanguage: string,
  ): LocalBubbleRenderGroup {
    const group: LocalBubbleRenderGroup = new LocalBubbleRenderGroup()
    const plan: LocalRenderPlanBlock = new LocalRenderPlanBlock()
    plan.block = renderPlans[members[0]].block.copy()
    const texts: string[] = []
    let left: number = Number.POSITIVE_INFINITY
    let top: number = Number.POSITIVE_INFINITY
    let right: number = Number.NEGATIVE_INFINITY
    let bottom: number = Number.NEGATIVE_INFINITY
    const ids: string[] = []
    for (let index: number = 0; index < members.length; index++) {
      const member: LocalRenderPlanBlock = renderPlans[members[index]]
      const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(member.block.polygon)
      left = Math.min(left, raw.left)
      top = Math.min(top, raw.top)
      right = Math.max(right, raw.right)
      bottom = Math.max(bottom, raw.bottom)
      texts.push(member.translatedText.trim())
      ids.push(member.block.blockId)
      group.memberIndexes.push(members[index])
    }
    plan.block.polygon = [
      new ComicPoint(left, top),
      new ComicPoint(right, top),
      new ComicPoint(right, bottom),
      new ComicPoint(left, bottom),
    ]
    plan.translatedText = texts.join(
      ComicLocalVisualBackend.targetUsesVerticalLayout(targetLanguage) ? '' : ' ',
    )
    group.plan = plan
    group.textRect = ComicLocalVisualBackend.copyRenderRect(textRects[representative])
    group.fill = fillStyles[representative]
    DiagnosticLogger.info(
      'comic-translation',
      'local_bubble_render_group_merged',
      `blocks=${ids.join(',')} rect=${Math.round(group.textRect.left)},` +
        `${Math.round(group.textRect.top)},${Math.round(group.textRect.right)},` +
        `${Math.round(group.textRect.bottom)}`,
    )
    return group
  }

  private static copyRenderRect(source: LocalRenderRect): LocalRenderRect {
    const rect: LocalRenderRect = new LocalRenderRect()
    rect.left = source.left
    rect.top = source.top
    rect.right = source.right
    rect.bottom = source.bottom
    rect.shapeConstrained = source.shapeConstrained
    return rect
  }

  static targetUsesVerticalLayout(targetLanguage: string): boolean {
    const normalized: string = targetLanguage.trim().toLowerCase()
    return normalized === 'zh' || normalized.startsWith('zh-') ||
      normalized === 'ja' || normalized.startsWith('ja-')
  }

  private static renderStyleHint(sourceStyleHint: string, targetLanguage: string): string {
    if (sourceStyleHint === LOCAL_VERTICAL_STYLE_HINT &&
      ComicLocalVisualBackend.targetUsesVerticalLayout(targetLanguage)) {
      return LOCAL_VERTICAL_STYLE_HINT
    }
    return LOCAL_HORIZONTAL_STYLE_HINT
  }

  private static renderTextRect(
    raw: LocalRenderRect,
    imageWidth: number,
    imageHeight: number,
    sourceStyleHint: string,
    renderStyleHint: string,
  ): LocalRenderRect {
    if (sourceStyleHint !== LOCAL_VERTICAL_STYLE_HINT ||
      renderStyleHint !== LOCAL_HORIZONTAL_STYLE_HINT) {
      return ComicLocalVisualBackend.sourceTreatmentRect(
        raw,
        imageWidth,
        imageHeight,
        renderStyleHint,
      )
    }
    const rawWidth: number = Math.max(1, raw.width())
    const rawHeight: number = Math.max(1, raw.height())
    const safeMargin: number = Math.min(16, imageWidth * 0.02, imageHeight * 0.02)
    const availableWidth: number = Math.max(1, imageWidth - safeMargin * 2)
    const availableHeight: number = Math.max(1, imageHeight - safeMargin * 2)
    const preferredWidth: number = Math.max(
      rawWidth + 60,
      rawWidth * 2.2,
      Math.min(320, rawHeight * 0.65),
    )
    // The 360 px expansion cap must not make an already-wide paragraph narrower than its
    // detected source region. Preserving that width reduces Latin line count and keeps the
    // translation inside the original paragraph's vertical footprint instead of crowding
    // artwork beneath it.
    const targetWidth: number = Math.min(
      availableWidth,
      Math.max(rawWidth, Math.min(360, preferredWidth)),
    )
    const targetHeight: number = Math.min(
      availableHeight,
      Math.max(rawHeight, Math.min(180, rawHeight * 1.2)),
    )
    return ComicLocalVisualBackend.pageAwareRect(
      raw,
      targetWidth,
      targetHeight,
      imageWidth,
      imageHeight,
      safeMargin,
    )
  }

  private static async resolvedRenderTextRect(
    pixelMap: image.PixelMap,
    block: ComicTextBlock,
    imageWidth: number,
    imageHeight: number,
    fill: LocalFillStyle,
    targetLanguage: string,
  ): Promise<LocalRenderRect> {
    const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
    const renderStyleHint: string = ComicLocalVisualBackend.renderStyleHint(
      block.styleHint,
      targetLanguage,
    )
    const fallback: LocalRenderRect = ComicLocalVisualBackend.renderTextRect(
      raw,
      imageWidth,
      imageHeight,
      block.styleHint,
      renderStyleHint,
    )
    if (renderStyleHint !== LOCAL_HORIZONTAL_STYLE_HINT) {
      return fallback
    }
    try {
      return await ComicLocalVisualBackend.bubbleSafeTextRect(
        pixelMap,
        raw,
        fallback,
        imageWidth,
        imageHeight,
        fill,
        block.blockId,
      )
    } catch (error) {
      DiagnosticLogger.warn(
        'comic-translation',
        'local_bubble_safe_rect_fallback',
        `block=${block.blockId} message=${(error as Error).message}`,
      )
      return fallback
    }
  }

  private static async bubbleSafeTextRect(
    pixelMap: image.PixelMap,
    raw: LocalRenderRect,
    fallback: LocalRenderRect,
    imageWidth: number,
    imageHeight: number,
    fill: LocalFillStyle,
    blockId: string,
  ): Promise<LocalRenderRect> {
    // The fallback rectangle is intentionally generous for Latin wrapping. Read a bounded
    // neighbourhood around it so a closed balloon outline can constrain that expansion.
    const expansionX: number = Math.min(
      128,
      Math.max(56, fallback.width() * 0.45),
    )
    const expansionY: number = 112
    const left: number = Math.max(0, Math.floor(fallback.left - expansionX))
    const top: number = Math.max(0, Math.floor(fallback.top - expansionY))
    const right: number = Math.min(imageWidth, Math.ceil(fallback.right + expansionX))
    const bottom: number = Math.min(imageHeight, Math.ceil(fallback.bottom + expansionY))
    const width: number = right - left
    const height: number = bottom - top
    if (width <= 4 || height <= 4) {
      return fallback
    }
    const rowBytes: number = width * 4
    const buffer: ArrayBuffer = new ArrayBuffer(rowBytes * height)
    await pixelMap.readPixels({
      pixels: buffer,
      offset: 0,
      stride: rowBytes,
      region: {
        x: left,
        y: top,
        size: { width: width, height: height },
      },
    })
    const pixels: Uint8Array = new Uint8Array(buffer)
    const rawLeft: number = Math.max(0, Math.floor(raw.left) - left)
    const rawTop: number = Math.max(0, Math.floor(raw.top) - top)
    const rawRight: number = Math.min(width, Math.ceil(raw.right) - left)
    const rawBottom: number = Math.min(height, Math.ceil(raw.bottom) - top)
    const centerX: number = Math.max(0, Math.min(width - 1,
      Math.floor((raw.left + raw.right) / 2) - left))
    const centerY: number = Math.max(0, Math.min(height - 1,
      Math.floor((raw.top + raw.bottom) / 2) - top))
    let seed: number = -1
    let seedDistance: number = Number.MAX_VALUE
    for (let y: number = rawTop; y < rawBottom; y++) {
      for (let x: number = rawLeft; x < rawRight; x++) {
        const pixelOffset: number = y * rowBytes + x * 4
        if (!ComicLocalVisualBackend.isBubbleInteriorPixel(pixels, pixelOffset, fill)) {
          continue
        }
        const xDistance: number = x - centerX
        const yDistance: number = y - centerY
        const distance: number = xDistance * xDistance + yDistance * yDistance
        if (distance < seedDistance) {
          seed = y * width + x
          seedDistance = distance
        }
      }
    }
    if (seed < 0) {
      return fallback
    }
    const pixelCount: number = width * height
    const visited: Uint8Array = new Uint8Array(pixelCount)
    const queue: Int32Array = new Int32Array(pixelCount)
    const xCounts: Uint32Array = new Uint32Array(width)
    const yCounts: Uint32Array = new Uint32Array(height)
    let readIndex: number = 0
    let writeIndex: number = 1
    let area: number = 0
    let touchesCandidateEdge: boolean = false
    queue[0] = seed
    visited[seed] = 1
    while (readIndex < writeIndex) {
      const current: number = queue[readIndex]
      readIndex = readIndex + 1
      const x: number = current % width
      const y: number = Math.floor(current / width)
      area = area + 1
      xCounts[x] = xCounts[x] + 1
      yCounts[y] = yCounts[y] + 1
      if (x === 0 || y === 0 || x === width - 1 || y === height - 1) {
        touchesCandidateEdge = true
      }
      if (x > 0) {
        writeIndex = ComicLocalVisualBackend.enqueueBubbleInterior(
          pixels, visited, queue, current - 1, rowBytes, fill, writeIndex,
        )
      }
      if (x + 1 < width) {
        writeIndex = ComicLocalVisualBackend.enqueueBubbleInterior(
          pixels, visited, queue, current + 1, rowBytes, fill, writeIndex,
        )
      }
      if (y > 0) {
        writeIndex = ComicLocalVisualBackend.enqueueBubbleInterior(
          pixels, visited, queue, current - width, rowBytes, fill, writeIndex,
        )
      }
      if (y + 1 < height) {
        writeIndex = ComicLocalVisualBackend.enqueueBubbleInterior(
          pixels, visited, queue, current + width, rowBytes, fill, writeIndex,
        )
      }
    }
    const minimumArea: number = Math.max(64, raw.width() * raw.height() * 0.72)
    if (touchesCandidateEdge || area < minimumArea) {
      return fallback
    }
    // A balloon tail occupies only a small fraction of the connected component. Trim the
    // sparse outer 1.2% before taking bounds so it cannot pull centred prose into the tail.
    const trimCount: number = Math.max(1, Math.floor(area * 0.012))
    let componentLeft: number = 0
    let accumulated: number = 0
    while (componentLeft < width - 1 && accumulated + xCounts[componentLeft] <= trimCount) {
      accumulated = accumulated + xCounts[componentLeft]
      componentLeft = componentLeft + 1
    }
    let componentRight: number = width - 1
    accumulated = 0
    while (componentRight > componentLeft &&
      accumulated + xCounts[componentRight] <= trimCount) {
      accumulated = accumulated + xCounts[componentRight]
      componentRight = componentRight - 1
    }
    let componentTop: number = 0
    accumulated = 0
    while (componentTop < height - 1 && accumulated + yCounts[componentTop] <= trimCount) {
      accumulated = accumulated + yCounts[componentTop]
      componentTop = componentTop + 1
    }
    let componentBottom: number = height - 1
    accumulated = 0
    while (componentBottom > componentTop &&
      accumulated + yCounts[componentBottom] <= trimCount) {
      accumulated = accumulated + yCounts[componentBottom]
      componentBottom = componentBottom - 1
    }
    const componentWidth: number = componentRight - componentLeft + 1
    const componentHeight: number = componentBottom - componentTop + 1
    if (componentWidth < raw.width() * 0.75 || componentHeight < raw.height() * 0.75) {
      return fallback
    }
    const insetX: number = Math.max(4, Math.min(14, componentWidth * 0.035))
    const insetY: number = Math.max(4, Math.min(12, componentHeight * 0.045))
    const safe: LocalRenderRect = new LocalRenderRect()
    safe.left = left + componentLeft + insetX
    safe.top = top + componentTop + insetY
    safe.right = left + componentRight + 1 - insetX
    safe.bottom = top + componentBottom + 1 - insetY
    if (safe.width() < 24 || safe.height() < 24) {
      return fallback
    }
    safe.shapeConstrained = true
    DiagnosticLogger.info(
      'comic-translation',
      'local_bubble_safe_rect',
      `block=${blockId} fallback=${Math.round(fallback.left)},${Math.round(fallback.top)},` +
        `${Math.round(fallback.right)},${Math.round(fallback.bottom)} ` +
        `safe=${Math.round(safe.left)},${Math.round(safe.top)},` +
        `${Math.round(safe.right)},${Math.round(safe.bottom)} area=${area}`,
    )
    return safe
  }

  private static enqueueBubbleInterior(
    pixels: Uint8Array,
    visited: Uint8Array,
    queue: Int32Array,
    pixelIndex: number,
    rowBytes: number,
    fill: LocalFillStyle,
    writeIndex: number,
  ): number {
    if (visited[pixelIndex] !== 0) {
      return writeIndex
    }
    visited[pixelIndex] = 1
    const x: number = pixelIndex % (rowBytes / 4)
    const y: number = Math.floor(pixelIndex / (rowBytes / 4))
    if (!ComicLocalVisualBackend.isBubbleInteriorPixel(
      pixels,
      y * rowBytes + x * 4,
      fill,
    )) {
      return writeIndex
    }
    queue[writeIndex] = pixelIndex
    return writeIndex + 1
  }

  private static isBubbleInteriorPixel(
    pixels: Uint8Array,
    offset: number,
    fill: LocalFillStyle,
  ): boolean {
    // PixelMap.readPixels exposes BGRA_8888 bytes.
    const blue: number = pixels[offset]
    const green: number = pixels[offset + 1]
    const red: number = pixels[offset + 2]
    const colorDelta: number = Math.max(
      Math.abs(red - fill.red),
      Math.abs(green - fill.green),
      Math.abs(blue - fill.blue),
    )
    const luminance: number = red * 0.299 + green * 0.587 + blue * 0.114
    const fillLuminance: number = fill.red * 0.299 + fill.green * 0.587 + fill.blue * 0.114
    return colorDelta <= 56 && Math.abs(luminance - fillLuminance) <= 48
  }

  private static pageAwareRect(
    raw: LocalRenderRect,
    width: number,
    height: number,
    imageWidth: number,
    imageHeight: number,
    safeMargin: number,
  ): LocalRenderRect {
    const rect: LocalRenderRect = new LocalRenderRect()
    const pageCenter: number = imageWidth / 2
    const rawWidth: number = Math.max(1, raw.width())
    if (raw.right <= pageCenter) {
      if (width >= rawWidth) {
        rect.right = raw.right
        rect.left = rect.right - width
      } else {
        rect.left = raw.left
        rect.right = rect.left + width
      }
    } else if (raw.left >= pageCenter) {
      if (width >= rawWidth) {
        rect.left = raw.left
        rect.right = rect.left + width
      } else {
        rect.right = raw.right
        rect.left = rect.right - width
      }
    } else {
      rect.left = (raw.left + raw.right - width) / 2
      rect.right = rect.left + width
    }
    rect.top = (raw.top + raw.bottom - height) / 2
    rect.bottom = rect.top + height
    return ComicLocalVisualBackend.clampRect(
      rect,
      imageWidth,
      imageHeight,
      safeMargin,
    )
  }

  private static centeredRect(
    raw: LocalRenderRect,
    width: number,
    height: number,
    imageWidth: number,
    imageHeight: number,
  ): LocalRenderRect {
    const rect: LocalRenderRect = new LocalRenderRect()
    rect.left = (raw.left + raw.right - width) / 2
    rect.top = (raw.top + raw.bottom - height) / 2
    rect.right = rect.left + width
    rect.bottom = rect.top + height
    if (rect.left < 0) {
      rect.right = rect.right - rect.left
      rect.left = 0
    }
    if (rect.right > imageWidth) {
      rect.left = Math.max(0, rect.left - (rect.right - imageWidth))
      rect.right = imageWidth
    }
    if (rect.top < 0) {
      rect.bottom = rect.bottom - rect.top
      rect.top = 0
    }
    if (rect.bottom > imageHeight) {
      rect.top = Math.max(0, rect.top - (rect.bottom - imageHeight))
      rect.bottom = imageHeight
    }
    return rect
  }

  private static clampRect(
    source: LocalRenderRect,
    imageWidth: number,
    imageHeight: number,
    margin: number,
  ): LocalRenderRect {
    const rect: LocalRenderRect = new LocalRenderRect()
    rect.left = source.left
    rect.top = source.top
    rect.right = source.right
    rect.bottom = source.bottom
    const minimumX: number = margin
    const maximumX: number = Math.max(minimumX, imageWidth - margin)
    const minimumY: number = margin
    const maximumY: number = Math.max(minimumY, imageHeight - margin)
    if (rect.left < minimumX) {
      rect.right = rect.right + (minimumX - rect.left)
      rect.left = minimumX
    }
    if (rect.right > maximumX) {
      rect.left = rect.left - (rect.right - maximumX)
      rect.right = maximumX
    }
    if (rect.top < minimumY) {
      rect.bottom = rect.bottom + (minimumY - rect.top)
      rect.top = minimumY
    }
    if (rect.bottom > maximumY) {
      rect.top = rect.top - (rect.bottom - maximumY)
      rect.bottom = maximumY
    }
    rect.left = Math.max(minimumX, rect.left)
    rect.top = Math.max(minimumY, rect.top)
    return rect
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
    return style
  }

  private static async eraseSourceRegions(
    pixelMap: image.PixelMap,
    imageWidth: number,
    imageHeight: number,
    targets: LocalSourceTreatmentTarget[],
    sourceInpainter: ComicLocalSourceInpainter | null,
    pageTextMask: Uint8Array | null,
  ): Promise<void> {
    if (targets.length <= 0) {
      return
    }
    // AOT needs enough known artwork around the glyph mask. A six-pixel crop leaves narrow
    // vertical text regions almost entirely masked and produces unstable colour hallucinations.
    const border: number = 64
    const treatmentLefts: number[] = []
    const treatmentTops: number[] = []
    const treatmentRights: number[] = []
    const treatmentBottoms: number[] = []
    const rawLefts: number[] = []
    const rawTops: number[] = []
    const rawRights: number[] = []
    const rawBottoms: number[] = []
    const activeTargets: LocalSourceTreatmentTarget[] = []
    let outerLeft: number = imageWidth
    let outerTop: number = imageHeight
    let outerRight: number = 0
    let outerBottom: number = 0
    let largestIndividualEdge: number = 0
    for (let index: number = 0; index < targets.length; index++) {
      const target: LocalSourceTreatmentTarget = targets[index]
      const treatmentLeft: number = Math.max(0, Math.floor(target.treatment.left))
      const treatmentTop: number = Math.max(0, Math.floor(target.treatment.top))
      const treatmentRight: number =
        Math.min(imageWidth, Math.ceil(target.treatment.right))
      const treatmentBottom: number =
        Math.min(imageHeight, Math.ceil(target.treatment.bottom))
      if (treatmentRight <= treatmentLeft || treatmentBottom <= treatmentTop) {
        continue
      }
      treatmentLefts.push(treatmentLeft)
      treatmentTops.push(treatmentTop)
      treatmentRights.push(treatmentRight)
      treatmentBottoms.push(treatmentBottom)
      rawLefts.push(Math.max(treatmentLeft, Math.floor(target.raw.left)))
      rawTops.push(Math.max(treatmentTop, Math.floor(target.raw.top)))
      rawRights.push(target.styleHint === LOCAL_VERTICAL_STYLE_HINT ?
        Math.min(
          treatmentRight,
          Math.ceil(
            target.raw.right + Math.max(8, Math.min(18, target.raw.width() * 0.25)),
          ),
        ) : Math.min(treatmentRight, Math.ceil(target.raw.right)))
      rawBottoms.push(Math.min(treatmentBottom, Math.ceil(target.raw.bottom)))
      activeTargets.push(target)
      const targetOuterLeft: number = Math.max(0, treatmentLeft - border)
      const targetOuterTop: number = Math.max(0, treatmentTop - border)
      const targetOuterRight: number = Math.min(imageWidth, treatmentRight + border)
      const targetOuterBottom: number = Math.min(imageHeight, treatmentBottom + border)
      outerLeft = Math.min(outerLeft, targetOuterLeft)
      outerTop = Math.min(outerTop, targetOuterTop)
      outerRight = Math.max(outerRight, targetOuterRight)
      outerBottom = Math.max(outerBottom, targetOuterBottom)
      largestIndividualEdge = Math.max(
        largestIndividualEdge,
        targetOuterRight - targetOuterLeft,
        targetOuterBottom - targetOuterTop,
      )
    }
    if (treatmentLefts.length <= 0) {
      return
    }
    const width: number = outerRight - outerLeft
    const height: number = outerBottom - outerTop
    if (width <= 1 || height <= 1) {
      return
    }
    // One AOT call is useful only while combining neighbouring columns does not materially
    // reduce the model's effective resolution. Widely spread members keep their old
    // independent treatment even if layout can safely share one large balloon.
    if (activeTargets.length > 1 &&
      Math.max(width, height) > largestIndividualEdge * 1.35) {
      for (let index: number = 0; index < activeTargets.length; index++) {
        await ComicLocalVisualBackend.eraseSourceRegions(
          pixelMap,
          imageWidth,
          imageHeight,
          [activeTargets[index]],
          sourceInpainter,
          pageTextMask,
        )
      }
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
    const maskBuffer: ArrayBuffer = new ArrayBuffer(width * height)
    const mask: Uint8Array = new Uint8Array(maskBuffer)
    const allowed: Uint8Array = new Uint8Array(width * height)
    const fallbackColors: Uint8Array = new Uint8Array(width * height * 3)
    let masked: number = 0
    for (let targetIndex: number = 0;
      targetIndex < treatmentLefts.length; targetIndex++) {
      const background: LocalFillStyle = activeTargets[targetIndex].background
      for (let globalY: number = treatmentTops[targetIndex];
        globalY < treatmentBottoms[targetIndex]; globalY++) {
        const y: number = globalY - outerTop
        for (let globalX: number = treatmentLefts[targetIndex];
          globalX < treatmentRights[targetIndex]; globalX++) {
          const allowedIndex: number = y * width + globalX - outerLeft
          allowed[allowedIndex] = 1
          const colorOffset: number = allowedIndex * 3
          fallbackColors[colorOffset] = background.blue
          fallbackColors[colorOffset + 1] = background.green
          fallbackColors[colorOffset + 2] = background.red
        }
      }
      let targetMasked: number = 0
      for (let globalY: number = rawTops[targetIndex];
        globalY < rawBottoms[targetIndex]; globalY++) {
        const y: number = globalY - outerTop
        for (let globalX: number = rawLefts[targetIndex];
          globalX < rawRights[targetIndex]; globalX++) {
          const x: number = globalX - outerLeft
          let isTextPixel: boolean = false
          if (pageTextMask !== null) {
            isTextPixel = pageTextMask[globalY * imageWidth + globalX] !== 0
          } else {
            const offset: number = y * rowBytes + x * 4
            const blue: number = pixels[offset]
            const green: number = pixels[offset + 1]
            const red: number = pixels[offset + 2]
            const backgroundLuminance: number = background.red * 0.299 +
              background.green * 0.587 + background.blue * 0.114
            const luminance: number = red * 0.299 + green * 0.587 + blue * 0.114
            const colorDelta: number = Math.max(
              Math.abs(red - background.red),
              Math.abs(green - background.green),
              Math.abs(blue - background.blue),
            )
            isTextPixel = Math.abs(luminance - backgroundLuminance) >= 36 && colorDelta >= 44
          }
          if (isTextPixel) {
            targetMasked = targetMasked + 1
            if (mask[y * width + x] === 0) {
              mask[y * width + x] = 1
              masked = masked + 1
            }
          }
        }
      }
      if (targetMasked <= 0 && pageTextMask !== null) {
        throw new Error('Local comic text mask did not cover a translated block')
      }
    }
    if (masked <= 0) {
      return
    }
    for (let dilation: number = 0;
      dilation < LOCAL_TEXT_MASK_DILATION_PASSES; dilation++) {
      const expanded: Uint8Array = new Uint8Array(mask)
      for (let y: number = 1; y < height - 1; y++) {
        for (let x: number = 1; x < width - 1; x++) {
          if (mask[y * width + x] === 0) {
            continue
          }
          for (let yOffset: number = -1; yOffset <= 1; yOffset++) {
            for (let xOffset: number = -1; xOffset <= 1; xOffset++) {
              const expandedX: number = x + xOffset
              const expandedY: number = y + yOffset
              if (allowed[expandedY * width + expandedX] !== 0) {
                expanded[expandedY * width + expandedX] = 1
              }
            }
          }
        }
      }
      mask.set(expanded)
    }
    if (sourceInpainter !== null) {
      try {
        const result: ComicNativeInpaintingResult = await sourceInpainter.inpaint(
          buffer,
          maskBuffer,
          width,
          height,
          rowBytes,
        )
        pixels.set(new Uint8Array(result.pixels))
        await pixelMap.writePixels(area)
        DiagnosticLogger.info(
          'comic-translation',
          'local_source_inpainted',
          `backend=${result.backend} blocks=${activeTargets.length} region=${width}x${height} ` +
          `inference=${result.inferenceWidth}x${result.inferenceHeight} ` +
          `load=${result.modelLoadMs}ms inference=${result.inferenceMs}ms`,
        )
        return
      } catch (error) {
        DiagnosticLogger.warn(
          'comic-translation',
          'local_source_inpaint_failed',
          (error as Error).message,
        )
      }
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
        const colorOffset: number = index * 3
        pixels[offset] = fallbackColors[colorOffset]
        pixels[offset + 1] = fallbackColors[colorOffset + 1]
        pixels[offset + 2] = fallbackColors[colorOffset + 2]
      }
    }
    await pixelMap.writePixels(area)
  }

  private static drawVerticalLayout(
    canvas: drawing.Canvas,
    layout: LocalVerticalTextLayout,
    rect: LocalRenderRect,
    horizontalPadding: number,
    verticalPadding: number,
    contentWidth: number,
    contentHeight: number,
    font: drawing.Font,
  ): void {
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
    maxFontSize: number,
  ): LocalTextLayout {
    const initialSize: number = Math.max(
      LOCAL_MIN_FONT_SIZE,
      Math.min(LOCAL_MAX_FONT_SIZE, maxFontSize, Math.floor(height * 0.62)),
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
      if (/[A-Za-z0-9]/.test(text) &&
        !ComicLocalVisualBackend.latinWordsFit(text, width, size, font)) {
        continue
      }
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
    const normalized: string = text.replace(/[\r\n]+/g, '\n').trim()
    if (/[A-Za-z0-9]/.test(normalized)) {
      return ComicLocalVisualBackend.wrapWords(
        normalized.replace(/\n+/g, ' '),
        width,
        font,
      )
    }
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

  private static wrapWords(text: string, width: number, font: drawing.Font): string[] {
    const lines: string[] = []
    const paragraphs: string[] = text.split('\n')
    for (let paragraphIndex: number = 0;
      paragraphIndex < paragraphs.length; paragraphIndex++) {
      const words: string[] = paragraphs[paragraphIndex].trim().split(/\s+/)
      let current: string = ''
      for (let wordIndex: number = 0; wordIndex < words.length; wordIndex++) {
        const word: string = words[wordIndex]
        if (word.length <= 0) {
          continue
        }
        const candidate: string = current.length > 0 ? `${current} ${word}` : word
        if (font.measureText(candidate, drawing.TextEncoding.TEXT_ENCODING_UTF8) <= width) {
          current = candidate
          continue
        }
        if (current.length > 0) {
          lines.push(current)
          current = ''
        }
        let piece: string = ''
        for (let charIndex: number = 0; charIndex < word.length; charIndex++) {
          const nextPiece: string = piece + word.charAt(charIndex)
          if (piece.length > 0 &&
            font.measureText(nextPiece, drawing.TextEncoding.TEXT_ENCODING_UTF8) > width) {
            lines.push(piece)
            piece = word.charAt(charIndex)
          } else {
            piece = nextPiece
          }
        }
        current = piece
      }
      if (current.length > 0) {
        lines.push(current)
      }
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

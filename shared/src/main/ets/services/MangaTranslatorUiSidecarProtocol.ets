import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import {
  ComicAnalysisState,
  ComicPageDocument,
  ComicPoint,
  ComicSourceOrigin,
  ComicTextBlock,
  ComicTextKind,
  ComicTranslationState,
} from '../model/ComicTranslation'
import {
  ComicBackendTemplate,
  ComicRegionAnalysisResult,
  ComicTranslationBatch,
} from '../model/ComicVisualTranslation'
import { ComicRegionAnalysisRequest } from './ComicVisualTranslationBackend'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'

export const MANGA_TRANSLATOR_UI_BACKEND_ID: string = 'manga-translator-ui'
export const MANGA_TRANSLATOR_UI_PROFILE_ID: string =
  'manga-translator-ui-v1.9.9-nexte-load-text-v2-recall-v2'
export const MANGA_TRANSLATOR_UI_PROTOCOL_REVISION: number = 4
export const MANGA_TRANSLATOR_UI_UPSTREAM_TAG: string = 'v1.9.9'
export const MANGA_TRANSLATOR_UI_UPSTREAM_COMMIT: string =
  '696dc63bd0b4803f96cc3d4f844322cef4910f8e'
export const MANGA_TRANSLATOR_UI_EXPORT_PATH: string = '/translate/export/original'
export const MANGA_TRANSLATOR_UI_IMPORT_PATH: string =
  '/translate/import/json/nexte-load-text-v2'
export const MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH: string = '/auth/login'
export const MANGA_TRANSLATOR_UI_AUTH_CHECK_PATH: string = '/auth/check'
export const MANGA_TRANSLATOR_UI_EXPORT_JSON_ENTRY: string = 'translation.json'
export const MANGA_TRANSLATOR_UI_EXPORT_TEXT_ENTRY: string = 'original.txt'
/**
 * Keeps the sidecar visual-only: OCR text is copied through, then NextE's selected LLM translates it.
 * The detector values pin the upstream v1.9.9 example's recall profile instead of inheriting the
 * stricter Pydantic defaults. Hybrid OCR retries empty/low-confidence 48px lines with MangaOCR.
 */
export const MANGA_TRANSLATOR_UI_VISUAL_ONLY_CONFIG_JSON: string =
  '{"translator":{"translator":"original","target_lang":"CHS"},' +
    '"detector":{"detector":"default","detection_size":2048,"text_threshold":0.5,' +
    '"det_rotate":false,"det_auto_rotate":false,"det_invert":false,' +
    '"det_gamma_correct":false,"box_threshold":0.5,"unclip_ratio":2.5,' +
    '"use_yolo_obb":true,"yolo_obb_conf":0.4,"yolo_obb_iou":0.6,' +
    '"yolo_obb_overlap_threshold":0.1,"min_box_area_ratio":0},' +
    '"ocr":{"ocr":"48px","use_hybrid_ocr":true,"secondary_ocr":"mocr",' +
    '"min_text_length":0,"ignore_bubble":0,"prob":0.1}}'

const MANGA_TRANSLATOR_UI_TEMPLATE_MIME: string =
  'application/vnd.manga-translator-ui.translation+json'
const MAX_EXPORT_JSON_BYTES: number = 4 * 1024 * 1024
const MAX_EXPORT_TEXT_BYTES: number = 1024 * 1024
const MAX_REGIONS: number = 512
const MAX_LINES_PER_REGION: number = 64
const MAX_SOURCE_TEXT_CHARS: number = 8192
const COORDINATE_TOLERANCE: number = 1
const LOW_SIGNAL_ASCII_CONFIDENCE_CEILING: number = 0.5
const LOW_SIGNAL_ASCII_MAX_AREA_RATIO: number = 0.0005

class RawMangaTranslatorUiRegion {
  lines: number[][][] = []
  texts: string[] = []
  text: string = ''
  translation: string = ''
  angle: number = 0
  font_size: number = 0
  fg_colors: number[] = []
  bg_colors: number[] = []
  direction: string = ''
  alignment: string = ''
  target_lang: string = ''
  source_lang: string = ''
  line_spacing: number = 0
  default_stroke_width: number = 0
  adjust_bg_color: boolean = false
  prob: number = 0
}

class RawMangaTranslatorUiPage {
  regions: RawMangaTranslatorUiRegion[] = []
  original_width: number = 0
  original_height: number = 0
  mask_raw: string | null = null
  mask_is_refined: boolean = false
}

class RawMangaTranslatorUiEnvelope {
  temp_image: RawMangaTranslatorUiPage | null = null
}

/**
 * Narrow compatibility protocol for manga-translator-ui v1.9.9.
 *
 * The upstream JSON remains an opaque, regenerable render template. NextE only
 * normalizes the source text and geometry needed by ComicPageDocument, then
 * writes validated translations back to the matching region before /import/json.
 */
export class MangaTranslatorUiSidecarProtocol {
  static parseExport(
    request: ComicRegionAnalysisRequest,
    translationJson: Uint8Array,
    originalText: Uint8Array,
  ): ComicRegionAnalysisResult {
    ComicVisualTranslationContract.validateRegionAnalysisRequest(request)
    MangaTranslatorUiSidecarProtocol.validateExportSizes(translationJson, originalText)
    const jsonText: string = MangaTranslatorUiSidecarProtocol.decode(translationJson)
    const envelope: RawMangaTranslatorUiEnvelope =
      JSON.parse(jsonText) as RawMangaTranslatorUiEnvelope
    const page: RawMangaTranslatorUiPage =
      MangaTranslatorUiSidecarProtocol.requirePage(envelope, request)
    MangaTranslatorUiSidecarProtocol.validateOriginalText(originalText, page.regions.length)
    const filteredLowSignalRegions: boolean =
      MangaTranslatorUiSidecarProtocol.filterLowSignalRegions(
        page,
        request.source.imageWidth,
        request.source.imageHeight,
      )

    const document: ComicPageDocument = new ComicPageDocument()
    document.projectId = request.source.projectId
    document.pageIndex = request.source.pageIndex
    document.imageHash = request.source.imageHash
    document.imageWidth = request.source.imageWidth
    document.imageHeight = request.source.imageHeight
    document.imagePreparationProfile.profileId = MANGA_TRANSLATOR_UI_PROFILE_ID + ':source-original'
    document.imagePreparationProfile.preparedWidth = request.source.imageWidth
    document.imagePreparationProfile.preparedHeight = request.source.imageHeight
    document.imagePreparationProfile.tileCount = 1
    document.analysisRevision = request.requestedDocumentRevision
    document.analysisState = ComicAnalysisState.READY
    document.translationState = ComicTranslationState.MISSING
    document.hasText = page.regions.length > 0

    for (let index: number = 0; index < page.regions.length; index++) {
      document.blocks.push(MangaTranslatorUiSidecarProtocol.normalizeRegion(
        page.regions[index],
        request.source.pageIndex,
        index,
        request.source.imageWidth,
        request.source.imageHeight,
        request.requestedDocumentRevision,
      ))
    }

    const template: ComicBackendTemplate = new ComicBackendTemplate()
    const templatePayload: Uint8Array = filteredLowSignalRegions
      ? new util.TextEncoder().encodeInto(JSON.stringify(envelope))
      : new Uint8Array(translationJson)
    if (templatePayload.length <= 0 || templatePayload.length > MAX_EXPORT_JSON_BYTES) {
      throw new Error('Manga translator UI filtered template size is invalid')
    }
    template.backendId = MANGA_TRANSLATOR_UI_BACKEND_ID
    template.profileId = MANGA_TRANSLATOR_UI_PROFILE_ID
    template.protocolRevision = MANGA_TRANSLATOR_UI_PROTOCOL_REVISION
    template.contentHash = MangaTranslatorUiSidecarProtocol.sha256(templatePayload)
    template.mimeType = MANGA_TRANSLATOR_UI_TEMPLATE_MIME
    template.payload = templatePayload

    const result: ComicRegionAnalysisResult = new ComicRegionAnalysisResult()
    result.backendId = MANGA_TRANSLATOR_UI_BACKEND_ID
    result.profileId = MANGA_TRANSLATOR_UI_PROFILE_ID
    result.regionRevision = request.requestedRegionRevision
    result.document = document
    result.adapterTemplate = template
    ComicVisualTranslationContract.validateRegionAnalysisResult(
      request,
      result.backendId,
      result.profileId,
      result.regionRevision,
      result.document,
      result.adapterTemplate,
    )
    return result
  }

  static buildImportJson(
    document: ComicPageDocument,
    translations: ComicTranslationBatch,
    template: ComicBackendTemplate,
  ): Uint8Array {
    ComicVisualTranslationContract.validateTranslationBatch(document, translations)
    MangaTranslatorUiSidecarProtocol.validateTemplate(template)
    const envelope: RawMangaTranslatorUiEnvelope = JSON.parse(
      MangaTranslatorUiSidecarProtocol.decode(template.payload),
    ) as RawMangaTranslatorUiEnvelope
    const page: RawMangaTranslatorUiPage = MangaTranslatorUiSidecarProtocol.requireTemplatePage(
      envelope,
      document,
    )
    const translated: Map<string, string> = new Map<string, string>()
    for (let index: number = 0; index < translations.blocks.length; index++) {
      translated.set(
        translations.blocks[index].blockId,
        translations.blocks[index].translatedText,
      )
    }
    for (let index: number = 0; index < page.regions.length; index++) {
      const expectedBlockId: string = MangaTranslatorUiSidecarProtocol.blockId(
        document.pageIndex,
        index,
      )
      const block: ComicTextBlock = document.blocks[index]
      const translatedText: string | undefined = translated.get(expectedBlockId)
      if (block.blockId !== expectedBlockId || block.readingOrder !== index ||
        block.sourceText !== page.regions[index].text || translatedText === undefined) {
        throw new Error('Manga translator UI template no longer matches the page document')
      }
      page.regions[index].translation = translatedText
    }
    const output: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify(envelope))
    if (output.length <= 0 || output.length > MAX_EXPORT_JSON_BYTES) {
      throw new Error('Manga translator UI import JSON size is invalid')
    }
    return output
  }

  private static validateExportSizes(translationJson: Uint8Array, originalText: Uint8Array): void {
    if (translationJson.length <= 0 || translationJson.length > MAX_EXPORT_JSON_BYTES ||
      originalText.length > MAX_EXPORT_TEXT_BYTES) {
      throw new Error('Manga translator UI export size is invalid')
    }
  }

  private static validateOriginalText(originalText: Uint8Array, regionCount: number): void {
    const value: string = MangaTranslatorUiSidecarProtocol.decode(originalText)
    if (regionCount > 0 && value.trim().length === 0) {
      throw new Error('Manga translator UI export is missing original text')
    }
  }

  private static requirePage(
    envelope: RawMangaTranslatorUiEnvelope,
    request: ComicRegionAnalysisRequest,
  ): RawMangaTranslatorUiPage {
    if (envelope === null || envelope.temp_image === null ||
      typeof envelope.temp_image !== 'object') {
      throw new Error('Manga translator UI export envelope is invalid')
    }
    const page: RawMangaTranslatorUiPage = envelope.temp_image
    if (page.original_width !== request.source.imageWidth ||
      page.original_height !== request.source.imageHeight ||
      !Array.isArray(page.regions) || page.regions.length > MAX_REGIONS) {
      const regionCount: string = Array.isArray(page.regions)
        ? `${page.regions.length}`
        : 'invalid'
      throw new Error(
        'Manga translator UI export page identity is invalid ' +
          `(source=${request.source.imageWidth}x${request.source.imageHeight},` +
          `export=${page.original_width}x${page.original_height},regions=${regionCount})`,
      )
    }
    return page
  }

  private static requireTemplatePage(
    envelope: RawMangaTranslatorUiEnvelope,
    document: ComicPageDocument,
  ): RawMangaTranslatorUiPage {
    if (envelope === null || envelope.temp_image === null ||
      typeof envelope.temp_image !== 'object') {
      throw new Error('Manga translator UI template envelope is invalid')
    }
    const page: RawMangaTranslatorUiPage = envelope.temp_image
    if (page.original_width !== document.imageWidth ||
      page.original_height !== document.imageHeight ||
      !Array.isArray(page.regions) || page.regions.length !== document.blocks.length ||
      page.regions.length > MAX_REGIONS) {
      throw new Error('Manga translator UI template page identity is invalid')
    }
    for (let index: number = 0; index < page.regions.length; index++) {
      MangaTranslatorUiSidecarProtocol.validatePinnedRegion(page.regions[index])
    }
    return page
  }

  private static normalizeRegion(
    region: RawMangaTranslatorUiRegion,
    pageIndex: number,
    regionIndex: number,
    width: number,
    height: number,
    documentRevision: number,
  ): ComicTextBlock {
    MangaTranslatorUiSidecarProtocol.validatePinnedRegion(region)
    const block: ComicTextBlock = new ComicTextBlock()
    block.blockId = MangaTranslatorUiSidecarProtocol.blockId(pageIndex, regionIndex)
    block.readingOrder = regionIndex
    block.kind = ComicTextKind.OTHER
    block.sourceText = region.text
    block.normalizedSourceText = region.text.trim()
    block.styleHint = region.direction
    block.sourceOrigin = ComicSourceOrigin.OCR
    block.providerConfidence = region.prob >= 0 && region.prob <= 1 ? region.prob : null
    block.sourceRevision = documentRevision
    const polygon: ComicPoint[] = MangaTranslatorUiSidecarProtocol.regionPolygon(region, width, height)
    for (let index: number = 0; index < polygon.length; index++) {
      block.polygon.push(polygon[index])
    }
    return block
  }

  /**
   * High-recall detection can emit tiny low-confidence Latin strokes such as a panel line read as
   * "I". Drop only that narrow, deterministic noise class before the LLM sees it. Clearing the
   * exported mask makes load_text rebuild masking from the retained regions, so a rejected region
   * remains pixel-identical instead of being inpainted without replacement text.
   */
  private static filterLowSignalRegions(
    page: RawMangaTranslatorUiPage,
    width: number,
    height: number,
  ): boolean {
    const retained: RawMangaTranslatorUiRegion[] = []
    let filtered: boolean = false
    for (let index: number = 0; index < page.regions.length; index++) {
      const region: RawMangaTranslatorUiRegion = page.regions[index]
      MangaTranslatorUiSidecarProtocol.validatePinnedRegion(region)
      if (MangaTranslatorUiSidecarProtocol.isLowSignalAsciiRegion(region, width, height)) {
        filtered = true
      } else {
        retained.push(region)
      }
    }
    if (filtered) {
      page.regions = retained
      page.mask_raw = null
      page.mask_is_refined = false
    }
    return filtered
  }

  private static isLowSignalAsciiRegion(
    region: RawMangaTranslatorUiRegion,
    width: number,
    height: number,
  ): boolean {
    if (!/^[A-Za-z]$/.test(region.text.trim()) ||
      region.prob >= LOW_SIGNAL_ASCII_CONFIDENCE_CEILING) {
      return false
    }
    let minX: number = Number.POSITIVE_INFINITY
    let minY: number = Number.POSITIVE_INFINITY
    let maxX: number = Number.NEGATIVE_INFINITY
    let maxY: number = Number.NEGATIVE_INFINITY
    for (let lineIndex: number = 0; lineIndex < region.lines.length; lineIndex++) {
      const line: number[][] = region.lines[lineIndex]
      for (let pointIndex: number = 0; pointIndex < line.length; pointIndex++) {
        minX = Math.min(minX, line[pointIndex][0])
        minY = Math.min(minY, line[pointIndex][1])
        maxX = Math.max(maxX, line[pointIndex][0])
        maxY = Math.max(maxY, line[pointIndex][1])
      }
    }
    const areaRatio: number = ((maxX - minX) * (maxY - minY)) / (width * height)
    return areaRatio <= LOW_SIGNAL_ASCII_MAX_AREA_RATIO
  }

  private static validatePinnedRegion(region: RawMangaTranslatorUiRegion): void {
    if (region === null || typeof region !== 'object' || !Array.isArray(region.lines) ||
      region.lines.length <= 0 || region.lines.length > MAX_LINES_PER_REGION ||
      typeof region.text !== 'string' || region.text.trim().length === 0 ||
      region.text.length > MAX_SOURCE_TEXT_CHARS ||
      typeof region.translation !== 'string' || !Number.isFinite(region.angle) ||
      !Number.isFinite(region.font_size) || !Array.isArray(region.fg_colors) ||
      !Array.isArray(region.bg_colors) || typeof region.direction !== 'string' ||
      typeof region.alignment !== 'string' || typeof region.target_lang !== 'string' ||
      typeof region.source_lang !== 'string' || !Number.isFinite(region.line_spacing) ||
      !Number.isFinite(region.default_stroke_width) ||
      typeof region.adjust_bg_color !== 'boolean' || !Number.isFinite(region.prob)) {
      throw new Error('Manga translator UI region does not match the pinned v1.9.9 profile')
    }
    MangaTranslatorUiSidecarProtocol.validateColor(region.fg_colors)
    MangaTranslatorUiSidecarProtocol.validateColor(region.bg_colors)
    for (let lineIndex: number = 0; lineIndex < region.lines.length; lineIndex++) {
      const line: number[][] = region.lines[lineIndex]
      if (!Array.isArray(line) || line.length !== 4) {
        throw new Error('Manga translator UI region line is invalid')
      }
      for (let pointIndex: number = 0; pointIndex < line.length; pointIndex++) {
        if (!Array.isArray(line[pointIndex]) || line[pointIndex].length !== 2 ||
          !Number.isFinite(line[pointIndex][0]) || !Number.isFinite(line[pointIndex][1])) {
          throw new Error('Manga translator UI region point is invalid')
        }
      }
    }
  }

  private static validateColor(value: number[]): void {
    if (value.length !== 3) {
      throw new Error('Manga translator UI region color is invalid')
    }
    for (let index: number = 0; index < value.length; index++) {
      if (!Number.isFinite(value[index]) || value[index] < 0 || value[index] > 255) {
        throw new Error('Manga translator UI region color is invalid')
      }
    }
  }

  private static regionPolygon(
    region: RawMangaTranslatorUiRegion,
    width: number,
    height: number,
  ): ComicPoint[] {
    let minX: number = Number.POSITIVE_INFINITY
    let minY: number = Number.POSITIVE_INFINITY
    let maxX: number = Number.NEGATIVE_INFINITY
    let maxY: number = Number.NEGATIVE_INFINITY
    for (let lineIndex: number = 0; lineIndex < region.lines.length; lineIndex++) {
      const line: number[][] = region.lines[lineIndex]
      for (let pointIndex: number = 0; pointIndex < line.length; pointIndex++) {
        minX = Math.min(minX, line[pointIndex][0])
        minY = Math.min(minY, line[pointIndex][1])
        maxX = Math.max(maxX, line[pointIndex][0])
        maxY = Math.max(maxY, line[pointIndex][1])
      }
    }
    if (!(maxX > minX) || !(maxY > minY)) {
      throw new Error('Manga translator UI region bounds are invalid')
    }
    const centerX: number = (minX + maxX) / 2
    const centerY: number = (minY + maxY) / 2
    const radians: number = region.angle * Math.PI / 180
    const cosine: number = Math.cos(radians)
    const sine: number = Math.sin(radians)
    const raw: number[][] = [
      [minX, minY],
      [maxX, minY],
      [maxX, maxY],
      [minX, maxY],
    ]
    const output: ComicPoint[] = []
    for (let index: number = 0; index < raw.length; index++) {
      const dx: number = raw[index][0] - centerX
      const dy: number = raw[index][1] - centerY
      const x: number = centerX + dx * cosine - dy * sine
      const y: number = centerY + dx * sine + dy * cosine
      output.push(new ComicPoint(
        MangaTranslatorUiSidecarProtocol.boundedCoordinate(x, width),
        MangaTranslatorUiSidecarProtocol.boundedCoordinate(y, height),
      ))
    }
    return output
  }

  private static boundedCoordinate(value: number, edge: number): number {
    if (!Number.isFinite(value) || value < -COORDINATE_TOLERANCE ||
      value > edge + COORDINATE_TOLERANCE) {
      throw new Error('Manga translator UI region is outside the source image')
    }
    return Math.min(edge, Math.max(0, value))
  }

  private static validateTemplate(template: ComicBackendTemplate): void {
    if (template.backendId !== MANGA_TRANSLATOR_UI_BACKEND_ID ||
      template.profileId !== MANGA_TRANSLATOR_UI_PROFILE_ID ||
      template.protocolRevision !== MANGA_TRANSLATOR_UI_PROTOCOL_REVISION ||
      template.mimeType !== MANGA_TRANSLATOR_UI_TEMPLATE_MIME ||
      template.payload.length <= 0 || template.payload.length > MAX_EXPORT_JSON_BYTES ||
      template.contentHash !== MangaTranslatorUiSidecarProtocol.sha256(template.payload)) {
      throw new Error('Manga translator UI adapter template is invalid')
    }
  }

  private static blockId(pageIndex: number, regionIndex: number): string {
    return 'p' + pageIndex + '-r' + regionIndex
  }

  private static decode(value: Uint8Array): string {
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
    return decoder.decodeToString(value)
  }

  private static sha256(value: Uint8Array): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: value })
    const digest: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < digest.length; index++) {
      parts.push(digest[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}

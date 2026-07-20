import {
  COMIC_TRANSLATION_SCHEMA_VERSION,
  ComicAnalysisState,
  ComicPageDocument,
  ComicPoint,
  ComicQualitySeverity,
  ComicQualitySignal,
  ComicRenderState,
  ComicSourceOrigin,
  ComicTextBlock,
  ComicTextKind,
  ComicTranslationOrigin,
  ComicTranslationState,
} from '../model/ComicTranslation'
import {
  ComicPageAnalysisRequest,
  ComicPageAnalysisResult,
} from './ComicPageAnalyzer'

const MAX_PROVIDER_PAYLOAD_CHARS: number = 2 * 1024 * 1024
const MAX_COMIC_TEXT_BLOCKS: number = 512
const MAX_COMIC_POLYGON_POINTS: number = 64
const MAX_COMIC_QUALITY_SIGNALS: number = 512
const MAX_COMIC_TEXT_CHARS: number = 4096
const MAX_COMIC_SUMMARY_CHARS: number = 4096
const MAX_COMIC_SIGNAL_MESSAGE_CHARS: number = 512
const MAX_COMIC_IDENTIFIER_CHARS: number = 160
const MAX_COMIC_IMAGE_PATH_CHARS: number = 4096
const MAX_COMIC_IMAGE_EDGE: number = 100000
const MAX_COMIC_IMAGE_TILES: number = 4096

class RawComicPoint {
  x: number = 0
  y: number = 0
}

class RawComicTextBlock {
  blockId: string = ''
  readingOrder: number = 0
  kind: string = ''
  sourceText: string = ''
  normalizedSourceText: string = ''
  translatedText: string = ''
  polygon: RawComicPoint[] = []
  speakerId: string = ''
  styleHint: string = ''
  sourceOrigin: string = ''
  translationOrigin: string = ''
  providerConfidence: number | null = null
}

class RawComicQualitySignal {
  code: string = ''
  severity: string = ''
  blockId: string = ''
  message: string = ''
}

class RawComicPageAnalysisPayload {
  schemaVersion: number = 0
  projectId: string = ''
  pageIndex: number = -1
  imageHash: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
  hasText: boolean = false
  pageSummary: string = ''
  blocks: RawComicTextBlock[] = []
  qualitySignals: RawComicQualitySignal[] = []
}

export class ComicPageAnalysisParser {
  static parse(
    request: ComicPageAnalysisRequest,
    rawText: string,
    providerId: string,
    modelId: string,
    analysisPromptVersion: string,
  ): ComicPageAnalysisResult {
    ComicPageAnalysisParser.validateRequest(request)
    const normalizedProviderId: string = ComicPageAnalysisParser.requiredString(
      providerId,
      'provider id',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    const normalizedModelId: string = ComicPageAnalysisParser.requiredString(
      modelId,
      'model id',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    const normalizedPromptVersion: string = ComicPageAnalysisParser.requiredString(
      analysisPromptVersion,
      'analysis prompt version',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    if (rawText.length === 0 || rawText.length > MAX_PROVIDER_PAYLOAD_CHARS) {
      throw new Error('Comic analysis payload size is invalid')
    }

    const raw: RawComicPageAnalysisPayload = JSON.parse(rawText) as RawComicPageAnalysisPayload
    const schemaVersion: number = ComicPageAnalysisParser.safeInteger(raw.schemaVersion)
    if (schemaVersion !== COMIC_TRANSLATION_SCHEMA_VERSION) {
      throw new Error('Unsupported comic translation schema')
    }
    if (ComicPageAnalysisParser.safeString(raw.projectId) !== request.projectId) {
      throw new Error('Comic analysis project identity mismatch')
    }
    if (ComicPageAnalysisParser.safeInteger(raw.pageIndex, -1) !== request.pageIndex) {
      throw new Error('Comic analysis page identity mismatch')
    }
    if (ComicPageAnalysisParser.safeString(raw.imageHash) !== request.imageHash) {
      throw new Error('Comic analysis image identity mismatch')
    }
    const imageWidth: number = ComicPageAnalysisParser.positiveImageEdge(raw.imageWidth, 'width')
    const imageHeight: number = ComicPageAnalysisParser.positiveImageEdge(raw.imageHeight, 'height')
    if (request.sourceWidth > 0 && request.sourceWidth !== imageWidth) {
      throw new Error('Comic analysis image width mismatch')
    }
    if (request.sourceHeight > 0 && request.sourceHeight !== imageHeight) {
      throw new Error('Comic analysis image height mismatch')
    }
    if (typeof raw.hasText !== 'boolean') {
      throw new Error('Comic analysis hasText must be boolean')
    }
    if (!Array.isArray(raw.blocks) || raw.blocks.length > MAX_COMIC_TEXT_BLOCKS) {
      throw new Error('Comic analysis blocks are invalid')
    }
    if (raw.hasText && raw.blocks.length === 0) {
      throw new Error('Comic analysis reported text without blocks')
    }
    if (!raw.hasText && raw.blocks.length > 0) {
      throw new Error('Comic analysis returned blocks for a no-text page')
    }

    const document: ComicPageDocument = new ComicPageDocument()
    document.schemaVersion = schemaVersion
    document.projectId = request.projectId
    document.pageIndex = request.pageIndex
    document.imageHash = request.imageHash
    document.imageWidth = imageWidth
    document.imageHeight = imageHeight
    document.imagePreparationProfile = request.imagePreparationProfile.copy()
    document.analysisRevision = request.requestedAnalysisRevision
    document.analysisState = ComicAnalysisState.READY
    document.renderState = ComicRenderState.UNAVAILABLE
    document.hasText = raw.hasText
    document.pageSummary = ComicPageAnalysisParser.boundedString(
      raw.pageSummary,
      'page summary',
      MAX_COMIC_SUMMARY_CHARS,
    )

    const blockIds: Set<string> = new Set<string>()
    const readingOrders: Set<number> = new Set<number>()
    let translatedBlocks: number = 0
    for (let index: number = 0; index < raw.blocks.length; index++) {
      const block: ComicTextBlock = ComicPageAnalysisParser.normalizeBlock(
        raw.blocks[index],
        request,
        imageWidth,
        imageHeight,
      )
      if (blockIds.has(block.blockId)) {
        throw new Error('Comic analysis block id must be unique')
      }
      if (readingOrders.has(block.readingOrder)) {
        throw new Error('Comic analysis reading order must be unique')
      }
      blockIds.add(block.blockId)
      readingOrders.add(block.readingOrder)
      if (block.translatedText.length > 0) {
        translatedBlocks = translatedBlocks + 1
      }
      document.blocks.push(block)
    }
    document.blocks.sort(
      (left: ComicTextBlock, right: ComicTextBlock): number => left.readingOrder - right.readingOrder,
    )

    let hasErrorSignal: boolean = false
    if (raw.qualitySignals !== undefined && raw.qualitySignals !== null) {
      if (!Array.isArray(raw.qualitySignals)) {
        throw new Error('Comic analysis quality signals must be an array')
      }
      if (raw.qualitySignals.length > MAX_COMIC_QUALITY_SIGNALS) {
        throw new Error('Comic analysis has too many quality signals')
      }
      for (let index: number = 0; index < raw.qualitySignals.length; index++) {
        const signal: ComicQualitySignal = ComicPageAnalysisParser.normalizeSignal(raw.qualitySignals[index])
        if (signal.blockId.length > 0 && !blockIds.has(signal.blockId)) {
          throw new Error('Comic analysis quality signal references an unknown block')
        }
        if (signal.severity === ComicQualitySeverity.ERROR) {
          hasErrorSignal = true
        }
        document.qualitySignals.push(signal)
      }
    }

    if (translatedBlocks === 0) {
      document.translationState = ComicTranslationState.MISSING
      document.translationRevision = 0
    } else if (translatedBlocks < document.blocks.length || hasErrorSignal) {
      document.translationState = ComicTranslationState.REVIEW_REQUIRED
      document.translationRevision = request.requestedTranslationRevision
    } else {
      document.translationState = ComicTranslationState.PROVISIONAL
      document.translationRevision = request.requestedTranslationRevision
    }

    const result: ComicPageAnalysisResult = new ComicPageAnalysisResult()
    result.providerId = normalizedProviderId
    result.modelId = normalizedModelId
    result.analysisPromptVersion = normalizedPromptVersion
    result.document = document
    return result
  }

  private static validateRequest(request: ComicPageAnalysisRequest): void {
    ComicPageAnalysisParser.requiredString(
      request.projectId,
      'request project id',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    if (request.pageIndex < 0 || Math.floor(request.pageIndex) !== request.pageIndex) {
      throw new Error('Comic analysis request page index is invalid')
    }
    ComicPageAnalysisParser.requiredString(
      request.imageFilePath,
      'request image file path',
      MAX_COMIC_IMAGE_PATH_CHARS,
    )
    ComicPageAnalysisParser.requiredString(
      request.imageHash,
      'request image hash',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    if (request.sourceWidth < 0 || request.sourceHeight < 0 ||
      Math.floor(request.sourceWidth) !== request.sourceWidth ||
      Math.floor(request.sourceHeight) !== request.sourceHeight) {
      throw new Error('Comic analysis request image dimensions are invalid')
    }
    if ((request.sourceWidth === 0) !== (request.sourceHeight === 0)) {
      throw new Error('Comic analysis request image dimensions must both be known or unknown')
    }
    if (request.sourceWidth > MAX_COMIC_IMAGE_EDGE || request.sourceHeight > MAX_COMIC_IMAGE_EDGE) {
      throw new Error('Comic analysis request image dimensions are too large')
    }
    ComicPageAnalysisParser.requiredString(
      request.imagePreparationProfile.profileId,
      'request image preparation profile id',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    ComicPageAnalysisParser.requiredString(
      request.imagePreparationProfile.mimeType,
      'request image preparation mime type',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    ComicPageAnalysisParser.positiveImageEdge(
      request.imagePreparationProfile.preparedWidth,
      'preparation width',
    )
    ComicPageAnalysisParser.positiveImageEdge(
      request.imagePreparationProfile.preparedHeight,
      'preparation height',
    )
    if (request.imagePreparationProfile.tileCount <= 0 ||
      request.imagePreparationProfile.tileCount > MAX_COMIC_IMAGE_TILES ||
      Math.floor(request.imagePreparationProfile.tileCount) !== request.imagePreparationProfile.tileCount) {
      throw new Error('Comic analysis request image preparation tile count is invalid')
    }
    if (request.requestedAnalysisRevision <= 0 ||
      Math.floor(request.requestedAnalysisRevision) !== request.requestedAnalysisRevision) {
      throw new Error('Comic analysis request revision is invalid')
    }
    if (request.requestedTranslationRevision <= 0 ||
      Math.floor(request.requestedTranslationRevision) !== request.requestedTranslationRevision) {
      throw new Error('Comic translation request revision is invalid')
    }
  }

  private static normalizeBlock(
    raw: RawComicTextBlock,
    request: ComicPageAnalysisRequest,
    imageWidth: number,
    imageHeight: number,
  ): ComicTextBlock {
    const block: ComicTextBlock = new ComicTextBlock()
    block.blockId = ComicPageAnalysisParser.requiredString(
      raw.blockId,
      'block id',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    block.readingOrder = ComicPageAnalysisParser.safeInteger(raw.readingOrder, -1)
    if (block.readingOrder < 0 || block.readingOrder >= MAX_COMIC_TEXT_BLOCKS) {
      throw new Error('Comic analysis reading order is invalid')
    }
    block.kind = ComicPageAnalysisParser.normalizeTextKind(raw.kind)
    block.sourceText = ComicPageAnalysisParser.requiredString(
      raw.sourceText,
      'source text',
      MAX_COMIC_TEXT_CHARS,
    )
    block.normalizedSourceText = ComicPageAnalysisParser.boundedString(
      raw.normalizedSourceText,
      'normalized source text',
      MAX_COMIC_TEXT_CHARS,
    )
    if (block.normalizedSourceText.length === 0) {
      block.normalizedSourceText = block.sourceText
    }
    block.translatedText = ComicPageAnalysisParser.boundedString(
      raw.translatedText,
      'translated text',
      MAX_COMIC_TEXT_CHARS,
    )
    block.speakerId = ComicPageAnalysisParser.boundedString(
      raw.speakerId,
      'speaker id',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    block.styleHint = ComicPageAnalysisParser.boundedString(
      raw.styleHint,
      'style hint',
      MAX_COMIC_SIGNAL_MESSAGE_CHARS,
    )
    block.sourceOrigin = ComicPageAnalysisParser.normalizeSourceOrigin(raw.sourceOrigin)
    block.translationOrigin = ComicPageAnalysisParser.normalizeTranslationOrigin(
      raw.translationOrigin,
      block.translatedText.length > 0,
    )
    block.providerConfidence = ComicPageAnalysisParser.normalizeConfidence(raw.providerConfidence)
    block.sourceRevision = request.requestedAnalysisRevision
    block.translationRevision = block.translatedText.length > 0 ? request.requestedTranslationRevision : 0
    block.manualSource = false
    block.manualTranslation = false

    if (raw.polygon !== undefined && raw.polygon !== null) {
      if (!Array.isArray(raw.polygon)) {
        throw new Error('Comic analysis polygon must be an array')
      }
      if (raw.polygon.length > MAX_COMIC_POLYGON_POINTS) {
        throw new Error('Comic analysis polygon has too many points')
      }
      if (raw.polygon.length > 0 && raw.polygon.length < 3) {
        throw new Error('Comic analysis polygon must have at least three points')
      }
      for (let index: number = 0; index < raw.polygon.length; index++) {
        const point: ComicPoint = ComicPageAnalysisParser.normalizePoint(
          raw.polygon[index],
          imageWidth,
          imageHeight,
        )
        block.polygon.push(point)
      }
    }
    return block
  }

  private static normalizePoint(raw: RawComicPoint, imageWidth: number, imageHeight: number): ComicPoint {
    if (typeof raw.x !== 'number' || !Number.isFinite(raw.x) ||
      typeof raw.y !== 'number' || !Number.isFinite(raw.y)) {
      throw new Error('Comic analysis polygon point is invalid')
    }
    if (raw.x < 0 || raw.x > imageWidth || raw.y < 0 || raw.y > imageHeight) {
      throw new Error('Comic analysis polygon point is out of bounds')
    }
    return new ComicPoint(raw.x, raw.y)
  }

  private static normalizeSignal(raw: RawComicQualitySignal): ComicQualitySignal {
    const signal: ComicQualitySignal = new ComicQualitySignal()
    signal.code = ComicPageAnalysisParser.requiredString(
      raw.code,
      'quality signal code',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    signal.severity = ComicPageAnalysisParser.normalizeSeverity(raw.severity)
    signal.blockId = ComicPageAnalysisParser.boundedString(
      raw.blockId,
      'quality signal block id',
      MAX_COMIC_IDENTIFIER_CHARS,
    )
    signal.message = ComicPageAnalysisParser.boundedString(
      raw.message,
      'quality signal message',
      MAX_COMIC_SIGNAL_MESSAGE_CHARS,
    )
    return signal
  }

  private static normalizeTextKind(value: string | null | undefined): ComicTextKind {
    const normalized: string = ComicPageAnalysisParser.safeString(value)
    if (normalized === ComicTextKind.DIALOGUE) {
      return ComicTextKind.DIALOGUE
    }
    if (normalized === ComicTextKind.NARRATION) {
      return ComicTextKind.NARRATION
    }
    if (normalized === ComicTextKind.SFX) {
      return ComicTextKind.SFX
    }
    if (normalized === ComicTextKind.ANNOTATION) {
      return ComicTextKind.ANNOTATION
    }
    if (normalized === ComicTextKind.OTHER) {
      return ComicTextKind.OTHER
    }
    throw new Error('Comic analysis text kind is invalid')
  }

  private static normalizeSourceOrigin(value: string | null | undefined): ComicSourceOrigin {
    const normalized: string = ComicPageAnalysisParser.safeString(value)
    if (normalized === ComicSourceOrigin.VISION) {
      return ComicSourceOrigin.VISION
    }
    if (normalized === ComicSourceOrigin.OCR) {
      return ComicSourceOrigin.OCR
    }
    throw new Error('Comic analysis source origin is invalid')
  }

  private static normalizeTranslationOrigin(
    value: string | null | undefined,
    hasTranslation: boolean,
  ): ComicTranslationOrigin {
    const normalized: string = ComicPageAnalysisParser.safeString(value)
    if (!hasTranslation && (normalized.length === 0 || normalized === ComicTranslationOrigin.NONE)) {
      return ComicTranslationOrigin.NONE
    }
    if (hasTranslation && normalized === ComicTranslationOrigin.VISION) {
      return ComicTranslationOrigin.VISION
    }
    if (hasTranslation && normalized === ComicTranslationOrigin.TEXT) {
      return ComicTranslationOrigin.TEXT
    }
    throw new Error('Comic analysis translation origin is invalid')
  }

  private static normalizeSeverity(value: string | null | undefined): ComicQualitySeverity {
    const normalized: string = ComicPageAnalysisParser.safeString(value)
    if (normalized === ComicQualitySeverity.INFO) {
      return ComicQualitySeverity.INFO
    }
    if (normalized === ComicQualitySeverity.WARNING) {
      return ComicQualitySeverity.WARNING
    }
    if (normalized === ComicQualitySeverity.ERROR) {
      return ComicQualitySeverity.ERROR
    }
    throw new Error('Comic analysis quality severity is invalid')
  }

  private static normalizeConfidence(value: number | null | undefined): number | null {
    if (value === undefined || value === null) {
      return null
    }
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) {
      throw new Error('Comic analysis provider confidence is invalid')
    }
    return value
  }

  private static positiveImageEdge(value: number | null | undefined, name: string): number {
    const edge: number = ComicPageAnalysisParser.safeInteger(value)
    if (edge <= 0 || edge > MAX_COMIC_IMAGE_EDGE) {
      throw new Error('Comic analysis image ' + name + ' is invalid')
    }
    return edge
  }

  private static requiredString(
    value: string | null | undefined,
    name: string,
    maxLength: number,
  ): string {
    const normalized: string = ComicPageAnalysisParser.boundedString(value, name, maxLength)
    if (normalized.length === 0) {
      throw new Error('Missing comic analysis ' + name)
    }
    return normalized
  }

  private static boundedString(
    value: string | null | undefined,
    name: string,
    maxLength: number,
  ): string {
    const normalized: string = ComicPageAnalysisParser.safeString(value)
    if (normalized.length > maxLength) {
      throw new Error('Comic analysis ' + name + ' is too long')
    }
    return normalized
  }

  private static safeString(value: string | null | undefined): string {
    if (typeof value !== 'string') {
      return ''
    }
    return value.trim()
  }

  private static safeInteger(value: number | null | undefined, fallback: number = 0): number {
    if (typeof value !== 'number' || !Number.isFinite(value) || Math.floor(value) !== value) {
      return fallback
    }
    return value
  }
}

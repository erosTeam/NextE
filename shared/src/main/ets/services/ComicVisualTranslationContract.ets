import { ComicPageDocument, ComicPoint, ComicTextBlock } from '../model/ComicTranslation'
import {
  COMIC_VISUAL_TRANSLATION_SCHEMA_VERSION,
  ComicBackendTemplate,
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicTranslationBatch,
  ComicVisualTranslationRoute,
} from '../model/ComicVisualTranslation'
import {
  ComicRegionAnalysisRequest,
  ComicRegionRenderRequest,
  ComicTextTranslationRequest,
  ComicVisualPageSource,
  ComicWholePageRenderRequest,
} from './ComicVisualTranslationBackend'

const MAX_COMIC_VISUAL_IDENTIFIER_CHARS: number = 160
const MAX_COMIC_VISUAL_PATH_CHARS: number = 4096
const MAX_COMIC_VISUAL_TEXT_CHARS: number = 8192
const MAX_COMIC_VISUAL_BLOCKS: number = 512
const MAX_COMIC_VISUAL_POLYGON_POINTS: number = 64
const MAX_COMIC_ADAPTER_TEMPLATE_BYTES: number = 4 * 1024 * 1024
const MAX_COMIC_RENDERED_PAGE_BYTES: number = 80 * 1024 * 1024

export class ComicVisualTranslationContract {
  static validateSource(source: ComicVisualPageSource): void {
    if (!ComicVisualTranslationContract.identifier(source.projectId) ||
      !ComicVisualTranslationContract.nonNegativeInteger(source.pageIndex) ||
      !ComicVisualTranslationContract.requiredText(source.imageFilePath, MAX_COMIC_VISUAL_PATH_CHARS) ||
      !ComicVisualTranslationContract.hash(source.imageHash) ||
      !ComicVisualTranslationContract.imageEdge(source.imageWidth) ||
      !ComicVisualTranslationContract.imageEdge(source.imageHeight)) {
      throw new Error('Comic visual source is invalid')
    }
  }

  static validateRegionAnalysisRequest(request: ComicRegionAnalysisRequest): void {
    ComicVisualTranslationContract.validateSource(request.source)
    if (!ComicVisualTranslationContract.positiveInteger(request.requestedRegionRevision) ||
      !ComicVisualTranslationContract.positiveInteger(request.requestedDocumentRevision)) {
      throw new Error('Comic region analysis revision is invalid')
    }
  }

  static validateRegionAnalysisResult(
    request: ComicRegionAnalysisRequest,
    resultBackendId: string,
    resultProfileId: string,
    resultRegionRevision: number,
    document: ComicPageDocument,
    adapterTemplate: ComicBackendTemplate,
  ): void {
    ComicVisualTranslationContract.validateRegionAnalysisRequest(request)
    if (!ComicVisualTranslationContract.identifier(resultBackendId) ||
      !ComicVisualTranslationContract.identifier(resultProfileId) ||
      resultRegionRevision !== request.requestedRegionRevision) {
      throw new Error('Comic region analysis backend identity is invalid')
    }
    ComicVisualTranslationContract.validateRegionDocument(request, document)
    ComicVisualTranslationContract.validateAdapterTemplate(
      adapterTemplate,
      resultBackendId,
      resultProfileId,
    )
  }

  static validateTranslationBatch(
    document: ComicPageDocument,
    batch: ComicTranslationBatch,
  ): void {
    if (batch.projectId !== document.projectId || batch.pageIndex !== document.pageIndex ||
      batch.sourceImageHash !== document.imageHash ||
      !ComicVisualTranslationContract.identifier(batch.targetLanguage) ||
      !ComicVisualTranslationContract.identifier(batch.sourceProfileId) ||
      !ComicVisualTranslationContract.positiveInteger(batch.sourceRevision) ||
      !ComicVisualTranslationContract.identifier(batch.modelId) ||
      !ComicVisualTranslationContract.identifier(batch.promptVersion) ||
      !ComicVisualTranslationContract.hash(batch.contextFingerprint) ||
      !ComicVisualTranslationContract.nonNegativeInteger(batch.glossaryRevision) ||
      !ComicVisualTranslationContract.positiveInteger(batch.translationRevision)) {
      throw new Error('Comic translation batch identity is invalid')
    }
    if (batch.blocks.length !== document.blocks.length ||
      batch.blocks.length > MAX_COMIC_VISUAL_BLOCKS) {
      throw new Error('Comic translation batch block count is invalid')
    }
    const expected: Set<string> = new Set<string>()
    for (let index: number = 0; index < document.blocks.length; index++) {
      expected.add(document.blocks[index].blockId)
    }
    const translated: Set<string> = new Set<string>()
    for (let index: number = 0; index < batch.blocks.length; index++) {
      const blockId: string = batch.blocks[index].blockId
      if (!expected.has(blockId) || translated.has(blockId) ||
        !ComicVisualTranslationContract.identifier(blockId) ||
        !ComicVisualTranslationContract.requiredText(
          batch.blocks[index].translatedText,
          MAX_COMIC_VISUAL_TEXT_CHARS,
        )) {
        throw new Error('Comic translation batch block is invalid')
      }
      translated.add(blockId)
    }
  }

  static validateTextTranslationRequest(request: ComicTextTranslationRequest): void {
    ComicVisualTranslationContract.validateSource(request.source)
    ComicVisualTranslationContract.validateDocumentIdentity(request.source, request.document)
    ComicVisualTranslationContract.validateDocumentBlocks(request.document, true)
    if (!ComicVisualTranslationContract.positiveInteger(request.document.analysisRevision) ||
      !ComicVisualTranslationContract.positiveInteger(request.requestedTranslationRevision) ||
      !ComicVisualTranslationContract.identifier(request.context.sourceLanguage) ||
      !ComicVisualTranslationContract.identifier(request.context.targetLanguage) ||
      !ComicVisualTranslationContract.nonNegativeInteger(request.context.glossaryRevision) ||
      !ComicVisualTranslationContract.nonNegativeInteger(request.context.styleGuideRevision) ||
      !ComicVisualTranslationContract.nonNegativeInteger(request.context.contextRevision) ||
      request.context.glossary.length > 256 ||
      request.context.translationMemory.length > 64 ||
      request.context.previousPages.length > 64) {
      throw new Error('Comic text translation request is invalid')
    }
  }

  static validateStagedRenderRequest(request: ComicRegionRenderRequest): void {
    ComicVisualTranslationContract.validateSource(request.source)
    ComicVisualTranslationContract.validateDocumentIdentity(request.source, request.document)
    ComicVisualTranslationContract.validateTranslationBatch(request.document, request.translations)
    ComicVisualTranslationContract.validateRenderableBlocks(request.document)
    ComicVisualTranslationContract.validateAdapterTemplate(
      request.adapterTemplate,
      request.identity.regionBackendId,
      request.identity.regionProfileId,
    )
    request.identity.assertValid()
    if (request.identity.route !== ComicVisualTranslationRoute.STAGED ||
      request.identity.projectId !== request.source.projectId ||
      request.identity.pageIndex !== request.source.pageIndex ||
      request.identity.sourceImageHash !== request.source.imageHash ||
      request.identity.sourceWidth !== request.source.imageWidth ||
      request.identity.sourceHeight !== request.source.imageHeight ||
      request.identity.regionRevision !== request.regionRevision ||
      request.identity.documentRevision !== request.document.analysisRevision ||
      request.identity.translationSourceProfileId !== request.translations.sourceProfileId ||
      request.identity.translationSourceRevision !== request.translations.sourceRevision ||
      request.identity.translationModelId !== request.translations.modelId ||
      request.identity.translationPromptVersion !== request.translations.promptVersion ||
      request.identity.translationContextFingerprint !== request.translations.contextFingerprint ||
      request.identity.glossaryRevision !== request.translations.glossaryRevision ||
      request.identity.translationRevision !== request.translations.translationRevision ||
      request.identity.targetLanguage !== request.translations.targetLanguage ||
      request.identity.regionBackendId !== request.adapterTemplate.backendId ||
      request.identity.regionProfileId !== request.adapterTemplate.profileId ||
      request.identity.renderBackendId !== request.adapterTemplate.backendId ||
      request.identity.renderProfileId !== request.renderProfile.profileId ||
      request.identity.renderTargetMimeType !== request.renderProfile.targetMimeType ||
      request.identity.sourceTreatmentProfileId !== request.renderProfile.sourceTreatmentProfileId ||
      request.identity.layoutProfileId !== request.renderProfile.layoutProfileId ||
      request.identity.renderRevision !== request.renderProfile.revision ||
      request.renderProfile.targetMimeType.length === 0) {
      throw new Error('Comic staged render request identity mismatch')
    }
  }

  static validateWholePageRenderRequest(request: ComicWholePageRenderRequest): void {
    ComicVisualTranslationContract.validateSource(request.source)
    request.identity.assertValid()
    if (request.identity.route !== ComicVisualTranslationRoute.WHOLE_PAGE_RENDER ||
      request.identity.projectId !== request.source.projectId ||
      request.identity.pageIndex !== request.source.pageIndex ||
      request.identity.sourceImageHash !== request.source.imageHash ||
      request.identity.sourceWidth !== request.source.imageWidth ||
      request.identity.sourceHeight !== request.source.imageHeight ||
      request.identity.targetLanguage !== request.context.targetLanguage) {
      throw new Error('Comic whole-page render request identity mismatch')
    }
  }

  static validateRenderedPage(
    expectedIdentity: ComicRenderedPageIdentity,
    page: ComicRenderedPage,
  ): void {
    expectedIdentity.assertValid()
    page.identity.assertValid()
    if (expectedIdentity.cacheKey() !== page.identity.cacheKey() ||
      !ComicVisualTranslationContract.hash(page.artifactHash) ||
      !ComicVisualTranslationContract.imageMime(page.mimeType) ||
      page.mimeType !== expectedIdentity.renderTargetMimeType ||
      page.width !== expectedIdentity.sourceWidth ||
      page.height !== expectedIdentity.sourceHeight ||
      !ComicVisualTranslationContract.positiveInteger(page.byteLength) ||
      page.byteLength > MAX_COMIC_RENDERED_PAGE_BYTES ||
      !ComicVisualTranslationContract.requiredText(page.localFilePath, MAX_COMIC_VISUAL_PATH_CHARS) ||
      !ComicVisualTranslationContract.nonNegativeInteger(page.createdAt) ||
      !ComicVisualTranslationContract.nonNegativeInteger(page.lastAccessAt) ||
      page.lastAccessAt < page.createdAt) {
      throw new Error('Comic rendered page artifact is invalid')
    }
  }

  static isRenderedPageStale(
    cached: ComicRenderedPage,
    requested: ComicRenderedPageIdentity,
  ): boolean {
    try {
      ComicVisualTranslationContract.validateRenderedPage(cached.identity, cached)
      requested.assertValid()
      return cached.identity.cacheKey() !== requested.cacheKey()
    } catch (_error) {
      return true
    }
  }

  private static validateRegionDocument(
    request: ComicRegionAnalysisRequest,
    document: ComicPageDocument,
  ): void {
    ComicVisualTranslationContract.validateDocumentIdentity(request.source, document)
    if (document.analysisRevision !== request.requestedDocumentRevision) {
      throw new Error('Comic region document revision is invalid')
    }
    ComicVisualTranslationContract.validateDocumentBlocks(document, true)
  }

  private static validateDocumentIdentity(
    source: ComicVisualPageSource,
    document: ComicPageDocument,
  ): void {
    if (document.projectId !== source.projectId || document.pageIndex !== source.pageIndex ||
      document.imageHash !== source.imageHash || document.imageWidth !== source.imageWidth ||
      document.imageHeight !== source.imageHeight) {
      throw new Error('Comic visual document identity mismatch')
    }
  }

  private static validateRenderableBlocks(document: ComicPageDocument): void {
    ComicVisualTranslationContract.validateDocumentBlocks(document, true)
  }

  private static validateDocumentBlocks(
    document: ComicPageDocument,
    requireGeometry: boolean,
  ): void {
    if (document.blocks.length > MAX_COMIC_VISUAL_BLOCKS ||
      (document.hasText && document.blocks.length === 0) ||
      (!document.hasText && document.blocks.length > 0)) {
      throw new Error('Comic visual document block count is invalid')
    }
    const blockIds: Set<string> = new Set<string>()
    const readingOrders: Set<number> = new Set<number>()
    for (let index: number = 0; index < document.blocks.length; index++) {
      const block: ComicTextBlock = document.blocks[index]
      if (!ComicVisualTranslationContract.identifier(block.blockId) ||
        blockIds.has(block.blockId) ||
        !ComicVisualTranslationContract.nonNegativeInteger(block.readingOrder) ||
        readingOrders.has(block.readingOrder) ||
        !ComicVisualTranslationContract.requiredText(block.sourceText, MAX_COMIC_VISUAL_TEXT_CHARS)) {
        throw new Error('Comic visual document block is invalid')
      }
      blockIds.add(block.blockId)
      readingOrders.add(block.readingOrder)
      ComicVisualTranslationContract.validatePolygon(
        block.polygon,
        document.imageWidth,
        document.imageHeight,
        requireGeometry,
      )
    }
  }

  private static validatePolygon(
    polygon: ComicPoint[],
    width: number,
    height: number,
    required: boolean,
  ): void {
    if ((required && polygon.length < 3) || polygon.length > MAX_COMIC_VISUAL_POLYGON_POINTS ||
      (polygon.length > 0 && polygon.length < 3)) {
      throw new Error('Comic visual block geometry is invalid')
    }
    for (let index: number = 0; index < polygon.length; index++) {
      if (!Number.isFinite(polygon[index].x) || !Number.isFinite(polygon[index].y) ||
        polygon[index].x < 0 || polygon[index].x > width ||
        polygon[index].y < 0 || polygon[index].y > height) {
        throw new Error('Comic visual block geometry is out of bounds')
      }
    }
  }

  private static validateAdapterTemplate(
    template: ComicBackendTemplate,
    backendId: string,
    profileId: string,
  ): void {
    if (template.backendId !== backendId || template.profileId !== profileId ||
      !ComicVisualTranslationContract.identifier(template.backendId) ||
      !ComicVisualTranslationContract.identifier(template.profileId) ||
      !ComicVisualTranslationContract.positiveInteger(template.protocolRevision) ||
      !ComicVisualTranslationContract.hash(template.contentHash) ||
      !ComicVisualTranslationContract.requiredText(template.mimeType, 160) ||
      template.payload.length <= 0 || template.payload.length > MAX_COMIC_ADAPTER_TEMPLATE_BYTES) {
      throw new Error('Comic backend adapter template is invalid')
    }
  }

  private static identifier(value: string): boolean {
    return value.length > 0 && value.length <= MAX_COMIC_VISUAL_IDENTIFIER_CHARS &&
      value === value.trim()
  }

  private static requiredText(value: string, maxChars: number): boolean {
    return value.trim().length > 0 && value.length <= maxChars
  }

  private static hash(value: string): boolean {
    return /^[a-f0-9]{64}$/.test(value)
  }

  private static nonNegativeInteger(value: number): boolean {
    return Number.isFinite(value) && value >= 0 && Math.floor(value) === value &&
      value <= Number.MAX_SAFE_INTEGER
  }

  private static positiveInteger(value: number): boolean {
    return value > 0 && ComicVisualTranslationContract.nonNegativeInteger(value)
  }

  private static imageEdge(value: number): boolean {
    return value > 0 && value <= 100000 && ComicVisualTranslationContract.nonNegativeInteger(value)
  }

  private static imageMime(value: string): boolean {
    return value === 'image/png' || value === 'image/jpeg' || value === 'image/webp'
  }
}

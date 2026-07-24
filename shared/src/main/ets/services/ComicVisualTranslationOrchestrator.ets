import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { ComicPageDocument } from '../model/ComicTranslation'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicRenderProfile,
  ComicBlockTranslation,
  ComicTranslationBatch,
  ComicVisualTranslationRoute,
} from '../model/ComicVisualTranslation'
import { ComicPageAnalysisContext } from './ComicPageAnalyzer'
import { ComicResponsesProtocol } from './ComicResponsesProtocol'
import {
  ComicRenderedPageRepository,
  ComicRenderedPageRepositoryContract,
} from './ComicRenderedPageRepository'
import {
  ComicRegionAnalysisRequest,
  ComicRegionRenderBackend,
  ComicRegionRenderRequest,
  ComicTextTranslationRequest,
  ComicTextTranslationResult,
  ComicTextTranslator,
  ComicVisualPageSource,
} from './ComicVisualTranslationBackend'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'
import { ComicTranslationConsistencyService } from './ComicTranslationConsistencyService'
import { ComicTranslationContextService } from './ComicTranslationContextService'
import {
  ComicTranslationRepository,
  ComicTranslationRequestIdentity,
} from './ComicTranslationRepository'
import { MAX_COMIC_PREVIOUS_PAGE_CONTEXT } from './ComicPreviousPageContextPolicy'

const MAX_COMIC_VISUAL_CONTEXT_DOCUMENTS: number = 32
const COMIC_VISUAL_DOCUMENT_PROMPT_VERSION: string = 'visual-staged-document-v1'

export class ComicVisualTranslationRequest {
  source: ComicVisualPageSource = new ComicVisualPageSource()
  context: ComicPageAnalysisContext = new ComicPageAnalysisContext()
  renderProfile: ComicRenderProfile = new ComicRenderProfile()
  requestedRegionRevision: number = 1
  requestedDocumentRevision: number = 1
  requestedTranslationRevision: number = 1
}

export class ComicVisualTranslationRunResult {
  renderedPage: ComicRenderedPage = new ComicRenderedPage()
  cacheHit: boolean = false
}

/** Produces only validated rendered-page artifacts; intermediate documents never become Reader output. */
export class ComicVisualTranslationOrchestrator {
  private readonly regionBackend: ComicRegionRenderBackend
  private readonly translator: ComicTextTranslator
  private readonly documentRepository: ComicTranslationRepository
  private readonly renderedRepository: ComicRenderedPageRepository
  private inFlight: Map<string, Promise<ComicVisualTranslationRunResult>> =
    new Map<string, Promise<ComicVisualTranslationRunResult>>()
  private cacheWritesEnabled: boolean = true

  constructor(
    regionBackend: ComicRegionRenderBackend,
    translator: ComicTextTranslator,
    documentRepository: ComicTranslationRepository,
    renderedRepository: ComicRenderedPageRepository,
  ) {
    this.regionBackend = regionBackend
    this.translator = translator
    this.documentRepository = documentRepository
    this.renderedRepository = renderedRepository
  }

  async run(
    sourceRequest: ComicVisualTranslationRequest,
    forceRefresh: boolean = false,
  ): Promise<ComicVisualTranslationRunResult> {
    ComicVisualTranslationOrchestrator.validateRequest(sourceRequest)
    const request: ComicVisualTranslationRequest =
      ComicVisualTranslationOrchestrator.copyRequest(sourceRequest)
    const baseIdentity: ComicTranslationRequestIdentity = this.documentIdentity(
      request,
      '0'.repeat(64),
    )
    const previous: ComicPageDocument[] = await this.documentRepository.loadPrevious(
      baseIdentity,
      MAX_COMIC_VISUAL_CONTEXT_DOCUMENTS,
    )
    request.context = ComicTranslationContextService.prepare(
      request.context,
      previous,
      request.source.pageIndex,
      MAX_COMIC_PREVIOUS_PAGE_CONTEXT,
    )
    const lookupKey: string = this.lookupKey(request)
    if (!forceRefresh) {
      const cached: ComicRenderedPage | null = await this.renderedRepository.load(lookupKey)
      if (cached !== null && this.matchesPipeline(cached, request)) {
        return ComicVisualTranslationOrchestrator.result(cached, true)
      }
    }
    const existing: Promise<ComicVisualTranslationRunResult> | undefined =
      this.inFlight.get(lookupKey)
    if (existing !== undefined) {
      const shared: ComicVisualTranslationRunResult = await existing
      return ComicVisualTranslationOrchestrator.result(shared.renderedPage, shared.cacheHit)
    }
    const task: Promise<ComicVisualTranslationRunResult> = this.produce(
      request,
      previous,
      lookupKey,
      !forceRefresh,
    )
    this.inFlight.set(lookupKey, task)
    try {
      const completed: ComicVisualTranslationRunResult = await task
      return ComicVisualTranslationOrchestrator.result(
        completed.renderedPage,
        completed.cacheHit,
      )
    } finally {
      if (this.inFlight.get(lookupKey) === task) {
        this.inFlight.delete(lookupKey)
      }
    }
  }

  latestSuccessful(
    source: ComicVisualPageSource,
    targetLanguage: string,
  ): Promise<ComicRenderedPage | null> {
    return this.renderedRepository.loadLatest(source, targetLanguage)
  }

  invalidateCacheWrites(): void {
    this.cacheWritesEnabled = false
  }

  private async produce(
    request: ComicVisualTranslationRequest,
    previous: ComicPageDocument[],
    lookupKey: string,
    allowDocumentReuse: boolean,
  ): Promise<ComicVisualTranslationRunResult> {
    const pipelineStartedAt: number = Date.now()
    let analysisMs: number = 0
    let translationMs: number = 0
    let renderMs: number = 0
    let persistMs: number = 0
    let documentCacheHit: boolean = false
    const analysisRequest: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
    analysisRequest.source = request.source.copy()
    analysisRequest.requestedRegionRevision = request.requestedRegionRevision
    analysisRequest.requestedDocumentRevision = request.requestedDocumentRevision
    let stageStartedAt: number = Date.now()
    const analysis = await this.regionBackend.analyze(analysisRequest)
    analysisMs = Date.now() - stageStartedAt
    ComicVisualTranslationContract.validateRegionAnalysisResult(
      analysisRequest,
      analysis.backendId,
      analysis.profileId,
      analysis.regionRevision,
      analysis.document,
      analysis.adapterTemplate,
    )
    if (!analysis.document.hasText || analysis.document.blocks.length === 0) {
      throw new Error('Comic page contains no detected text')
    }

    const translationRequest: ComicTextTranslationRequest = new ComicTextTranslationRequest()
    translationRequest.source = request.source.copy()
    translationRequest.document = analysis.document.copy()
    translationRequest.context = request.context.copy()
    translationRequest.requestedTranslationRevision = request.requestedTranslationRevision
    const expectedContextFingerprint: string =
      this.translator.contextFingerprint(translationRequest)
    const documentIdentity: ComicTranslationRequestIdentity = this.documentIdentity(
      request,
      expectedContextFingerprint,
    )
    let translation: ComicTextTranslationResult | null = null
    let translatedDocument: ComicPageDocument | null = null
    stageStartedAt = Date.now()
    if (allowDocumentReuse) {
      const cachedDocument: ComicPageDocument | null =
        await this.documentRepository.load(documentIdentity)
      if (cachedDocument !== null) {
        documentCacheHit = true
        translation = this.translationFromDocument(
          request,
          cachedDocument,
          expectedContextFingerprint,
        )
        ComicVisualTranslationContract.validateTranslationBatch(
          analysis.document,
          translation.batch,
        )
        this.validateTranslationIdentity(
          request,
          translation.batch,
          expectedContextFingerprint,
        )
        translatedDocument = ComicTranslationConsistencyService.audit(
          ComicTranslationContextService.applyTranslationBatch(
            analysis.document,
            translation.batch,
            translation.pageSummary,
            request.context.rollingSummary,
          ),
          previous,
        )
        translatedDocument.imagePreparationProfile.profileId = this.regionBackend.profileId()
      }
    }
    if (translation === null || translatedDocument === null) {
      translation = await this.translator.translate(translationRequest)
      ComicVisualTranslationContract.validateTranslationBatch(
        analysis.document,
        translation.batch,
      )
      this.validateTranslationIdentity(
        request,
        translation.batch,
        expectedContextFingerprint,
      )
      translatedDocument = ComicTranslationConsistencyService.audit(
        ComicTranslationContextService.applyTranslationBatch(
          analysis.document,
          translation.batch,
          translation.pageSummary,
          request.context.rollingSummary,
        ),
        previous,
      )
      translatedDocument.imagePreparationProfile.profileId = this.regionBackend.profileId()
    }
    translationMs = Date.now() - stageStartedAt
    const identity: ComicRenderedPageIdentity = this.renderedIdentity(
      request,
      analysis.regionRevision,
      translatedDocument,
      translation,
    )
    const renderRequest: ComicRegionRenderRequest = new ComicRegionRenderRequest()
    renderRequest.source = request.source.copy()
    renderRequest.regionRevision = analysis.regionRevision
    renderRequest.document = translatedDocument.copy()
    renderRequest.translations = translation.batch.copy()
    renderRequest.adapterTemplate = analysis.adapterTemplate.copy()
    renderRequest.renderProfile = request.renderProfile.copy()
    renderRequest.identity = identity.copy()
    stageStartedAt = Date.now()
    const renderedPage: ComicRenderedPage = await this.regionBackend.render(renderRequest)
    renderMs = Date.now() - stageStartedAt
    ComicVisualTranslationContract.validateRenderedPage(identity, renderedPage)

    stageStartedAt = Date.now()
    if (this.cacheWritesEnabled) {
      await this.documentRepository.save(documentIdentity, translatedDocument)
      await this.renderedRepository.save(lookupKey, renderedPage)
    } else {
      await this.renderedRepository.discardArtifact(renderedPage)
    }
    persistMs = Date.now() - stageStartedAt
    DiagnosticLogger.info(
      'comic-translation',
      'local_pipeline_stage_timings',
      `page=${request.source.pageIndex} analysis=${analysisMs}ms ` +
        `translation=${translationMs}ms render=${renderMs}ms persist=${persistMs}ms ` +
        `documentCache=${documentCacheHit ? 1 : 0} ` +
        `total=${Date.now() - pipelineStartedAt}ms`,
    )
    return ComicVisualTranslationOrchestrator.result(renderedPage, false)
  }

  private translationFromDocument(
    request: ComicVisualTranslationRequest,
    document: ComicPageDocument,
    contextFingerprint: string,
  ): ComicTextTranslationResult {
    const batch: ComicTranslationBatch = new ComicTranslationBatch()
    batch.projectId = request.source.projectId
    batch.pageIndex = request.source.pageIndex
    batch.sourceImageHash = request.source.imageHash
    batch.targetLanguage = request.context.targetLanguage
    batch.sourceProfileId = this.translator.sourceProfileId()
    batch.sourceRevision = this.translator.sourceRevision()
    batch.modelId = this.translator.modelId()
    batch.promptVersion = this.translator.promptVersion()
    batch.contextFingerprint = contextFingerprint
    batch.glossaryRevision = request.context.glossaryRevision
    batch.translationRevision = request.requestedTranslationRevision
    for (let index: number = 0; index < document.blocks.length; index++) {
      const block: ComicBlockTranslation = new ComicBlockTranslation()
      block.blockId = document.blocks[index].blockId
      block.translatedText = document.blocks[index].translatedText
      batch.blocks.push(block)
    }
    const result: ComicTextTranslationResult = new ComicTextTranslationResult()
    result.batch = batch
    result.pageSummary = document.pageSummary
    return result
  }

  private renderedIdentity(
    request: ComicVisualTranslationRequest,
    regionRevision: number,
    document: ComicPageDocument,
    translation: ComicTextTranslationResult,
  ): ComicRenderedPageIdentity {
    const identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
    identity.route = ComicVisualTranslationRoute.STAGED
    identity.projectId = request.source.projectId
    identity.pageIndex = request.source.pageIndex
    identity.sourceImageHash = request.source.imageHash
    identity.sourceWidth = request.source.imageWidth
    identity.sourceHeight = request.source.imageHeight
    identity.targetLanguage = translation.batch.targetLanguage
    identity.regionBackendId = this.regionBackend.backendId()
    identity.regionProfileId = this.regionBackend.profileId()
    identity.regionRevision = regionRevision
    identity.documentRevision = document.analysisRevision
    identity.translationSourceProfileId = translation.batch.sourceProfileId
    identity.translationSourceRevision = translation.batch.sourceRevision
    identity.translationModelId = translation.batch.modelId
    identity.translationPromptVersion = translation.batch.promptVersion
    identity.translationContextFingerprint = translation.batch.contextFingerprint
    identity.glossaryRevision = translation.batch.glossaryRevision
    identity.translationRevision = translation.batch.translationRevision
    identity.sourceTreatmentProfileId = request.renderProfile.sourceTreatmentProfileId
    identity.layoutProfileId = request.renderProfile.layoutProfileId
    identity.renderBackendId = this.regionBackend.backendId()
    identity.renderProfileId = request.renderProfile.profileId
    identity.renderTargetMimeType = request.renderProfile.targetMimeType
    identity.renderRevision = request.renderProfile.revision
    identity.assertValid()
    return identity
  }

  private documentIdentity(
    request: ComicVisualTranslationRequest,
    contextFingerprint: string,
  ): ComicTranslationRequestIdentity {
    const identity: ComicTranslationRequestIdentity = new ComicTranslationRequestIdentity()
    identity.projectId = request.source.projectId
    identity.pageIndex = request.source.pageIndex
    identity.imageHash = request.source.imageHash
    identity.imageWidth = request.source.imageWidth
    identity.imageHeight = request.source.imageHeight
    identity.providerId = 'visual-pipeline:' + ComicVisualTranslationOrchestrator.digest(
      JSON.stringify([
        this.regionBackend.backendId(),
        this.regionBackend.profileId(),
        `${this.regionBackend.protocolRevision()}`,
        `${request.requestedRegionRevision}`,
        this.translator.sourceProfileId(),
        `${this.translator.sourceRevision()}`,
        this.translator.promptVersion(),
      ]),
    )
    identity.modelId = this.translator.modelId()
    identity.analysisPromptVersion = COMIC_VISUAL_DOCUMENT_PROMPT_VERSION
    identity.sourceLanguage = request.context.sourceLanguage
    identity.targetLanguage = request.context.targetLanguage
    identity.analysisRevision = request.requestedDocumentRevision
    identity.translationRevision = request.requestedTranslationRevision
    identity.imagePreparationProfileId = this.regionBackend.profileId()
    identity.glossaryRevision = request.context.glossaryRevision
    identity.styleGuideRevision = request.context.styleGuideRevision
    identity.contextRevision = request.context.contextRevision
    identity.contextFingerprint = contextFingerprint
    identity.assertValid()
    return identity
  }

  private lookupKey(request: ComicVisualTranslationRequest): string {
    const contextLines: string[] = ComicResponsesProtocol.contextLines(
      request.context,
      request.source.pageIndex,
    )
    return ComicVisualTranslationOrchestrator.digest(JSON.stringify([
      request.source.projectId,
      `${request.source.pageIndex}`,
      request.source.imageHash,
      `${request.source.imageWidth}`,
      `${request.source.imageHeight}`,
      request.context.sourceLanguage,
      request.context.targetLanguage,
      JSON.stringify(contextLines),
      `${request.context.glossaryRevision}`,
      `${request.context.styleGuideRevision}`,
      `${request.context.contextRevision}`,
      this.regionBackend.backendId(),
      this.regionBackend.profileId(),
      `${this.regionBackend.protocolRevision()}`,
      `${request.requestedRegionRevision}`,
      `${request.requestedDocumentRevision}`,
      this.translator.sourceProfileId(),
      `${this.translator.sourceRevision()}`,
      this.translator.modelId(),
      this.translator.promptVersion(),
      `${request.requestedTranslationRevision}`,
      request.renderProfile.profileId,
      request.renderProfile.sourceTreatmentProfileId,
      request.renderProfile.layoutProfileId,
      request.renderProfile.targetMimeType,
      `${request.renderProfile.revision}`,
    ]))
  }

  private matchesPipeline(
    page: ComicRenderedPage,
    request: ComicVisualTranslationRequest,
  ): boolean {
    return ComicRenderedPageRepositoryContract.matchesScope(
      page,
      request.source,
      request.context.targetLanguage,
    ) && page.identity.route === ComicVisualTranslationRoute.STAGED &&
      page.identity.regionBackendId === this.regionBackend.backendId() &&
      page.identity.regionProfileId === this.regionBackend.profileId() &&
      page.identity.regionRevision === request.requestedRegionRevision &&
      page.identity.documentRevision === request.requestedDocumentRevision &&
      page.identity.translationSourceProfileId === this.translator.sourceProfileId() &&
      page.identity.translationSourceRevision === this.translator.sourceRevision() &&
      page.identity.translationModelId === this.translator.modelId() &&
      page.identity.translationPromptVersion === this.translator.promptVersion() &&
      page.identity.glossaryRevision === request.context.glossaryRevision &&
      page.identity.translationRevision === request.requestedTranslationRevision &&
      page.identity.renderBackendId === this.regionBackend.backendId() &&
      page.identity.renderProfileId === request.renderProfile.profileId &&
      page.identity.sourceTreatmentProfileId === request.renderProfile.sourceTreatmentProfileId &&
      page.identity.layoutProfileId === request.renderProfile.layoutProfileId &&
      page.identity.renderTargetMimeType === request.renderProfile.targetMimeType &&
      page.identity.renderRevision === request.renderProfile.revision
  }

  private validateTranslationIdentity(
    request: ComicVisualTranslationRequest,
    batch: ComicTranslationBatch,
    expectedContextFingerprint: string,
  ): void {
    if (batch.projectId !== request.source.projectId ||
      batch.pageIndex !== request.source.pageIndex ||
      batch.sourceImageHash !== request.source.imageHash ||
      batch.targetLanguage !== request.context.targetLanguage ||
      batch.sourceProfileId !== this.translator.sourceProfileId() ||
      batch.sourceRevision !== this.translator.sourceRevision() ||
      batch.modelId !== this.translator.modelId() ||
      batch.promptVersion !== this.translator.promptVersion() ||
      batch.contextFingerprint !== expectedContextFingerprint ||
      batch.glossaryRevision !== request.context.glossaryRevision ||
      batch.translationRevision !== request.requestedTranslationRevision) {
      throw new Error('Comic translation result identity does not match the active request')
    }
  }

  private static validateRequest(request: ComicVisualTranslationRequest): void {
    ComicVisualTranslationContract.validateSource(request.source)
    if (!ComicVisualTranslationOrchestrator.positiveInteger(request.requestedRegionRevision) ||
      !ComicVisualTranslationOrchestrator.positiveInteger(request.requestedDocumentRevision) ||
      !ComicVisualTranslationOrchestrator.positiveInteger(request.requestedTranslationRevision) ||
      request.renderProfile.profileId.length <= 0 ||
      request.renderProfile.sourceTreatmentProfileId.length <= 0 ||
      request.renderProfile.layoutProfileId.length <= 0 ||
      request.renderProfile.targetMimeType !== 'image/png' ||
      !ComicVisualTranslationOrchestrator.positiveInteger(request.renderProfile.revision)) {
      throw new Error('Comic visual translation request is invalid')
    }
  }

  private static copyRequest(source: ComicVisualTranslationRequest): ComicVisualTranslationRequest {
    const request: ComicVisualTranslationRequest = new ComicVisualTranslationRequest()
    request.source = source.source.copy()
    request.context = source.context.copy()
    request.renderProfile = source.renderProfile.copy()
    request.requestedRegionRevision = source.requestedRegionRevision
    request.requestedDocumentRevision = source.requestedDocumentRevision
    request.requestedTranslationRevision = source.requestedTranslationRevision
    return request
  }

  private static result(
    page: ComicRenderedPage,
    cacheHit: boolean,
  ): ComicVisualTranslationRunResult {
    const result: ComicVisualTranslationRunResult = new ComicVisualTranslationRunResult()
    result.renderedPage = page.copy()
    result.cacheHit = cacheHit
    return result
  }

  private static positiveInteger(value: number): boolean {
    return Number.isFinite(value) && value > 0 && Math.floor(value) === value &&
      value <= Number.MAX_SAFE_INTEGER
  }

  private static digest(value: string): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: new util.TextEncoder().encodeInto(value) })
    const bytes: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}

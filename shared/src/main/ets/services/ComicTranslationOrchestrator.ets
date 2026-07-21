import { ComicPageDocument } from '../model/ComicTranslation'
import {
  ComicPageAnalysisRequest,
  ComicPageAnalysisResult,
  ComicPageAnalyzer,
} from './ComicPageAnalyzer'
import { ComicPageAnalysisParser } from './ComicPageAnalysisParser'
import { ComicTranslationConsistencyService } from './ComicTranslationConsistencyService'
import { ComicTranslationContextService } from './ComicTranslationContextService'
import {
  ComicTranslationRepository,
  ComicTranslationRequestIdentity,
} from './ComicTranslationRepository'
import {
  ComicPreviousPageContextPolicy,
  MAX_COMIC_PREVIOUS_PAGE_CONTEXT,
} from './ComicPreviousPageContextPolicy'

export class ComicTranslationRunResult {
  identity: ComicTranslationRequestIdentity = new ComicTranslationRequestIdentity()
  document: ComicPageDocument = new ComicPageDocument()
  cacheHit: boolean = false
}

const MAX_COMIC_CONSISTENCY_PREVIOUS_PAGES: number = 32

/** Coordinates cache ownership and provider work without publishing Reader UI state. */
export class ComicTranslationOrchestrator {
  private readonly analyzer: ComicPageAnalyzer
  private readonly repository: ComicTranslationRepository
  private inFlight: Map<string, Promise<ComicTranslationRunResult>> = new Map()
  private cacheWritesEnabled: boolean = true

  constructor(analyzer: ComicPageAnalyzer, repository: ComicTranslationRepository) {
    this.analyzer = analyzer
    this.repository = repository
  }

  async run(
    sourceRequest: ComicPageAnalysisRequest,
    forceRefresh: boolean = false,
  ): Promise<ComicTranslationRunResult> {
    ComicPageAnalysisParser.validateRequest(sourceRequest)
    const request: ComicPageAnalysisRequest = ComicTranslationOrchestrator.copyRequest(sourceRequest)
    request.context.previousPages = ComicPreviousPageContextPolicy.normalize(
      request.context.previousPages,
      request.pageIndex,
    )
    const baseIdentity: ComicTranslationRequestIdentity =
      ComicTranslationRequestIdentity.from(request, this.analyzer)
    const previous: ComicPageDocument[] = await this.repository.loadPrevious(
      baseIdentity,
      MAX_COMIC_CONSISTENCY_PREVIOUS_PAGES,
    )
    request.context = ComicTranslationContextService.prepare(
      request.context,
      previous,
      request.pageIndex,
      MAX_COMIC_PREVIOUS_PAGE_CONTEXT,
    )
    const identity: ComicTranslationRequestIdentity =
      ComicTranslationRequestIdentity.from(request, this.analyzer)
    if (!forceRefresh) {
      const cached: ComicPageDocument | null = await this.repository.load(identity)
      if (cached !== null) {
        return ComicTranslationOrchestrator.result(
          identity,
          ComicTranslationConsistencyService.audit(cached, previous),
          true,
        )
      }
    }
    const key: string = identity.cacheKey()
    const existing: Promise<ComicTranslationRunResult> | undefined = this.inFlight.get(key)
    if (existing !== undefined) {
      const shared: ComicTranslationRunResult = await existing
      return ComicTranslationOrchestrator.result(shared.identity, shared.document, shared.cacheHit)
    }
    const task: Promise<ComicTranslationRunResult> = this.analyzeAndSave(
      identity,
      request,
      previous,
    )
    this.inFlight.set(key, task)
    try {
      const completed: ComicTranslationRunResult = await task
      return ComicTranslationOrchestrator.result(
        completed.identity,
        completed.document,
        completed.cacheHit,
      )
    } finally {
      if (this.inFlight.get(key) === task) {
        this.inFlight.delete(key)
      }
    }
  }

  /** Prevents older work from repopulating a generated cache after an explicit clear. */
  invalidateCacheWrites(): void {
    this.cacheWritesEnabled = false
  }

  private async analyzeAndSave(
    identity: ComicTranslationRequestIdentity,
    request: ComicPageAnalysisRequest,
    previous: ComicPageDocument[],
  ): Promise<ComicTranslationRunResult> {
    const analysis: ComicPageAnalysisResult = await this.analyzer.analyze(request)
    if (analysis.providerId !== identity.providerId || analysis.modelId !== identity.modelId ||
      analysis.analysisPromptVersion !== identity.analysisPromptVersion ||
      !identity.matchesDocument(analysis.document)) {
      throw new Error('Comic translation analyzer result identity mismatch')
    }
    if (this.cacheWritesEnabled) {
      await this.repository.save(identity, analysis.document)
    }
    return ComicTranslationOrchestrator.result(
      identity,
      ComicTranslationConsistencyService.audit(analysis.document, previous),
      false,
    )
  }

  private static copyRequest(source: ComicPageAnalysisRequest): ComicPageAnalysisRequest {
    const request: ComicPageAnalysisRequest = new ComicPageAnalysisRequest()
    request.projectId = source.projectId
    request.pageIndex = source.pageIndex
    request.imageFilePath = source.imageFilePath
    request.imageHash = source.imageHash
    request.sourceWidth = source.sourceWidth
    request.sourceHeight = source.sourceHeight
    request.requestedAnalysisRevision = source.requestedAnalysisRevision
    request.requestedTranslationRevision = source.requestedTranslationRevision
    request.imagePreparationProfile = source.imagePreparationProfile.copy()
    request.context = source.context.copy()
    return request
  }

  private static result(
    identity: ComicTranslationRequestIdentity,
    document: ComicPageDocument,
    cacheHit: boolean,
  ): ComicTranslationRunResult {
    const result: ComicTranslationRunResult = new ComicTranslationRunResult()
    result.identity = identity.copy()
    result.document = document.copy()
    result.cacheHit = cacheHit
    return result
  }
}

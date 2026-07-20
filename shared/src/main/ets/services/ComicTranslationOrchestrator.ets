import { ComicPageDocument } from '../model/ComicTranslation'
import {
  ComicPageAnalysisContext,
  ComicPageAnalysisRequest,
  ComicPageAnalysisResult,
  ComicPageAnalyzer,
  ComicPreviousPageContext,
} from './ComicPageAnalyzer'
import {
  ComicTranslationRepository,
  ComicTranslationRequestIdentity,
} from './ComicTranslationRepository'

const MAX_PREVIOUS_PAGE_CONTEXT: number = 2

export class ComicTranslationRunResult {
  identity: ComicTranslationRequestIdentity = new ComicTranslationRequestIdentity()
  document: ComicPageDocument = new ComicPageDocument()
  cacheHit: boolean = false
}

/** Coordinates cache ownership and provider work without publishing Reader UI state. */
export class ComicTranslationOrchestrator {
  private readonly analyzer: ComicPageAnalyzer
  private readonly repository: ComicTranslationRepository
  private inFlight: Map<string, Promise<ComicTranslationRunResult>> = new Map()

  constructor(analyzer: ComicPageAnalyzer, repository: ComicTranslationRepository) {
    this.analyzer = analyzer
    this.repository = repository
  }

  async run(
    request: ComicPageAnalysisRequest,
    forceRefresh: boolean = false,
  ): Promise<ComicTranslationRunResult> {
    const identity: ComicTranslationRequestIdentity =
      ComicTranslationRequestIdentity.from(request, this.analyzer)
    if (!forceRefresh) {
      const cached: ComicPageDocument | null = await this.repository.load(identity)
      if (cached !== null) {
        return ComicTranslationOrchestrator.result(identity, cached, true)
      }
    }
    const key: string = identity.cacheKey()
    const existing: Promise<ComicTranslationRunResult> | undefined = this.inFlight.get(key)
    if (existing !== undefined) {
      const shared: ComicTranslationRunResult = await existing
      return ComicTranslationOrchestrator.result(shared.identity, shared.document, shared.cacheHit)
    }
    const task: Promise<ComicTranslationRunResult> = this.analyzeAndSave(identity, request)
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

  private async analyzeAndSave(
    identity: ComicTranslationRequestIdentity,
    sourceRequest: ComicPageAnalysisRequest,
  ): Promise<ComicTranslationRunResult> {
    const request: ComicPageAnalysisRequest = ComicTranslationOrchestrator.copyRequest(sourceRequest)
    const remainingContext: number = Math.max(
      0,
      MAX_PREVIOUS_PAGE_CONTEXT - request.context.previousPages.length,
    )
    if (remainingContext > 0) {
      const previous: ComicPageDocument[] = await this.repository.loadPrevious(
        identity,
        remainingContext,
      )
      ComicTranslationOrchestrator.mergePreviousContext(request.context, previous)
    }
    const analysis: ComicPageAnalysisResult = await this.analyzer.analyze(request)
    if (analysis.providerId !== identity.providerId || analysis.modelId !== identity.modelId ||
      analysis.analysisPromptVersion !== identity.analysisPromptVersion ||
      !identity.matchesDocument(analysis.document)) {
      throw new Error('Comic translation analyzer result identity mismatch')
    }
    await this.repository.save(identity, analysis.document)
    return ComicTranslationOrchestrator.result(identity, analysis.document, false)
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

  private static mergePreviousContext(
    context: ComicPageAnalysisContext,
    documents: ComicPageDocument[],
  ): void {
    for (let documentIndex: number = 0;
      documentIndex < documents.length && context.previousPages.length < MAX_PREVIOUS_PAGE_CONTEXT;
      documentIndex++) {
      const document: ComicPageDocument = documents[documentIndex]
      let alreadyPresent: boolean = false
      for (let contextIndex: number = 0; contextIndex < context.previousPages.length; contextIndex++) {
        if (context.previousPages[contextIndex].pageIndex === document.pageIndex) {
          alreadyPresent = true
          break
        }
      }
      if (!alreadyPresent) {
        context.previousPages.push(ComicTranslationOrchestrator.previousContext(document))
      }
    }
    context.previousPages.sort(
      (left: ComicPreviousPageContext, right: ComicPreviousPageContext): number =>
        left.pageIndex - right.pageIndex,
    )
  }

  private static previousContext(document: ComicPageDocument): ComicPreviousPageContext {
    const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
    previous.pageIndex = document.pageIndex
    const source: string[] = []
    const translated: string[] = []
    for (let index: number = 0; index < document.blocks.length; index++) {
      const sourceText: string = document.blocks[index].sourceText.trim()
      const translatedText: string = document.blocks[index].translatedText.trim()
      if (sourceText.length > 0) {
        source.push(sourceText)
      }
      if (translatedText.length > 0) {
        translated.push(translatedText)
      }
    }
    previous.sourceText = source.join('\n')
    previous.translatedText = translated.join('\n')
    previous.pageSummary = document.pageSummary
    return previous
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

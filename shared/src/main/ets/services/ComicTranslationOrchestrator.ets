import { ComicPageDocument } from '../model/ComicTranslation'
import {
  ComicPageAnalysisContext,
  ComicPageAnalysisRequest,
  ComicPageAnalysisResult,
  ComicPageAnalyzer,
  ComicPreviousPageContext,
} from './ComicPageAnalyzer'
import { ComicPageAnalysisParser } from './ComicPageAnalysisParser'
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
      MAX_COMIC_PREVIOUS_PAGE_CONTEXT,
    )
    ComicTranslationOrchestrator.mergePreviousContext(
      request.context,
      previous,
      request.pageIndex,
    )
    ComicTranslationOrchestrator.fillRollingSummary(request.context, request.pageIndex)
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
    request: ComicPageAnalysisRequest,
  ): Promise<ComicTranslationRunResult> {
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
    currentPageIndex: number,
  ): void {
    const combined: ComicPreviousPageContext[] = []
    for (let documentIndex: number = 0; documentIndex < documents.length; documentIndex++) {
      combined.push(ComicTranslationOrchestrator.previousContext(documents[documentIndex]))
    }
    for (let contextIndex: number = 0; contextIndex < context.previousPages.length; contextIndex++) {
      combined.push(context.previousPages[contextIndex].copy())
    }
    context.previousPages = ComicPreviousPageContextPolicy.normalize(
      combined,
      currentPageIndex,
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

  private static fillRollingSummary(
    context: ComicPageAnalysisContext,
    currentPageIndex: number,
  ): void {
    if (context.rollingSummary.trim().length > 0) {
      return
    }
    let latestPageIndex: number = -1
    let latestSummary: string = ''
    for (let index: number = 0; index < context.previousPages.length; index++) {
      const page: ComicPreviousPageContext = context.previousPages[index]
      const summary: string = page.pageSummary.trim()
      if (page.pageIndex >= 0 && page.pageIndex < currentPageIndex &&
        page.pageIndex > latestPageIndex && summary.length > 0) {
        latestPageIndex = page.pageIndex
        latestSummary = summary
      }
    }
    context.rollingSummary = latestSummary
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

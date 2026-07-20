import { describe, expect, it } from '@ohos/hypium'
import {
  ComicAnalysisState,
  ComicImagePreparationProfile,
  ComicPageAnalysisRequest,
  ComicPageAnalysisResult,
  ComicPageAnalyzer,
  ComicPageAnalyzerCapabilities,
  ComicPageDocument,
  ComicPreviousPageContext,
  ComicTextBlock,
  ComicTranslationOrchestrator,
  ComicTranslationRunResult,
  ComicTranslationState,
  InMemoryComicTranslationRepository,
} from 'shared'

const HASH_A: string = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
const HASH_B: string = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

function request(
  pageIndex: number = 0,
  imageHash: string = HASH_A,
  targetLanguage: string = 'zh-CN',
): ComicPageAnalysisRequest {
  const profile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
  profile.profileId = 'fixture-jpeg-v1'
  profile.mimeType = 'image/jpeg'
  profile.preparedWidth = 1200
  profile.preparedHeight = 1800

  const value: ComicPageAnalysisRequest = new ComicPageAnalysisRequest()
  value.projectId = 'fixture-project:zh-CN'
  value.pageIndex = pageIndex
  value.imageFilePath = `/fixture/page-${pageIndex}.jpg`
  value.imageHash = imageHash
  value.sourceWidth = 1200
  value.sourceHeight = 1800
  value.requestedAnalysisRevision = 1
  value.requestedTranslationRevision = 1
  value.imagePreparationProfile = profile
  value.context.sourceLanguage = 'ja'
  value.context.targetLanguage = targetLanguage
  value.context.glossaryRevision = 1
  value.context.styleGuideRevision = 1
  value.context.contextRevision = pageIndex + 1
  return value
}

function previousContext(
  pageIndex: number,
  translatedText: string,
  pageSummary: string = '',
): ComicPreviousPageContext {
  const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
  previous.pageIndex = pageIndex
  previous.sourceText = `caller-source-${pageIndex}`
  previous.translatedText = translatedText
  previous.pageSummary = pageSummary
  return previous
}

class OrchestratorFakeAnalyzer implements ComicPageAnalyzer {
  analyzeCount: number = 0
  failNext: boolean = false
  noTextNext: boolean = false
  capturedPreviousPages: number[] = []
  capturedPreviousTranslations: string[] = []
  capturedRollingSummary: string = ''
  translationSuffix: string = ''
  private readonly provider: string
  private readonly model: string
  private readonly prompt: string

  constructor(
    provider: string = 'fixture-provider',
    model: string = 'fixture-model',
    prompt: string = 'fixture-prompt-v1',
  ) {
    this.provider = provider
    this.model = model
    this.prompt = prompt
  }

  providerId(): string {
    return this.provider
  }

  modelId(): string {
    return this.model
  }

  analysisPromptVersion(): string {
    return this.prompt
  }

  capabilities(): ComicPageAnalyzerCapabilities {
    const capabilities: ComicPageAnalyzerCapabilities = new ComicPageAnalyzerCapabilities()
    capabilities.transcript = true
    capabilities.readingOrder = true
    capabilities.contextAwareTranslation = true
    return capabilities
  }

  async analyze(value: ComicPageAnalysisRequest): Promise<ComicPageAnalysisResult> {
    this.analyzeCount++
    this.capturedPreviousPages = []
    this.capturedPreviousTranslations = []
    this.capturedRollingSummary = value.context.rollingSummary
    for (let index: number = 0; index < value.context.previousPages.length; index++) {
      this.capturedPreviousPages.push(value.context.previousPages[index].pageIndex)
      this.capturedPreviousTranslations.push(value.context.previousPages[index].translatedText)
    }
    await Promise.resolve()
    if (this.failNext) {
      this.failNext = false
      throw new Error('fixture provider failure')
    }
    const document: ComicPageDocument = new ComicPageDocument()
    document.projectId = value.projectId
    document.pageIndex = value.pageIndex
    document.imageHash = value.imageHash
    document.imageWidth = value.sourceWidth
    document.imageHeight = value.sourceHeight
    document.imagePreparationProfile = value.imagePreparationProfile.copy()
    document.analysisRevision = value.requestedAnalysisRevision
    document.translationRevision = value.requestedTranslationRevision
    document.analysisState = ComicAnalysisState.READY
    document.translationState = ComicTranslationState.PROVISIONAL
    document.hasText = true
    document.pageSummary = `summary-${value.pageIndex}`
    if (this.noTextNext) {
      this.noTextNext = false
      document.translationRevision = 0
      document.translationState = ComicTranslationState.MISSING
      document.hasText = false
      const noTextResult: ComicPageAnalysisResult = new ComicPageAnalysisResult()
      noTextResult.providerId = this.provider
      noTextResult.modelId = this.model
      noTextResult.analysisPromptVersion = this.prompt
      noTextResult.document = document
      return noTextResult
    }
    const block: ComicTextBlock = new ComicTextBlock()
    block.blockId = `p${value.pageIndex}-b0`
    block.readingOrder = 0
    block.sourceText = `source-${value.pageIndex}`
    block.translatedText = `translation-${value.pageIndex}${this.translationSuffix}`
    document.blocks.push(block)

    const result: ComicPageAnalysisResult = new ComicPageAnalysisResult()
    result.providerId = this.provider
    result.modelId = this.model
    result.analysisPromptVersion = this.prompt
    result.document = document
    return result
  }
}

export default function comicTranslationOrchestratorTest(): void {
  describe('Comic translation orchestrator', () => {
    it('returns a copied cache hit without repeating provider work', 0, async (done: Function) => {
      const repository: InMemoryComicTranslationRepository =
        new InMemoryComicTranslationRepository()
      const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
      const orchestrator: ComicTranslationOrchestrator =
        new ComicTranslationOrchestrator(analyzer, repository)
      const first: ComicTranslationRunResult = await orchestrator.run(request())
      first.document.blocks[0].translatedText = 'mutated caller copy'
      const second: ComicTranslationRunResult = await orchestrator.run(request())
      expect(first.cacheHit).assertEqual(false)
      expect(second.cacheHit).assertEqual(true)
      expect(second.document.blocks[0].translatedText).assertEqual('translation-0')
      expect(analyzer.analyzeCount).assertEqual(1)
      done()
    })

    it('accepts and caches a valid no-text page with no translation revision', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        analyzer.noTextNext = true
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)
        const first: ComicTranslationRunResult = await orchestrator.run(request())
        const second: ComicTranslationRunResult = await orchestrator.run(request())
        expect(first.cacheHit).assertEqual(false)
        expect(first.document.hasText).assertEqual(false)
        expect(first.document.translationRevision).assertEqual(0)
        expect(first.document.translationState).assertEqual(ComicTranslationState.MISSING)
        expect(second.cacheHit).assertEqual(true)
        expect(second.document.hasText).assertEqual(false)
        expect(analyzer.analyzeCount).assertEqual(1)
        done()
      })

    it('deduplicates concurrent work for the exact request identity', 0, async (done: Function) => {
      const repository: InMemoryComicTranslationRepository =
        new InMemoryComicTranslationRepository()
      const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
      const orchestrator: ComicTranslationOrchestrator =
        new ComicTranslationOrchestrator(analyzer, repository)
      const pending: Promise<ComicTranslationRunResult>[] = [
        orchestrator.run(request()),
        orchestrator.run(request()),
      ]
      const results: ComicTranslationRunResult[] = await Promise.all(pending)
      expect(results.length).assertEqual(2)
      expect(analyzer.analyzeCount).assertEqual(1)
      expect(results[0].identity.cacheKey()).assertEqual(results[1].identity.cacheKey())
      done()
    })

    it('loads at most two prior pages as ordered context', 0, async (done: Function) => {
      const repository: InMemoryComicTranslationRepository =
        new InMemoryComicTranslationRepository()
      const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
      const orchestrator: ComicTranslationOrchestrator =
        new ComicTranslationOrchestrator(analyzer, repository)
      await orchestrator.run(request(0, HASH_A))
      await orchestrator.run(request(1, HASH_B))
      await orchestrator.run(request(2, HASH_A))
      expect(analyzer.capturedPreviousPages.length).assertEqual(2)
      expect(analyzer.capturedPreviousPages[0]).assertEqual(0)
      expect(analyzer.capturedPreviousPages[1]).assertEqual(1)
      expect(analyzer.capturedRollingSummary).assertEqual('summary-1')
      done()
    })

    it('normalizes caller context before repository merge and cache identity', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)
        await orchestrator.run(request(0, HASH_A))
        await orchestrator.run(request(1, HASH_B))
        await orchestrator.run(request(2, HASH_A))

        const first: ComicPageAnalysisRequest = request(3, HASH_B)
        first.context.previousPages = [
          previousContext(3, 'current-page-must-not-pass'),
          previousContext(0, 'stale-caller-page'),
          previousContext(2, 'caller-page-2-old'),
          previousContext(-1, 'negative-page-must-not-pass'),
          previousContext(2, 'caller-page-2', 'caller-summary-2'),
          previousContext(4, 'future-page-must-not-pass'),
        ]
        const firstResult: ComicTranslationRunResult = await orchestrator.run(first)
        expect(firstResult.cacheHit).assertEqual(false)
        expect(analyzer.capturedPreviousPages.length).assertEqual(2)
        expect(analyzer.capturedPreviousPages[0]).assertEqual(1)
        expect(analyzer.capturedPreviousPages[1]).assertEqual(2)
        expect(analyzer.capturedPreviousTranslations[0]).assertEqual('translation-1')
        expect(analyzer.capturedPreviousTranslations[1]).assertEqual('caller-page-2')
        expect(analyzer.capturedRollingSummary).assertEqual('caller-summary-2')

        const second: ComicPageAnalysisRequest = request(3, HASH_B)
        second.context.previousPages = [
          previousContext(0, 'changed-but-still-omitted'),
          previousContext(2, 'caller-page-2', 'caller-summary-2'),
          previousContext(99, 'changed-future-page'),
        ]
        const secondResult: ComicTranslationRunResult = await orchestrator.run(second)
        expect(secondResult.cacheHit).assertEqual(true)
        expect(analyzer.analyzeCount).assertEqual(4)
        done()
      })

    it('preserves an explicit rolling summary instead of replacing it from page cache', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)
        await orchestrator.run(request(0, HASH_A))
        const next: ComicPageAnalysisRequest = request(1, HASH_B)
        next.context.rollingSummary = 'caller-owned summary'
        await orchestrator.run(next)
        expect(analyzer.capturedRollingSummary).assertEqual('caller-owned summary')
        done()
      })

    it('separates image, language, model and prompt cache identities', 0, async (done: Function) => {
      const repository: InMemoryComicTranslationRepository =
        new InMemoryComicTranslationRepository()
      const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
      const orchestrator: ComicTranslationOrchestrator =
        new ComicTranslationOrchestrator(analyzer, repository)
      await orchestrator.run(request(0, HASH_A, 'zh-CN'))
      await orchestrator.run(request(0, HASH_B, 'zh-CN'))
      await orchestrator.run(request(0, HASH_A, 'en'))
      expect(analyzer.analyzeCount).assertEqual(3)

      const otherAnalyzer: OrchestratorFakeAnalyzer =
        new OrchestratorFakeAnalyzer('fixture-provider', 'fixture-model-2', 'fixture-prompt-v2')
      const otherOrchestrator: ComicTranslationOrchestrator =
        new ComicTranslationOrchestrator(otherAnalyzer, repository)
      await otherOrchestrator.run(request(0, HASH_A, 'zh-CN'))
      expect(otherAnalyzer.analyzeCount).assertEqual(1)
      done()
    })

    it('keeps the last successful document after a failed forced refresh', 0, async (done: Function) => {
      const repository: InMemoryComicTranslationRepository =
        new InMemoryComicTranslationRepository()
      const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
      const orchestrator: ComicTranslationOrchestrator =
        new ComicTranslationOrchestrator(analyzer, repository)
      await orchestrator.run(request())
      analyzer.failNext = true
      let failed: boolean = false
      try {
        await orchestrator.run(request(), true)
      } catch (_error) {
        failed = true
      }
      const restored: ComicTranslationRunResult = await orchestrator.run(request())
      expect(failed).assertEqual(true)
      expect(restored.cacheHit).assertEqual(true)
      expect(restored.document.blocks[0].translatedText).assertEqual('translation-0')
      expect(analyzer.analyzeCount).assertEqual(2)
      done()
    })

    it('invalidates a downstream cache entry when actual previous-page context changes', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)
        await orchestrator.run(request(0, HASH_A))
        await orchestrator.run(request(1, HASH_B))
        analyzer.translationSuffix = '-revised'
        await orchestrator.run(request(0, HASH_A), true)
        const rerun: ComicTranslationRunResult = await orchestrator.run(request(1, HASH_B))
        expect(rerun.cacheHit).assertEqual(false)
        expect(analyzer.analyzeCount).assertEqual(4)
        expect(analyzer.capturedPreviousTranslations[0]).assertEqual('translation-0-revised')
        done()
      })
  })
}

import { describe, expect, it } from '@ohos/hypium'
import {
  ComicAnalysisState,
  ComicGlossaryTerm,
  ComicImagePreparationProfile,
  ComicPageAnalysisRequest,
  ComicPageAnalysisResult,
  ComicPageAnalyzer,
  ComicPageAnalyzerCapabilities,
  ComicPageDocument,
  ComicPreviousPageContext,
  ComicQualitySeverity,
  ComicQualitySignal,
  ComicResponsesProtocol,
  ComicTextBlock,
  ComicTranslationConsistencyService,
  ComicTranslationMemoryService,
  ComicTranslationOrchestrator,
  ComicTranslationRunResult,
  ComicTranslationState,
  ComicTranslationMemoryEntry,
  COMIC_TRANSLATION_CONSISTENCY_SIGNAL_CODE,
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
  capturedMemorySources: string[] = []
  capturedMemoryTranslations: string[] = []
  capturedMemoryOccurrences: number[] = []
  capturedRollingSummary: string = ''
  translationSuffix: string = ''
  sourceTextOverride: string = ''
  translatedTextOverride: string = ''
  qualitySignalSeverity: ComicQualitySeverity | null = null
  qualitySignalPageLevel: boolean = false
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

  contextFingerprint(request: ComicPageAnalysisRequest): string {
    return ComicResponsesProtocol.contextFingerprint(request)
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
    this.capturedMemorySources = []
    this.capturedMemoryTranslations = []
    this.capturedMemoryOccurrences = []
    this.capturedRollingSummary = value.context.rollingSummary
    for (let index: number = 0; index < value.context.previousPages.length; index++) {
      this.capturedPreviousPages.push(value.context.previousPages[index].pageIndex)
      this.capturedPreviousTranslations.push(value.context.previousPages[index].translatedText)
    }
    for (let index: number = 0; index < value.context.translationMemory.length; index++) {
      this.capturedMemorySources.push(value.context.translationMemory[index].sourceText)
      this.capturedMemoryTranslations.push(value.context.translationMemory[index].translatedText)
      this.capturedMemoryOccurrences.push(value.context.translationMemory[index].occurrenceCount)
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
    block.sourceText = this.sourceTextOverride.length > 0
      ? this.sourceTextOverride
      : `source-${value.pageIndex}`
    block.normalizedSourceText = block.sourceText
    block.translatedText = this.translatedTextOverride.length > 0
      ? this.translatedTextOverride
      : `translation-${value.pageIndex}${this.translationSuffix}`
    document.blocks.push(block)
    if (this.qualitySignalSeverity !== null) {
      const signal: ComicQualitySignal = new ComicQualitySignal()
      signal.code = 'fixture_review'
      signal.severity = this.qualitySignalSeverity
      signal.blockId = this.qualitySignalPageLevel ? '' : block.blockId
      document.qualitySignals.push(signal)
    }

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

    it('reuses cache when only prompt-omitted context tails change', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)
        const sharedPrefix: string = 'visible-prefix-' + 'x'.repeat(6000)
        const first: ComicPageAnalysisRequest = request()
        first.context.rollingSummary = sharedPrefix + '-omitted-a'
        const firstResult: ComicTranslationRunResult = await orchestrator.run(first)
        const second: ComicPageAnalysisRequest = request()
        second.context.rollingSummary = sharedPrefix + '-omitted-b'
        const secondResult: ComicTranslationRunResult = await orchestrator.run(second)
        expect(firstResult.cacheHit).assertEqual(false)
        expect(secondResult.cacheHit).assertEqual(true)
        expect(analyzer.analyzeCount).assertEqual(1)

        const changed: ComicPageAnalysisRequest = request()
        changed.context.rollingSummary = 'changed-visible-prefix-' + 'x'.repeat(6000)
        const changedResult: ComicTranslationRunResult = await orchestrator.run(changed)
        expect(changedResult.cacheHit).assertEqual(false)
        expect(analyzer.analyzeCount).assertEqual(2)
        done()
      })

    it('rejects malformed numeric identity before analyzer work', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)
        const invalid: ComicPageAnalysisRequest[] = []
        const invalidPage: ComicPageAnalysisRequest = request()
        invalidPage.pageIndex = Number.NaN
        invalid.push(invalidPage)
        const invalidWidth: ComicPageAnalysisRequest = request()
        invalidWidth.sourceWidth = Number.POSITIVE_INFINITY
        invalid.push(invalidWidth)
        const invalidRevision: ComicPageAnalysisRequest = request()
        invalidRevision.requestedAnalysisRevision = 1.5
        invalid.push(invalidRevision)
        const invalidContextRevision: ComicPageAnalysisRequest = request()
        invalidContextRevision.context.contextRevision = Number.POSITIVE_INFINITY
        invalid.push(invalidContextRevision)
        let rejected: number = 0
        for (let index: number = 0; index < invalid.length; index++) {
          try {
            await orchestrator.run(invalid[index])
          } catch (_error) {
            rejected++
          }
        }
        expect(rejected).assertEqual(invalid.length)
        expect(analyzer.analyzeCount).assertEqual(0)
        done()
      })

    it('rejects oversized context collections before analyzer work', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)
        const oversizedGlossary: ComicPageAnalysisRequest = request()
        for (let index: number = 0; index < 257; index++) {
          oversizedGlossary.context.glossary.push(new ComicGlossaryTerm())
        }
        const oversizedAliases: ComicPageAnalysisRequest = request()
        const aliasedTerm: ComicGlossaryTerm = new ComicGlossaryTerm()
        for (let index: number = 0; index < 65; index++) {
          aliasedTerm.aliases.push(`alias-${index}`)
        }
        oversizedAliases.context.glossary.push(aliasedTerm)
        const oversizedPrevious: ComicPageAnalysisRequest = request(65)
        for (let index: number = 0; index < 65; index++) {
          oversizedPrevious.context.previousPages.push(previousContext(index, `page-${index}`))
        }
        const oversizedMemory: ComicPageAnalysisRequest = request(65)
        for (let index: number = 0; index < 65; index++) {
          oversizedMemory.context.translationMemory.push(new ComicTranslationMemoryEntry())
        }
        const invalid: ComicPageAnalysisRequest[] = [
          oversizedGlossary,
          oversizedAliases,
          oversizedPrevious,
          oversizedMemory,
        ]
        let rejected: number = 0
        for (let index: number = 0; index < invalid.length; index++) {
          try {
            await orchestrator.run(invalid[index])
          } catch (_error) {
            rejected++
          }
        }
        expect(rejected).assertEqual(invalid.length)
        expect(analyzer.analyzeCount).assertEqual(0)
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

    it('keeps review-targeted generated text out of later model context', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)
        await orchestrator.run(request(0, HASH_A))
        analyzer.qualitySignalSeverity = ComicQualitySeverity.INFO
        await orchestrator.run(request(1, HASH_B))
        analyzer.qualitySignalSeverity = ComicQualitySeverity.WARNING
        await orchestrator.run(request(2, HASH_A))
        analyzer.qualitySignalPageLevel = true
        await orchestrator.run(request(3, HASH_B))
        analyzer.qualitySignalSeverity = null
        analyzer.qualitySignalPageLevel = false
        await orchestrator.run(request(4, HASH_A))

        expect(analyzer.capturedPreviousPages.length).assertEqual(2)
        expect(analyzer.capturedPreviousPages[0]).assertEqual(1)
        expect(analyzer.capturedPreviousPages[1]).assertEqual(2)
        expect(analyzer.capturedPreviousTranslations[0]).assertEqual('translation-1')
        expect(analyzer.capturedPreviousTranslations[1]).assertEqual('')
        expect(analyzer.capturedRollingSummary).assertEqual('summary-2')
        done()
      })

    it('flags gallery translation drift beyond the two-page prompt window', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)

        analyzer.sourceTextOverride = '優'
        analyzer.translatedTextOverride = '优'
        await orchestrator.run(request(0, HASH_A))
        analyzer.sourceTextOverride = '兄'
        analyzer.translatedTextOverride = '哥哥'
        await orchestrator.run(request(1, HASH_B))
        analyzer.sourceTextOverride = '駅'
        analyzer.translatedTextOverride = '车站'
        await orchestrator.run(request(2, HASH_A))
        analyzer.sourceTextOverride = '優'
        analyzer.translatedTextOverride = '小优'
        const drifted: ComicTranslationRunResult = await orchestrator.run(request(3, HASH_B))

        expect(analyzer.capturedPreviousPages.length).assertEqual(2)
        expect(analyzer.capturedPreviousPages[0]).assertEqual(1)
        expect(analyzer.capturedPreviousPages[1]).assertEqual(2)
        expect(drifted.document.qualitySignals.length).assertEqual(1)
        expect(drifted.document.qualitySignals[0].code)
          .assertEqual(COMIC_TRANSLATION_CONSISTENCY_SIGNAL_CODE)
        expect(drifted.document.qualitySignals[0].blockId).assertEqual('p3-b0')
        expect(ComicTranslationConsistencyService.hasConflict(drifted.document, 'p3-b0'))
          .assertEqual(true)
        expect(ComicTranslationConsistencyService.hasConflict(drifted.document, 'p2-b0'))
          .assertEqual(false)

        const persisted: ComicPageDocument | null = await repository.load(drifted.identity)
        expect(persisted?.qualitySignals.length).assertEqual(0)
        expect((await repository.loadPrevious(drifted.identity, Number.NaN)).length).assertEqual(0)
        expect((await repository.loadPrevious(
          drifted.identity,
          Number.POSITIVE_INFINITY,
        )).length).assertEqual(0)
        const cached: ComicTranslationRunResult = await orchestrator.run(request(3, HASH_B))
        expect(cached.cacheHit).assertEqual(true)
        expect(cached.document.qualitySignals.length).assertEqual(1)
        done()
      })

    it('does not treat an informational consistency code as an actionable conflict', 0,
      (done: Function) => {
        const previous: ComicPageDocument = new ComicPageDocument()
        previous.hasText = true
        const previousBlock: ComicTextBlock = new ComicTextBlock()
        previousBlock.blockId = 'p0-b0'
        previousBlock.sourceText = '優'
        previousBlock.normalizedSourceText = '優'
        previousBlock.translatedText = '优'
        previous.blocks.push(previousBlock)

        const current: ComicPageDocument = new ComicPageDocument()
        current.hasText = true
        const currentBlock: ComicTextBlock = new ComicTextBlock()
        currentBlock.blockId = 'p1-b0'
        currentBlock.sourceText = '優'
        currentBlock.normalizedSourceText = '優'
        currentBlock.translatedText = '小优'
        current.blocks.push(currentBlock)
        const informational: ComicQualitySignal = new ComicQualitySignal()
        informational.code = COMIC_TRANSLATION_CONSISTENCY_SIGNAL_CODE
        informational.severity = ComicQualitySeverity.INFO
        informational.blockId = currentBlock.blockId
        informational.message = 'provider metadata only'
        current.qualitySignals.push(informational)

        expect(ComicTranslationConsistencyService.hasConflict(
          current,
          currentBlock.blockId,
        )).assertEqual(false)
        const audited: ComicPageDocument = ComicTranslationConsistencyService.audit(
          current,
          [previous],
        )
        expect(audited.qualitySignals.length).assertEqual(2)
        expect(audited.qualitySignals[0].severity).assertEqual(ComicQualitySeverity.INFO)
        expect(audited.qualitySignals[1].severity).assertEqual(ComicQualitySeverity.WARNING)
        expect(ComicTranslationConsistencyService.hasConflict(
          audited,
          currentBlock.blockId,
        )).assertEqual(true)
        done()
      })

    it('ignores review-targeted evidence during consistency audit', 0,
      (done: Function) => {
        const previous: ComicPageDocument = new ComicPageDocument()
        previous.hasText = true
        previous.translationState = ComicTranslationState.PROVISIONAL
        const previousBlock: ComicTextBlock = new ComicTextBlock()
        previousBlock.blockId = 'p0-b0'
        previousBlock.sourceText = '優'
        previousBlock.normalizedSourceText = '優'
        previousBlock.translatedText = '优'
        previous.blocks.push(previousBlock)
        const historicalSignal: ComicQualitySignal = new ComicQualitySignal()
        historicalSignal.code = 'provider_note'
        historicalSignal.severity = ComicQualitySeverity.INFO
        historicalSignal.blockId = previousBlock.blockId
        previous.qualitySignals.push(historicalSignal)

        const current: ComicPageDocument = new ComicPageDocument()
        current.hasText = true
        current.translationState = ComicTranslationState.PROVISIONAL
        const currentBlock: ComicTextBlock = new ComicTextBlock()
        currentBlock.blockId = 'p1-b0'
        currentBlock.sourceText = '優'
        currentBlock.normalizedSourceText = '優'
        currentBlock.translatedText = '小优'
        current.blocks.push(currentBlock)
        expect(ComicTranslationConsistencyService.audit(
          current,
          [previous],
        ).qualitySignals.length).assertEqual(1)

        historicalSignal.severity = ComicQualitySeverity.WARNING
        expect(ComicTranslationConsistencyService.audit(
          current,
          [previous],
        ).qualitySignals.length).assertEqual(0)
        historicalSignal.blockId = ''
        expect(ComicTranslationConsistencyService.audit(
          current,
          [previous],
        ).qualitySignals.length).assertEqual(0)

        previous.qualitySignals = []
        previous.translationState = ComicTranslationState.REVIEW_REQUIRED
        const missing: ComicTextBlock = new ComicTextBlock()
        missing.blockId = 'p0-b1'
        missing.sourceText = '兄'
        missing.normalizedSourceText = '兄'
        previous.blocks.push(missing)
        expect(ComicTranslationConsistencyService.audit(
          current,
          [previous],
        ).qualitySignals.length).assertEqual(1)

        previous.translationState = ComicTranslationState.PROVISIONAL
        const currentWarning: ComicQualitySignal = new ComicQualitySignal()
        currentWarning.code = 'uncertain_text'
        currentWarning.severity = ComicQualitySeverity.WARNING
        currentWarning.blockId = currentBlock.blockId
        current.qualitySignals.push(currentWarning)
        const currentAudited: ComicPageDocument = ComicTranslationConsistencyService.audit(
          current,
          [previous],
        )
        expect(currentAudited.qualitySignals.length).assertEqual(1)
        expect(ComicTranslationConsistencyService.hasConflict(
          currentAudited,
          currentBlock.blockId,
        )).assertEqual(false)
        done()
      })

    it('prioritizes a local conflict over saturated informational metadata', 0,
      (done: Function) => {
        const previous: ComicPageDocument = new ComicPageDocument()
        previous.hasText = true
        const previousBlock: ComicTextBlock = new ComicTextBlock()
        previousBlock.blockId = 'p0-b0'
        previousBlock.sourceText = '優'
        previousBlock.normalizedSourceText = '優'
        previousBlock.translatedText = '优'
        previous.blocks.push(previousBlock)

        const current: ComicPageDocument = new ComicPageDocument()
        current.hasText = true
        const currentBlock: ComicTextBlock = new ComicTextBlock()
        currentBlock.blockId = 'p1-b0'
        currentBlock.sourceText = '優'
        currentBlock.normalizedSourceText = '優'
        currentBlock.translatedText = '小优'
        current.blocks.push(currentBlock)
        const metadataBlock: ComicTextBlock = new ComicTextBlock()
        metadataBlock.blockId = 'p1-b1'
        metadataBlock.sourceText = '注'
        metadataBlock.normalizedSourceText = '注'
        metadataBlock.translatedText = '注'
        current.blocks.push(metadataBlock)
        for (let index: number = 0; index < 512; index++) {
          const informational: ComicQualitySignal = new ComicQualitySignal()
          informational.code = `provider_info_${index}`
          informational.severity = ComicQualitySeverity.INFO
          informational.blockId = metadataBlock.blockId
          current.qualitySignals.push(informational)
        }

        const audited: ComicPageDocument = ComicTranslationConsistencyService.audit(
          current,
          [previous],
        )
        expect(audited.qualitySignals.length).assertEqual(512)
        expect(audited.qualitySignals[510].code).assertEqual('provider_info_510')
        expect(audited.qualitySignals[511].code)
          .assertEqual(COMIC_TRANSLATION_CONSISTENCY_SIGNAL_CODE)
        expect(current.qualitySignals[511].code).assertEqual('provider_info_511')

        for (let index: number = 0; index < current.qualitySignals.length; index++) {
          current.qualitySignals[index].severity = ComicQualitySeverity.WARNING
        }
        const fullyActionable: ComicPageDocument = ComicTranslationConsistencyService.audit(
          current,
          [previous],
        )
        expect(fullyActionable.qualitySignals.length).assertEqual(512)
        expect(ComicTranslationConsistencyService.hasConflict(
          fullyActionable,
          currentBlock.blockId,
        )).assertEqual(false)
        expect(current.qualitySignals[511].code).assertEqual('provider_info_511')
        done()
      })

    it('carries stable exact translation memory beyond the two-page prompt window', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)

        analyzer.sourceTextOverride = '優'
        analyzer.translatedTextOverride = '优'
        await orchestrator.run(request(0, HASH_A))
        await orchestrator.run(request(1, HASH_B))
        analyzer.sourceTextOverride = '兄'
        analyzer.translatedTextOverride = '哥哥'
        await orchestrator.run(request(2, HASH_A))
        analyzer.sourceTextOverride = '兄'
        analyzer.translatedTextOverride = '兄长'
        await orchestrator.run(request(3, HASH_B))
        analyzer.sourceTextOverride = '今日'
        analyzer.translatedTextOverride = '今天'
        await orchestrator.run(request(4, HASH_A))

        expect(analyzer.capturedPreviousPages.length).assertEqual(2)
        expect(analyzer.capturedPreviousPages[0]).assertEqual(2)
        expect(analyzer.capturedPreviousPages[1]).assertEqual(3)
        expect(analyzer.capturedMemorySources.length).assertEqual(1)
        expect(analyzer.capturedMemorySources[0]).assertEqual('優')
        expect(analyzer.capturedMemoryTranslations[0]).assertEqual('优')
        expect(analyzer.capturedMemoryOccurrences[0]).assertEqual(2)

        const supplied: ComicTranslationMemoryEntry = new ComicTranslationMemoryEntry()
        supplied.sourceText = '優'
        supplied.translatedText = '小优'
        supplied.firstSeenPageIndex = 0
        supplied.occurrenceCount = 2
        const next: ComicPageAnalysisRequest = request(5, HASH_B)
        next.context.translationMemory.push(supplied)
        analyzer.sourceTextOverride = '終'
        analyzer.translatedTextOverride = '结束'
        await orchestrator.run(next)
        expect(analyzer.capturedMemorySources.length).assertEqual(1)
        expect(analyzer.capturedMemorySources[0]).assertEqual('優')
        expect(analyzer.capturedMemoryTranslations[0]).assertEqual('小优')
        done()
      })

    it('keeps review-targeted generated translations out of exact memory', 0,
      (done: Function) => {
        const first: ComicPageDocument = new ComicPageDocument()
        first.pageIndex = 0
        first.translationState = ComicTranslationState.PROVISIONAL
        const firstBlock: ComicTextBlock = new ComicTextBlock()
        firstBlock.blockId = 'p0-b0'
        firstBlock.sourceText = '優'
        firstBlock.normalizedSourceText = '優'
        firstBlock.translatedText = '优'
        first.blocks.push(firstBlock)

        const second: ComicPageDocument = first.copy()
        second.pageIndex = 1
        second.blocks[0].blockId = 'p1-b0'
        const informational: ComicQualitySignal = new ComicQualitySignal()
        informational.code = 'provider_note'
        informational.severity = ComicQualitySeverity.INFO
        informational.blockId = second.blocks[0].blockId
        informational.message = 'metadata only'
        second.qualitySignals.push(informational)
        expect(ComicTranslationMemoryService.build([first, second]).length).assertEqual(1)

        informational.severity = ComicQualitySeverity.WARNING
        expect(ComicTranslationMemoryService.build([first, second]).length).assertEqual(0)

        informational.blockId = ''
        expect(ComicTranslationMemoryService.build([first, second]).length).assertEqual(0)

        second.qualitySignals = []
        second.translationState = ComicTranslationState.REVIEW_REQUIRED
        const missing: ComicTextBlock = new ComicTextBlock()
        missing.blockId = 'p1-b1'
        missing.sourceText = '兄'
        missing.normalizedSourceText = '兄'
        second.blocks.push(missing)
        expect(ComicTranslationMemoryService.build([first, second]).length).assertEqual(1)
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

    it('does not repopulate cache after its writes are invalidated', 0,
      async (done: Function) => {
        const repository: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const analyzer: OrchestratorFakeAnalyzer = new OrchestratorFakeAnalyzer()
        const orchestrator: ComicTranslationOrchestrator =
          new ComicTranslationOrchestrator(analyzer, repository)
        orchestrator.invalidateCacheWrites()
        const generated: ComicTranslationRunResult = await orchestrator.run(request())
        const cached: ComicPageDocument | null = await repository.load(generated.identity)
        expect(cached === null).assertEqual(true)
        expect(generated.document.blocks.length).assertEqual(1)
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

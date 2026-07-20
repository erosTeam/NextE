import { application } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicGlossaryTerm,
  ComicGlossaryTermProvenance,
  ComicGlossaryTermStatus,
  ComicImagePreparationProfile,
  ComicPageAnalysisContext,
  ComicPageAnalysisParser,
  ComicPageAnalysisRequest,
  ComicPageAnalysisResult,
  ComicPageAnalyzer,
  ComicPageAnalyzerCapabilities,
  ComicPageDocument,
  ComicPreviousPageContext,
  ComicResponsesProtocol,
  ComicTextBlock,
  ComicTranslationAccuracySnapshot,
  ComicTranslationEvaluationSnapshot,
  ComicTranslationEvaluator,
  ComicTranslationReferenceBlock,
  ComicTranslationReferencePage,
  ComicTranslationOrigin,
  ComicTranslationState,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const FIXTURE_PATH: string = 'comic_translation_phase0_page.json'
const FIXTURE_PROJECT_ID: string = 'fixture-gallery:zh-CN'
const FIXTURE_IMAGE_HASH: string = 'fixture-image-sha256'
const EVALUATION_MANIFEST_PATH: string = 'comic_translation_eval_manifest.json'

class RawEvaluationBlock {
  sourceVariants: string[] = []
  requiredTranslationTerms: string[] = []
}

class RawEvaluationPage {
  pageIndex: number = -1
  rawFile: string = ''
  sha256: string = ''
  width: number = 0
  height: number = 0
  features: string[] = []
  blocks: RawEvaluationBlock[] = []
}

class RawEvaluationManifest {
  schemaVersion: number = 0
  fixtureSetId: string = ''
  projectId: string = ''
  sourceLanguage: string = ''
  targetLanguage: string = ''
  provenance: string = ''
  pages: RawEvaluationPage[] = []
}

async function loadRawFixture(path: string): Promise<Uint8Array> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  const context = await application.createModuleContext(ability.context, FIXTURE_MODULE)
  try {
    return await context.resourceManager.getRawFileContent(path)
  } catch (_error) {
    return new Uint8Array(0)
  }
}

async function loadComicTranslationFixture(): Promise<string> {
  const bytes: Uint8Array = await loadRawFixture(FIXTURE_PATH)
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  return decoder.decodeToString(bytes)
}

async function loadEvaluationManifest(): Promise<RawEvaluationManifest> {
  const bytes: Uint8Array = await loadRawFixture(EVALUATION_MANIFEST_PATH)
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  return JSON.parse(decoder.decodeToString(bytes)) as RawEvaluationManifest
}

function fixtureHash(bytes: Uint8Array): string {
  const md = cryptoFramework.createMd('SHA256')
  md.updateSync({ data: bytes })
  const digest: Uint8Array = md.digestSync().data
  const parts: string[] = []
  for (let index: number = 0; index < digest.length; index++) {
    parts.push(digest[index].toString(16).padStart(2, '0'))
  }
  return parts.join('')
}

function evaluationReference(
  manifest: RawEvaluationManifest,
  rawPage: RawEvaluationPage,
): ComicTranslationReferencePage {
  const reference: ComicTranslationReferencePage = new ComicTranslationReferencePage()
  reference.projectId = manifest.projectId
  reference.pageIndex = rawPage.pageIndex
  reference.imageHash = rawPage.sha256
  for (let index: number = 0; index < rawPage.blocks.length; index++) {
    const rawBlock: RawEvaluationBlock = rawPage.blocks[index]
    const block: ComicTranslationReferenceBlock = new ComicTranslationReferenceBlock()
    block.sourceVariants = rawBlock.sourceVariants.slice()
    block.requiredTranslationTerms = rawBlock.requiredTranslationTerms.slice()
    reference.blocks.push(block)
  }
  return reference
}

function evaluatedDocument(reference: ComicTranslationReferencePage): ComicPageDocument {
  const document: ComicPageDocument = new ComicPageDocument()
  document.projectId = reference.projectId
  document.pageIndex = reference.pageIndex
  document.imageHash = reference.imageHash
  for (let index: number = 0; index < reference.blocks.length; index++) {
    const expected: ComicTranslationReferenceBlock = reference.blocks[index]
    const block: ComicTextBlock = new ComicTextBlock()
    block.blockId = `eval-${reference.pageIndex}-${index}`
    block.readingOrder = index
    block.sourceText = expected.sourceVariants[0]
    block.normalizedSourceText = block.sourceText
    block.translatedText = expected.requiredTranslationTerms.length > 0
      ? expected.requiredTranslationTerms.join('')
      : 'fixture translation'
    document.blocks.push(block)
  }
  return document
}

function buildComicAnalysisRequest(): ComicPageAnalysisRequest {
  const profile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
  profile.profileId = 'original-v1'
  profile.mimeType = 'image/jpeg'
  profile.preparedWidth = 1200
  profile.preparedHeight = 1800
  profile.tileCount = 1

  const term: ComicGlossaryTerm = new ComicGlossaryTerm()
  term.sourceTerm = 'ユウ'
  term.targetTerm = '优'
  term.status = ComicGlossaryTermStatus.LOCKED
  term.provenance = ComicGlossaryTermProvenance.USER
  term.firstSeenPageIndex = 0
  term.updatedRevision = 2

  const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
  previous.pageIndex = 0
  previous.sourceText = 'ユウは駅へ向かった。'
  previous.translatedText = '优去了车站。'
  previous.pageSummary = '优前往车站。'

  const analysisContext: ComicPageAnalysisContext = new ComicPageAnalysisContext()
  analysisContext.sourceLanguage = 'ja'
  analysisContext.targetLanguage = 'zh-CN'
  analysisContext.rollingSummary = '优正准备与朋友会面。'
  analysisContext.styleGuide = 'Use concise conversational Chinese.'
  analysisContext.glossaryRevision = 2
  analysisContext.styleGuideRevision = 1
  analysisContext.contextRevision = 3
  analysisContext.glossary.push(term)
  analysisContext.previousPages.push(previous)

  const request: ComicPageAnalysisRequest = new ComicPageAnalysisRequest()
  request.projectId = FIXTURE_PROJECT_ID
  request.pageIndex = 1
  request.imageFilePath = '/fixture/comic-page.jpg'
  request.imageHash = FIXTURE_IMAGE_HASH
  request.sourceWidth = 1200
  request.sourceHeight = 1800
  request.requestedAnalysisRevision = 4
  request.requestedTranslationRevision = 5
  request.imagePreparationProfile = profile
  request.context = analysisContext
  return request
}

class FakeComicPageAnalyzer implements ComicPageAnalyzer {
  private readonly rawText: string

  constructor(rawText: string) {
    this.rawText = rawText
  }

  providerId(): string {
    return 'fixture-vision'
  }

  modelId(): string {
    return 'fixture-model-v1'
  }

  analysisPromptVersion(): string {
    return 'phase0-fixture-v1'
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

  analyze(request: ComicPageAnalysisRequest): Promise<ComicPageAnalysisResult> {
    const result: ComicPageAnalysisResult = ComicPageAnalysisParser.parse(
      request,
      this.rawText,
      this.providerId(),
      this.modelId(),
      'phase0-fixture-v1',
    )
    return Promise.resolve(result)
  }
}

export default function comicTranslationPhase0Test(): void {
  describe('Comic translation Phase 0', () => {
    it('normalizes a provider-neutral fixture without requiring geometry', 0, async (done: Function) => {
      const rawText: string = await loadComicTranslationFixture()
      const request: ComicPageAnalysisRequest = buildComicAnalysisRequest()
      const analyzer: FakeComicPageAnalyzer = new FakeComicPageAnalyzer(rawText)
      const result: ComicPageAnalysisResult = await analyzer.analyze(request)
      const snapshot: ComicTranslationEvaluationSnapshot =
        ComicTranslationEvaluator.snapshot(result.document)

      expect(rawText.length > 0).assertEqual(true)
      expect(analyzer.capabilities().geometry).assertEqual(false)
      expect(analyzer.capabilities().contextAwareTranslation).assertEqual(true)
      expect(request.context.glossary[0].status).assertEqual(ComicGlossaryTermStatus.LOCKED)
      expect(request.context.previousPages[0].pageIndex).assertEqual(0)
      expect(result.document.projectId).assertEqual(FIXTURE_PROJECT_ID)
      expect(result.document.pageIndex).assertEqual(1)
      expect(result.document.imageHash).assertEqual(FIXTURE_IMAGE_HASH)
      expect(result.document.analysisRevision).assertEqual(4)
      expect(result.document.translationRevision).assertEqual(5)
      expect(result.document.translationState).assertEqual(ComicTranslationState.PROVISIONAL)
      expect(result.document.blocks.length).assertEqual(2)
      expect(result.document.blocks[0].blockId).assertEqual('p1-b0')
      expect(result.document.blocks[0].translatedText).assertEqual('早上好，优。')
      expect(result.document.blocks[0].polygon.length).assertEqual(0)
      expect(snapshot.totalBlocks).assertEqual(2)
      expect(snapshot.translatedBlocks).assertEqual(2)
      expect(snapshot.geometryBlocks).assertEqual(0)
      expect(snapshot.warningSignals).assertEqual(1)

      const copied: ComicPageDocument = result.document.copy()
      copied.blocks[0].translatedText = 'fixture-copy-change'
      expect(result.document.blocks[0].translatedText).assertEqual('早上好，优。')
      done()
    })

    it('rejects a provider response for another page identity', 0, async (done: Function) => {
      const rawText: string = await loadComicTranslationFixture()
      const mismatched: string = rawText.replace('"pageIndex": 1', '"pageIndex": 2')
      let rejected: boolean = false
      try {
        ComicPageAnalysisParser.parse(
          buildComicAnalysisRequest(),
          mismatched,
          'fixture-vision',
          'fixture-model-v1',
          'phase0-fixture-v1',
        )
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertEqual(true)
      done()
    })

    it('rejects an invalid image preparation profile before parsing provider data', 0, async (done: Function) => {
      const rawText: string = await loadComicTranslationFixture()
      const request: ComicPageAnalysisRequest = buildComicAnalysisRequest()
      request.imagePreparationProfile.tileCount = 0
      let rejected: boolean = false
      try {
        ComicPageAnalysisParser.parse(
          request,
          rawText,
          'fixture-vision',
          'fixture-model-v1',
          'phase0-fixture-v1',
        )
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertEqual(true)
      done()
    })

    it('accepts an explicit no-text page without inventing blocks', 0, (done: Function) => {
      const request: ComicPageAnalysisRequest = buildComicAnalysisRequest()
      const noTextPayload: string =
        '{"schemaVersion":1,"projectId":"fixture-gallery:zh-CN","pageIndex":1,' +
        '"imageHash":"fixture-image-sha256","imageWidth":1200,"imageHeight":1800,' +
        '"hasText":false,"pageSummary":"","blocks":[],"qualitySignals":[]}'
      const result: ComicPageAnalysisResult = ComicPageAnalysisParser.parse(
        request,
        noTextPayload,
        'fixture-vision',
        'fixture-model-v1',
        'phase0-fixture-v1',
      )
      expect(result.document.hasText).assertEqual(false)
      expect(result.document.blocks.length).assertEqual(0)
      expect(result.document.translationState).assertEqual(ComicTranslationState.MISSING)
      done()
    })

    it('derives translation provenance when provider metadata disagrees with translated text', 0, async (done: Function) => {
      const rawText: string = await loadComicTranslationFixture()
      const missingTranslatedOrigin: string = rawText.replace(
        '"translationOrigin": "vision"',
        '"translationOrigin": "none"',
      )
      const translated: ComicPageAnalysisResult = ComicPageAnalysisParser.parse(
        buildComicAnalysisRequest(),
        missingTranslatedOrigin,
        'fixture-vision',
        'fixture-model-v1',
        'phase0-fixture-v1',
      )
      expect(translated.document.blocks[1].translatedText.length > 0).assertEqual(true)
      expect(translated.document.blocks[1].translationOrigin).assertEqual(
        ComicTranslationOrigin.VISION,
      )

      const untranslatedWithVisionOrigin: string = rawText.replace(
        '"translatedText": "我在车站等你。"',
        '"translatedText": ""',
      )
      const partial: ComicPageAnalysisResult = ComicPageAnalysisParser.parse(
        buildComicAnalysisRequest(),
        untranslatedWithVisionOrigin,
        'fixture-vision',
        'fixture-model-v1',
        'phase0-fixture-v1',
      )
      expect(partial.document.blocks[1].translatedText).assertEqual('')
      expect(partial.document.blocks[1].translationOrigin).assertEqual(
        ComicTranslationOrigin.NONE,
      )
      expect(partial.document.translationState).assertEqual(ComicTranslationState.REVIEW_REQUIRED)
      done()
    })

    it('keeps the original evaluation pages and manifest hashes aligned', 0, async (done: Function) => {
      const manifest: RawEvaluationManifest = await loadEvaluationManifest()
      expect(manifest.schemaVersion).assertEqual(1)
      expect(manifest.fixtureSetId).assertEqual('nexte-original-manga-eval-v1')
      expect(manifest.pages.length).assertEqual(2)
      for (let index: number = 0; index < manifest.pages.length; index++) {
        const page: RawEvaluationPage = manifest.pages[index]
        const bytes: Uint8Array = await loadRawFixture(page.rawFile)
        expect(bytes.length > 0).assertEqual(true)
        expect(fixtureHash(bytes)).assertEqual(page.sha256)
        expect(page.width).assertEqual(1024)
        expect(page.height).assertEqual(1536)
        expect(page.blocks.length).assertEqual(index === 0 ? 5 : 6)
      }
      done()
    })

    it('scores transcript, reading order and required name translation separately', 0, async (done: Function) => {
      const manifest: RawEvaluationManifest = await loadEvaluationManifest()
      const reference: ComicTranslationReferencePage = evaluationReference(manifest, manifest.pages[0])
      const document: ComicPageDocument = evaluatedDocument(reference)
      const accurate: ComicTranslationAccuracySnapshot =
        ComicTranslationEvaluator.accuracy(document, reference)
      expect(accurate.transcriptMatchPercent()).assertEqual(100)
      expect(accurate.passed()).assertEqual(true)

      const wrong: ComicPageDocument = document.copy()
      const first: ComicTextBlock = wrong.blocks[0]
      wrong.blocks[0] = wrong.blocks[1]
      wrong.blocks[1] = first
      wrong.blocks[3].translatedText = 'incorrect name'
      const mismatched: ComicTranslationAccuracySnapshot =
        ComicTranslationEvaluator.accuracy(wrong, reference)
      expect(mismatched.matchedSourceBlocks).assertEqual(5)
      expect(mismatched.readingOrderErrors).assertEqual(1)
      expect(mismatched.requiredTranslationTermErrors).assertEqual(1)
      expect(mismatched.passed()).assertEqual(false)
      done()
    })

    it('reports missing and unexpected transcript blocks independently', 0, async (done: Function) => {
      const manifest: RawEvaluationManifest = await loadEvaluationManifest()
      const reference: ComicTranslationReferencePage = evaluationReference(manifest, manifest.pages[1])
      const document: ComicPageDocument = evaluatedDocument(reference)
      document.blocks.splice(2, 1)
      const extra: ComicTextBlock = new ComicTextBlock()
      extra.blockId = 'unexpected'
      extra.readingOrder = 99
      extra.sourceText = 'provider invented text'
      extra.translatedText = 'fixture translation'
      document.blocks.push(extra)
      const snapshot: ComicTranslationAccuracySnapshot =
        ComicTranslationEvaluator.accuracy(document, reference)
      expect(snapshot.missingSourceBlocks).assertEqual(1)
      expect(snapshot.unexpectedSourceBlocks).assertEqual(1)
      expect(snapshot.transcriptMatchPercent()).assertEqual(83.33)
      expect(snapshot.passed()).assertEqual(false)
      done()
    })

  })
}

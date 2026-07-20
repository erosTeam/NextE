import { common } from '@kit.AbilityKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicAnalysisState,
  ComicImagePreparationProfile,
  ComicPageDocument,
  ComicPoint,
  ComicQualitySeverity,
  ComicQualitySignal,
  ComicRenderState,
  ComicSourceOrigin,
  ComicTextBlock,
  ComicTextKind,
  ComicTranslationDocumentCodec,
  InMemoryComicTranslationRepository,
  ComicTranslationOrigin,
  ComicTranslationRequestIdentity,
  ComicTranslationState,
  PersistentComicTranslationRepository,
  RdbComicTranslationRepository,
} from 'shared'

const TEST_PROJECT_ID: string = 'ohos-test:comic-translation-persistent-cache'

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

function identity(pageIndex: number): ComicTranslationRequestIdentity {
  const value: ComicTranslationRequestIdentity = new ComicTranslationRequestIdentity()
  value.projectId = TEST_PROJECT_ID
  value.pageIndex = pageIndex
  value.imageHash = `${pageIndex + 1}`.repeat(64)
  value.imageWidth = 1200
  value.imageHeight = 1800
  value.providerId = 'fixture-provider'
  value.modelId = 'fixture-model'
  value.analysisPromptVersion = 'fixture-prompt-v1'
  value.sourceLanguage = 'ja'
  value.targetLanguage = 'zh-CN'
  value.analysisRevision = 1
  value.translationRevision = 1
  value.imagePreparationProfileId = 'fixture-jpeg-v1'
  value.glossaryRevision = 0
  value.styleGuideRevision = 1
  value.contextRevision = pageIndex + 1
  value.contextFingerprint = 'c'.repeat(64)
  return value
}

function document(value: ComicTranslationRequestIdentity): ComicPageDocument {
  const profile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
  profile.profileId = value.imagePreparationProfileId
  profile.mimeType = 'image/jpeg'
  profile.preparedWidth = value.imageWidth
  profile.preparedHeight = value.imageHeight
  profile.tileCount = 1

  const block: ComicTextBlock = new ComicTextBlock()
  block.blockId = `page-${value.pageIndex}-block-0`
  block.readingOrder = 0
  block.kind = ComicTextKind.DIALOGUE
  block.sourceText = `source-${value.pageIndex}`
  block.normalizedSourceText = block.sourceText
  block.translatedText = `translation-${value.pageIndex}`
  block.polygon = [
    new ComicPoint(10, 10),
    new ComicPoint(100, 10),
    new ComicPoint(100, 100),
  ]
  block.sourceOrigin = ComicSourceOrigin.VISION
  block.translationOrigin = ComicTranslationOrigin.VISION
  block.providerConfidence = 0.9
  block.sourceRevision = 1
  block.translationRevision = 1

  const signal: ComicQualitySignal = new ComicQualitySignal()
  signal.code = 'fixture-review'
  signal.severity = ComicQualitySeverity.WARNING
  signal.blockId = block.blockId
  signal.message = 'fixture signal'

  const result: ComicPageDocument = new ComicPageDocument()
  result.projectId = value.projectId
  result.pageIndex = value.pageIndex
  result.imageHash = value.imageHash
  result.imageWidth = value.imageWidth
  result.imageHeight = value.imageHeight
  result.imagePreparationProfile = profile
  result.analysisRevision = value.analysisRevision
  result.translationRevision = value.translationRevision
  result.analysisState = ComicAnalysisState.READY
  result.translationState = ComicTranslationState.REVIEW_REQUIRED
  result.renderState = ComicRenderState.UNAVAILABLE
  result.hasText = true
  result.pageSummary = `summary-${value.pageIndex}`
  result.blocks.push(block)
  result.qualitySignals.push(signal)
  return result
}

function noTextDocument(value: ComicTranslationRequestIdentity): ComicPageDocument {
  const result: ComicPageDocument = document(value)
  result.translationRevision = 0
  result.translationState = ComicTranslationState.MISSING
  result.hasText = false
  result.blocks = []
  result.qualitySignals = []
  return result
}

export default function comicTranslationPersistentRepositoryTest(): void {
  describe('Comic translation persistent repository', () => {
    it('round-trips a normalized document as isolated model objects', 0, () => {
      const sourceIdentity: ComicTranslationRequestIdentity = identity(0)
      const sourceDocument: ComicPageDocument = document(sourceIdentity)
      const payload: string = ComicTranslationDocumentCodec.encode(sourceDocument)
      const restored: ComicPageDocument = ComicTranslationDocumentCodec.decode(payload)
      sourceDocument.blocks[0].translatedText = 'mutated source'
      expect(restored.projectId).assertEqual(TEST_PROJECT_ID)
      expect(restored.blocks.length).assertEqual(1)
      expect(restored.blocks[0].translatedText).assertEqual('translation-0')
      expect(restored.blocks[0].polygon.length).assertEqual(3)
      expect(restored.qualitySignals[0].blockId).assertEqual('page-0-block-0')
    })

    it('rejects an unsupported persisted document schema', 0, () => {
      const payload: string = ComicTranslationDocumentCodec.encode(document(identity(0)))
        .replace('"schemaVersion":1', '"schemaVersion":999')
      let rejected: boolean = false
      try {
        ComicTranslationDocumentCodec.decode(payload)
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertEqual(true)
    })

    it('rejects unsafe persisted page and revision integers', 0, () => {
      const payload: string = ComicTranslationDocumentCodec.encode(document(identity(0)))
      const unsafePage: string = payload.replace(
        '"pageIndex":0',
        '"pageIndex":9007199254740992',
      )
      let pageRejected: boolean = false
      try {
        ComicTranslationDocumentCodec.decode(unsafePage)
      } catch (_error) {
        pageRejected = true
      }
      expect(pageRejected).assertEqual(true)

      const unsafeRevision: string = payload.replace(
        '"analysisRevision":1',
        '"analysisRevision":9007199254740992',
      )
      let revisionRejected: boolean = false
      try {
        ComicTranslationDocumentCodec.decode(unsafeRevision)
      } catch (_error) {
        revisionRejected = true
      }
      expect(revisionRejected).assertEqual(true)
    })

    it('rejects non-canonical persisted identifiers without rewriting free text', 0, () => {
      const payload: string = ComicTranslationDocumentCodec.encode(document(identity(0)))
      const invalidPayloads: string[] = [
        payload.replace(TEST_PROJECT_ID, ` ${TEST_PROJECT_ID}`),
        payload.replace('"profileId":"fixture-jpeg-v1"', '"profileId":"fixture-jpeg-v1 "'),
        payload.split('"blockId":"page-0-block-0"')
          .join('"blockId":" page-0-block-0"'),
        payload.replace('"speakerId":""', '"speakerId":" speaker-0 "'),
        payload.replace('"code":"fixture-review"', '"code":" fixture-review"'),
        payload.replace('"lastErrorCode":""', '"lastErrorCode":" diagnostic "'),
      ]
      for (let index: number = 0; index < invalidPayloads.length; index++) {
        let rejected: boolean = false
        try {
          ComicTranslationDocumentCodec.decode(invalidPayloads[index])
        } catch (_error) {
          rejected = true
        }
        expect(rejected).assertEqual(true)
      }

      const spacedText: string = payload
        .replace('"pageSummary":"summary-0"', '"pageSummary":" summary-0 "')
        .replace('"sourceText":"source-0"', '"sourceText":" source-0 "')
        .replace('"translatedText":"translation-0"', '"translatedText":" translation-0 "')
        .replace('"message":"fixture signal"', '"message":" fixture signal "')
      const restored: ComicPageDocument = ComicTranslationDocumentCodec.decode(spacedText)
      expect(restored.pageSummary).assertEqual(' summary-0 ')
      expect(restored.blocks[0].sourceText).assertEqual(' source-0 ')
      expect(restored.blocks[0].translatedText).assertEqual(' translation-0 ')
      expect(restored.qualitySignals[0].message).assertEqual(' fixture signal ')
    })

    it('rejects manually constructed invalid identities at repository entrypoints', 0,
      async (done: Function) => {
        const invalidIdentities: ComicTranslationRequestIdentity[] = []
        const project: ComicTranslationRequestIdentity = identity(0)
        project.projectId = ` ${TEST_PROJECT_ID}`
        invalidIdentities.push(project)
        const imageHash: ComicTranslationRequestIdentity = identity(0)
        imageHash.imageHash = 'A'.repeat(64)
        invalidIdentities.push(imageHash)
        const page: ComicTranslationRequestIdentity = identity(0)
        page.pageIndex = Number.MAX_SAFE_INTEGER + 1
        invalidIdentities.push(page)

        for (let index: number = 0; index < invalidIdentities.length; index++) {
          let cacheKeyRejected: boolean = false
          try {
            invalidIdentities[index].cacheKey()
          } catch (_error) {
            cacheKeyRejected = true
          }
          expect(cacheKeyRejected).assertEqual(true)
        }

        const memory: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        let loadRejected: boolean = false
        try {
          await memory.load(project)
        } catch (_error) {
          loadRejected = true
        }
        expect(loadRejected).assertEqual(true)
        let saveRejected: boolean = false
        try {
          await memory.save(project, document(project))
        } catch (_error) {
          saveRejected = true
        }
        expect(saveRejected).assertEqual(true)
        let previousRejected: boolean = false
        try {
          await memory.loadPrevious(project, 2)
        } catch (_error) {
          previousRejected = true
        }
        expect(previousRejected).assertEqual(true)
        done()
      })

    it('recovers exact and previous-page documents through new repository instances', 0,
      async (done: Function) => {
        const context: common.UIAbilityContext = await appContext()
        const cleanup: RdbComicTranslationRepository = new RdbComicTranslationRepository(context)
        await cleanup.removeProject(TEST_PROJECT_ID)
        try {
          const first: PersistentComicTranslationRepository =
            new PersistentComicTranslationRepository(context)
          const pageZeroIdentity: ComicTranslationRequestIdentity = identity(0)
          const pageOneIdentity: ComicTranslationRequestIdentity = identity(1)
          const pageTwoIdentity: ComicTranslationRequestIdentity = identity(2)
          await first.save(pageZeroIdentity, document(pageZeroIdentity))
          await first.save(pageOneIdentity, document(pageOneIdentity))
          await first.save(pageTwoIdentity, noTextDocument(pageTwoIdentity))

          const restarted: PersistentComicTranslationRepository =
            new PersistentComicTranslationRepository(context)
          const restored: ComicPageDocument | null = await restarted.load(pageZeroIdentity)
          expect(restored !== null).assertEqual(true)
          if (restored !== null) {
            restored.blocks[0].translatedText = 'mutated caller copy'
          }
          const restartedAgain: PersistentComicTranslationRepository =
            new PersistentComicTranslationRepository(context)
          const restoredAgain: ComicPageDocument | null = await restartedAgain.load(pageZeroIdentity)
          expect(restoredAgain !== null).assertEqual(true)
          if (restoredAgain !== null) {
            expect(restoredAgain.blocks[0].translatedText).assertEqual('translation-0')
          }
          const restoredNoText: ComicPageDocument | null = await restartedAgain.load(pageTwoIdentity)
          expect(restoredNoText !== null).assertEqual(true)
          if (restoredNoText !== null) {
            expect(restoredNoText.hasText).assertEqual(false)
            expect(restoredNoText.translationRevision).assertEqual(0)
          }
          const previous: ComicPageDocument[] = await restartedAgain.loadPrevious(identity(3), 2)
          expect(previous.length).assertEqual(2)
          expect(previous[0].pageIndex).assertEqual(1)
          expect(previous[1].pageIndex).assertEqual(2)
          expect(previous[1].hasText).assertEqual(false)
        } finally {
          await cleanup.removeProject(TEST_PROJECT_ID)
        }
        done()
      })
  })
}

import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  CacheStat,
  ComicBackendTemplate,
  ComicBlockTranslation,
  ComicPageDocument,
  ComicPoint,
  ComicRegionAnalysisRequest,
  ComicRegionAnalysisResult,
  ComicRegionRenderBackend,
  ComicRegionRenderRequest,
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicRenderProfile,
  ComicTextBlock,
  ComicTextKind,
  ComicTextTranslationRequest,
  ComicTextTranslationResult,
  ComicTextTranslator,
  ComicTranslationBatch,
  ComicVisualPageSource,
  ComicVisualTranslationContract,
  ComicVisualTranslationOrchestrator,
  ComicVisualTranslationRequest,
  ComicVisualTranslationRoute,
  InMemoryComicRenderedPageRepository,
  InMemoryComicTranslationRepository,
  PersistentComicRenderedPageRepository,
} from 'shared'

const FIXTURE_BACKEND_ID: string = 'fixture-region-render'
const FIXTURE_BACKEND_PROFILE: string = 'fixture-region-profile-v1'
const FIXTURE_TRANSLATOR_PROFILE: string = 'fixture-llm-source'
const FIXTURE_MODEL: string = 'fixture-vision-model'
const FIXTURE_PROMPT: string = 'fixture-block-translation-v1'
const FIXTURE_CONTEXT_FINGERPRINT: string = 'e'.repeat(64)

class FixtureRegionRenderBackend implements ComicRegionRenderBackend {
  analyzeCalls: number = 0
  renderCalls: number = 0
  failRender: boolean = false

  backendId(): string {
    return FIXTURE_BACKEND_ID
  }

  profileId(): string {
    return FIXTURE_BACKEND_PROFILE
  }

  protocolRevision(): number {
    return 1
  }

  async analyze(request: ComicRegionAnalysisRequest): Promise<ComicRegionAnalysisResult> {
    this.analyzeCalls++
    const result: ComicRegionAnalysisResult = new ComicRegionAnalysisResult()
    result.backendId = this.backendId()
    result.profileId = this.profileId()
    result.regionRevision = request.requestedRegionRevision
    result.document = fixtureDocument(request.source, request.requestedDocumentRevision)
    const template: ComicBackendTemplate = new ComicBackendTemplate()
    template.backendId = this.backendId()
    template.profileId = this.profileId()
    template.protocolRevision = this.protocolRevision()
    template.contentHash = 'd'.repeat(64)
    template.mimeType = 'application/json'
    template.payload = new Uint8Array([1, 2, 3])
    result.adapterTemplate = template
    return result
  }

  async render(request: ComicRegionRenderRequest): Promise<ComicRenderedPage> {
    this.renderCalls++
    ComicVisualTranslationContract.validateStagedRenderRequest(request)
    if (this.failRender) {
      throw new Error('fixture render failed')
    }
    const now: number = Date.now()
    const page: ComicRenderedPage = new ComicRenderedPage()
    page.identity = request.identity.copy()
    page.artifactHash = 'f'.repeat(64)
    page.mimeType = 'image/png'
    page.width = request.source.imageWidth
    page.height = request.source.imageHeight
    page.byteLength = 4096
    page.localFilePath = '/fixture/rendered-page.png'
    page.createdAt = now
    page.lastAccessAt = now
    return page
  }
}

class FixtureTextTranslator implements ComicTextTranslator {
  translateCalls: number = 0
  lastPreviousTranslation: string = ''
  returnWrongModel: boolean = false

  sourceProfileId(): string {
    return FIXTURE_TRANSLATOR_PROFILE
  }

  sourceRevision(): number {
    return 3
  }

  modelId(): string {
    return FIXTURE_MODEL
  }

  promptVersion(): string {
    return FIXTURE_PROMPT
  }

  contextFingerprint(_request: ComicTextTranslationRequest): string {
    return FIXTURE_CONTEXT_FINGERPRINT
  }

  async translate(request: ComicTextTranslationRequest): Promise<ComicTextTranslationResult> {
    this.translateCalls++
    const previous: string[] = []
    for (let index: number = 0; index < request.context.previousPages.length; index++) {
      previous.push(request.context.previousPages[index].translatedText)
    }
    this.lastPreviousTranslation = previous.join('\n')
    const batch: ComicTranslationBatch = new ComicTranslationBatch()
    batch.projectId = request.source.projectId
    batch.pageIndex = request.source.pageIndex
    batch.sourceImageHash = request.source.imageHash
    batch.targetLanguage = request.context.targetLanguage
    batch.sourceProfileId = this.sourceProfileId()
    batch.sourceRevision = this.sourceRevision()
    batch.modelId = this.returnWrongModel ? 'unexpected-model' : this.modelId()
    batch.promptVersion = this.promptVersion()
    batch.contextFingerprint = this.contextFingerprint(request)
    batch.glossaryRevision = request.context.glossaryRevision
    batch.translationRevision = request.requestedTranslationRevision
    for (let index: number = 0; index < request.document.blocks.length; index++) {
      const block: ComicBlockTranslation = new ComicBlockTranslation()
      block.blockId = request.document.blocks[index].blockId
      block.translatedText = `译文-${request.source.pageIndex}-${index}`
      batch.blocks.push(block)
    }
    const result: ComicTextTranslationResult = new ComicTextTranslationResult()
    result.batch = batch
    result.pageSummary = `累计摘要-${request.source.pageIndex}`
    return result
  }
}

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

function fixtureSource(pageIndex: number, hashChar: string): ComicVisualPageSource {
  const source: ComicVisualPageSource = new ComicVisualPageSource()
  source.projectId = 'visual-orchestrator-project'
  source.pageIndex = pageIndex
  source.imageFilePath = `/fixture/source-${pageIndex}.jpg`
  source.imageHash = hashChar.repeat(64)
  source.imageWidth = 1200
  source.imageHeight = 1800
  return source
}

function fixtureDocument(
  source: ComicVisualPageSource,
  documentRevision: number,
): ComicPageDocument {
  const document: ComicPageDocument = new ComicPageDocument()
  document.projectId = source.projectId
  document.pageIndex = source.pageIndex
  document.imageHash = source.imageHash
  document.imageWidth = source.imageWidth
  document.imageHeight = source.imageHeight
  document.imagePreparationProfile.profileId = FIXTURE_BACKEND_PROFILE
  document.imagePreparationProfile.preparedWidth = source.imageWidth
  document.imagePreparationProfile.preparedHeight = source.imageHeight
  document.imagePreparationProfile.tileCount = 1
  document.analysisRevision = documentRevision
  document.hasText = true
  const block: ComicTextBlock = new ComicTextBlock()
  block.blockId = `p${source.pageIndex}-r0`
  block.readingOrder = 0
  block.kind = ComicTextKind.DIALOGUE
  block.sourceText = `原文-${source.pageIndex}`
  block.normalizedSourceText = block.sourceText
  block.sourceRevision = documentRevision
  block.polygon = [
    new ComicPoint(10, 10),
    new ComicPoint(300, 10),
    new ComicPoint(300, 180),
    new ComicPoint(10, 180),
  ]
  document.blocks = [block]
  return document
}

function fixtureRenderProfile(): ComicRenderProfile {
  const profile: ComicRenderProfile = new ComicRenderProfile()
  profile.profileId = 'fixture-reader-render-v1'
  profile.sourceTreatmentProfileId = 'fixture-inpaint-v1'
  profile.layoutProfileId = 'fixture-layout-v1'
  profile.targetMimeType = 'image/png'
  profile.revision = 1
  return profile
}

function fixtureRequest(pageIndex: number, hashChar: string): ComicVisualTranslationRequest {
  const request: ComicVisualTranslationRequest = new ComicVisualTranslationRequest()
  request.source = fixtureSource(pageIndex, hashChar)
  request.context.sourceLanguage = 'ja'
  request.context.targetLanguage = 'zh-CN'
  request.context.styleGuide = 'Use concise natural Chinese.'
  request.context.styleGuideRevision = 1
  request.context.contextRevision = 1
  request.renderProfile = fixtureRenderProfile()
  return request
}

function orchestratorFixture(
  backend: FixtureRegionRenderBackend,
  translator: FixtureTextTranslator,
  documents: InMemoryComicTranslationRepository = new InMemoryComicTranslationRepository(),
  rendered: InMemoryComicRenderedPageRepository = new InMemoryComicRenderedPageRepository(),
): ComicVisualTranslationOrchestrator {
  return new ComicVisualTranslationOrchestrator(backend, translator, documents, rendered)
}

function renderedIdentity(source: ComicVisualPageSource): ComicRenderedPageIdentity {
  const identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  identity.route = ComicVisualTranslationRoute.STAGED
  identity.projectId = source.projectId
  identity.pageIndex = source.pageIndex
  identity.sourceImageHash = source.imageHash
  identity.sourceWidth = source.imageWidth
  identity.sourceHeight = source.imageHeight
  identity.targetLanguage = 'zh-CN'
  identity.regionBackendId = FIXTURE_BACKEND_ID
  identity.regionProfileId = FIXTURE_BACKEND_PROFILE
  identity.regionRevision = 1
  identity.documentRevision = 1
  identity.translationSourceProfileId = FIXTURE_TRANSLATOR_PROFILE
  identity.translationSourceRevision = 3
  identity.translationModelId = FIXTURE_MODEL
  identity.translationPromptVersion = FIXTURE_PROMPT
  identity.translationContextFingerprint = FIXTURE_CONTEXT_FINGERPRINT
  identity.translationRevision = 1
  identity.sourceTreatmentProfileId = 'fixture-inpaint-v1'
  identity.layoutProfileId = 'fixture-layout-v1'
  identity.renderBackendId = FIXTURE_BACKEND_ID
  identity.renderProfileId = 'fixture-reader-render-v1'
  identity.renderTargetMimeType = 'image/png'
  identity.renderRevision = 1
  return identity
}

function sha256(bytes: Uint8Array): string {
  const md = cryptoFramework.createMd('SHA256')
  md.updateSync({ data: bytes })
  const digest: Uint8Array = md.digestSync().data
  const parts: string[] = []
  for (let index: number = 0; index < digest.length; index++) {
    parts.push(digest[index].toString(16).padStart(2, '0'))
  }
  return parts.join('')
}

function writeBytes(path: string, bytes: Uint8Array): void {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    )
    fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.length })
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

export default function comicVisualTranslationOrchestratorTest(): void {
  describe('ComicVisualTranslationOrchestrator', () => {
    it('publishes one rendered page and skips all providers on an exact cache hit', 0,
      async (done: Function) => {
        const backend: FixtureRegionRenderBackend = new FixtureRegionRenderBackend()
        const translator: FixtureTextTranslator = new FixtureTextTranslator()
        const orchestrator: ComicVisualTranslationOrchestrator =
          orchestratorFixture(backend, translator)
        const request: ComicVisualTranslationRequest = fixtureRequest(0, 'a')
        const first = await orchestrator.run(request)
        const second = await orchestrator.run(request)
        expect(first.cacheHit).assertEqual(false)
        expect(second.cacheHit).assertEqual(true)
        expect(second.renderedPage.identity.route).assertEqual(ComicVisualTranslationRoute.STAGED)
        expect(backend.analyzeCalls).assertEqual(1)
        expect(translator.translateCalls).assertEqual(1)
        expect(backend.renderCalls).assertEqual(1)
        done()
      })

    it('feeds the completed previous visual page into the next page translation', 0,
      async (done: Function) => {
        const backend: FixtureRegionRenderBackend = new FixtureRegionRenderBackend()
        const translator: FixtureTextTranslator = new FixtureTextTranslator()
        const orchestrator: ComicVisualTranslationOrchestrator =
          orchestratorFixture(backend, translator)
        await orchestrator.run(fixtureRequest(0, 'a'))
        await orchestrator.run(fixtureRequest(1, 'b'))
        expect(translator.lastPreviousTranslation.includes('译文-0-0')).assertEqual(true)
        done()
      })

    it('rejects a translation batch that is not bound to the active translator', 0,
      async (done: Function) => {
        const backend: FixtureRegionRenderBackend = new FixtureRegionRenderBackend()
        const translator: FixtureTextTranslator = new FixtureTextTranslator()
        translator.returnWrongModel = true
        const orchestrator: ComicVisualTranslationOrchestrator =
          orchestratorFixture(backend, translator)
        let rejected: boolean = false
        try {
          await orchestrator.run(fixtureRequest(0, 'a'))
        } catch (_error) {
          rejected = true
        }
        expect(rejected).assertEqual(true)
        expect(backend.renderCalls).assertEqual(0)
        done()
      })

    it('does not reuse previous-page context across a region configuration revision', 0,
      async (done: Function) => {
        const backend: FixtureRegionRenderBackend = new FixtureRegionRenderBackend()
        const translator: FixtureTextTranslator = new FixtureTextTranslator()
        const orchestrator: ComicVisualTranslationOrchestrator =
          orchestratorFixture(backend, translator)
        await orchestrator.run(fixtureRequest(0, 'a'))
        const changed: ComicVisualTranslationRequest = fixtureRequest(1, 'b')
        changed.requestedRegionRevision = 2
        await orchestrator.run(changed)
        expect(translator.lastPreviousTranslation).assertEqual('')
        done()
      })

    it('retains the last successful rendered page when a forced rerender fails', 0,
      async (done: Function) => {
        const backend: FixtureRegionRenderBackend = new FixtureRegionRenderBackend()
        const translator: FixtureTextTranslator = new FixtureTextTranslator()
        const orchestrator: ComicVisualTranslationOrchestrator =
          orchestratorFixture(backend, translator)
        const request: ComicVisualTranslationRequest = fixtureRequest(0, 'a')
        const first = await orchestrator.run(request)
        backend.failRender = true
        let rejected: boolean = false
        try {
          await orchestrator.run(request, true)
        } catch (_error) {
          rejected = true
        }
        const retained: ComicRenderedPage | null = await orchestrator.latestSuccessful(
          request.source,
          request.context.targetLanguage,
        )
        expect(rejected).assertEqual(true)
        expect(retained?.identity.cacheKey()).assertEqual(first.renderedPage.identity.cacheKey())
        done()
      })

    it('does not repopulate generated caches after writes are invalidated', 0,
      async (done: Function) => {
        const backend: FixtureRegionRenderBackend = new FixtureRegionRenderBackend()
        const translator: FixtureTextTranslator = new FixtureTextTranslator()
        const documents: InMemoryComicTranslationRepository =
          new InMemoryComicTranslationRepository()
        const rendered: InMemoryComicRenderedPageRepository =
          new InMemoryComicRenderedPageRepository()
        const orchestrator: ComicVisualTranslationOrchestrator = orchestratorFixture(
          backend,
          translator,
          documents,
          rendered,
        )
        orchestrator.invalidateCacheWrites()
        await orchestrator.run(fixtureRequest(0, 'a'))
        const documentStat: CacheStat = await documents.stat()
        const renderedStat: CacheStat = await rendered.stat()
        expect(documentStat.count).assertEqual(0)
        expect(renderedStat.count).assertEqual(0)
        done()
      })

    it('restores a verified artifact across repository instances and rejects tampering', 0,
      async (done: Function) => {
        const context: common.UIAbilityContext = await appContext()
        const directoryName: string = 'comic-translated-pages-test-' +
          util.generateRandomUUID(true).toLowerCase()
        const dir: string = `${context.cacheDir}/${directoryName}`
        fileIo.mkdirSync(dir, true)
        const bytes: Uint8Array = new Uint8Array([1, 3, 5, 7, 9, 11, 13, 15])
        const artifactHash: string = sha256(bytes)
        const path: string = `${dir}/${'1'.repeat(64)}-${artifactHash}.png`
        const lookupKey: string = '2'.repeat(64)
        const source: ComicVisualPageSource = fixtureSource(0, 'a')
        const page: ComicRenderedPage = new ComicRenderedPage()
        page.identity = renderedIdentity(source)
        page.artifactHash = artifactHash
        page.mimeType = 'image/png'
        page.width = source.imageWidth
        page.height = source.imageHeight
        page.byteLength = bytes.length
        page.localFilePath = path
        page.createdAt = 1000
        page.lastAccessAt = 1000
        const first: PersistentComicRenderedPageRepository =
          new PersistentComicRenderedPageRepository(context, directoryName)
        try {
          writeBytes(path, bytes)
          await first.save(lookupKey, page)
          const restoredRepository: PersistentComicRenderedPageRepository =
            new PersistentComicRenderedPageRepository(context, directoryName)
          const restored: ComicRenderedPage | null = await restoredRepository.load(lookupKey)
          expect(restored?.artifactHash).assertEqual(artifactHash)
          const changed: Uint8Array = new Uint8Array(bytes)
          changed[0] = 2
          writeBytes(path, changed)
          expect(await restoredRepository.load(lookupKey)).assertEqual(null)
          await restoredRepository.discardArtifact(page)
          expect(fileIo.accessSync(path)).assertEqual(false)
        } finally {
          await first.clear()
          try {
            fileIo.rmdirSync(dir)
          } catch (_error) {
          }
        }
        done()
      })
  })
}

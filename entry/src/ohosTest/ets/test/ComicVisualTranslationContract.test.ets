import { application } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicAnalysisState,
  ComicBackendTemplate,
  ComicBlockTranslation,
  ComicPageAnalysisContext,
  ComicPageDocument,
  ComicPoint,
  ComicRegionAnalysisRequest,
  ComicRegionAnalysisResult,
  ComicRegionRenderBackend,
  ComicRegionRenderRequest,
  ComicRenderProfile,
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicSourceOrigin,
  ComicTextBlock,
  ComicTranslationBatch,
  ComicTranslationState,
  ComicVisualPageSource,
  ComicVisualTranslationContract,
  ComicVisualTranslationRoute,
  ComicWholePageRenderBackend,
  ComicWholePageRenderRequest,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const FIXTURE_PATH: string = 'comic_visual_translation_contract.json'

class RawVisualBlock {
  blockId: string = ''
  readingOrder: number = -1
  sourceText: string = ''
  translatedText: string = ''
  polygon: number[][] = []
}

class RawVisualFixture {
  schemaVersion: number = 0
  projectId: string = ''
  pageIndex: number = -1
  sourceImageHash: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
  targetLanguage: string = ''
  regionBackendId: string = ''
  regionProfileId: string = ''
  regionRevision: number = 0
  documentRevision: number = 0
  adapterTemplateHash: string = ''
  translationSourceProfileId: string = ''
  translationSourceRevision: number = 0
  translationModelId: string = ''
  translationPromptVersion: string = ''
  translationContextFingerprint: string = ''
  translationRevision: number = 0
  renderProfileId: string = ''
  sourceTreatmentProfileId: string = ''
  layoutProfileId: string = ''
  renderRevision: number = 0
  artifactHash: string = ''
  blocks: RawVisualBlock[] = []
}

async function loadFixture(): Promise<RawVisualFixture> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  const context = await application.createModuleContext(ability.context, FIXTURE_MODULE)
  const bytes: Uint8Array = await context.resourceManager.getRawFileContent(FIXTURE_PATH)
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  return JSON.parse(decoder.decodeToString(bytes)) as RawVisualFixture
}

function source(raw: RawVisualFixture): ComicVisualPageSource {
  const value: ComicVisualPageSource = new ComicVisualPageSource()
  value.projectId = raw.projectId
  value.pageIndex = raw.pageIndex
  value.imageFilePath = '/fixture/original-page.png'
  value.imageHash = raw.sourceImageHash
  value.imageWidth = raw.imageWidth
  value.imageHeight = raw.imageHeight
  return value
}

function document(raw: RawVisualFixture): ComicPageDocument {
  const value: ComicPageDocument = new ComicPageDocument()
  value.projectId = raw.projectId
  value.pageIndex = raw.pageIndex
  value.imageHash = raw.sourceImageHash
  value.imageWidth = raw.imageWidth
  value.imageHeight = raw.imageHeight
  value.analysisRevision = raw.documentRevision
  value.analysisState = ComicAnalysisState.READY
  value.translationState = ComicTranslationState.MISSING
  value.hasText = raw.blocks.length > 0
  for (let index: number = 0; index < raw.blocks.length; index++) {
    const rawBlock: RawVisualBlock = raw.blocks[index]
    const block: ComicTextBlock = new ComicTextBlock()
    block.blockId = rawBlock.blockId
    block.readingOrder = rawBlock.readingOrder
    block.sourceText = rawBlock.sourceText
    block.normalizedSourceText = rawBlock.sourceText
    block.sourceOrigin = ComicSourceOrigin.OCR
    block.sourceRevision = raw.documentRevision
    for (let pointIndex: number = 0; pointIndex < rawBlock.polygon.length; pointIndex++) {
      block.polygon.push(new ComicPoint(
        rawBlock.polygon[pointIndex][0],
        rawBlock.polygon[pointIndex][1],
      ))
    }
    value.blocks.push(block)
  }
  return value
}

function adapterTemplate(raw: RawVisualFixture): ComicBackendTemplate {
  const value: ComicBackendTemplate = new ComicBackendTemplate()
  value.backendId = raw.regionBackendId
  value.profileId = raw.regionProfileId
  value.protocolRevision = 1
  value.contentHash = raw.adapterTemplateHash
  value.mimeType = 'application/json'
  value.payload = new util.TextEncoder().encodeInto('{"fixture":"render-template"}')
  return value
}

function translations(raw: RawVisualFixture): ComicTranslationBatch {
  const value: ComicTranslationBatch = new ComicTranslationBatch()
  value.projectId = raw.projectId
  value.pageIndex = raw.pageIndex
  value.sourceImageHash = raw.sourceImageHash
  value.targetLanguage = raw.targetLanguage
  value.sourceProfileId = raw.translationSourceProfileId
  value.sourceRevision = raw.translationSourceRevision
  value.modelId = raw.translationModelId
  value.promptVersion = raw.translationPromptVersion
  value.contextFingerprint = raw.translationContextFingerprint
  value.translationRevision = raw.translationRevision
  for (let index: number = 0; index < raw.blocks.length; index++) {
    const block: ComicBlockTranslation = new ComicBlockTranslation()
    block.blockId = raw.blocks[index].blockId
    block.translatedText = raw.blocks[index].translatedText
    value.blocks.push(block)
  }
  return value
}

function renderProfile(raw: RawVisualFixture): ComicRenderProfile {
  const value: ComicRenderProfile = new ComicRenderProfile()
  value.profileId = raw.renderProfileId
  value.sourceTreatmentProfileId = raw.sourceTreatmentProfileId
  value.layoutProfileId = raw.layoutProfileId
  value.targetMimeType = 'image/png'
  value.revision = raw.renderRevision
  return value
}

function stagedIdentity(raw: RawVisualFixture): ComicRenderedPageIdentity {
  const value: ComicRenderedPageIdentity = commonIdentity(raw)
  value.route = ComicVisualTranslationRoute.STAGED
  value.regionBackendId = raw.regionBackendId
  value.regionProfileId = raw.regionProfileId
  value.regionRevision = raw.regionRevision
  value.documentRevision = raw.documentRevision
  value.renderBackendId = raw.regionBackendId
  return value
}

function wholePageIdentity(raw: RawVisualFixture): ComicRenderedPageIdentity {
  const value: ComicRenderedPageIdentity = commonIdentity(raw)
  value.route = ComicVisualTranslationRoute.WHOLE_PAGE_RENDER
  value.renderBackendId = 'fixture-whole-page-render'
  value.sourceTreatmentProfileId = 'provider-managed-treatment'
  value.layoutProfileId = 'provider-managed-layout'
  return value
}

function commonIdentity(raw: RawVisualFixture): ComicRenderedPageIdentity {
  const value: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  value.projectId = raw.projectId
  value.pageIndex = raw.pageIndex
  value.sourceImageHash = raw.sourceImageHash
  value.sourceWidth = raw.imageWidth
  value.sourceHeight = raw.imageHeight
  value.targetLanguage = raw.targetLanguage
  value.translationSourceProfileId = raw.translationSourceProfileId
  value.translationSourceRevision = raw.translationSourceRevision
  value.translationModelId = raw.translationModelId
  value.translationPromptVersion = raw.translationPromptVersion
  value.translationContextFingerprint = raw.translationContextFingerprint
  value.translationRevision = raw.translationRevision
  value.sourceTreatmentProfileId = raw.sourceTreatmentProfileId
  value.layoutProfileId = raw.layoutProfileId
  value.renderProfileId = raw.renderProfileId
  value.renderTargetMimeType = 'image/png'
  value.renderRevision = raw.renderRevision
  return value
}

function renderedPage(
  raw: RawVisualFixture,
  identity: ComicRenderedPageIdentity,
): ComicRenderedPage {
  const value: ComicRenderedPage = new ComicRenderedPage()
  value.identity = identity.copy()
  value.artifactHash = raw.artifactHash
  value.mimeType = 'image/png'
  value.width = raw.imageWidth
  value.height = raw.imageHeight
  value.byteLength = 48000
  value.localFilePath = '/fixture/rendered-page.png'
  value.createdAt = 1000
  value.lastAccessAt = 1000
  return value
}

function regionRequest(raw: RawVisualFixture): ComicRegionAnalysisRequest {
  const value: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
  value.source = source(raw)
  value.requestedRegionRevision = raw.regionRevision
  value.requestedDocumentRevision = raw.documentRevision
  return value
}

function stagedRenderRequest(raw: RawVisualFixture): ComicRegionRenderRequest {
  const value: ComicRegionRenderRequest = new ComicRegionRenderRequest()
  value.source = source(raw)
  value.regionRevision = raw.regionRevision
  value.document = document(raw)
  value.translations = translations(raw)
  value.adapterTemplate = adapterTemplate(raw)
  value.renderProfile = renderProfile(raw)
  value.identity = stagedIdentity(raw)
  return value
}

class FixtureRegionBackend implements ComicRegionRenderBackend {
  private readonly raw: RawVisualFixture

  constructor(raw: RawVisualFixture) {
    this.raw = raw
  }

  backendId(): string {
    return this.raw.regionBackendId
  }

  profileId(): string {
    return this.raw.regionProfileId
  }

  protocolRevision(): number {
    return 1
  }

  async analyze(request: ComicRegionAnalysisRequest): Promise<ComicRegionAnalysisResult> {
    const result: ComicRegionAnalysisResult = new ComicRegionAnalysisResult()
    result.backendId = this.backendId()
    result.profileId = this.profileId()
    result.regionRevision = request.requestedRegionRevision
    result.document = document(this.raw)
    result.adapterTemplate = adapterTemplate(this.raw)
    return result
  }

  async render(request: ComicRegionRenderRequest): Promise<ComicRenderedPage> {
    ComicVisualTranslationContract.validateStagedRenderRequest(request)
    return renderedPage(this.raw, request.identity)
  }
}

class FixtureWholePageBackend implements ComicWholePageRenderBackend {
  private readonly raw: RawVisualFixture

  constructor(raw: RawVisualFixture) {
    this.raw = raw
  }

  sourceProfileId(): string {
    return this.raw.translationSourceProfileId
  }

  sourceRevision(): number {
    return this.raw.translationSourceRevision
  }

  modelId(): string {
    return this.raw.translationModelId
  }

  promptVersion(): string {
    return this.raw.translationPromptVersion
  }

  contextFingerprint(_request: ComicWholePageRenderRequest): string {
    return this.raw.translationContextFingerprint
  }

  async render(request: ComicWholePageRenderRequest): Promise<ComicRenderedPage> {
    ComicVisualTranslationContract.validateWholePageRenderRequest(request)
    return renderedPage(this.raw, request.identity)
  }
}

export default function comicVisualTranslationContractTest(): void {
  describe('Comic visual translation contract', () => {
    it('accepts the staged fixture through one visual artifact boundary', 0,
      async (done: Function) => {
        const raw: RawVisualFixture = await loadFixture()
        const backend: FixtureRegionBackend = new FixtureRegionBackend(raw)
        const analysisRequest: ComicRegionAnalysisRequest = regionRequest(raw)
        const analysis: ComicRegionAnalysisResult = await backend.analyze(analysisRequest)
        ComicVisualTranslationContract.validateRegionAnalysisResult(
          analysisRequest,
          analysis.backendId,
          analysis.profileId,
          analysis.regionRevision,
          analysis.document,
          analysis.adapterTemplate,
        )
        const request: ComicRegionRenderRequest = stagedRenderRequest(raw)
        const page: ComicRenderedPage = await backend.render(request)
        ComicVisualTranslationContract.validateRenderedPage(request.identity, page)
        expect(page.identity.route).assertEqual(ComicVisualTranslationRoute.STAGED)
        expect(page.identity.cacheKey()).assertEqual(request.identity.cacheKey())
        done()
      })

    it('rejects missing, duplicate, and out-of-bounds staged geometry', 0,
      async (done: Function) => {
        const raw: RawVisualFixture = await loadFixture()
        const request: ComicRegionAnalysisRequest = regionRequest(raw)
        const template: ComicBackendTemplate = adapterTemplate(raw)
        const missing: ComicPageDocument = document(raw)
        missing.blocks[0].polygon = []
        const duplicate: ComicPageDocument = document(raw)
        duplicate.blocks[1].blockId = duplicate.blocks[0].blockId
        const outside: ComicPageDocument = document(raw)
        outside.blocks[0].polygon[0].x = raw.imageWidth + 1
        const candidates: ComicPageDocument[] = [missing, duplicate, outside]
        for (let index: number = 0; index < candidates.length; index++) {
          let rejected: boolean = false
          try {
            ComicVisualTranslationContract.validateRegionAnalysisResult(
              request,
              raw.regionBackendId,
              raw.regionProfileId,
              raw.regionRevision,
              candidates[index],
              template,
            )
          } catch (_error) {
            rejected = true
          }
          expect(rejected).assertEqual(true)
        }
        done()
      })

    it('requires one non-empty translation for every known block', 0,
      async (done: Function) => {
        const raw: RawVisualFixture = await loadFixture()
        const sourceDocument: ComicPageDocument = document(raw)
        const missing: ComicTranslationBatch = translations(raw)
        missing.blocks.pop()
        const duplicate: ComicTranslationBatch = translations(raw)
        duplicate.blocks[1].blockId = duplicate.blocks[0].blockId
        const unknown: ComicTranslationBatch = translations(raw)
        unknown.blocks[1].blockId = 'unknown'
        const empty: ComicTranslationBatch = translations(raw)
        empty.blocks[0].translatedText = ''
        const candidates: ComicTranslationBatch[] = [missing, duplicate, unknown, empty]
        for (let index: number = 0; index < candidates.length; index++) {
          let rejected: boolean = false
          try {
            ComicVisualTranslationContract.validateTranslationBatch(
              sourceDocument,
              candidates[index],
            )
          } catch (_error) {
            rejected = true
          }
          expect(rejected).assertEqual(true)
        }
        done()
      })

    it('invalidates only downstream render identity inputs', 0, async (done: Function) => {
      const raw: RawVisualFixture = await loadFixture()
      const base: ComicRenderedPageIdentity = stagedIdentity(raw)
      const page: ComicRenderedPage = renderedPage(raw, base)
      const changedTranslation: ComicRenderedPageIdentity = base.copy()
      changedTranslation.translationRevision++
      const changedLayout: ComicRenderedPageIdentity = base.copy()
      changedLayout.layoutProfileId = 'fixture-cjk-layout-v2'
      expect(ComicVisualTranslationContract.isRenderedPageStale(page, base)).assertEqual(false)
      expect(ComicVisualTranslationContract.isRenderedPageStale(
        page,
        changedTranslation,
      )).assertEqual(true)
      expect(ComicVisualTranslationContract.isRenderedPageStale(page, changedLayout)).assertEqual(true)
      const moved: ComicRenderedPage = page.copy()
      moved.localFilePath = '/fixture/relocated-rendered-page.png'
      expect(ComicVisualTranslationContract.isRenderedPageStale(moved, base)).assertEqual(false)
      done()
    })

    it('accepts whole-page image output without staged geometry', 0,
      async (done: Function) => {
        const raw: RawVisualFixture = await loadFixture()
        const backend: FixtureWholePageBackend = new FixtureWholePageBackend(raw)
        const request: ComicWholePageRenderRequest = new ComicWholePageRenderRequest()
        request.source = source(raw)
        request.context = new ComicPageAnalysisContext()
        request.context.targetLanguage = raw.targetLanguage
        request.identity = wholePageIdentity(raw)
        const page: ComicRenderedPage = await backend.render(request)
        ComicVisualTranslationContract.validateRenderedPage(request.identity, page)
        expect(page.identity.regionBackendId).assertEqual('')
        expect(page.identity.route).assertEqual(ComicVisualTranslationRoute.WHOLE_PAGE_RENDER)
        done()
      })

    it('rejects mismatched rendered artifacts before Reader publication', 0,
      async (done: Function) => {
        const raw: RawVisualFixture = await loadFixture()
        const identity: ComicRenderedPageIdentity = stagedIdentity(raw)
        const wrongHash: ComicRenderedPage = renderedPage(raw, identity)
        wrongHash.artifactHash = 'not-a-hash'
        const wrongSize: ComicRenderedPage = renderedPage(raw, identity)
        wrongSize.width++
        const wrongMime: ComicRenderedPage = renderedPage(raw, identity)
        wrongMime.mimeType = 'application/json'
        const wrongIdentity: ComicRenderedPage = renderedPage(raw, identity)
        wrongIdentity.identity.pageIndex++
        const candidates: ComicRenderedPage[] = [wrongHash, wrongSize, wrongMime, wrongIdentity]
        for (let index: number = 0; index < candidates.length; index++) {
          let rejected: boolean = false
          try {
            ComicVisualTranslationContract.validateRenderedPage(identity, candidates[index])
          } catch (_error) {
            rejected = true
          }
          expect(rejected).assertEqual(true)
        }
        done()
      })
  })
}

import { application, common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicBlockTranslation,
  ComicLocalVisualBackend,
  ComicRegionAnalysisRequest,
  ComicRegionAnalysisResult,
  ComicRegionRenderRequest,
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicRenderProfile,
  ComicTranslationBatch,
  ComicVisualPageSource,
  ComicVisualTranslationContract,
  ComicVisualTranslationRoute,
  HarmonyComicLocalOcrEngine,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const FIXTURE_PATH: string = 'comic_translation_eval_page_01.png'
const FIXTURE_HASH: string =
  'b12a64700e64a9e707152d0570a8af8c5296055226f953c769307cb59e3176a9'
const CONTEXT_HASH: string =
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'

function writeFile(path: string, bytes: Uint8Array): void {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    )
    const buffer: ArrayBuffer = bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    )
    const written: number = fileIo.writeSync(file.fd, buffer, { length: buffer.byteLength })
    if (written !== bytes.length) {
      throw new Error('Local comic fixture write failed')
    }
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

function removeFile(path: string): void {
  try {
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path)
    }
  } catch (_error) {}
}

function translated(sourceText: string): string {
  switch (sourceText.trim()) {
    case '午後七時、雨。':
      return '晚上七点，雨。'
    case '月影駅 東口':
      return '月影站 东口'
    case 'ゆう':
    case '優':
      return '优'
    case '駅で迷った。':
      return '我在车站迷路了。'
    case 'ごめん。':
      return '抱歉。'
    case '優、遅かったね。':
      return '优，你来晚了。'
    default:
      return sourceText.trim()
  }
}

function source(path: string): ComicVisualPageSource {
  const value: ComicVisualPageSource = new ComicVisualPageSource()
  value.projectId = 'local-comic-visual-fixture'
  value.pageIndex = 0
  value.imageFilePath = path
  value.imageHash = FIXTURE_HASH
  value.imageWidth = 1024
  value.imageHeight = 1536
  return value
}

function renderRequest(
  backend: ComicLocalVisualBackend,
  sourcePath: string,
  analysis: ComicRegionAnalysisResult,
): ComicRegionRenderRequest {
  const request: ComicRegionRenderRequest = new ComicRegionRenderRequest()
  request.source = source(sourcePath)
  request.regionRevision = analysis.regionRevision
  request.document = analysis.document
  request.adapterTemplate = analysis.adapterTemplate

  const translations: ComicTranslationBatch = new ComicTranslationBatch()
  translations.projectId = request.source.projectId
  translations.pageIndex = request.source.pageIndex
  translations.sourceImageHash = request.source.imageHash
  translations.targetLanguage = 'zh-CN'
  translations.sourceProfileId = 'local-comic-test-translator'
  translations.sourceRevision = 1
  translations.modelId = 'deterministic-fixture-translator'
  translations.promptVersion = 'local-comic-fixture-v1'
  translations.contextFingerprint = CONTEXT_HASH
  translations.translationRevision = 1
  for (let index: number = 0; index < analysis.document.blocks.length; index++) {
    const block: ComicBlockTranslation = new ComicBlockTranslation()
    block.blockId = analysis.document.blocks[index].blockId
    block.translatedText = translated(analysis.document.blocks[index].sourceText)
    translations.blocks.push(block)
  }
  request.translations = translations

  const profile: ComicRenderProfile = new ComicRenderProfile()
  profile.profileId = 'reader-local-basic-render-v1'
  profile.sourceTreatmentProfileId = 'local-opaque-mask-v1'
  profile.layoutProfileId = 'local-centered-text-v1'
  profile.targetMimeType = 'image/png'
  profile.revision = 1
  request.renderProfile = profile

  const identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  identity.route = ComicVisualTranslationRoute.STAGED
  identity.projectId = request.source.projectId
  identity.pageIndex = request.source.pageIndex
  identity.sourceImageHash = request.source.imageHash
  identity.sourceWidth = request.source.imageWidth
  identity.sourceHeight = request.source.imageHeight
  identity.targetLanguage = translations.targetLanguage
  identity.regionBackendId = backend.backendId()
  identity.regionProfileId = backend.profileId()
  identity.regionRevision = analysis.regionRevision
  identity.documentRevision = analysis.document.analysisRevision
  identity.translationSourceProfileId = translations.sourceProfileId
  identity.translationSourceRevision = translations.sourceRevision
  identity.translationModelId = translations.modelId
  identity.translationPromptVersion = translations.promptVersion
  identity.translationContextFingerprint = translations.contextFingerprint
  identity.glossaryRevision = translations.glossaryRevision
  identity.translationRevision = translations.translationRevision
  identity.sourceTreatmentProfileId = profile.sourceTreatmentProfileId
  identity.layoutProfileId = profile.layoutProfileId
  identity.renderBackendId = backend.backendId()
  identity.renderProfileId = profile.profileId
  identity.renderTargetMimeType = profile.targetMimeType
  identity.renderRevision = profile.revision
  request.identity = identity
  return request
}

export default function comicLocalVisualBackendTest(): void {
  describe('Comic local visual backend', () => {
    it('recognizes and renders the comic fixture without an endpoint', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext: common.Context = await application.createModuleContext(
          ability.context,
          FIXTURE_MODULE,
        )
        const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
          FIXTURE_PATH,
        )
        const sourcePath: string = `${ability.context.cacheDir}/local-comic-visual-source.png`
        writeFile(sourcePath, bytes)
        const ocr: HarmonyComicLocalOcrEngine = new HarmonyComicLocalOcrEngine()
        try {
          const languages: string[] = await ocr.supportedLanguages()
          expect(languages.includes('ja')).assertEqual(true)
          const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
            ability.context,
            ocr,
          )
          const analysisRequest: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
          analysisRequest.source = source(sourcePath)
          analysisRequest.requestedRegionRevision = 1
          analysisRequest.requestedDocumentRevision = 1
          const analysis: ComicRegionAnalysisResult = await backend.analyze(analysisRequest)
          expect(analysis.document.blocks.length > 0).assertEqual(true)
          const recognized: string[] = []
          for (let index: number = 0; index < analysis.document.blocks.length; index++) {
            recognized.push(analysis.document.blocks[index].sourceText)
          }
          expect(recognized.includes('小')).assertEqual(false)
          const request: ComicRegionRenderRequest = renderRequest(
            backend,
            sourcePath,
            analysis,
          )
          const page: ComicRenderedPage = await backend.render(request)
          ComicVisualTranslationContract.validateRenderedPage(request.identity, page)
          expect(page.width).assertEqual(1024)
          expect(page.height).assertEqual(1536)
          expect(fileIo.accessSync(page.localFilePath)).assertEqual(true)
          console.info(
            `ComicLocalVisualBackend blocks=${analysis.document.blocks.length} ` +
              `text=${recognized.join('|')} artifact=${page.localFilePath} ` +
              `hash=${page.artifactHash} bytes=${page.byteLength}`,
          )
        } finally {
          await ocr.release()
          removeFile(sourcePath)
        }
        done()
      })
  })
}

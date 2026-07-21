import { application, common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicBlockTranslation,
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
  MANGA_TRANSLATOR_UI_BACKEND_ID,
  MANGA_TRANSLATOR_UI_EXPORT_PATH,
  MANGA_TRANSLATOR_UI_IMPORT_PATH,
  MANGA_TRANSLATOR_UI_PROFILE_ID,
  MangaTranslatorUiSidecarArchive,
  MangaTranslatorUiSidecarBackend,
  MangaTranslatorUiSidecarConfig,
  MangaTranslatorUiSidecarTransport,
  MangaTranslatorUiSidecarTransportRequest,
  MangaTranslatorUiSidecarTransportResponse,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const FIXTURE_PATH: string = 'comic_manga_translator_ui_v1_9_9_fixture.json'
const SOURCE_IMAGE_PATH: string = 'comic_translation_eval_page_01.png'
const CONTEXT_HASH: string =
  'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'

class RawFixtureTranslation {
  blockId: string = ''
  translatedText: string = ''
}

class RawSidecarFixture {
  projectId: string = ''
  pageIndex: number = -1
  sourceImageHash: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
  targetLanguage: string = ''
  exportZipBase64: string = ''
  translations: RawFixtureTranslation[] = []
}

class FakeSidecarTransport implements MangaTranslatorUiSidecarTransport {
  requests: MangaTranslatorUiSidecarTransportRequest[] = []
  responses: MangaTranslatorUiSidecarTransportResponse[] = []
  private responseIndex: number = 0

  async post(
    request: MangaTranslatorUiSidecarTransportRequest,
  ): Promise<MangaTranslatorUiSidecarTransportResponse> {
    this.requests.push(request)
    if (this.responseIndex >= this.responses.length) {
      throw new Error('Unexpected fake sidecar request')
    }
    const response: MangaTranslatorUiSidecarTransportResponse =
      this.responses[this.responseIndex]
    this.responseIndex++
    return response
  }
}

async function loadFixture(context: common.Context): Promise<RawSidecarFixture> {
  const bytes: Uint8Array = await context.resourceManager.getRawFileContent(FIXTURE_PATH)
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  return JSON.parse(decoder.decodeToString(bytes)) as RawSidecarFixture
}

function response(statusCode: number, body: Uint8Array): MangaTranslatorUiSidecarTransportResponse {
  const value: MangaTranslatorUiSidecarTransportResponse =
    new MangaTranslatorUiSidecarTransportResponse()
  value.statusCode = statusCode
  value.body = body
  return value
}

function source(raw: RawSidecarFixture, path: string): ComicVisualPageSource {
  const value: ComicVisualPageSource = new ComicVisualPageSource()
  value.projectId = raw.projectId
  value.pageIndex = raw.pageIndex
  value.imageFilePath = path
  value.imageHash = raw.sourceImageHash
  value.imageWidth = raw.imageWidth
  value.imageHeight = raw.imageHeight
  return value
}

function analysisRequest(raw: RawSidecarFixture, path: string): ComicRegionAnalysisRequest {
  const value: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
  value.source = source(raw, path)
  value.requestedRegionRevision = 1
  value.requestedDocumentRevision = 1
  return value
}

function translations(
  raw: RawSidecarFixture,
  analysis: ComicRegionAnalysisResult,
): ComicTranslationBatch {
  const value: ComicTranslationBatch = new ComicTranslationBatch()
  value.projectId = raw.projectId
  value.pageIndex = raw.pageIndex
  value.sourceImageHash = raw.sourceImageHash
  value.targetLanguage = raw.targetLanguage
  value.sourceProfileId = 'fixture-shared-llm-source'
  value.sourceRevision = 1
  value.modelId = 'fixture-context-model'
  value.promptVersion = 'fixture-block-translation-v1'
  value.contextFingerprint = CONTEXT_HASH
  value.translationRevision = 1
  for (let index: number = 0; index < raw.translations.length; index++) {
    const block: ComicBlockTranslation = new ComicBlockTranslation()
    block.blockId = raw.translations[index].blockId
    block.translatedText = raw.translations[index].translatedText
    value.blocks.push(block)
  }
  expect(value.blocks.length).assertEqual(analysis.document.blocks.length)
  return value
}

function renderRequest(
  raw: RawSidecarFixture,
  path: string,
  analysis: ComicRegionAnalysisResult,
): ComicRegionRenderRequest {
  const request: ComicRegionRenderRequest = new ComicRegionRenderRequest()
  request.source = source(raw, path)
  request.regionRevision = analysis.regionRevision
  request.document = analysis.document
  request.translations = translations(raw, analysis)
  request.adapterTemplate = analysis.adapterTemplate

  const profile: ComicRenderProfile = new ComicRenderProfile()
  profile.profileId = 'manga-translator-ui-v1.9.9-render-v1'
  profile.sourceTreatmentProfileId = 'manga-translator-ui-v1.9.9-inpaint-v1'
  profile.layoutProfileId = 'manga-translator-ui-v1.9.9-layout-v1'
  profile.targetMimeType = 'image/png'
  profile.revision = 1
  request.renderProfile = profile

  const identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  identity.route = ComicVisualTranslationRoute.STAGED
  identity.projectId = raw.projectId
  identity.pageIndex = raw.pageIndex
  identity.sourceImageHash = raw.sourceImageHash
  identity.sourceWidth = raw.imageWidth
  identity.sourceHeight = raw.imageHeight
  identity.targetLanguage = raw.targetLanguage
  identity.regionBackendId = MANGA_TRANSLATOR_UI_BACKEND_ID
  identity.regionProfileId = MANGA_TRANSLATOR_UI_PROFILE_ID
  identity.regionRevision = analysis.regionRevision
  identity.documentRevision = analysis.document.analysisRevision
  identity.translationSourceProfileId = request.translations.sourceProfileId
  identity.translationSourceRevision = request.translations.sourceRevision
  identity.translationModelId = request.translations.modelId
  identity.translationPromptVersion = request.translations.promptVersion
  identity.translationContextFingerprint = request.translations.contextFingerprint
  identity.glossaryRevision = request.translations.glossaryRevision
  identity.translationRevision = request.translations.translationRevision
  identity.sourceTreatmentProfileId = profile.sourceTreatmentProfileId
  identity.layoutProfileId = profile.layoutProfileId
  identity.renderBackendId = MANGA_TRANSLATOR_UI_BACKEND_ID
  identity.renderProfileId = profile.profileId
  identity.renderTargetMimeType = profile.targetMimeType
  identity.renderRevision = profile.revision
  request.identity = identity
  return request
}

function config(baseUrl: string = 'http://127.0.0.1:5003'): MangaTranslatorUiSidecarConfig {
  const value: MangaTranslatorUiSidecarConfig = new MangaTranslatorUiSidecarConfig()
  value.baseUrl = baseUrl
  value.authorizationValue = 'Bearer fixture-sidecar-token'
  value.translationConfigJson = '{}'
  return value
}

function containsText(bytes: Uint8Array, text: string): boolean {
  const needle: Uint8Array = new util.TextEncoder().encodeInto(text)
  if (needle.length <= 0 || needle.length > bytes.length) {
    return false
  }
  for (let offset: number = 0; offset <= bytes.length - needle.length; offset++) {
    let matches: boolean = true
    for (let index: number = 0; index < needle.length; index++) {
      if (bytes[offset + index] !== needle[index]) {
        matches = false
        break
      }
    }
    if (matches) {
      return true
    }
  }
  return false
}

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
      throw new Error('Fixture image write failed')
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

function replaceAll(bytes: Uint8Array, original: string, replacement: string): Uint8Array {
  const output: Uint8Array = new Uint8Array(bytes)
  const before: Uint8Array = new util.TextEncoder().encodeInto(original)
  const after: Uint8Array = new util.TextEncoder().encodeInto(replacement)
  if (before.length !== after.length) {
    throw new Error('ZIP fixture replacement length mismatch')
  }
  for (let offset: number = 0; offset <= output.length - before.length; offset++) {
    let matches: boolean = true
    for (let index: number = 0; index < before.length; index++) {
      if (output[offset + index] !== before[index]) {
        matches = false
        break
      }
    }
    if (matches) {
      output.set(after, offset)
      offset += before.length - 1
    }
  }
  return output
}

export default function mangaTranslatorUiSidecarBackendTest(): void {
  describe('Manga translator UI sidecar backend', () => {
    it('connects export and JSON import to one validated rendered page', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext = await application.createModuleContext(ability.context, FIXTURE_MODULE)
        const raw: RawSidecarFixture = await loadFixture(fixtureContext)
        const imageBytes: Uint8Array =
          await fixtureContext.resourceManager.getRawFileContent(SOURCE_IMAGE_PATH)
        const sourcePath: string = `${ability.context.cacheDir}/sidecar-backend-source.png`
        writeFile(sourcePath, imageBytes)
        const transport: FakeSidecarTransport = new FakeSidecarTransport()
        transport.responses.push(response(
          200,
          new util.Base64Helper().decodeSync(raw.exportZipBase64),
        ))
        transport.responses.push(response(200, imageBytes))
        let renderedPath: string = ''
        try {
          const backend: MangaTranslatorUiSidecarBackend = new MangaTranslatorUiSidecarBackend(
            ability.context,
            config(),
            transport,
          )
          const request: ComicRegionAnalysisRequest = analysisRequest(raw, sourcePath)
          const analysis: ComicRegionAnalysisResult = await backend.analyze(request)
          expect(analysis.document.blocks.length).assertEqual(2)
          expect(transport.requests.length).assertEqual(1)
          expect(transport.requests[0].url.endsWith(MANGA_TRANSLATOR_UI_EXPORT_PATH)).assertEqual(true)
          expect(transport.requests[0].headers['Authorization']).assertEqual(
            'Bearer fixture-sidecar-token',
          )
          expect(containsText(transport.requests[0].body, 'name="image"')).assertEqual(true)
          expect(containsText(transport.requests[0].body, 'name="config"')).assertEqual(true)

          const render: ComicRegionRenderRequest = renderRequest(raw, sourcePath, analysis)
          const page: ComicRenderedPage = await backend.render(render)
          renderedPath = page.localFilePath
          ComicVisualTranslationContract.validateRenderedPage(render.identity, page)
          expect(page.width).assertEqual(raw.imageWidth)
          expect(page.height).assertEqual(raw.imageHeight)
          expect(fileIo.accessSync(page.localFilePath)).assertEqual(true)
          expect(transport.requests.length).assertEqual(2)
          expect(transport.requests[1].url.endsWith(MANGA_TRANSLATOR_UI_IMPORT_PATH)).assertEqual(true)
          expect(containsText(transport.requests[1].body, 'name="json_file"')).assertEqual(true)
          expect(containsText(transport.requests[1].body, '这是测试')).assertEqual(true)
          expect(containsText(transport.requests[1].body, '去下一处吧')).assertEqual(true)
        } finally {
          removeFile(renderedPath)
          removeFile(sourcePath)
        }
        done()
      })

    it('rejects public HTTP and unsafe ZIP names before extraction', 0,
      async (done: Function) => {
        const publicConfig: MangaTranslatorUiSidecarConfig = config('http://example.com:5003')
        let publicHttpRejected: boolean = false
        try {
          publicConfig.validatedBaseUrl()
        } catch (_error) {
          publicHttpRejected = true
        }
        expect(publicHttpRejected).assertEqual(true)

        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext = await application.createModuleContext(ability.context, FIXTURE_MODULE)
        const raw: RawSidecarFixture = await loadFixture(fixtureContext)
        const archive: Uint8Array = new util.Base64Helper().decodeSync(raw.exportZipBase64)
        const unsafe: Uint8Array = replaceAll(
          archive,
          'translation.json',
          '../nslation.json',
        )
        let archiveRejected: boolean = false
        try {
          MangaTranslatorUiSidecarArchive.inspect(unsafe)
        } catch (_error) {
          archiveRejected = true
        }
        expect(archiveRejected).assertEqual(true)
        done()
      })

    it('does not persist a render response with mismatched dimensions', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext = await application.createModuleContext(ability.context, FIXTURE_MODULE)
        const raw: RawSidecarFixture = await loadFixture(fixtureContext)
        const imageBytes: Uint8Array =
          await fixtureContext.resourceManager.getRawFileContent(SOURCE_IMAGE_PATH)
        const sourcePath: string = `${ability.context.cacheDir}/sidecar-wrong-size-source.png`
        writeFile(sourcePath, imageBytes)
        const wrongSize: Uint8Array = new Uint8Array(imageBytes)
        wrongSize[16] = 0
        wrongSize[17] = 0
        wrongSize[18] = 3
        wrongSize[19] = 255
        const transport: FakeSidecarTransport = new FakeSidecarTransport()
        transport.responses.push(response(
          200,
          new util.Base64Helper().decodeSync(raw.exportZipBase64),
        ))
        transport.responses.push(response(200, wrongSize))
        try {
          const backend: MangaTranslatorUiSidecarBackend = new MangaTranslatorUiSidecarBackend(
            ability.context,
            config(),
            transport,
          )
          const analysis: ComicRegionAnalysisResult = await backend.analyze(
            analysisRequest(raw, sourcePath),
          )
          let rejected: boolean = false
          try {
            await backend.render(renderRequest(raw, sourcePath, analysis))
          } catch (_error) {
            rejected = true
          }
          expect(rejected).assertEqual(true)
        } finally {
          removeFile(sourcePath)
        }
        done()
      })
  })
}

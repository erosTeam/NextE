import { application, common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicGlossaryTerm,
  ComicVisualPageSource,
  ComicVisualTranslationRoute,
  ComicWholePageRenderRequest,
  TORII_BILLING_BYOK,
  TORII_BILLING_MANAGED,
  TORII_DEFAULT_MODEL_ID,
  TORII_FONT_WILDWORDS,
  TORII_WHOLE_PAGE_ENDPOINT,
  TORII_WHOLE_PAGE_LAYOUT_PROFILE_ID,
  TORII_WHOLE_PAGE_PROMPT_VERSION,
  TORII_WHOLE_PAGE_RENDER_PROFILE_ID,
  TORII_WHOLE_PAGE_SOURCE_REVISION,
  TORII_WHOLE_PAGE_SOURCE_TREATMENT_PROFILE_ID,
  ToriiWholePageConfig,
  ToriiWholePageContextStore,
  ToriiWholePageRenderBackend,
  ToriiWholePageTransport,
  ToriiWholePageTransportRequest,
  ToriiWholePageTransportResponse,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const SOURCE_IMAGE_PATH: string = 'comic_translation_eval_page_01.png'
const SOURCE_WIDTH: number = 1024
const SOURCE_HEIGHT: number = 1536

class FakeToriiTransport implements ToriiWholePageTransport {
  requests: ToriiWholePageTransportRequest[] = []
  responses: ToriiWholePageTransportResponse[] = []
  private responseIndex: number = 0

  async post(
    request: ToriiWholePageTransportRequest,
  ): Promise<ToriiWholePageTransportResponse> {
    this.requests.push(request)
    if (this.responseIndex >= this.responses.length) {
      throw new Error('Unexpected fake Torii request')
    }
    const response: ToriiWholePageTransportResponse = this.responses[this.responseIndex]
    this.responseIndex++
    return response
  }
}

function transportResponse(statusCode: number, text: string): ToriiWholePageTransportResponse {
  const response: ToriiWholePageTransportResponse = new ToriiWholePageTransportResponse()
  response.statusCode = statusCode
  response.body = new util.TextEncoder().encodeInto(text)
  response.rawHeader = JSON.stringify({
    success: statusCode >= 200 && statusCode <= 299 ? 'true' : 'false',
    'content-type': 'application/json',
  })
  return response
}

function failedBusinessResponse(message: string): ToriiWholePageTransportResponse {
  const response: ToriiWholePageTransportResponse = transportResponse(
    200,
    JSON.stringify({ message: message }),
  )
  response.rawHeader = JSON.stringify({ success: 'false' })
  return response
}

function successfulResponse(
  imageBytes: Uint8Array,
  context: string,
  mimeType: string = 'image/png',
): ToriiWholePageTransportResponse {
  const dataUrl: string = `data:${mimeType};base64,` +
    new util.Base64Helper().encodeToStringSync(imageBytes)
  const body: string = '{"image":' + JSON.stringify(dataUrl) +
    ',"inpainted":"unused-stage-artifact","context":' + JSON.stringify(context) +
    ',"text":"unused-stage-text"}'
  return transportResponse(200, body)
}

function managedConfig(): ToriiWholePageConfig {
  const config: ToriiWholePageConfig = new ToriiWholePageConfig()
  config.toriiApiKey = 'fixture-torii-secret'
  config.modelId = TORII_DEFAULT_MODEL_ID
  config.billingMode = TORII_BILLING_MANAGED
  return config
}

function byokConfig(): ToriiWholePageConfig {
  const config: ToriiWholePageConfig = managedConfig()
  config.billingMode = TORII_BILLING_BYOK
  config.modelId = 'fixture-custom-model'
  config.fontId = TORII_FONT_WILDWORDS
  config.byokSourceProfileId = 'fixture-openai-compatible'
  config.byokSourceRevision = 3
  config.byokBaseUrl = 'https://llm.fixture.example/v1'
  config.byokApiKey = 'fixture-provider-secret'
  return config
}

function source(path: string, imageBytes: Uint8Array, pageIndex: number): ComicVisualPageSource {
  const value: ComicVisualPageSource = new ComicVisualPageSource()
  value.projectId = 'torii-whole-page-backend-project'
  value.pageIndex = pageIndex
  value.imageFilePath = path
  value.imageHash = sha256(imageBytes)
  value.imageWidth = SOURCE_WIDTH
  value.imageHeight = SOURCE_HEIGHT
  return value
}

function renderRequest(
  backend: ToriiWholePageRenderBackend,
  imageSource: ComicVisualPageSource,
  rollingContext: string,
): ComicWholePageRenderRequest {
  const request: ComicWholePageRenderRequest = new ComicWholePageRenderRequest()
  request.source = imageSource
  request.context.sourceLanguage = 'ja'
  request.context.targetLanguage = 'zh-CN'
  request.context.rollingSummary = rollingContext
  request.context.styleGuide = '人名优保持一致。'
  request.context.glossaryRevision = 1
  const term: ComicGlossaryTerm = new ComicGlossaryTerm()
  term.sourceTerm = '優'
  term.targetTerm = '小优'
  request.context.glossary.push(term)

  const identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  identity.route = ComicVisualTranslationRoute.WHOLE_PAGE_RENDER
  identity.projectId = imageSource.projectId
  identity.pageIndex = imageSource.pageIndex
  identity.sourceImageHash = imageSource.imageHash
  identity.sourceWidth = imageSource.imageWidth
  identity.sourceHeight = imageSource.imageHeight
  identity.targetLanguage = request.context.targetLanguage
  identity.translationSourceProfileId = backend.sourceProfileId()
  identity.translationSourceRevision = TORII_WHOLE_PAGE_SOURCE_REVISION
  identity.translationModelId = backend.modelId()
  identity.translationPromptVersion = TORII_WHOLE_PAGE_PROMPT_VERSION
  identity.translationContextFingerprint = backend.contextFingerprint(request)
  identity.glossaryRevision = request.context.glossaryRevision
  identity.translationRevision = 1
  identity.sourceTreatmentProfileId = TORII_WHOLE_PAGE_SOURCE_TREATMENT_PROFILE_ID
  identity.layoutProfileId = TORII_WHOLE_PAGE_LAYOUT_PROFILE_ID
  identity.renderBackendId = backend.sourceProfileId()
  identity.renderProfileId = TORII_WHOLE_PAGE_RENDER_PROFILE_ID
  identity.renderTargetMimeType = 'image/png'
  identity.renderRevision = 1
  request.identity = identity
  return request
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

function multipartText(bytes: Uint8Array): string {
  return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes)
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

function readFile(path: string, length: number): Uint8Array {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
    const buffer: ArrayBuffer = new ArrayBuffer(length)
    const read: number = fileIo.readSync(file.fd, buffer, { length: length })
    if (read !== length) {
      throw new Error('Fixture image read failed')
    }
    return new Uint8Array(buffer)
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

function removeFile(path: string): void {
  try {
    if (path.length > 0 && fileIo.accessSync(path)) {
      fileIo.unlinkSync(path)
    }
  } catch (_error) {}
}

export default function toriiWholePageRenderBackendTest(): void {
  describe('ToriiWholePageRenderBackend', () => {
    it('uses one whole-page endpoint and carries returned context to the next page', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const appContext: common.UIAbilityContext = ability.context as common.UIAbilityContext
        const fixtureContext = await application.createModuleContext(ability.context, FIXTURE_MODULE)
        const imageBytes: Uint8Array =
          await fixtureContext.resourceManager.getRawFileContent(SOURCE_IMAGE_PATH)
        const sourcePath: string = `${appContext.cacheDir}/torii-whole-page-source.png`
        writeFile(sourcePath, imageBytes)
        const contextStore: ToriiWholePageContextStore =
          new ToriiWholePageContextStore(appContext)
        await contextStore.clear()
        const transport: FakeToriiTransport = new FakeToriiTransport()
        transport.responses.push(successfulResponse(imageBytes, '角色名“优”保持为“优”。'))
        transport.responses.push(successfulResponse(imageBytes, '角色名“优”保持为“优”。'))
        const backend: ToriiWholePageRenderBackend = new ToriiWholePageRenderBackend(
          appContext,
          managedConfig(),
          contextStore,
          transport,
        )
        let firstPath: string = ''
        let secondPath: string = ''
        try {
          const firstRequest: ComicWholePageRenderRequest = renderRequest(
            backend,
            source(sourcePath, imageBytes, 0),
            '',
          )
          const first: ComicRenderedPage = await backend.render(firstRequest)
          firstPath = first.localFilePath
          const nextContext: string = await contextStore.loadPrevious(
            backend.contextScope(first.identity.projectId, 1, first.identity.targetLanguage),
          )
          expect(nextContext).assertEqual('角色名“优”保持为“优”。')
          const secondRequest: ComicWholePageRenderRequest = renderRequest(
            backend,
            source(sourcePath, imageBytes, 1),
            nextContext,
          )
          const second: ComicRenderedPage = await backend.render(secondRequest)
          secondPath = second.localFilePath

          expect(transport.requests.length).assertEqual(2)
          expect(transport.requests[0].url).assertEqual(TORII_WHOLE_PAGE_ENDPOINT)
          expect(transport.requests[1].url).assertEqual(TORII_WHOLE_PAGE_ENDPOINT)
          expect(transport.requests[0].headers['Authorization'])
            .assertEqual('Bearer fixture-torii-secret')
          const firstBodyText: string = multipartText(transport.requests[0].body)
          const secondBodyText: string = multipartText(transport.requests[1].body)
          expect(firstBodyText.includes('name="translator"')).assertEqual(true)
          expect(firstBodyText.includes(TORII_DEFAULT_MODEL_ID)).assertEqual(true)
          expect(firstBodyText.includes('name="font"')).assertEqual(true)
          expect(firstBodyText.includes('\r\n\r\nnoto\r\n')).assertEqual(true)
          expect(firstBodyText.includes('\r\n\r\nNone\r\n')).assertEqual(true)
          expect(firstBodyText.includes('Glossary: 優 => 小优.')).assertEqual(true)
          expect(secondBodyText.includes(nextContext)).assertEqual(true)
          expect(firstBodyText.includes('x-byok-')).assertEqual(false)
          expect(firstBodyText.includes('fixture-shared-llm-secret')).assertEqual(false)
          expect(transport.requests[0].url.includes('/ocr')).assertEqual(false)
          expect(transport.requests[0].url.includes('/inpaint')).assertEqual(false)
          expect(transport.requests[0].url.includes('/typeset')).assertEqual(false)
        } finally {
          removeFile(firstPath)
          removeFile(secondPath)
          removeFile(sourcePath)
          await contextStore.clear()
        }
        done()
      })

    it('reuses an OpenAI-compatible source endpoint, model, and optional key in BYOK mode', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const appContext: common.UIAbilityContext = ability.context as common.UIAbilityContext
        const fixtureContext = await application.createModuleContext(ability.context, FIXTURE_MODULE)
        const imageBytes: Uint8Array =
          await fixtureContext.resourceManager.getRawFileContent(SOURCE_IMAGE_PATH)
        const sourcePath: string = `${appContext.cacheDir}/torii-byok-source.png`
        writeFile(sourcePath, imageBytes)
        const contextStore: ToriiWholePageContextStore =
          new ToriiWholePageContextStore(appContext)
        const transport: FakeToriiTransport = new FakeToriiTransport()
        transport.responses.push(successfulResponse(imageBytes, 'BYOK fixture context'))
        const backend: ToriiWholePageRenderBackend = new ToriiWholePageRenderBackend(
          appContext,
          byokConfig(),
          contextStore,
          transport,
        )
        let renderedPath: string = ''
        try {
          const page: ComicRenderedPage = await backend.render(renderRequest(
            backend,
            source(sourcePath, imageBytes, 0),
            '',
          ))
          renderedPath = page.localFilePath
          expect(transport.requests.length).assertEqual(1)
          const requestBodyText: string = multipartText(transport.requests[0].body)
          expect(requestBodyText.includes('name="translator"')).assertEqual(true)
          expect(requestBodyText.includes('fixture-custom-model')).assertEqual(true)
          expect(requestBodyText.includes('name="x-byok-local-url"')).assertEqual(true)
          expect(requestBodyText.includes('https://llm.fixture.example/v1')).assertEqual(true)
          expect(requestBodyText.includes('name="x-byok-local"')).assertEqual(true)
          expect(requestBodyText.includes('fixture-provider-secret')).assertEqual(true)
          expect(requestBodyText.includes('\r\n\r\nwildwords\r\n')).assertEqual(true)
        } finally {
          removeFile(renderedPath)
          removeFile(sourcePath)
          await contextStore.clear()
        }
        done()
      })

    it('normalizes a Torii JPEG response to the PNG render contract', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const appContext: common.UIAbilityContext = ability.context as common.UIAbilityContext
        const fixtureContext = await application.createModuleContext(ability.context, FIXTURE_MODULE)
        const sourceBytes: Uint8Array =
          await fixtureContext.resourceManager.getRawFileContent(SOURCE_IMAGE_PATH)
        const jpegBytes: Uint8Array = await appContext.resourceManager.getRawFileContent(
          'comic_translation_live_eval_page_01.jpg',
        )
        const sourcePath: string = `${appContext.cacheDir}/torii-jpeg-response-source.png`
        writeFile(sourcePath, sourceBytes)
        const contextStore: ToriiWholePageContextStore =
          new ToriiWholePageContextStore(appContext)
        const transport: FakeToriiTransport = new FakeToriiTransport()
        transport.responses.push(successfulResponse(
          jpegBytes,
          'JPEG fixture context',
          'image/jpeg',
        ))
        const backend: ToriiWholePageRenderBackend = new ToriiWholePageRenderBackend(
          appContext,
          managedConfig(),
          contextStore,
          transport,
        )
        let renderedPath: string = ''
        try {
          const page: ComicRenderedPage = await backend.render(renderRequest(
            backend,
            source(sourcePath, sourceBytes, 0),
            '',
          ))
          renderedPath = page.localFilePath
          expect(page.mimeType).assertEqual('image/png')
          const renderedBytes: Uint8Array = readFile(renderedPath, page.byteLength)
          expect(renderedBytes[0]).assertEqual(0x89)
          expect(renderedBytes[1]).assertEqual(0x50)
          expect(renderedBytes[2]).assertEqual(0x4e)
          expect(renderedBytes[3]).assertEqual(0x47)
        } finally {
          removeFile(renderedPath)
          removeFile(sourcePath)
          await contextStore.clear()
        }
        done()
      })

    it('rejects a wrong-size result before publishing an artifact', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const appContext: common.UIAbilityContext = ability.context as common.UIAbilityContext
        const fixtureContext = await application.createModuleContext(ability.context, FIXTURE_MODULE)
        const imageBytes: Uint8Array =
          await fixtureContext.resourceManager.getRawFileContent(SOURCE_IMAGE_PATH)
        const wrongSize: Uint8Array = new Uint8Array(imageBytes)
        wrongSize[19] = 255
        const sourcePath: string = `${appContext.cacheDir}/torii-wrong-size-source.png`
        writeFile(sourcePath, imageBytes)
        const contextStore: ToriiWholePageContextStore =
          new ToriiWholePageContextStore(appContext)
        const transport: FakeToriiTransport = new FakeToriiTransport()
        transport.responses.push(successfulResponse(wrongSize, 'unused'))
        const backend: ToriiWholePageRenderBackend = new ToriiWholePageRenderBackend(
          appContext,
          managedConfig(),
          contextStore,
          transport,
        )
        let rejected: boolean = false
        let message: string = ''
        try {
          await backend.render(renderRequest(
            backend,
            source(sourcePath, imageBytes, 0),
            '',
          ))
        } catch (error) {
          rejected = true
          message = (error as Error).message
        } finally {
          removeFile(sourcePath)
          await contextStore.clear()
        }
        expect(rejected).assertEqual(true)
        expect(message).assertEqual(
          'Torii whole-page result dimensions do not match the source',
        )
        done()
      })

    it('rejects an explicit Torii business failure returned with HTTP 200', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const appContext: common.UIAbilityContext = ability.context as common.UIAbilityContext
        const fixtureContext = await application.createModuleContext(ability.context, FIXTURE_MODULE)
        const imageBytes: Uint8Array =
          await fixtureContext.resourceManager.getRawFileContent(SOURCE_IMAGE_PATH)
        const sourcePath: string = `${appContext.cacheDir}/torii-business-failure-source.png`
        writeFile(sourcePath, imageBytes)
        const contextStore: ToriiWholePageContextStore =
          new ToriiWholePageContextStore(appContext)
        const transport: FakeToriiTransport = new FakeToriiTransport()
        transport.responses.push(failedBusinessResponse('fixture provider rejected request'))
        const backend: ToriiWholePageRenderBackend = new ToriiWholePageRenderBackend(
          appContext,
          managedConfig(),
          contextStore,
          transport,
        )
        let message: string = ''
        try {
          await backend.render(renderRequest(
            backend,
            source(sourcePath, imageBytes, 0),
            '',
          ))
        } catch (error) {
          message = (error as Error).message
        } finally {
          removeFile(sourcePath)
          await contextStore.clear()
        }
        expect(message).assertEqual(
          'Torii whole-page request did not confirm success (false): ' +
            'fixture provider rejected request',
        )
        done()
      })

    it('rejects a 200 response that does not explicitly confirm success', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const appContext: common.UIAbilityContext = ability.context as common.UIAbilityContext
        const fixtureContext = await application.createModuleContext(ability.context, FIXTURE_MODULE)
        const imageBytes: Uint8Array =
          await fixtureContext.resourceManager.getRawFileContent(SOURCE_IMAGE_PATH)
        const sourcePath: string = `${appContext.cacheDir}/torii-missing-success-source.png`
        writeFile(sourcePath, imageBytes)
        const contextStore: ToriiWholePageContextStore =
          new ToriiWholePageContextStore(appContext)
        const transport: FakeToriiTransport = new FakeToriiTransport()
        const response: ToriiWholePageTransportResponse = transportResponse(
          200,
          JSON.stringify({ detail: 'fixture response omitted success' }),
        )
        response.rawHeader = JSON.stringify({ 'content-type': 'application/json' })
        transport.responses.push(response)
        const backend: ToriiWholePageRenderBackend = new ToriiWholePageRenderBackend(
          appContext,
          managedConfig(),
          contextStore,
          transport,
        )
        let message: string = ''
        try {
          await backend.render(renderRequest(
            backend,
            source(sourcePath, imageBytes, 0),
            '',
          ))
        } catch (error) {
          message = (error as Error).message
        } finally {
          removeFile(sourcePath)
          await contextStore.clear()
        }
        expect(message).assertEqual(
          'Torii whole-page request did not confirm success (missing): ' +
            'fixture response omitted success',
        )
        done()
      })
  })
}

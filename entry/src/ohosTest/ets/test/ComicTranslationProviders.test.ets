import { common } from '@kit.AbilityKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  AxiosTextResponse,
  CodexOAuthDeviceSession,
  CodexOAuthHttpTransport,
  ComicGlossaryTerm,
  ComicGlossaryTermStatus,
  ComicImagePreparationProfile,
  ComicProviderHttpError,
  ComicProviderStageError,
  ComicResponsesHttpTransport,
  ComicResponsesRequestBuilder,
  ComicTranslationCodexUsageService,
  ComicTranslationModelCatalogService,
  ComicTranslationLiveEvaluationService,
  ComicTranslationReaderPageInput,
  ComicTranslationRuntimeService,
  ComicPageAnalysisRequest,
  ComicPreviousPageContext,
  ComicResponsesProtocol,
  ExperimentalCodexOAuthService,
  OpenAiApiComicPageAnalyzer,
} from 'shared'

const PROVIDER_FIXTURE_IMAGE_HASH: string = 'd'.repeat(64)

class FakeCodexOAuthTransport implements CodexOAuthHttpTransport {
  pollCalls: number = 0

  requestText(
    url: string,
    _method: string,
    _headers: Record<string, string>,
    _body: string,
    _connectTimeoutMs: number,
    _readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    const response: AxiosTextResponse = new AxiosTextResponse()
    if (url.endsWith('/usercode')) {
      response.statusCode = 200
      response.body = '{"user_code":"ABCD-EFGH","device_auth_id":"device-fixture","interval":3}'
      return Promise.resolve(response)
    }
    this.pollCalls++
    if (this.pollCalls === 1) {
      response.statusCode = 403
      response.body = '{}'
      return Promise.resolve(response)
    }
    response.statusCode = 200
    response.body = '{"authorization_code":"authorization-fixture","code_verifier":"verifier-fixture"}'
    return Promise.resolve(response)
  }
}

class CountingComicResponsesTransport implements ComicResponsesHttpTransport {
  requestCount: number = 0

  requestText(
    _url: string,
    _method: string,
    _headers: Record<string, string>,
    _body: string,
    _connectTimeoutMs: number,
    _readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    this.requestCount++
    return Promise.resolve(new AxiosTextResponse())
  }
}

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

function writeBytes(path: string, bytes: Uint8Array): void {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    )
    fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
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

class FixtureOutputText {
  type: string = 'output_text'
  text: string = ''
}

class FixtureMessage {
  type: string = 'message'
  phase: string = 'final_answer'
  content: FixtureOutputText[] = []
}

class FixtureResponsesEnvelope {
  output: FixtureMessage[] = []
}

class FixtureOutputItemDoneEvent {
  type: string = 'response.output_item.done'
  item: FixtureMessage = new FixtureMessage()
}

class FixtureCompletedResponse {
  status: string = 'completed'
  output: FixtureMessage[] | null = null
}

class FixtureCompletedEvent {
  type: string = 'response.completed'
  response: FixtureCompletedResponse = new FixtureCompletedResponse()
}

function fixtureMessage(pageJson: string): FixtureMessage {
  const outputText: FixtureOutputText = new FixtureOutputText()
  outputText.text = pageJson
  const message: FixtureMessage = new FixtureMessage()
  message.content = [outputText]
  return message
}

function providerRequest(): ComicPageAnalysisRequest {
  const request: ComicPageAnalysisRequest = new ComicPageAnalysisRequest()
  request.projectId = 'provider-fixture:zh-CN'
  request.pageIndex = 2
  request.imageFilePath = '/data/storage/el2/base/cache/provider-fixture.jpg'
  request.imageHash = PROVIDER_FIXTURE_IMAGE_HASH
  request.sourceWidth = 1200
  request.sourceHeight = 1800
  request.requestedAnalysisRevision = 1
  request.requestedTranslationRevision = 1
  const profile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
  profile.profileId = 'original-jpeg-v1'
  profile.mimeType = 'image/jpeg'
  profile.preparedWidth = 1200
  profile.preparedHeight = 1800
  profile.tileCount = 1
  request.imagePreparationProfile = profile
  request.context.sourceLanguage = 'ja'
  request.context.targetLanguage = 'zh-CN'
  request.context.rollingSummary = '优正在寻找失踪的哥哥。'
  const term: ComicGlossaryTerm = new ComicGlossaryTerm()
  term.sourceTerm = '優'
  term.targetTerm = '优'
  term.status = ComicGlossaryTermStatus.LOCKED
  request.context.glossary = [term]
  const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
  previous.pageIndex = 1
  previous.sourceText = 'お兄ちゃんを探してる。'
  previous.translatedText = '我在找哥哥。'
  request.context.previousPages = [previous]
  return request
}

function readerPageInput(imageFilePath: string): ComicTranslationReaderPageInput {
  const input: ComicTranslationReaderPageInput = new ComicTranslationReaderPageInput()
  input.projectId = 'reader-fixture:zh-CN'
  input.pageIndex = 0
  input.imageFilePath = imageFilePath
  input.imageWidth = 1200
  input.imageHeight = 1800
  input.sourceLanguage = 'ja'
  input.targetLanguage = 'zh-CN'
  return input
}

function providerPageJson(): string {
  return '{"schemaVersion":1,"projectId":"provider-fixture:zh-CN","pageIndex":2,' +
    '"imageHash":"' + PROVIDER_FIXTURE_IMAGE_HASH + '","imageWidth":1200,"imageHeight":1800,' +
    '"hasText":false,"pageSummary":"","blocks":[],"qualitySignals":[]}'
}

function providerPreviousContext(
  pageIndex: number,
  translatedText: string,
): ComicPreviousPageContext {
  const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
  previous.pageIndex = pageIndex
  previous.sourceText = `source-${pageIndex}`
  previous.translatedText = translatedText
  previous.pageSummary = `summary-${pageIndex}`
  return previous
}

export default function comicTranslationProvidersTest(): void {
  describe('ComicTranslationProviders', () => {
    it('assembles glossary and previous-page context without changing page identity', 0, (done: Function) => {
      const prompt: string = ComicResponsesProtocol.buildPrompt(providerRequest())
      expect(prompt.includes('projectId="provider-fixture:zh-CN"')).assertEqual(true)
      expect(prompt.includes('source="優" target="优" status=locked')).assertEqual(true)
      expect(prompt.includes('translation="我在找哥哥。"')).assertEqual(true)
      expect(prompt.includes('rollingSummary="优正在寻找失踪的哥哥。"')).assertEqual(true)
      expect(prompt.includes('concise cumulative rolling summary')).assertEqual(true)
      expect(prompt.includes('Set polygon=[] for every block.')).assertEqual(true)
      done()
    })

    it('fingerprints only context that remains visible in the bounded prompt', 0,
      (done: Function) => {
        const first: ComicPageAnalysisRequest = providerRequest()
        const second: ComicPageAnalysisRequest = providerRequest()
        const sharedPrefix: string = 'visible-prefix-' + 'x'.repeat(6000)
        first.context.rollingSummary = sharedPrefix + '-omitted-a'
        second.context.rollingSummary = sharedPrefix + '-omitted-b'
        first.context.glossary[0].notes = 'not sent a'
        second.context.glossary[0].notes = 'not sent b'
        first.context.glossary[0].updatedRevision = 1
        second.context.glossary[0].updatedRevision = 99

        const firstPrompt: string = ComicResponsesProtocol.buildPrompt(first)
        const secondPrompt: string = ComicResponsesProtocol.buildPrompt(second)
        const firstFingerprint: string = ComicResponsesProtocol.contextFingerprint(first)
        const secondFingerprint: string = ComicResponsesProtocol.contextFingerprint(second)
        expect(firstPrompt).assertEqual(secondPrompt)
        expect(firstFingerprint).assertEqual(secondFingerprint)

        second.context.rollingSummary = 'changed-visible-prefix-' + 'x'.repeat(6000)
        expect(ComicResponsesProtocol.contextFingerprint(second) === firstFingerprint)
          .assertEqual(false)
        done()
      })

    it('bounds adversarial long context without dropping locked terms or newest pages', 0,
      (done: Function) => {
        const request: ComicPageAnalysisRequest = providerRequest()
        request.pageIndex = 3
        const hostile: string = 'quote=" slash=\\ newline=\n'.repeat(12000)
        request.context.rollingSummary = hostile
        request.context.styleGuide = hostile
        request.context.glossary = []
        for (let index: number = 0; index < 80; index++) {
          const term: ComicGlossaryTerm = new ComicGlossaryTerm()
          term.sourceTerm = index === 0 ? 'locked-anchor' : hostile
          term.targetTerm = index === 0 ? 'locked-target' : hostile
          term.status = index === 0
            ? ComicGlossaryTermStatus.LOCKED
            : ComicGlossaryTermStatus.PROVISIONAL
          term.aliases = [hostile, hostile]
          request.context.glossary.push(term)
        }
        request.context.previousPages = []
        for (let pageIndex: number = 0; pageIndex < 3; pageIndex++) {
          const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
          previous.pageIndex = pageIndex
          previous.sourceText = hostile
          previous.translatedText = hostile
          previous.pageSummary = hostile
          request.context.previousPages.push(previous)
        }
        const prompt: string = ComicResponsesProtocol.buildPrompt(request)
        expect(prompt.length <= 48000).assertEqual(true)
        expect(prompt.includes('source="locked-anchor" target="locked-target" status=locked'))
          .assertEqual(true)
        expect(prompt.includes('pageIndex=1')).assertEqual(true)
        expect(prompt.includes('pageIndex=2')).assertEqual(true)
        expect(prompt.includes('pageIndex=0')).assertEqual(false)
        expect(prompt.includes('additional glossary terms omitted by prompt budget')).assertEqual(true)
        done()
      })

    it('normalizes direct provider previous-page context defensively', 0,
      (done: Function) => {
        const request: ComicPageAnalysisRequest = providerRequest()
        request.pageIndex = 3
        request.context.previousPages = [
          providerPreviousContext(2, 'duplicate-old'),
          providerPreviousContext(1, 'page-one'),
          providerPreviousContext(3, 'current-page'),
          providerPreviousContext(2, 'duplicate-new'),
          providerPreviousContext(4, 'future-page'),
          providerPreviousContext(1.5, 'fractional-page'),
        ]
        const prompt: string = ComicResponsesProtocol.buildPrompt(request)
        expect(prompt.includes('- pageIndex=1 source=')).assertEqual(true)
        expect(prompt.includes('- pageIndex=2 source=')).assertEqual(true)
        expect(prompt.includes('- pageIndex=3 source=')).assertEqual(false)
        expect(prompt.includes('- pageIndex=4 source=')).assertEqual(false)
        expect(prompt.includes('fractional-page')).assertEqual(false)
        expect(prompt.includes('duplicate-old')).assertEqual(false)
        expect(prompt.includes('duplicate-new')).assertEqual(true)
        done()
      })

    it('rejects an invalid direct provider request before file or transport work', 0,
      async (done: Function) => {
        const transport: CountingComicResponsesTransport = new CountingComicResponsesTransport()
        const analyzer: OpenAiApiComicPageAnalyzer = new OpenAiApiComicPageAnalyzer(
          'https://api.openai.com/v1',
          'fixture-key',
          'fixture-model',
          transport,
        )
        const request: ComicPageAnalysisRequest = providerRequest()
        request.pageIndex = Number.POSITIVE_INFINITY
        let message: string = ''
        try {
          await analyzer.analyze(request)
        } catch (error) {
          message = (error as Error).message
        }
        expect(message.includes('page index is invalid')).assertEqual(true)
        expect(transport.requestCount).assertEqual(0)
        done()
      })

    it('rejects non-canonical direct provider identity before image file access', 0,
      async (done: Function) => {
        const transport: CountingComicResponsesTransport = new CountingComicResponsesTransport()
        const analyzer: OpenAiApiComicPageAnalyzer = new OpenAiApiComicPageAnalyzer(
          'https://api.openai.com/v1',
          'fixture-key',
          'fixture-model',
          transport,
        )
        const nonCanonicalInputs: ComicPageAnalysisRequest[] = []
        const project: ComicPageAnalysisRequest = providerRequest()
        project.projectId = ' provider-fixture:zh-CN'
        nonCanonicalInputs.push(project)
        const sourceLanguage: ComicPageAnalysisRequest = providerRequest()
        sourceLanguage.context.sourceLanguage = 'ja '
        nonCanonicalInputs.push(sourceLanguage)
        const targetLanguage: ComicPageAnalysisRequest = providerRequest()
        targetLanguage.context.targetLanguage = ' zh-CN'
        nonCanonicalInputs.push(targetLanguage)
        const profile: ComicPageAnalysisRequest = providerRequest()
        profile.imagePreparationProfile.profileId = ' original-jpeg-v1'
        nonCanonicalInputs.push(profile)
        for (let index: number = 0; index < nonCanonicalInputs.length; index++) {
          let identityMessage: string = ''
          try {
            await analyzer.analyze(nonCanonicalInputs[index])
          } catch (error) {
            identityMessage = (error as Error).message
          }
          expect(identityMessage.includes('is not normalized')).assertEqual(true)
        }

        const invalidHash: ComicPageAnalysisRequest = providerRequest()
        invalidHash.imageHash = 'not-a-sha256'
        let hashMessage: string = ''
        try {
          await analyzer.analyze(invalidHash)
        } catch (error) {
          hashMessage = (error as Error).message
        }
        expect(hashMessage.includes('image hash is invalid')).assertEqual(true)

        const oversizedPath: ComicPageAnalysisRequest = providerRequest()
        oversizedPath.imageFilePath = ' '.repeat(4096) + 'x'
        let pathMessage: string = ''
        try {
          await analyzer.analyze(oversizedPath)
        } catch (error) {
          pathMessage = (error as Error).message
        }
        expect(pathMessage.includes('image file path is too long')).assertEqual(true)
        expect(transport.requestCount).assertEqual(0)
        done()
      })

    it('rejects an oversized direct provider model before file or transport work', 0,
      async (done: Function) => {
        const transport: CountingComicResponsesTransport = new CountingComicResponsesTransport()
        const analyzer: OpenAiApiComicPageAnalyzer = new OpenAiApiComicPageAnalyzer(
          'https://api.openai.com/v1',
          'fixture-key',
          'm'.repeat(161),
          transport,
        )
        let message: string = ''
        try {
          await analyzer.analyze(providerRequest())
        } catch (error) {
          message = (error as Error).message
        }
        expect(message.includes('model id is too long')).assertEqual(true)
        expect(transport.requestCount).assertEqual(0)
        done()
      })

    it('verifies final image hash and MIME before provider transport', 0,
      async (done: Function) => {
        const context: common.UIAbilityContext = await appContext()
        const path: string = `${context.cacheDir}/comic-provider-image-identity.jpg`
        const bytes: Uint8Array = new Uint8Array([
          0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46,
          0x49, 0x46, 0x00, 0x01, 0x02, 0x03, 0xff, 0xd9,
        ])
        const expectedHash: string = sha256(bytes)
        const transport: CountingComicResponsesTransport = new CountingComicResponsesTransport()
        const analyzer: OpenAiApiComicPageAnalyzer = new OpenAiApiComicPageAnalyzer(
          'https://api.openai.com/v1',
          'fixture-key',
          'fixture-model',
          transport,
        )
        try {
          writeBytes(path, bytes)
          const changed: ComicPageAnalysisRequest = providerRequest()
          changed.imageFilePath = path
          changed.imageHash = 'a'.repeat(64)
          let changedMessage: string = ''
          try {
            await analyzer.analyze(changed)
          } catch (error) {
            changedMessage = (error as Error).message
          }
          expect(changedMessage.includes('image identity changed')).assertEqual(true)
          expect(transport.requestCount).assertEqual(0)

          const mislabeled: ComicPageAnalysisRequest = providerRequest()
          mislabeled.imageFilePath = path
          mislabeled.imageHash = expectedHash
          mislabeled.imagePreparationProfile.mimeType = 'image/png'
          let mimeMessage: string = ''
          try {
            await analyzer.analyze(mislabeled)
          } catch (error) {
            mimeMessage = (error as Error).message
          }
          expect(mimeMessage.includes('MIME type does not match')).assertEqual(true)
          expect(transport.requestCount).assertEqual(0)

          const matching: ComicPageAnalysisRequest = providerRequest()
          matching.imageFilePath = path
          matching.imageHash = expectedHash
          let transportMessage: string = ''
          try {
            await analyzer.analyze(matching)
          } catch (error) {
            transportMessage = (error as Error).message
          }
          expect(transportMessage.includes('HTTP 0')).assertEqual(true)
          expect(transport.requestCount).assertEqual(1)
        } finally {
          try {
            fileIo.unlinkSync(path)
          } catch (_error) {
          }
        }
        done()
      })

    it('rejects non-exact Reader identifiers before image file access', 0,
      async (done: Function) => {
        const context: common.UIAbilityContext = await appContext()
        const missingPath: string = `${context.cacheDir}/comic-reader-preflight-missing.jpg`
        try {
          fileIo.unlinkSync(missingPath)
        } catch (_error) {
        }
        const invalidInputs: ComicTranslationReaderPageInput[] = []
        const project: ComicTranslationReaderPageInput = readerPageInput(missingPath)
        project.projectId = ' reader-fixture:zh-CN'
        invalidInputs.push(project)
        const source: ComicTranslationReaderPageInput = readerPageInput(missingPath)
        source.sourceLanguage = 'ja '
        invalidInputs.push(source)
        const target: ComicTranslationReaderPageInput = readerPageInput(missingPath)
        target.targetLanguage = ' zh-CN'
        invalidInputs.push(target)

        for (let index: number = 0; index < invalidInputs.length; index++) {
          let message: string = ''
          try {
            await ComicTranslationRuntimeService.runReaderPage(context, invalidInputs[index])
          } catch (error) {
            message = (error as Error).message
          }
          expect(message).assertEqual('Comic reader image source is invalid')
        }
        done()
      })

    it('extracts a normal Responses API output document', 0, (done: Function) => {
      const pageJson: string = providerPageJson()
      const envelope: FixtureResponsesEnvelope = new FixtureResponsesEnvelope()
      envelope.output = [fixtureMessage(pageJson)]
      const responseBody: string = JSON.stringify(envelope)
      expect(ComicResponsesProtocol.extractAssistantJson(responseBody, false)).assertEqual(pageJson)
      done()
    })

    it('reconstructs Codex output from done events when terminal output is null', 0, (done: Function) => {
      const pageJson: string = providerPageJson()
      const doneEnvelope: FixtureOutputItemDoneEvent = new FixtureOutputItemDoneEvent()
      doneEnvelope.item = fixtureMessage(pageJson)
      const doneEvent: string = JSON.stringify(doneEnvelope)
      const terminalEvent: string = JSON.stringify(new FixtureCompletedEvent())
      const stream: string = 'data: ' + doneEvent + '\n\n' + 'data: ' + terminalEvent + '\n\n'
      expect(ComicResponsesProtocol.extractAssistantJson(stream, true)).assertEqual(pageJson)
      done()
    })

    it('classifies provider request errors without retaining response details', 0, (done: Function) => {
      const error: ComicProviderHttpError = new ComicProviderHttpError(
        400,
        '{"error":{"message":"Unsupported parameter: max_output_tokens"}}',
      )
      expect(error.detailCode).assertEqual('unsupported_max_output_tokens')
      expect(error.message.includes('max_output_tokens')).assertEqual(false)
      expect(ComicProviderHttpError.classifyResponse(
        '{"detail":"Missing required field: tool_choice"}',
      )).assertEqual('missing_tool_choice')
      expect(ComicProviderHttpError.classifyResponse('opaque upstream failure')).assertEqual('')
      done()
    })

    it('keeps public and Codex Responses request fields separate', 0, (done: Function) => {
      const codexBody: string = ComicResponsesRequestBuilder.build(
        'codex-fixture',
        'Analyze the page.',
        'data:image/jpeg;base64,fixture',
        true,
        true,
      )
      expect(codexBody.includes('"max_output_tokens"')).assertEqual(false)
      expect(codexBody.includes('"tool_choice":"auto"')).assertEqual(true)
      expect(codexBody.includes('"parallel_tool_calls":false')).assertEqual(true)
      expect(codexBody.includes('"reasoning":null')).assertEqual(true)
      expect(codexBody.includes('"include":[]')).assertEqual(true)

      const publicBody: string = ComicResponsesRequestBuilder.build(
        'api-fixture',
        'Analyze the page.',
        'data:image/jpeg;base64,fixture',
        false,
        false,
      )
      expect(publicBody.includes('"max_output_tokens":8192')).assertEqual(true)
      expect(publicBody.includes('"tool_choice"')).assertEqual(false)
      done()
    })

    it('maps live-evaluation parser failures to fixed diagnostic codes', 0, (done: Function) => {
      expect(ComicTranslationLiveEvaluationService.classifyError(
        new Error('Comic analysis image identity mismatch'),
      )).assertEqual('output_identity_image')
      expect(ComicTranslationLiveEvaluationService.classifyError(
        new Error('Comic analysis reading order must be unique'),
      )).assertEqual('output_reading_order_invalid')
      expect(ComicTranslationLiveEvaluationService.classifyError(
        new Error('socket disconnected'),
      )).assertEqual('provider_transport_failed')
      const stageError: ComicProviderStageError =
        new ComicProviderStageError('output', 'text_kind')
      expect(stageError.stageCode).assertEqual('output')
      expect(stageError.detailCode).assertEqual('text_kind')
      expect(stageError.message.includes('visible source text')).assertEqual(false)
      done()
    })

    it('models pending and approved Codex device-code polling separately', 0, async (done: Function) => {
      const transport: FakeCodexOAuthTransport = new FakeCodexOAuthTransport()
      const session: CodexOAuthDeviceSession =
        await ExperimentalCodexOAuthService.requestDeviceCode(transport)
      expect(session.userCode).assertEqual('ABCD-EFGH')
      const pending = await ExperimentalCodexOAuthService.pollDeviceCodeOnce(session, transport)
      expect(pending.pending).assertEqual(true)
      const approved = await ExperimentalCodexOAuthService.pollDeviceCodeOnce(session, transport)
      expect(approved.pending).assertEqual(false)
      expect(approved.exchange?.authorizationCode).assertEqual('authorization-fixture')
      done()
    })

    it('extracts workspace and expiry claims without exposing the JWT', 0, (done: Function) => {
      const token: string = 'fixture.' +
        'eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdC1maXh0dXJlIn0sImV4cCI6MjAwMDAwMDAwMH0' +
        '.signature'
      expect(ExperimentalCodexOAuthService.extractAccountId(token)).assertEqual('acct-fixture')
      expect(ExperimentalCodexOAuthService.jwtExpiry(token)).assertEqual(2000000000000)
      done()
    })

    it('normalizes public API and account-scoped Codex model catalogs', 0, (done: Function) => {
      const apiModels: string[] = ComicTranslationModelCatalogService.parseApiModels(
        '{"data":[{"id":"vision-b"},{"id":"vision-a"},{"id":"vision-a"}]}',
      )
      expect(apiModels.length).assertEqual(2)
      expect(apiModels[0]).assertEqual('vision-a')
      expect(apiModels[1]).assertEqual('vision-b')

      const codexModels: string[] = ComicTranslationModelCatalogService.parseCodexModels(
        '{"models":[' +
          '{"slug":"hidden","visibility":"hidden","priority":0},' +
          '{"slug":"unsupported","supported_in_api":false,"priority":0},' +
          '{"slug":"later","supported_in_api":true,"priority":10},' +
          '{"slug":"first","supported_in_api":true,"priority":1},' +
          '{"slug":"first","priority":2}' +
        ']}',
      )
      expect(codexModels.length).assertEqual(2)
      expect(codexModels[0]).assertEqual('first')
      expect(codexModels[1]).assertEqual('later')
      done()
    })

    it('normalizes the Codex five-hour and weekly usage windows', 0, (done: Function) => {
      const usage = ComicTranslationCodexUsageService.parse(
        '{"plan_type":"pro","rate_limit":{"allowed":true,"limit_reached":false,' +
          '"primary_window":{"used_percent":37.4,"limit_window_seconds":18000,' +
          '"reset_after_seconds":7200,"reset_at":2000000000},' +
          '"secondary_window":{"used_percent":62,"limit_window_seconds":604800,' +
          '"reset_after_seconds":360000,"reset_at":2000500000}}}',
      )
      expect(usage.planType).assertEqual('pro')
      expect(usage.primary?.usedPercent).assertEqual(37.4)
      expect(usage.primary?.windowSeconds).assertEqual(18000)
      expect(usage.primary?.resetsAtMs).assertEqual(2000000000000)
      expect(usage.secondary?.usedPercent).assertEqual(62)
      expect(usage.secondary?.windowSeconds).assertEqual(604800)
      expect(usage.fiveHour?.usedPercent).assertEqual(37.4)
      expect(usage.weekly?.usedPercent).assertEqual(62)
      done()
    })

    it('classifies windows by duration instead of response position', 0, (done: Function) => {
      const usage = ComicTranslationCodexUsageService.parse(
        '{"plan_type":"pro","rate_limit":{"primary_window":' +
          '{"used_percent":99,"limit_window_seconds":604800,"reset_at":2000500000},' +
          '"secondary_window":null}}',
      )
      expect(usage.fiveHour).assertEqual(null)
      expect(usage.weekly?.usedPercent).assertEqual(99)
      done()
    })

    it('restores only the matching account quota cache', 0, (done: Function) => {
      const usage = ComicTranslationCodexUsageService.parse(
        '{"plan_type":"pro","rate_limit":{"primary_window":' +
          '{"used_percent":25,"limit_window_seconds":18000,"reset_at":2000000000},' +
          '"secondary_window":{"used_percent":40,"limit_window_seconds":604800,' +
          '"reset_at":2000500000}}}',
      )
      const cached: string = ComicTranslationCodexUsageService.serializeCached(
        'acct-fixture',
        usage,
      )
      const restored = ComicTranslationCodexUsageService.parseCached(cached, 'acct-fixture')
      expect(restored?.fiveHour?.usedPercent).assertEqual(25)
      expect(restored?.weekly?.usedPercent).assertEqual(40)
      expect(ComicTranslationCodexUsageService.parseCached(cached, 'acct-other')).assertEqual(null)
      done()
    })
  })
}

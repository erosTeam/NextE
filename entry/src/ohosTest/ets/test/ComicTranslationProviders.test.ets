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
  ComicResponsesRequestBuilder,
  ComicTranslationCodexUsageService,
  ComicTranslationModelCatalogService,
  ComicTranslationLiveEvaluationService,
  ComicPageAnalysisRequest,
  ComicPreviousPageContext,
  ComicResponsesProtocol,
  ExperimentalCodexOAuthService,
} from 'shared'

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
  request.imageHash = 'provider-fixture-sha256'
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

function providerPageJson(): string {
  return '{"schemaVersion":1,"projectId":"provider-fixture:zh-CN","pageIndex":2,' +
    '"imageHash":"provider-fixture-sha256","imageWidth":1200,"imageHeight":1800,' +
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

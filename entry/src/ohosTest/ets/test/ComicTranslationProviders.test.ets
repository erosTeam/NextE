import { describe, expect, it } from '@ohos/hypium'
import {
  AxiosTextResponse,
  CodexOAuthDeviceSession,
  CodexOAuthHttpTransport,
  ComicGlossaryTerm,
  ComicGlossaryTermStatus,
  ComicImagePreparationProfile,
  ComicTranslationCodexUsageService,
  ComicTranslationModelCatalogService,
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

export default function comicTranslationProvidersTest(): void {
  describe('ComicTranslationProviders', () => {
    it('assembles glossary and previous-page context without changing page identity', 0, (done: Function) => {
      const prompt: string = ComicResponsesProtocol.buildPrompt(providerRequest())
      expect(prompt.includes('projectId="provider-fixture:zh-CN"')).assertEqual(true)
      expect(prompt.includes('source="優" target="优" status=locked')).assertEqual(true)
      expect(prompt.includes('translation="我在找哥哥。"')).assertEqual(true)
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

import { describe, expect, it } from '@ohos/hypium'
import {
  AxiosTextResponse,
  TORII_CREDITS_ENDPOINT,
  TORII_DEFAULT_MODEL_ID,
  ToriiCreditsHttpTransport,
  ToriiCreditsService,
  ToriiCreditsSnapshot,
  ToriiTranslatorModel,
  ToriiTranslatorModelCatalog,
  ToriiWholePageLiveEvaluationPageReport,
  ToriiWholePageLiveEvaluationReport,
  ToriiWholePageCredential,
} from 'shared'

class FakeToriiCreditsTransport implements ToriiCreditsHttpTransport {
  url: string = ''
  method: string = ''
  body: string = ''
  authorization: string = ''
  response: AxiosTextResponse = new AxiosTextResponse()

  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    _connectTimeoutMs: number,
    _readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    this.url = url
    this.method = method
    this.body = body
    this.authorization = headers['Authorization']
    return Promise.resolve(this.response)
  }
}

export default function toriiWholePageSettingsTest(): void {
  describe('ToriiWholePageSettings', () => {
    it('uses the versioned official model snapshot and rejects unknown IDs', 0, () => {
      const models: ToriiTranslatorModel[] = ToriiTranslatorModelCatalog.all()
      expect(models.length).assertEqual(8)
      expect(models[0].modelId).assertEqual(TORII_DEFAULT_MODEL_ID)
      expect(ToriiTranslatorModelCatalog.find('manually-entered-model')).assertEqual(null)
      expect(ToriiTranslatorModelCatalog.find('gpt-5.4') !== null).assertEqual(true)
    })

    it('round-trips the Torii credential, drops legacy BYOK secrets, and rejects controls', 0, () => {
      const credential: ToriiWholePageCredential = new ToriiWholePageCredential()
      credential.toriiApiKey = 'fixture-torii-key'
      const raw: string = ToriiWholePageCredential.serialize(credential)
      const restored: ToriiWholePageCredential = ToriiWholePageCredential.parse(raw)
      expect(restored.toriiApiKey).assertEqual(credential.toriiApiKey)
      expect(raw.includes('fixture-provider-key')).assertFalse()
      const legacy: ToriiWholePageCredential = ToriiWholePageCredential.parse(
        '{"version":1,"toriiApiKey":"fixture-legacy-key","byokApiKey":"discarded"}',
      )
      expect(legacy.toriiApiKey).assertEqual('fixture-legacy-key')

      credential.toriiApiKey = 'unsafe\nkey'
      let rejected: boolean = false
      try {
        ToriiWholePageCredential.serialize(credential)
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertEqual(true)
    })

    it('queries available credits without a request body', 0, async () => {
      const transport: FakeToriiCreditsTransport = new FakeToriiCreditsTransport()
      transport.response.statusCode = 200
      transport.response.body = '{"credits":145.25}'

      const snapshot: ToriiCreditsSnapshot = await ToriiCreditsService.fetch(
        'fixture-torii-key',
        transport,
      )
      expect(snapshot.credits).assertEqual(145.25)
      expect(transport.url).assertEqual(TORII_CREDITS_ENDPOINT)
      expect(transport.method).assertEqual('GET')
      expect(transport.body).assertEqual('')
      expect(transport.authorization).assertEqual('Bearer fixture-torii-key')
    })

    it('keeps the cached balance scoped to its Torii key', 0, () => {
      const snapshot: ToriiCreditsSnapshot = new ToriiCreditsSnapshot()
      snapshot.credits = 12.5
      snapshot.fetchedAtMs = Date.now()
      const cached: string = ToriiCreditsService.serializeCached(
        'fixture-torii-key-a',
        snapshot,
      )
      const restored: ToriiCreditsSnapshot | null = ToriiCreditsService.parseCached(
        cached,
        'fixture-torii-key-a',
      )
      expect(restored === null).assertFalse()
      expect(restored?.credits).assertEqual(12.5)
      expect(ToriiCreditsService.parseCached(cached, 'fixture-torii-key-b'))
        .assertEqual(null)
    })

    it('rejects failed or invalid balance responses without exposing the key', 0, async () => {
      const transport: FakeToriiCreditsTransport = new FakeToriiCreditsTransport()
      transport.response.statusCode = 401
      transport.response.body = '{"detail":"unauthorized"}'
      let message: string = ''
      try {
        await ToriiCreditsService.fetch('fixture-sensitive-torii-key', transport)
      } catch (error) {
        message = (error as Error).message
      }
      expect(message).assertEqual('Torii credits query failed (HTTP 401)')
      expect(message.includes('fixture-sensitive-torii-key')).assertFalse()

      let invalidRejected: boolean = false
      try {
        ToriiCreditsService.parse('{"credits":-1}')
      } catch (_error) {
        invalidRejected = true
      }
      expect(invalidRejected).assertTrue()
    })

    it('expires a cached balance after twenty-four hours', 0, () => {
      const snapshot: ToriiCreditsSnapshot = new ToriiCreditsSnapshot()
      snapshot.credits = 88
      snapshot.fetchedAtMs = Date.now() - 24 * 60 * 60 * 1000 - 1
      const cached: string = ToriiCreditsService.serializeCached(
        'fixture-torii-key',
        snapshot,
      )
      expect(ToriiCreditsService.parseCached(cached, 'fixture-torii-key'))
        .assertEqual(null)
    })

    it('accepts only two complete visual evaluation artifacts', 0, () => {
      const report: ToriiWholePageLiveEvaluationReport =
        new ToriiWholePageLiveEvaluationReport()
      for (let index: number = 0; index < 2; index++) {
        const page: ToriiWholePageLiveEvaluationPageReport =
          new ToriiWholePageLiveEvaluationPageReport()
        page.pageIndex = index
        page.artifactHash = 'a'.repeat(64)
        page.artifactBytes = 1024
        page.artifactPath = `/data/fixture-${index}.png`
        page.width = 1024
        page.height = 1536
        report.pages.push(page)
      }
      expect(report.passed()).assertTrue()
      report.pages[1].errorCode = 'provider_failure'
      report.pages[1].errorDetail = 'fixture failure'
      report.errorCode = report.pages[1].errorCode
      report.errorDetail = report.pages[1].errorDetail
      report.failedPageIndex = 1
      expect(report.passed()).assertFalse()
      expect(report.failedPageIndex).assertEqual(1)
      expect(report.errorDetail).assertEqual('fixture failure')
    })
  })
}

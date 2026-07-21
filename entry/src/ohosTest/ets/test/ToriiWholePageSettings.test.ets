import { describe, expect, it } from '@ohos/hypium'
import {
  AxiosTextResponse,
  COMIC_VISUAL_ROUTE_TORII,
  ComicVisualProviderSettingsSnapshot,
  TORII_BILLING_BYOK,
  TORII_BILLING_MANAGED,
  TORII_BYOK_GOOGLE,
  TORII_BYOK_OPENAI,
  TORII_BYOK_OPENROUTER,
  TORII_CREDITS_ENDPOINT,
  TORII_DEFAULT_MODEL_ID,
  ToriiCreditsHttpTransport,
  ToriiCreditsService,
  ToriiCreditsSnapshot,
  ToriiTranslatorModel,
  ToriiTranslatorModelCatalog,
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
      expect(ToriiTranslatorModelCatalog.compatible(
        'gpt-5.4',
        TORII_BILLING_MANAGED,
        TORII_BYOK_GOOGLE,
      )).assertEqual(true)
    })

    it('filters direct BYOK models while OpenRouter accepts the published catalog', 0, () => {
      expect(ToriiTranslatorModelCatalog.compatible(
        'gemini-3.1-flash-lite',
        TORII_BILLING_BYOK,
        TORII_BYOK_GOOGLE,
      )).assertEqual(true)
      expect(ToriiTranslatorModelCatalog.compatible(
        'gpt-5.4',
        TORII_BILLING_BYOK,
        TORII_BYOK_GOOGLE,
      )).assertEqual(false)
      expect(ToriiTranslatorModelCatalog.compatible(
        'gpt-5.4',
        TORII_BILLING_BYOK,
        TORII_BYOK_OPENROUTER,
      )).assertEqual(true)

      const invalid: ComicVisualProviderSettingsSnapshot =
        new ComicVisualProviderSettingsSnapshot()
      invalid.route = COMIC_VISUAL_ROUTE_TORII
      invalid.toriiModelId = 'gemini-3.1-flash-lite'
      invalid.toriiBillingMode = TORII_BILLING_BYOK
      invalid.toriiByokProvider = TORII_BYOK_OPENAI
      let rejected: boolean = false
      try {
        invalid.assertValid()
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertEqual(true)
    })

    it('round-trips bounded credentials and rejects control characters', 0, () => {
      const credential: ToriiWholePageCredential = new ToriiWholePageCredential()
      credential.toriiApiKey = 'fixture-torii-key'
      credential.byokApiKey = 'fixture-provider-key'
      const raw: string = ToriiWholePageCredential.serialize(credential)
      const restored: ToriiWholePageCredential = ToriiWholePageCredential.parse(raw)
      expect(restored.toriiApiKey).assertEqual(credential.toriiApiKey)
      expect(restored.byokApiKey).assertEqual(credential.byokApiKey)

      credential.byokApiKey = 'unsafe\nkey'
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
  })
}

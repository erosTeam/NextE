import { describe, expect, it } from '@ohos/hypium'
import {
  COMIC_VISUAL_ROUTE_TORII,
  ComicVisualProviderSettingsSnapshot,
  TORII_BILLING_BYOK,
  TORII_BILLING_MANAGED,
  TORII_BYOK_GOOGLE,
  TORII_BYOK_OPENAI,
  TORII_BYOK_OPENROUTER,
  TORII_DEFAULT_MODEL_ID,
  ToriiTranslatorModel,
  ToriiTranslatorModelCatalog,
  ToriiWholePageCredential,
} from 'shared'

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
  })
}

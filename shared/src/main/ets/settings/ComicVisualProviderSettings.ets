import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'

export const COMIC_VISUAL_ROUTE_LOCAL: string = 'local'
export const COMIC_VISUAL_ROUTE_TORII: string = 'torii_whole_page'
export const TORII_BILLING_MANAGED: string = 'managed'
export const TORII_BILLING_BYOK: string = 'byok'
export const TORII_BYOK_OPENROUTER: string = 'openrouter'
export const TORII_BYOK_OPENAI: string = 'openai'
export const TORII_BYOK_GOOGLE: string = 'google'
export const TORII_BYOK_ANTHROPIC: string = 'anthropic'
export const TORII_BYOK_DEEPSEEK: string = 'deepseek'
export const TORII_BYOK_XAI: string = 'xai'
export const TORII_FONT_NOTO: string = 'noto'
export const TORII_FONT_WILDWORDS: string = 'wildwords'
export const TORII_MODEL_CATALOG_REVIEWED_AT: string = '2026-07-22'
export const TORII_DEFAULT_MODEL_ID: string = 'gemini-3.1-flash-lite'

export class ToriiTranslatorModel {
  modelId: string = ''
  displayName: string = ''
  baseCredits: number = 0
  directProvider: string = ''

  copy(): ToriiTranslatorModel {
    const value: ToriiTranslatorModel = new ToriiTranslatorModel()
    value.modelId = this.modelId
    value.displayName = this.displayName
    value.baseCredits = this.baseCredits
    value.directProvider = this.directProvider
    return value
  }
}

/** Versioned snapshot of the model IDs published by Torii's official API reference. */
export class ToriiTranslatorModelCatalog {
  static all(): ToriiTranslatorModel[] {
    return [
      ToriiTranslatorModelCatalog.model(
        'gemini-3.1-flash-lite', 'Gemini 3.1 Flash Lite', 1, TORII_BYOK_GOOGLE,
      ),
      ToriiTranslatorModelCatalog.model('deepseek', 'DeepSeek V4 Flash', 1, TORII_BYOK_DEEPSEEK),
      ToriiTranslatorModelCatalog.model('grok-4.20', 'Grok 4.20', 1, TORII_BYOK_XAI),
      ToriiTranslatorModelCatalog.model('kimi-k2.5', 'Kimi K2.5', 2, ''),
      ToriiTranslatorModelCatalog.model('gpt-5.4', 'GPT-5.4', 2, TORII_BYOK_OPENAI),
      ToriiTranslatorModelCatalog.model('gemini-3-flash', 'Gemini 3 Flash', 2, TORII_BYOK_GOOGLE),
      ToriiTranslatorModelCatalog.model(
        'claude-sonnet-4.6', 'Claude Sonnet 4.6', 2, TORII_BYOK_ANTHROPIC,
      ),
      ToriiTranslatorModelCatalog.model(
        'gemini-3.5-flash', 'Gemini 3.5 Flash', 3, TORII_BYOK_GOOGLE,
      ),
    ]
  }

  static find(modelId: string): ToriiTranslatorModel | null {
    const models: ToriiTranslatorModel[] = ToriiTranslatorModelCatalog.all()
    for (let index: number = 0; index < models.length; index++) {
      if (models[index].modelId === modelId) {
        return models[index]
      }
    }
    return null
  }

  static compatible(modelId: string, billingMode: string, byokProvider: string): boolean {
    const model: ToriiTranslatorModel | null = ToriiTranslatorModelCatalog.find(modelId)
    if (model === null) {
      return false
    }
    if (billingMode === TORII_BILLING_MANAGED) {
      return true
    }
    return billingMode === TORII_BILLING_BYOK &&
      (byokProvider === TORII_BYOK_OPENROUTER || model.directProvider === byokProvider)
  }

  static byokProviders(): string[] {
    return [
      TORII_BYOK_OPENROUTER,
      TORII_BYOK_OPENAI,
      TORII_BYOK_GOOGLE,
      TORII_BYOK_ANTHROPIC,
      TORII_BYOK_DEEPSEEK,
      TORII_BYOK_XAI,
    ]
  }

  private static model(
    modelId: string,
    displayName: string,
    baseCredits: number,
    directProvider: string,
  ): ToriiTranslatorModel {
    const model: ToriiTranslatorModel = new ToriiTranslatorModel()
    model.modelId = modelId
    model.displayName = displayName
    model.baseCredits = baseCredits
    model.directProvider = directProvider
    return model
  }
}

export class ComicVisualProviderSettingsSnapshot {
  route: string = COMIC_VISUAL_ROUTE_LOCAL
  toriiModelId: string = TORII_DEFAULT_MODEL_ID
  toriiBillingMode: string = TORII_BILLING_MANAGED
  toriiByokSourceProfileId: string = ''
  toriiByokModelId: string = ''
  toriiFontId: string = TORII_FONT_NOTO

  copy(): ComicVisualProviderSettingsSnapshot {
    const value: ComicVisualProviderSettingsSnapshot =
      new ComicVisualProviderSettingsSnapshot()
    value.route = this.route
    value.toriiModelId = this.toriiModelId
    value.toriiBillingMode = this.toriiBillingMode
    value.toriiByokSourceProfileId = this.toriiByokSourceProfileId
    value.toriiByokModelId = this.toriiByokModelId
    value.toriiFontId = this.toriiFontId
    return value
  }

  assertValid(): void {
    if ((this.route !== COMIC_VISUAL_ROUTE_LOCAL &&
      this.route !== COMIC_VISUAL_ROUTE_TORII) ||
      (this.toriiBillingMode !== TORII_BILLING_MANAGED &&
        this.toriiBillingMode !== TORII_BILLING_BYOK) ||
      ToriiTranslatorModelCatalog.find(this.toriiModelId) === null ||
      (this.toriiFontId !== TORII_FONT_NOTO &&
        this.toriiFontId !== TORII_FONT_WILDWORDS) ||
      !ComicVisualProviderSettingsSnapshot.validOptionalByokBinding(
        this.toriiByokSourceProfileId,
        this.toriiByokModelId,
      )) {
      throw new Error('Comic visual provider settings are invalid')
    }
  }

  byokConfigured(): boolean {
    return this.toriiByokSourceProfileId.length > 0 && this.toriiByokModelId.length > 0
  }

  private static validOptionalByokBinding(sourceProfileId: string, modelId: string): boolean {
    const emptySource: boolean = sourceProfileId.length === 0
    const emptyModel: boolean = modelId.length === 0
    if (emptySource && emptyModel) {
      return true
    }
    return !emptySource && ComicVisualProviderSettingsSnapshot.identifier(sourceProfileId, 160) &&
      (emptyModel || ComicVisualProviderSettingsSnapshot.identifier(modelId, 160))
  }

  private static identifier(value: string, maxChars: number): boolean {
    if (value.length === 0 || value.length > maxChars || value !== value.trim()) {
      return false
    }
    for (let index: number = 0; index < value.length; index++) {
      const code: number = value.charCodeAt(index)
      if (code <= 31 || code === 127) {
        return false
      }
    }
    return true
  }
}

export class ComicVisualProviderSettings {
  static async load(
    context: common.UIAbilityContext,
  ): Promise<ComicVisualProviderSettingsSnapshot> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const snapshot: ComicVisualProviderSettingsSnapshot =
      new ComicVisualProviderSettingsSnapshot()
    snapshot.route = store.getSync(
      StorageKeys.COMIC_TRANSLATION_VISUAL_ROUTE,
      COMIC_VISUAL_ROUTE_LOCAL,
    ) as string
    snapshot.toriiModelId = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_MODEL,
      TORII_DEFAULT_MODEL_ID,
    ) as string
    snapshot.toriiBillingMode = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_BILLING_MODE,
      TORII_BILLING_MANAGED,
    ) as string
    snapshot.toriiByokSourceProfileId = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_BYOK_SOURCE_PROFILE,
      '',
    ) as string
    snapshot.toriiByokModelId = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_BYOK_MODEL,
      '',
    ) as string
    snapshot.toriiFontId = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_FONT,
      TORII_FONT_NOTO,
    ) as string
    try {
      snapshot.assertValid()
      return snapshot
    } catch (_error) {
      return new ComicVisualProviderSettingsSnapshot()
    }
  }

  static async save(
    context: common.UIAbilityContext,
    snapshot: ComicVisualProviderSettingsSnapshot,
  ): Promise<void> {
    snapshot.assertValid()
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.putSync(StorageKeys.COMIC_TRANSLATION_VISUAL_ROUTE, snapshot.route)
    store.putSync(StorageKeys.COMIC_TRANSLATION_TORII_MODEL, snapshot.toriiModelId)
    store.putSync(
      StorageKeys.COMIC_TRANSLATION_TORII_BILLING_MODE,
      snapshot.toriiBillingMode,
    )
    if (snapshot.toriiByokSourceProfileId.length > 0) {
      store.putSync(
        StorageKeys.COMIC_TRANSLATION_TORII_BYOK_SOURCE_PROFILE,
        snapshot.toriiByokSourceProfileId,
      )
    } else {
      store.deleteSync(StorageKeys.COMIC_TRANSLATION_TORII_BYOK_SOURCE_PROFILE)
    }
    if (snapshot.toriiByokModelId.length > 0) {
      store.putSync(StorageKeys.COMIC_TRANSLATION_TORII_BYOK_MODEL, snapshot.toriiByokModelId)
    } else {
      store.deleteSync(StorageKeys.COMIC_TRANSLATION_TORII_BYOK_MODEL)
    }
    store.putSync(StorageKeys.COMIC_TRANSLATION_TORII_FONT, snapshot.toriiFontId)
    store.deleteSync(StorageKeys.COMIC_TRANSLATION_TORII_BYOK_PROVIDER)
    store.flushSync()
  }
}

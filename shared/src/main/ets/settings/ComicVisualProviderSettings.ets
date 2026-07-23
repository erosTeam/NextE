import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'

export const COMIC_VISUAL_ROUTE_LOCAL: string = 'local'
export const COMIC_VISUAL_ROUTE_TORII: string = 'torii_whole_page'
export const TORII_FONT_NOTO: string = 'noto'
export const TORII_FONT_WILDWORDS: string = 'wildwords'
export const TORII_FONT_MA_SHAN_ZHENG: string = 'mashanzheng'
export const TORII_MODEL_CATALOG_REVIEWED_AT: string = '2026-07-22'
export const TORII_DEFAULT_MODEL_ID: string = 'gemini-3.1-flash-lite'

export class ToriiFontOption {
  fontId: string = ''
  displayName: string = ''

  static create(fontId: string, displayName: string): ToriiFontOption {
    const option: ToriiFontOption = new ToriiFontOption()
    option.fontId = fontId
    option.displayName = displayName
    return option
  }
}

/** Target-aware subset of Torii's published font catalog used by NextE. */
export class ToriiFontCatalog {
  static forTargetLanguage(targetLanguage: string): ToriiFontOption[] {
    const options: ToriiFontOption[] = [
      ToriiFontOption.create(TORII_FONT_NOTO, 'NotoSans'),
    ]
    if (ToriiFontCatalog.isEnglish(targetLanguage)) {
      options.push(ToriiFontOption.create(TORII_FONT_WILDWORDS, 'WildWords'))
      options.push(ToriiFontOption.create(
        TORII_FONT_MA_SHAN_ZHENG,
        'MaShanZheng',
      ))
    } else if (ToriiFontCatalog.isSimplifiedChinese(targetLanguage)) {
      options.push(ToriiFontOption.create(
        TORII_FONT_MA_SHAN_ZHENG,
        'MaShanZheng',
      ))
    }
    return options
  }

  static supports(fontId: string, targetLanguage: string): boolean {
    const options: ToriiFontOption[] =
      ToriiFontCatalog.forTargetLanguage(targetLanguage)
    for (let index: number = 0; index < options.length; index++) {
      if (options[index].fontId === fontId) {
        return true
      }
    }
    return false
  }

  static effectiveFontId(fontId: string, targetLanguage: string): string {
    return ToriiFontCatalog.supports(fontId, targetLanguage)
      ? fontId
      : TORII_FONT_NOTO
  }

  static displayName(fontId: string): string {
    if (fontId === TORII_FONT_WILDWORDS) {
      return 'WildWords'
    }
    if (fontId === TORII_FONT_MA_SHAN_ZHENG) {
      return 'MaShanZheng'
    }
    return 'NotoSans'
  }

  private static normalizedLanguage(targetLanguage: string): string {
    return targetLanguage.trim().toLowerCase().replace('_', '-')
  }

  private static isEnglish(targetLanguage: string): boolean {
    const normalized: string = ToriiFontCatalog.normalizedLanguage(targetLanguage)
    return normalized === 'en' || normalized.startsWith('en-')
  }

  private static isSimplifiedChinese(targetLanguage: string): boolean {
    const normalized: string = ToriiFontCatalog.normalizedLanguage(targetLanguage)
    return normalized === 'zh' || normalized === 'zh-cn' ||
      normalized === 'zh-hans' || normalized.startsWith('zh-hans-')
  }
}

export class ToriiTranslatorModel {
  modelId: string = ''
  displayName: string = ''
  baseCredits: number = 0

  copy(): ToriiTranslatorModel {
    const value: ToriiTranslatorModel = new ToriiTranslatorModel()
    value.modelId = this.modelId
    value.displayName = this.displayName
    value.baseCredits = this.baseCredits
    return value
  }
}

/** Versioned snapshot of the model IDs published by Torii's official API reference. */
export class ToriiTranslatorModelCatalog {
  static all(): ToriiTranslatorModel[] {
    return [
      ToriiTranslatorModelCatalog.model(
        'gemini-3.1-flash-lite', 'Gemini 3.1 Flash Lite', 1,
      ),
      ToriiTranslatorModelCatalog.model('deepseek', 'DeepSeek V4 Flash', 1),
      ToriiTranslatorModelCatalog.model('grok-4.20', 'Grok 4.20', 1),
      ToriiTranslatorModelCatalog.model('kimi-k2.5', 'Kimi K2.5', 2),
      ToriiTranslatorModelCatalog.model('gpt-5.4', 'GPT-5.4', 2),
      ToriiTranslatorModelCatalog.model('gemini-3-flash', 'Gemini 3 Flash', 2),
      ToriiTranslatorModelCatalog.model(
        'claude-sonnet-4.6', 'Claude Sonnet 4.6', 2,
      ),
      ToriiTranslatorModelCatalog.model(
        'gemini-3.5-flash', 'Gemini 3.5 Flash', 3,
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

  private static model(
    modelId: string,
    displayName: string,
    baseCredits: number,
  ): ToriiTranslatorModel {
    const model: ToriiTranslatorModel = new ToriiTranslatorModel()
    model.modelId = modelId
    model.displayName = displayName
    model.baseCredits = baseCredits
    return model
  }
}

export class ComicVisualProviderSettingsSnapshot {
  route: string = COMIC_VISUAL_ROUTE_LOCAL
  toriiModelId: string = TORII_DEFAULT_MODEL_ID
  toriiFontId: string = TORII_FONT_NOTO

  copy(): ComicVisualProviderSettingsSnapshot {
    const value: ComicVisualProviderSettingsSnapshot =
      new ComicVisualProviderSettingsSnapshot()
    value.route = this.route
    value.toriiModelId = this.toriiModelId
    value.toriiFontId = this.toriiFontId
    return value
  }

  assertValid(): void {
    if ((this.route !== COMIC_VISUAL_ROUTE_LOCAL &&
      this.route !== COMIC_VISUAL_ROUTE_TORII) ||
      ToriiTranslatorModelCatalog.find(this.toriiModelId) === null ||
      (this.toriiFontId !== TORII_FONT_NOTO &&
        this.toriiFontId !== TORII_FONT_WILDWORDS &&
        this.toriiFontId !== TORII_FONT_MA_SHAN_ZHENG)) {
      throw new Error('Comic visual provider settings are invalid')
    }
  }
}

export class ComicVisualProviderSettings {
  private static runtimeRevisionValue: number = 0

  static runtimeRevision(): number {
    return ComicVisualProviderSettings.runtimeRevisionValue
  }

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
    snapshot.toriiFontId = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_FONT,
      TORII_FONT_NOTO,
    ) as string
    ComicVisualProviderSettings.retireLegacyByokSettings(store)
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
    store.putSync(StorageKeys.COMIC_TRANSLATION_TORII_FONT, snapshot.toriiFontId)
    ComicVisualProviderSettings.deleteLegacyByokSettings(store)
    store.flushSync()
    ComicVisualProviderSettings.runtimeRevisionValue++
  }

  private static retireLegacyByokSettings(store: preferences.Preferences): void {
    const billingMode: string = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BILLING_MODE,
      '',
    ) as string
    const provider: string = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BYOK_PROVIDER,
      '',
    ) as string
    const sourceProfile: string = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BYOK_SOURCE_PROFILE,
      '',
    ) as string
    const model: string = store.getSync(
      StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BYOK_MODEL,
      '',
    ) as string
    if (billingMode.length === 0 && provider.length === 0 &&
      sourceProfile.length === 0 && model.length === 0) {
      return
    }
    ComicVisualProviderSettings.deleteLegacyByokSettings(store)
    store.flushSync()
  }

  private static deleteLegacyByokSettings(store: preferences.Preferences): void {
    store.deleteSync(StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BILLING_MODE)
    store.deleteSync(StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BYOK_PROVIDER)
    store.deleteSync(StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BYOK_SOURCE_PROFILE)
    store.deleteSync(StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BYOK_MODEL)
  }
}

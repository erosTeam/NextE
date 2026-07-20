import { AppStorageV2 } from '@kit.ArkUI'
import { COMIC_TRANSLATION_PROVIDER_OPENAI_API } from '../model/ComicTranslationProvider'

/** Provider selection is reactive; raw Codex OAuth tokens intentionally never enter this holder. */
@ObservedV2
export class ComicTranslationProviderSettingsState {
  @Trace provider: string = COMIC_TRANSLATION_PROVIDER_OPENAI_API
  @Trace apiBaseUrl: string = 'https://api.openai.com/v1'
  @Trace apiKey: string = ''
  @Trace apiModel: string = 'gpt-4o-mini'
  @Trace codexModel: string = ''
  @Trace codexConnected: boolean = false
  @Trace codexAccountId: string = ''
}

const COMIC_TRANSLATION_PROVIDER_SETTINGS_KEY: string = 'v2_comicTranslationProviderSettings'

export function connectComicTranslationProviderSettings(): ComicTranslationProviderSettingsState {
  return AppStorageV2.connect(
    ComicTranslationProviderSettingsState,
    COMIC_TRANSLATION_PROVIDER_SETTINGS_KEY,
    () => new ComicTranslationProviderSettingsState(),
  )!
}

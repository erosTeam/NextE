import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  COMMENT_TRANSLATION_DISPLAY_BILINGUAL,
  COMMENT_TRANSLATION_DISPLAY_REPLACE,
  connectCommentTranslationSettings,
} from '../state/CommentTranslationSettingsState'

export class CommentTranslationSettingsSnapshot {
  enabled: boolean = false
  autoTranslate: boolean = false
  displayMode: string = COMMENT_TRANSLATION_DISPLAY_REPLACE
  useGoogleOnly: boolean = false
  apiUrl: string = ''
  apiKey: string = ''
  model: string = ''
}

/** Preferences-backed comment translation settings. API key is sensitive: never log it or export it. */
export class CommentTranslationSettings {
  static normalizeDisplayMode(mode: string): string {
    return mode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL
      ? COMMENT_TRANSLATION_DISPLAY_BILINGUAL
      : COMMENT_TRANSLATION_DISPLAY_REPLACE
  }

  static apply(snapshot: CommentTranslationSettingsSnapshot): void {
    const state = connectCommentTranslationSettings()
    state.enabled = snapshot.enabled
    state.autoTranslate = snapshot.autoTranslate
    state.displayMode = CommentTranslationSettings.normalizeDisplayMode(snapshot.displayMode)
    state.useGoogleOnly = snapshot.useGoogleOnly
    state.apiUrl = snapshot.apiUrl
    state.apiKey = snapshot.apiKey
    state.model = snapshot.model
  }

  static current(): CommentTranslationSettingsSnapshot {
    const state = connectCommentTranslationSettings()
    const snapshot = new CommentTranslationSettingsSnapshot()
    snapshot.enabled = state.enabled
    snapshot.autoTranslate = state.autoTranslate
    snapshot.displayMode = CommentTranslationSettings.normalizeDisplayMode(state.displayMode)
    snapshot.useGoogleOnly = state.useGoogleOnly
    snapshot.apiUrl = state.apiUrl
    snapshot.apiKey = state.apiKey
    snapshot.model = state.model
    return snapshot
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const snapshot = new CommentTranslationSettingsSnapshot()
      snapshot.enabled = store.getSync(StorageKeys.COMMENT_TRANSLATION_ENABLED, false) as boolean
      snapshot.autoTranslate = store.getSync(StorageKeys.COMMENT_TRANSLATION_AUTO, false) as boolean
      snapshot.displayMode = store.getSync(
        StorageKeys.COMMENT_TRANSLATION_DISPLAY_MODE,
        COMMENT_TRANSLATION_DISPLAY_REPLACE,
      ) as string
      snapshot.useGoogleOnly = store.getSync(StorageKeys.COMMENT_TRANSLATION_GOOGLE_ONLY, false) as boolean
      snapshot.apiUrl = store.getSync(StorageKeys.COMMENT_TRANSLATION_API_URL, '') as string
      snapshot.apiKey = store.getSync(StorageKeys.COMMENT_TRANSLATION_API_KEY, '') as string
      snapshot.model = store.getSync(StorageKeys.COMMENT_TRANSLATION_MODEL, '') as string
      CommentTranslationSettings.apply(snapshot)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'comment_translation_restore_failed', (error as Error).message)
      CommentTranslationSettings.apply(new CommentTranslationSettingsSnapshot())
    }
  }

  static async save(context: common.UIAbilityContext, snapshot: CommentTranslationSettingsSnapshot): Promise<void> {
    snapshot.displayMode = CommentTranslationSettings.normalizeDisplayMode(snapshot.displayMode)
    CommentTranslationSettings.apply(snapshot)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.COMMENT_TRANSLATION_ENABLED, snapshot.enabled)
      store.putSync(StorageKeys.COMMENT_TRANSLATION_AUTO, snapshot.autoTranslate)
      store.putSync(StorageKeys.COMMENT_TRANSLATION_DISPLAY_MODE, snapshot.displayMode)
      store.putSync(StorageKeys.COMMENT_TRANSLATION_GOOGLE_ONLY, snapshot.useGoogleOnly)
      store.putSync(StorageKeys.COMMENT_TRANSLATION_API_URL, snapshot.apiUrl)
      store.putSync(StorageKeys.COMMENT_TRANSLATION_API_KEY, snapshot.apiKey)
      store.putSync(StorageKeys.COMMENT_TRANSLATION_MODEL, snapshot.model)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'comment_translation_save_failed', (error as Error).message)
    }
  }
}

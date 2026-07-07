import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { TagTranslationService, TagTranslationStatus } from '../services/TagTranslationService'
import {
  TAG_INTRO_IMAGE_DISABLE,
  TAG_INTRO_IMAGE_NON_H,
  TAG_INTRO_IMAGE_R18,
  TAG_INTRO_IMAGE_R18G,
  connectTagTranslationSettings,
  TAG_TRANSLATION_UPDATE_EVERY_START,
  TAG_TRANSLATION_UPDATE_MANUAL,
  TagTranslationSettingsState,
} from '../state/TagTranslationSettingsState'

const AUTO_UPDATE_DELAY_MS: number = 10000

export class TagTranslationSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const state: TagTranslationSettingsState = connectTagTranslationSettings()
      state.enabled = store.getSync(StorageKeys.TAG_TRANSLATION_ENABLED, false) as boolean
      state.useCdn = store.getSync(StorageKeys.TAG_TRANSLATION_USE_CDN, false) as boolean
      state.updateMode = TagTranslationSettings.normalizeMode(
        store.getSync(StorageKeys.TAG_TRANSLATION_UPDATE_MODE, TAG_TRANSLATION_UPDATE_MANUAL) as string,
      )
      state.introImageLevel = TagTranslationSettings.normalizeIntroImageLevel(
        store.getSync(StorageKeys.TAG_TRANSLATION_INTRO_IMAGE_LEVEL, TAG_INTRO_IMAGE_NON_H) as string,
      )
      await TagTranslationSettings.refreshStatus(context)
      TagTranslationSettings.scheduleStartupUpdate(context)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'tagtranslation_restore_failed', (error as Error).message)
    }
  }

  static async setEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectTagTranslationSettings().enabled = enabled
    await TagTranslationSettings.saveBoolean(context, StorageKeys.TAG_TRANSLATION_ENABLED, enabled)
  }

  static async setUseCdn(context: common.UIAbilityContext, useCdn: boolean): Promise<void> {
    connectTagTranslationSettings().useCdn = useCdn
    await TagTranslationSettings.saveBoolean(context, StorageKeys.TAG_TRANSLATION_USE_CDN, useCdn)
  }

  static async setUpdateMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = TagTranslationSettings.normalizeMode(mode)
    connectTagTranslationSettings().updateMode = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.TAG_TRANSLATION_UPDATE_MODE, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'tagtranslation_mode_save_failed', (error as Error).message)
    }
  }

  static async setIntroImageLevel(context: common.UIAbilityContext, level: string): Promise<void> {
    const normalized: string = TagTranslationSettings.normalizeIntroImageLevel(level)
    connectTagTranslationSettings().introImageLevel = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.TAG_TRANSLATION_INTRO_IMAGE_LEVEL, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'tagtranslation_intro_image_save_failed', (error as Error).message)
    }
  }

  static async refreshStatus(context: common.UIAbilityContext): Promise<void> {
    const status: TagTranslationStatus = await TagTranslationService.status(context)
    const state: TagTranslationSettingsState = connectTagTranslationSettings()
    state.version = status.version
    state.rowCount = status.rowCount
  }

  static async updateNow(context: common.UIAbilityContext, force: boolean = true): Promise<number> {
    const state: TagTranslationSettingsState = connectTagTranslationSettings()
    const count: number = await TagTranslationService.updateFromLatestRelease(context, state.useCdn, force)
    await TagTranslationSettings.refreshStatus(context)
    return count
  }

  private static scheduleStartupUpdate(context: common.UIAbilityContext): void {
    const state: TagTranslationSettingsState = connectTagTranslationSettings()
    if (!state.enabled || state.updateMode !== TAG_TRANSLATION_UPDATE_EVERY_START) {
      return
    }
    setTimeout(() => {
      TagTranslationSettings.updateNow(context, false)
        .then((count: number) => {
          DiagnosticLogger.info('tag-translation', 'startup_update_done', `${count} rows`)
        })
        .catch((error: Error) => {
          DiagnosticLogger.warn('tag-translation', 'startup_update_failed', error.message)
        })
    }, AUTO_UPDATE_DELAY_MS)
  }

  private static async saveBoolean(
    context: common.UIAbilityContext,
    key: string,
    value: boolean,
  ): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(key, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'tagtranslation_save_failed', (error as Error).message)
    }
  }

  private static normalizeMode(mode: string): string {
    return mode === TAG_TRANSLATION_UPDATE_EVERY_START
      ? TAG_TRANSLATION_UPDATE_EVERY_START
      : TAG_TRANSLATION_UPDATE_MANUAL
  }

  private static normalizeIntroImageLevel(level: string): string {
    switch (level) {
      case TAG_INTRO_IMAGE_DISABLE:
      case TAG_INTRO_IMAGE_R18:
      case TAG_INTRO_IMAGE_R18G:
        return level
      default:
        return TAG_INTRO_IMAGE_NON_H
    }
  }
}

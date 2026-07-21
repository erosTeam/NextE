import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { MangaTranslatorUiSidecarConfig } from '../services/MangaTranslatorUiSidecarBackend'

export class MangaRenderingServiceSettingsSnapshot {
  baseUrl: string = ''

  configured(): boolean {
    return this.baseUrl.length > 0
  }
}

/** Persists non-secret manga rendering service configuration. */
export class MangaRenderingServiceSettings {
  static async load(
    context: common.UIAbilityContext,
  ): Promise<MangaRenderingServiceSettingsSnapshot> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const snapshot: MangaRenderingServiceSettingsSnapshot =
      new MangaRenderingServiceSettingsSnapshot()
    snapshot.baseUrl = MangaRenderingServiceSettings.normalizeBaseUrl(
      store.getSync(StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_URL, '') as string,
    )
    return snapshot
  }

  static async save(
    context: common.UIAbilityContext,
    snapshot: MangaRenderingServiceSettingsSnapshot,
  ): Promise<void> {
    const baseUrl: string = MangaRenderingServiceSettings.normalizeBaseUrl(snapshot.baseUrl)
    if (baseUrl.length > 0) {
      const config: MangaTranslatorUiSidecarConfig = new MangaTranslatorUiSidecarConfig()
      config.baseUrl = baseUrl
      config.validatedBaseUrl()
    }
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    if (baseUrl.length === 0) {
      store.deleteSync(StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_URL)
    } else {
      store.putSync(StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_URL, baseUrl)
    }
    store.flushSync()
  }

  private static normalizeBaseUrl(value: string): string {
    let output: string = typeof value === 'string' ? value.trim() : ''
    while (output.endsWith('/')) {
      output = output.substring(0, output.length - 1)
    }
    return output
  }
}

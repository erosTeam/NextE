import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { MangaTranslatorUiSidecarConfig } from '../services/MangaTranslatorUiSidecarBackend'
import {
  MANGA_TRANSLATOR_UI_DETECTION_BALANCED,
  MANGA_TRANSLATOR_UI_DETECTION_HIGH_RECALL,
  MANGA_TRANSLATOR_UI_INPAINTER_FAST,
  MANGA_TRANSLATOR_UI_INPAINTER_QUALITY,
  MangaTranslatorUiSidecarProfileCatalog,
} from '../services/MangaTranslatorUiSidecarProtocol'

export class MangaRenderingServiceSettingsSnapshot {
  baseUrl: string = ''
  detectionProfile: string = MANGA_TRANSLATOR_UI_DETECTION_HIGH_RECALL
  inpaintingProfile: string = MANGA_TRANSLATOR_UI_INPAINTER_QUALITY

  configured(): boolean {
    return this.baseUrl.length > 0
  }

  copy(): MangaRenderingServiceSettingsSnapshot {
    const value: MangaRenderingServiceSettingsSnapshot =
      new MangaRenderingServiceSettingsSnapshot()
    value.baseUrl = this.baseUrl
    value.detectionProfile = this.detectionProfile
    value.inpaintingProfile = this.inpaintingProfile
    return value
  }

  assertValid(): void {
    MangaTranslatorUiSidecarProfileCatalog.assertOptions(
      this.detectionProfile,
      this.inpaintingProfile,
    )
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
    snapshot.detectionProfile = store.getSync(
      StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_DETECTION,
      MANGA_TRANSLATOR_UI_DETECTION_HIGH_RECALL,
    ) as string
    snapshot.inpaintingProfile = store.getSync(
      StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_INPAINTER,
      MANGA_TRANSLATOR_UI_INPAINTER_QUALITY,
    ) as string
    if (snapshot.detectionProfile !== MANGA_TRANSLATOR_UI_DETECTION_HIGH_RECALL &&
      snapshot.detectionProfile !== MANGA_TRANSLATOR_UI_DETECTION_BALANCED) {
      snapshot.detectionProfile = MANGA_TRANSLATOR_UI_DETECTION_HIGH_RECALL
    }
    if (snapshot.inpaintingProfile !== MANGA_TRANSLATOR_UI_INPAINTER_QUALITY &&
      snapshot.inpaintingProfile !== MANGA_TRANSLATOR_UI_INPAINTER_FAST) {
      snapshot.inpaintingProfile = MANGA_TRANSLATOR_UI_INPAINTER_QUALITY
    }
    return snapshot
  }

  static async save(
    context: common.UIAbilityContext,
    snapshot: MangaRenderingServiceSettingsSnapshot,
  ): Promise<void> {
    snapshot.assertValid()
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
    store.putSync(
      StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_DETECTION,
      snapshot.detectionProfile,
    )
    store.putSync(
      StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_INPAINTER,
      snapshot.inpaintingProfile,
    )
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

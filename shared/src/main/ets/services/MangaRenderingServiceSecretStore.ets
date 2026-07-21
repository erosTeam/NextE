import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'

const MAX_RENDER_SERVICE_CREDENTIAL_CHARS: number = 8192

/** Stores the optional sidecar Authorization value separately from ordinary settings. */
export class MangaRenderingServiceSecretStore {
  static async read(context: common.UIAbilityContext): Promise<string> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    return MangaRenderingServiceSecretStore.validate(
      store.getSync(StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_CREDENTIAL, '') as string,
    )
  }

  static async save(context: common.UIAbilityContext, value: string): Promise<void> {
    const credential: string = MangaRenderingServiceSecretStore.validate(value)
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    if (credential.length === 0) {
      store.deleteSync(StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_CREDENTIAL)
    } else {
      store.putSync(StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_CREDENTIAL, credential)
    }
    store.flushSync()
  }

  private static validate(value: string): string {
    if (typeof value !== 'string' || value.length > MAX_RENDER_SERVICE_CREDENTIAL_CHARS ||
      /[\r\n]/.test(value)) {
      throw new Error('Manga rendering service credential is invalid')
    }
    return value
  }
}

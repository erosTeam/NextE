import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'

const RENDER_SERVICE_CREDENTIAL_VERSION: number = 1
const MAX_RENDER_SERVICE_SECRET_CHARS: number = 8192
const MIN_RENDER_SERVICE_USERNAME_CHARS: number = 2
const MAX_RENDER_SERVICE_USERNAME_CHARS: number = 50
const MIN_RENDER_SERVICE_PASSWORD_CHARS: number = 6
const MAX_RENDER_SERVICE_PASSWORD_CHARS: number = 2048

class StoredMangaRenderingServiceCredential {
  version: number = RENDER_SERVICE_CREDENTIAL_VERSION
  username: string = ''
  password: string = ''
}

/** Account credentials replace expiring manual tokens; legacy tokens remain readable for migration. */
export class MangaRenderingServiceCredential {
  username: string = ''
  password: string = ''
  legacySessionToken: string = ''

  hasAccount(): boolean {
    return this.username.length > 0 && this.password.length > 0
  }

  hasLegacySession(): boolean {
    return this.legacySessionToken.length > 0
  }

  configured(): boolean {
    return this.hasAccount() || this.hasLegacySession()
  }

  copy(): MangaRenderingServiceCredential {
    const output: MangaRenderingServiceCredential = new MangaRenderingServiceCredential()
    output.username = this.username
    output.password = this.password
    output.legacySessionToken = this.legacySessionToken
    return output
  }

  static account(username: string, password: string): MangaRenderingServiceCredential {
    const output: MangaRenderingServiceCredential = new MangaRenderingServiceCredential()
    output.username = username.trim()
    output.password = password
    MangaRenderingServiceCredential.validate(output)
    return output
  }

  static parseStored(rawValue: string): MangaRenderingServiceCredential {
    const raw: string = MangaRenderingServiceCredential.validateStoredString(rawValue)
    const output: MangaRenderingServiceCredential = new MangaRenderingServiceCredential()
    if (raw.length === 0) {
      return output
    }
    if (!raw.startsWith('{')) {
      output.legacySessionToken = raw
      MangaRenderingServiceCredential.validate(output)
      return output
    }
    let stored: StoredMangaRenderingServiceCredential
    try {
      stored = JSON.parse(raw) as StoredMangaRenderingServiceCredential
    } catch (_error) {
      throw new Error('Manga rendering service credential is invalid')
    }
    if (stored === null || typeof stored !== 'object' ||
      stored.version !== RENDER_SERVICE_CREDENTIAL_VERSION ||
      typeof stored.username !== 'string' || typeof stored.password !== 'string') {
      throw new Error('Manga rendering service credential is invalid')
    }
    output.username = stored.username
    output.password = stored.password
    MangaRenderingServiceCredential.validate(output)
    return output
  }

  static serialize(value: MangaRenderingServiceCredential): string {
    MangaRenderingServiceCredential.validate(value)
    if (!value.configured()) {
      return ''
    }
    if (value.hasLegacySession()) {
      return value.legacySessionToken
    }
    const stored: StoredMangaRenderingServiceCredential =
      new StoredMangaRenderingServiceCredential()
    stored.username = value.username
    stored.password = value.password
    const output: string = JSON.stringify(stored)
    MangaRenderingServiceCredential.validateStoredString(output)
    return output
  }

  private static validate(value: MangaRenderingServiceCredential): void {
    const hasUsername: boolean = value.username.length > 0
    const hasPassword: boolean = value.password.length > 0
    const hasLegacy: boolean = value.legacySessionToken.length > 0
    if (hasLegacy && (hasUsername || hasPassword)) {
      throw new Error('Manga rendering service credential is invalid')
    }
    if (hasUsername !== hasPassword) {
      throw new Error('Manga rendering service account is incomplete')
    }
    if (hasUsername && (value.username !== value.username.trim() ||
      value.username.length < MIN_RENDER_SERVICE_USERNAME_CHARS ||
      value.username.length > MAX_RENDER_SERVICE_USERNAME_CHARS ||
      /[\r\n\t]/.test(value.username) || value.username.includes('\u0000') ||
      value.password.length < MIN_RENDER_SERVICE_PASSWORD_CHARS ||
      value.password.length > MAX_RENDER_SERVICE_PASSWORD_CHARS ||
      value.password.includes('\u0000'))) {
      throw new Error('Manga rendering service account is invalid')
    }
    if (hasLegacy && (value.legacySessionToken.length > MAX_RENDER_SERVICE_SECRET_CHARS ||
      /[\r\n]/.test(value.legacySessionToken) ||
      value.legacySessionToken.includes('\u0000'))) {
      throw new Error('Manga rendering service credential is invalid')
    }
  }

  private static validateStoredString(value: string): string {
    if (typeof value !== 'string' || value.length > MAX_RENDER_SERVICE_SECRET_CHARS ||
      /[\r\n]/.test(value) || value.includes('\u0000')) {
      throw new Error('Manga rendering service credential is invalid')
    }
    return value
  }
}

/** Stores sidecar account credentials separately from ordinary settings. */
export class MangaRenderingServiceSecretStore {
  static async read(
    context: common.UIAbilityContext,
  ): Promise<MangaRenderingServiceCredential> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    return MangaRenderingServiceCredential.parseStored(
      store.getSync(StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_CREDENTIAL, '') as string,
    )
  }

  static async save(
    context: common.UIAbilityContext,
    value: MangaRenderingServiceCredential,
  ): Promise<void> {
    const credential: string = MangaRenderingServiceCredential.serialize(value)
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
}

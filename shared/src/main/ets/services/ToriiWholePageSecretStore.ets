import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'

const TORII_CREDENTIAL_VERSION: number = 2
const TORII_LEGACY_CREDENTIAL_VERSION: number = 1
const MAX_TORII_CREDENTIAL_CHARS: number = 16 * 1024
const MAX_TORII_API_KEY_CHARS: number = 8192

class StoredToriiWholePageCredential {
  version: number = TORII_CREDENTIAL_VERSION
  toriiApiKey: string = ''
}

class LegacyStoredToriiWholePageCredential {
  version: number = TORII_LEGACY_CREDENTIAL_VERSION
  toriiApiKey: string = ''
  byokApiKey: string = ''
}

export class ToriiWholePageCredential {
  toriiApiKey: string = ''

  copy(): ToriiWholePageCredential {
    const value: ToriiWholePageCredential = new ToriiWholePageCredential()
    value.toriiApiKey = this.toriiApiKey
    return value
  }

  static parse(rawValue: string): ToriiWholePageCredential {
    const output: ToriiWholePageCredential = new ToriiWholePageCredential()
    if (rawValue.length === 0) {
      return output
    }
    if (rawValue.length > MAX_TORII_CREDENTIAL_CHARS || /[\r\n]/.test(rawValue)) {
      throw new Error('Torii credential is invalid')
    }
    let stored: StoredToriiWholePageCredential
    try {
      stored = JSON.parse(rawValue) as StoredToriiWholePageCredential
    } catch (_error) {
      throw new Error('Torii credential is invalid')
    }
    if (stored === null || typeof stored !== 'object' ||
      (stored.version !== TORII_CREDENTIAL_VERSION &&
        stored.version !== TORII_LEGACY_CREDENTIAL_VERSION) ||
      typeof stored.toriiApiKey !== 'string') {
      throw new Error('Torii credential is invalid')
    }
    if (stored.version === TORII_LEGACY_CREDENTIAL_VERSION) {
      const legacy: LegacyStoredToriiWholePageCredential =
        JSON.parse(rawValue) as LegacyStoredToriiWholePageCredential
      if (typeof legacy.byokApiKey !== 'string') {
        throw new Error('Torii credential is invalid')
      }
    }
    output.toriiApiKey = stored.toriiApiKey
    ToriiWholePageCredential.validate(output)
    return output
  }

  static serialize(value: ToriiWholePageCredential): string {
    ToriiWholePageCredential.validate(value)
    if (value.toriiApiKey.length === 0) {
      return ''
    }
    const stored: StoredToriiWholePageCredential = new StoredToriiWholePageCredential()
    stored.toriiApiKey = value.toriiApiKey
    const raw: string = JSON.stringify(stored)
    if (raw.length <= 0 || raw.length > MAX_TORII_CREDENTIAL_CHARS || /[\r\n]/.test(raw)) {
      throw new Error('Torii credential is invalid')
    }
    return raw
  }

  private static validate(value: ToriiWholePageCredential): void {
    ToriiWholePageCredential.validateKey(value.toriiApiKey)
  }

  private static validateKey(value: string): void {
    if (value.length > MAX_TORII_API_KEY_CHARS || value !== value.trim() ||
      /[\r\n\t]/.test(value) || value.includes('\u0000')) {
      throw new Error('Torii credential is invalid')
    }
  }
}

export class ToriiWholePageSecretStore {
  static async read(context: common.UIAbilityContext): Promise<ToriiWholePageCredential> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    return ToriiWholePageCredential.parse(
      store.getSync(StorageKeys.COMIC_TRANSLATION_TORII_CREDENTIAL, '') as string,
    )
  }

  static async save(
    context: common.UIAbilityContext,
    value: ToriiWholePageCredential,
  ): Promise<void> {
    const raw: string = ToriiWholePageCredential.serialize(value)
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    if (raw.length === 0) {
      store.deleteSync(StorageKeys.COMIC_TRANSLATION_TORII_CREDENTIAL)
    } else {
      store.putSync(StorageKeys.COMIC_TRANSLATION_TORII_CREDENTIAL, raw)
    }
    store.flushSync()
  }
}

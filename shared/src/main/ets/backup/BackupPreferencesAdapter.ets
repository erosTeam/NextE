import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { SettingsBootstrap } from '../settings/SettingsBootstrap'
import { BackupSecretDenylist } from './BackupSecretDenylist'
import { BackupSettingsValue } from './BackupTypes'

type SettingsMap = Record<string, BackupSettingsValue>

/** Complete WebDAV configuration restored only from an encrypted backup. */
export class BackupWebDavCredentialGroup {
  url: string = ''
  username: string = ''
  enabled: boolean = false
  password: string = ''
}

/**
 * Reads/writes the unified `nexte_settings` Preferences store for backup. The store is split by the
 * secret denylist: non-secret keys form the plaintext 'preferences' section; credential keys (cookie
 * bundle, saved accounts, complete WebDAV configuration, API keys) form the encrypted-only 'secrets'
 * section.
 * Runtime-only status keys never travel in either section. Restore is additive (overwrites present keys,
 * keeps absent ones) and re-applies the store into live state via SettingsBootstrap.loadAll so changes
 * take effect without a restart.
 */
export class BackupPreferencesAdapter {
  private static readonly PLAINTEXT_EXCLUDED_KEYS: string[] = [
    StorageKeys.FAVORITES_FAVCATS,
    StorageKeys.SEARCH_HISTORY,
    StorageKeys.LOCAL_FAVORITES,
    StorageKeys.VIEWED_HISTORY,
    StorageKeys.READING_PROGRESS,
    StorageKeys.DOWNLOAD_GALLERY_QUEUE,
    StorageKeys.HOME_CUSTOM_PROFILES,
    StorageKeys.HOME_CUSTOM_PROFILES_SELECTED,
    StorageKeys.LOCAL_BLOCK_RULES,
  ]

  private static readonly VOLATILE_EXCLUDED_KEYS: string[] = [
    StorageKeys.DOWNLOAD_ARCHIVE_BOT_BALANCE_GP,
    StorageKeys.DOWNLOAD_ARCHIVE_BOT_BALANCE_UPDATED_AT,
    StorageKeys.SECURITY_LAST_BACKGROUND_AT,
    StorageKeys.SYNC_LAST_RUN_AT,
    StorageKeys.SYNC_LAST_STATUS,
    StorageKeys.SYNC_LAST_DETAIL,
    StorageKeys.SYNC_HUAWEI_CLOUD_LAST_RUN_AT,
    StorageKeys.SYNC_HUAWEI_CLOUD_LAST_STATUS,
    StorageKeys.SYNC_HUAWEI_CLOUD_LAST_DETAIL,
    StorageKeys.SYNC_HUAWEI_CLOUD_LAST_CLOUD_DISABLED,
    StorageKeys.SAFE_MODE_UNLOCKED,
  ]

  // Non-secret keys → plaintext section.
  static async exportPreferences(context: common.UIAbilityContext): Promise<SettingsMap> {
    return BackupPreferencesAdapter.dump(context, false)
  }

  // Secret keys → encrypted-only section.
  static async exportSecrets(context: common.UIAbilityContext): Promise<SettingsMap> {
    return BackupPreferencesAdapter.dump(context, true)
  }

  private static async dump(
    context: common.UIAbilityContext,
    secret: boolean,
  ): Promise<SettingsMap> {
    const out: SettingsMap = {}
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const all = store.getAllSync() as Record<string, preferences.ValueType>
    const keys: string[] = Object.keys(all)
    for (let i: number = 0; i < keys.length; i++) {
      const key: string = keys[i]
      if (BackupPreferencesAdapter.isVolatileExcluded(key)) {
        continue
      }
      if (BackupSecretDenylist.isSecret(key) !== secret) {
        continue
      }
      if (!secret && BackupPreferencesAdapter.isPlaintextExcluded(key)) {
        continue
      }
      const value = all[key]
      // The store only holds string/number/boolean (composite settings are JSON strings).
      if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
        out[key] = value
      }
    }
    return out
  }

  private static isVolatileExcluded(key: string): boolean {
    return BackupPreferencesAdapter.VOLATILE_EXCLUDED_KEYS.indexOf(key) >= 0
  }

  private static isPlaintextExcluded(key: string): boolean {
    if (BackupPreferencesAdapter.PLAINTEXT_EXCLUDED_KEYS.indexOf(key) >= 0) {
      return true
    }
    // FavcatListSettings stores account-scoped cache snapshots as `favorites.favcats.<memberId>`.
    // They are the same non-portable cache as the legacy base key and must not leak into plaintext
    // backup or be re-imported across accounts.
    return key.startsWith(`${StorageKeys.FAVORITES_FAVCATS}.`)
  }

  private static acceptsKey(key: string, allowSecret: boolean): boolean {
    if (BackupPreferencesAdapter.isVolatileExcluded(key)) {
      return false
    }
    const secretKey: boolean = BackupSecretDenylist.isSecret(key)
    if (!allowSecret && secretKey) {
      return false
    }
    if (!allowSecret && BackupPreferencesAdapter.isPlaintextExcluded(key)) {
      return false
    }
    if (allowSecret && !secretKey) {
      return false
    }
    return true
  }

  // Write a backed-up map back into the store. `allowSecret=false` re-checks the denylist so a tampered
  // plaintext backup can never smuggle a credential key in; `allowSecret=true` is used only for the
  // section decrypted from the cipher container.
  static async restore(
    context: common.UIAbilityContext,
    map: SettingsMap,
    allowSecret: boolean,
  ): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const keys: string[] = Object.keys(map)
    for (let i: number = 0; i < keys.length; i++) {
      const key: string = keys[i]
      if (!BackupPreferencesAdapter.acceptsKey(key, allowSecret)) {
        continue
      }
      // Restore this provider configuration only through restoreWebDavCredentialGroup(). Old encrypted
      // envelopes split it across preferences + secrets, while plaintext files have no password at all.
      if (BackupSecretDenylist.isWebDavCredentialKey(key)) {
        continue
      }
      store.putSync(key, map[key])
    }
    store.flushSync()
  }

  /**
   * Restore WebDAV as one complete encrypted credential group. New encrypted backups place all four
   * fields in `secrets`; legacy encrypted backups put URL/username/enabled in preferences and only the
   * password in secrets. A plaintext backup, or an incomplete encrypted group, intentionally leaves the
   * target's existing provider configuration untouched.
   */
  static async restoreWebDavCredentialGroup(
    context: common.UIAbilityContext,
    plaintext: SettingsMap,
    secrets: SettingsMap,
    fromEncrypted: boolean,
  ): Promise<void> {
    const group: BackupWebDavCredentialGroup | null =
      BackupPreferencesAdapter.resolveWebDavCredentialGroup(plaintext, secrets, fromEncrypted)
    if (group === null) {
      return
    }
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.putSync(StorageKeys.SYNC_WEBDAV_URL, group.url)
    store.putSync(StorageKeys.SYNC_WEBDAV_USERNAME, group.username)
    store.putSync(StorageKeys.SYNC_WEBDAV_ENABLED, group.enabled)
    store.putSync(StorageKeys.SYNC_WEBDAV_PASSWORD, group.password)
    store.flushSync()
  }

  /** Pure resolver retained for device tests: plaintext and incomplete encrypted groups must be inert. */
  static resolveWebDavCredentialGroup(
    plaintext: SettingsMap,
    secrets: SettingsMap,
    fromEncrypted: boolean,
  ): BackupWebDavCredentialGroup | null {
    const url: BackupSettingsValue | undefined =
      BackupPreferencesAdapter.webDavCredentialValue(plaintext, secrets, StorageKeys.SYNC_WEBDAV_URL)
    const username: BackupSettingsValue | undefined =
      BackupPreferencesAdapter.webDavCredentialValue(plaintext, secrets, StorageKeys.SYNC_WEBDAV_USERNAME)
    const enabled: BackupSettingsValue | undefined =
      BackupPreferencesAdapter.webDavCredentialValue(plaintext, secrets, StorageKeys.SYNC_WEBDAV_ENABLED)
    const password: BackupSettingsValue | undefined =
      BackupPreferencesAdapter.webDavCredentialValue(plaintext, secrets, StorageKeys.SYNC_WEBDAV_PASSWORD)
    return BackupPreferencesAdapter.resolveWebDavCredentialValues(
      url,
      username,
      enabled,
      password,
      fromEncrypted,
    )
  }

  /** Pure scalar boundary for device tests; map routing stays in resolveWebDavCredentialGroup(). */
  static resolveWebDavCredentialValues(
    url: BackupSettingsValue | undefined,
    username: BackupSettingsValue | undefined,
    enabled: BackupSettingsValue | undefined,
    password: BackupSettingsValue | undefined,
    fromEncrypted: boolean,
  ): BackupWebDavCredentialGroup | null {
    if (!fromEncrypted) {
      return null
    }
    if (
      typeof url !== 'string' ||
      typeof username !== 'string' ||
      typeof enabled !== 'boolean' ||
      typeof password !== 'string'
    ) {
      return null
    }
    const group: BackupWebDavCredentialGroup = new BackupWebDavCredentialGroup()
    group.url = url
    group.username = username
    group.enabled = enabled
    group.password = password
    return group
  }

  private static webDavCredentialValue(
    plaintext: SettingsMap,
    secrets: SettingsMap,
    key: string,
  ): BackupSettingsValue | undefined {
    return secrets[key] !== undefined ? secrets[key] : plaintext[key]
  }

  static async replace(
    context: common.UIAbilityContext,
    map: SettingsMap,
    allowSecret: boolean,
  ): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const all = store.getAllSync() as Record<string, preferences.ValueType>
    const existingKeys: string[] = Object.keys(all)
    for (let i: number = 0; i < existingKeys.length; i++) {
      const key: string = existingKeys[i]
      if (BackupPreferencesAdapter.acceptsKey(key, allowSecret) && map[key] === undefined) {
        store.deleteSync(key)
      }
    }
    const keys: string[] = Object.keys(map)
    for (let i: number = 0; i < keys.length; i++) {
      const key: string = keys[i]
      if (BackupPreferencesAdapter.acceptsKey(key, allowSecret)) {
        store.putSync(key, map[key])
      }
    }
    store.flushSync()
  }

  // Re-run every *Settings.restore() so the freshly written store re-hydrates AppStorageV2/state holders
  // (theme, cookies, layout, …) immediately instead of only on next launch.
  static async reapply(context: common.UIAbilityContext): Promise<void> {
    await SettingsBootstrap.loadAll(context)
  }

  static count(map: SettingsMap): number {
    return Object.keys(map).length
  }
}

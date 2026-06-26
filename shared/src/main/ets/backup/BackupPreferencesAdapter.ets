import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { SettingsBootstrap } from '../settings/SettingsBootstrap'
import { BackupSecretDenylist } from './BackupSecretDenylist'
import { BackupSettingsValue } from './BackupTypes'

type SettingsMap = Record<string, BackupSettingsValue>

/**
 * Reads/writes the unified `nexte_settings` Preferences store for backup. The store is split by the
 * secret denylist: non-secret keys form the plaintext 'preferences' section; the secret keys (cookie
 * bundle, saved accounts, LLM API key) form the encrypted-only 'secrets' section. Restore is additive
 * (overwrites present keys, keeps absent ones) and re-applies the store into live state via
 * SettingsBootstrap.loadAll so changes take effect without a restart.
 */
export class BackupPreferencesAdapter {
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
      if (BackupSecretDenylist.isSecret(key) !== secret) {
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
      if (!allowSecret && BackupSecretDenylist.isSecret(key)) {
        continue
      }
      store.putSync(key, map[key])
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

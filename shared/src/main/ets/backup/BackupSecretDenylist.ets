import { StorageKeys } from '../constants/StorageKeys'

/**
 * Splits the single `nexte_settings` Preferences store into plaintext-safe keys and secret keys.
 *
 * The plaintext backup dumps the WHOLE store so newly added settings are captured automatically (no
 * per-field allowlist). This denylist is the single guard that keeps credential-bearing keys out of the
 * plaintext envelope; those same keys form the encrypted 'secrets' section instead. Matching is by
 * case-insensitive substring so any future credential key is excluded without editing this file.
 */
export class BackupSecretDenylist {
  // Case-insensitive markers. 'cookie' -> auth.cookieJar; 'apikey' -> commentTranslation.apiKey;
  // the rest are belt-and-suspenders for any future secret key.
  private static readonly SENSITIVE_SUBSTRINGS: string[] = [
    'cookie',
    'apikey',
    'token',
    'password',
    'secret',
    'credential',
  ]

  // Exact secret keys with no obvious substring marker (the saved-accounts credential bundle list).
  private static readonly EXACT_KEYS: string[] = [StorageKeys.AUTH_ACCOUNTS]

  /** True when the key is a secret — excluded from plaintext, included only in the encrypted section. */
  static isSecret(key: string): boolean {
    // Account profile snapshots are keyed as `auth.profile.<memberId>`. Keep the whole dynamic key
    // family in the encrypted-only section, as declared by the persistence inventory.
    if (key.startsWith(StorageKeys.USER_PROFILE_PREFIX)) {
      return true
    }
    const lower: string = key.toLowerCase()
    for (let i: number = 0; i < BackupSecretDenylist.SENSITIVE_SUBSTRINGS.length; i++) {
      if (lower.includes(BackupSecretDenylist.SENSITIVE_SUBSTRINGS[i])) {
        return true
      }
    }
    return BackupSecretDenylist.EXACT_KEYS.indexOf(key) >= 0
  }
}

import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { EhCookieStore } from '../network/EhCookieStore'
import { EhConstants } from '../constants/EhConstants'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectAuth, AuthState } from '../state/AuthState'

/**
 * Persistence for the sensitive EH auth cookie bundle. HarmonyOS has no cookie jar, so the
 * in-memory jar (EhCookieStore) is the runtime source of truth; this class mirrors it to/from
 * the Preferences store so login survives an app restart. EH's two sites (e-hentai.org /
 * exhentai.org) share one auth bundle (ipb_member_id/ipb_pass_hash + optional sk/star), plus
 * igneous which only ExHentai needs — so this is a single flat bundle, not V2Next's per-host
 * map. Serialized as a cookie-header string ("name=value; …"); only logs counts, never values.
 */
export class CookieJarSettings {
  // The cookies that constitute the persisted auth bundle (everything else is request-scoped).
  private static readonly AUTH_NAMES: string[] = [
    EhConstants.COOKIE_MEMBER_ID,
    EhConstants.COOKIE_PASS_HASH,
    EhConstants.COOKIE_IGNEOUS,
    EhConstants.COOKIE_SK,
    EhConstants.COOKIE_STAR,
  ]

  /** Pull a single cookie value out of a "name=value; name2=value2" header. '' if absent. */
  static parseCookieValue(header: string, name: string): string {
    if (header.length === 0) {
      return ''
    }
    const pairs: string[] = header.split(';')
    for (const pair of pairs) {
      const trimmed: string = pair.trim()
      const eq: number = trimmed.indexOf('=')
      if (eq <= 0) {
        continue
      }
      if (trimmed.substring(0, eq) === name) {
        return trimmed.substring(eq + 1).trim()
      }
    }
    return ''
  }

  /** Apply the recognized auth cookies from a captured WebView cookie header into the jar.
   * Returns true iff both identity cookies (member id + pass hash) are now present. */
  static applyFromHeader(header: string): boolean {
    const store: EhCookieStore = EhCookieStore.getInstance()
    for (const name of CookieJarSettings.AUTH_NAMES) {
      const value: string = CookieJarSettings.parseCookieValue(header, name)
      if (value.length > 0 && value !== 'mystery') {
        store.set(name, value)
      }
    }
    return store.isLogin()
  }

  /** Serialize the jar's auth bundle to a cookie-header string for storage. */
  private static serialize(): string {
    const store: EhCookieStore = EhCookieStore.getInstance()
    const parts: string[] = []
    for (const name of CookieJarSettings.AUTH_NAMES) {
      const value: string = store.get(name)
      if (value.length > 0) {
        parts.push(`${name}=${value}`)
      }
    }
    return parts.join('; ')
  }

  /** Persist the current jar bundle to Preferences + refresh the AuthState mirror. */
  static async save(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.COOKIE_JAR, CookieJarSettings.serialize())
      store.flushSync()
      CookieJarSettings.syncAuthState()
      DiagnosticLogger.info('auth', 'cookie_jar_saved', `login=${EhCookieStore.getInstance().isLogin()}`)
    } catch (error) {
      DiagnosticLogger.warn('auth', 'cookie_jar_save_failed', (error as Error).message)
    }
  }

  /** Restore the persisted bundle into the jar + AuthState at startup (best-effort). */
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const serialized: string = store.getSync(StorageKeys.COOKIE_JAR, '') as string
      if (serialized.length > 0) {
        CookieJarSettings.applyFromHeader(serialized)
      }
      CookieJarSettings.syncAuthState()
      DiagnosticLogger.info('auth', 'cookie_jar_restored', `login=${EhCookieStore.getInstance().isLogin()}`)
    } catch (error) {
      DiagnosticLogger.warn('auth', 'cookie_jar_restore_failed', (error as Error).message)
    }
  }

  /** Log out: clear the jar, the persisted bundle, and the AuthState mirror. */
  static async clear(context: common.UIAbilityContext): Promise<void> {
    EhCookieStore.getInstance().clear()
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.deleteSync(StorageKeys.COOKIE_JAR)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('auth', 'cookie_jar_clear_failed', (error as Error).message)
    }
    CookieJarSettings.syncAuthState()
  }

  /** Push the jar's login facts into the reactive AuthState (non-sensitive fields only). */
  static syncAuthState(): void {
    const store: EhCookieStore = EhCookieStore.getInstance()
    const auth: AuthState = connectAuth()
    auth.isLogin = store.isLogin()
    auth.hasIgneous = store.get(EhConstants.COOKIE_IGNEOUS).length > 0
    auth.memberId = store.get(EhConstants.COOKIE_MEMBER_ID)
  }
}

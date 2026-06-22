import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { EhCookieStore } from '../network/EhCookieStore'
import { EhHttpClient, EhTextResponse } from '../network/EhHttpClient'
import { EhConstants } from '../constants/EhConstants'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectAuth, AuthState } from '../state/AuthState'
import { AccountListSettings } from './AccountListSettings'

/**
 * Persistence for the sensitive EH auth cookie bundle. HarmonyOS has no cookie jar, so the
 * in-memory jar (EhCookieStore) is the runtime source of truth; this class mirrors it to/from
 * the Preferences store so login survives an app restart. EH's two sites (e-hentai.org /
 * exhentai.org) share one auth bundle (ipb_member_id/ipb_pass_hash + optional sk/star), plus
 * igneous which only ExHentai needs — so this is a single flat bundle, not V2Next's per-host
 * map. Serialized as a cookie-header string ("name=value; …"); only logs counts, never values.
 */
export class CookieJarSettings {
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

  /**
   * Apply a captured WebView cookie header (login) OR a persisted cookie string (restore) into the jar —
   * preserving the COMPLETE cookie set, not just a known auth bundle. EH gates some galleries
   * (ExHentai-only content shown as "removed or unavailable" on the e-hentai.org URL) on donor/permission
   * cookies whose names we do not enumerate; keeping only the 5 known cookies dropped them, making a
   * logged-in donor look unauthenticated and the gallery look hard-deleted. `nw` is re-forced per request,
   * and EH's `mystery` placeholder (e.g. igneous=mystery for non-donor) carries no value, so both are
   * skipped. Returns true iff both identity cookies (member id + pass hash) are present.
   */
  static applyFromHeader(header: string): boolean {
    const store: EhCookieStore = EhCookieStore.getInstance()
    const pairs: string[] = header.split(';')
    for (const pair of pairs) {
      const trimmed: string = pair.trim()
      const eq: number = trimmed.indexOf('=')
      if (eq <= 0) {
        continue
      }
      const name: string = trimmed.substring(0, eq).trim()
      const value: string = trimmed.substring(eq + 1).trim()
      if (
        name.length > 0 &&
        name !== EhConstants.COOKIE_NW &&
        value.length > 0 &&
        value !== 'mystery'
      ) {
        store.set(name, value)
      }
    }
    return store.isLogin()
  }

  /**
   * Like applyFromHeader, but CLEARS the jar first so the result is exactly the pasted account — no cookies
   * leftover from a previously-active account. Used by the cookie-import login so adding a second account
   * never inherits the previous account's igneous/sk. Returns true iff both identity cookies are present.
   */
  static replaceFromHeader(header: string): boolean {
    EhCookieStore.getInstance().clear()
    return CookieJarSettings.applyFromHeader(header)
  }

  /**
   * Capture auth cookies from a response Set-Cookie blob (HttpResponse.cookies). Regex-extracts each known
   * auth cookie by name — robust against the comma/newline-joined multi-Set-Cookie string HarmonyOS
   * returns — and skips the `mystery` igneous placeholder. Does NOT persist; the caller saves.
   */
  static applyFromSetCookie(setCookie: string): void {
    if (setCookie.length === 0) {
      return
    }
    const store: EhCookieStore = EhCookieStore.getInstance()
    const names: string[] = [
      EhConstants.COOKIE_MEMBER_ID,
      EhConstants.COOKIE_PASS_HASH,
      EhConstants.COOKIE_IGNEOUS,
      EhConstants.COOKIE_SK,
      EhConstants.COOKIE_STAR,
    ]
    // Value stops at ; , whitespace, or " — the last so this also works when fed a JSON-stringified
    // response header (HttpResponse.cookies is lossy, so the auth cookies are read from there).
    for (const name of names) {
      const match: RegExpExecArray | null = new RegExp(`${name}=([^;,\\s"]+)`).exec(setCookie)
      if (match !== null && match[1].length > 0 && match[1] !== 'mystery') {
        store.set(name, match[1])
      }
    }
  }

  /**
   * Obtain a REAL igneous (ExHentai access) the way eros_fe does (getExIgneous): GET exhentai.org/uconfig.php
   * with the identity cookies — exhentai responds with `Set-Cookie: igneous=<hash>` for accounts that have
   * EX access (and `mystery`/nothing otherwise). Capture it, persist, refresh AuthState. Returns true iff a
   * real igneous is now present (i.e. the account can use ExHentai).
   */
  static async refreshIgneous(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const resp: EhTextResponse = await EhHttpClient.getInstance().getText(
        `${EhConstants.EX_BASE_URL}/uconfig.php`,
      )
      // HarmonyOS HttpResponse.cookies drops the igneous Set-Cookie (verified: igneous is absent from
      // .cookies but present in the full response header), so capture from rawHeader, falling back to
      // .cookies. applyFromSetCookie regex-extracts each auth cookie by name, so the header JSON is fine.
      let setCookie: string = resp.rawHeader !== undefined ? resp.rawHeader : ''
      if (setCookie.length === 0 && resp.cookies !== undefined) {
        setCookie = resp.cookies
      }
      CookieJarSettings.applyFromSetCookie(setCookie)
      const igneous: string = EhCookieStore.getInstance().get(EhConstants.COOKIE_IGNEOUS)
      const unlocked: boolean = igneous.length > 0 && igneous !== 'mystery'
      DiagnosticLogger.info(
        'auth',
        'refresh_igneous',
        `status=${resp.statusCode} unlocked=${unlocked}`,
      )
      if (unlocked) {
        await CookieJarSettings.save(context)
        return true
      }
      return false
    } catch (error) {
      DiagnosticLogger.warn('auth', 'refresh_igneous_failed', (error as Error).message)
      return false
    }
  }

  /** Serialize the COMPLETE jar (every captured cookie, not just the known bundle) for storage. */
  private static serialize(): string {
    return EhCookieStore.getInstance().serializeForPersist()
  }

  /** Persist the current jar bundle to Preferences + refresh the AuthState mirror. */
  static async save(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.COOKIE_JAR, CookieJarSettings.serialize())
      store.flushSync()
      CookieJarSettings.syncAuthState()
      await AccountListSettings.recordActive(context)
      DiagnosticLogger.info(
        'auth',
        'cookie_jar_saved',
        `login=${EhCookieStore.getInstance().isLogin()}`,
      )
    } catch (error) {
      DiagnosticLogger.warn('auth', 'cookie_jar_save_failed', (error as Error).message)
    }
  }

  /** Restore the persisted bundle into the jar + AuthState at startup (best-effort). */
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const serialized: string = store.getSync(StorageKeys.COOKIE_JAR, '') as string
      if (serialized.length > 0) {
        CookieJarSettings.applyFromHeader(serialized)
      }
      CookieJarSettings.syncAuthState()
      await AccountListSettings.load(context)
      await AccountListSettings.recordActive(context)
      DiagnosticLogger.info(
        'auth',
        'cookie_jar_restored',
        `login=${EhCookieStore.getInstance().isLogin()}`,
      )
    } catch (error) {
      DiagnosticLogger.warn('auth', 'cookie_jar_restore_failed', (error as Error).message)
    }
  }

  /** Log out: clear the jar, the persisted bundle, and the AuthState mirror. */
  static async clear(context: common.UIAbilityContext): Promise<void> {
    EhCookieStore.getInstance().clear()
    // Refresh visible account UI immediately; persistence deletion may await Preferences I/O.
    CookieJarSettings.syncAuthState()
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.deleteSync(StorageKeys.COOKIE_JAR)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('auth', 'cookie_jar_clear_failed', (error as Error).message)
    }
    CookieJarSettings.syncAuthState()
    await AccountListSettings.load(context)
    DiagnosticLogger.info('auth', 'cookie_jar_cleared', 'login=false')
  }

  /** Switch the active account to a saved one: load its bundle into the jar, persist, refresh. */
  static async switchTo(context: common.UIAbilityContext, memberId: string): Promise<void> {
    const bundle: string = await AccountListSettings.bundleOf(context, memberId)
    if (bundle.length === 0) {
      return
    }
    EhCookieStore.getInstance().clear()
    CookieJarSettings.applyFromHeader(bundle)
    await CookieJarSettings.save(context)
  }

  /** Remove a saved account; if it was the active one, switch to another saved account or fully log out. */
  static async removeAccount(context: common.UIAbilityContext, memberId: string): Promise<void> {
    const wasActive: boolean =
      EhCookieStore.getInstance().get(EhConstants.COOKIE_MEMBER_ID) === memberId
    const remaining: string[] = await AccountListSettings.remove(context, memberId)
    if (wasActive) {
      if (remaining.length > 0) {
        await CookieJarSettings.switchTo(context, remaining[0])
      } else {
        await CookieJarSettings.clear(context)
      }
    }
  }

  /**
   * In-app forums password login (eros_fe userLogin). POSTs the credentials to the forums login and reads
   * the response Set-Cookie for the identity cookies. NOTE: forums.e-hentai.org is often Cloudflare-gated,
   * so this can 403 on some networks — the WebView login is the reliable path; this is the direct form per
   * request. Returns true iff the response carried ipb_member_id + ipb_pass_hash (a clean login replaces
   * the active account). The current account is left untouched on failure.
   */
  static async passwordLogin(
    context: common.UIAbilityContext,
    username: string,
    password: string,
  ): Promise<boolean> {
    const body: string =
      `CookieDate=365&UserName=${encodeURIComponent(username)}` +
      `&PassWord=${encodeURIComponent(password)}&temporary_https=off&submit=Log+me+in`
    try {
      const resp: EhTextResponse = await EhHttpClient.getInstance().postLogin(
        EhConstants.FORUMS_LOGIN_URL,
        body,
        'https://forums.e-hentai.org/index.php?act=Login&CODE=00',
      )
      const setCookie: string = resp.rawHeader !== undefined ? resp.rawHeader : ''
      const member: RegExpExecArray | null = new RegExp(
        `${EhConstants.COOKIE_MEMBER_ID}=([0-9]+)`,
      ).exec(setCookie)
      const hash: RegExpExecArray | null = new RegExp(
        `${EhConstants.COOKIE_PASS_HASH}=([0-9a-f]+)`,
      ).exec(setCookie)
      const ok: boolean = member !== null && hash !== null
      DiagnosticLogger.info('auth', 'password_login', `status=${resp.statusCode} ok=${ok}`)
      if (ok) {
        EhCookieStore.getInstance().clear()
        CookieJarSettings.applyFromSetCookie(setCookie)
        await CookieJarSettings.save(context)
        return true
      }
      return false
    } catch (error) {
      DiagnosticLogger.warn('auth', 'password_login_failed', (error as Error).message)
      return false
    }
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

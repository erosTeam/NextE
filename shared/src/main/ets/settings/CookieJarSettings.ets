import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { webview } from '@kit.ArkWeb'
import { EhCookieStore } from '../network/EhCookieStore'
import { EhHttpClient, EhTextResponse } from '../network/EhHttpClient'
import { EhConstants } from '../constants/EhConstants'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectAuth, AuthState } from '../state/AuthState'
import { AccountListSettings } from './AccountListSettings'
import { UserProfileService } from '../services/UserProfileService'
import { CookieJarEntry } from '../model/CookieJarEntry'

/**
 * Persistence for the sensitive EH auth cookie bundle. HarmonyOS has no cookie jar, so the
 * in-memory jar (EhCookieStore) is the runtime source of truth; this class mirrors it to/from
 * the Preferences store so login survives an app restart. EH's two sites (e-hentai.org /
 * exhentai.org) share one auth bundle (ipb_member_id/ipb_pass_hash + optional sk/star), plus
 * igneous which only ExHentai needs — so this is a single flat bundle, not V2Next's per-host
 * map. Serialized as a cookie-header string ("name=value; …"); only logs counts, never values.
 */
export class CookieJarSettings {
  private static authCookieNames(): string[] {
    return [
      EhConstants.COOKIE_MEMBER_ID,
      EhConstants.COOKIE_PASS_HASH,
      EhConstants.COOKIE_IGNEOUS,
      EhConstants.COOKIE_SK,
      EhConstants.COOKIE_STAR,
      'ipb_session_id',
    ]
  }

  /** Pull a single cookie value out of any supported pasted cookie format. '' if absent. */
  static parseCookieValue(header: string, name: string): string {
    const entries: CookieJarEntry[] = CookieJarSettings.parseCookieEntries(header)
    for (let i: number = 0; i < entries.length; i++) {
      if (entries[i].name === name) {
        return entries[i].value
      }
    }
    return ''
  }

  /** User-facing export / import canonical form. Values are sensitive. */
  static formatEntries(entries: CookieJarEntry[]): string {
    const parts: string[] = []
    for (let i: number = 0; i < entries.length; i++) {
      if (entries[i].name.length > 0 && entries[i].value.length > 0) {
        parts.push(`${entries[i].name}=${entries[i].value}`)
      }
    }
    return parts.join('; ')
  }

  /**
   * Parse common pasted cookie sources into complete cookie entries:
   *   - Cookie header: a=b; c=d
   *   - One cookie per line, with optional Cookie: / Set-Cookie: prefixes
   *   - Browser-export JSON arrays containing { name, value }
   */
  static parseCookieEntries(raw: string): CookieJarEntry[] {
    const text: string = raw.trim()
    if (text.length === 0) {
      return []
    }
    const jsonEntries: CookieJarEntry[] = CookieJarSettings.parseJsonCookieEntries(text)
    if (jsonEntries.length > 0) {
      return jsonEntries
    }
    const entries: CookieJarEntry[] = []
    const seen: Map<string, boolean> = new Map<string, boolean>()
    const lines: string[] = text.replace(/\r/g, '\n').split('\n')
    for (let i: number = 0; i < lines.length; i++) {
      CookieJarSettings.parseCookieLine(lines[i], entries, seen)
    }
    return entries
  }

  private static parseJsonCookieEntries(text: string): CookieJarEntry[] {
    if (!text.startsWith('[') && !text.startsWith('{')) {
      return []
    }
    try {
      const root: Object = JSON.parse(text) as Object
      const entries: CookieJarEntry[] = []
      const seen: Map<string, boolean> = new Map<string, boolean>()
      if (Array.isArray(root)) {
        CookieJarSettings.parseJsonCookieArray(root, entries, seen)
      } else if (root !== null && typeof root === 'object') {
        const rec = root as Record<string, Object>
        const cookies: Object | undefined = rec.cookies
        if (cookies !== undefined && Array.isArray(cookies)) {
          CookieJarSettings.parseJsonCookieArray(cookies, entries, seen)
        }
      }
      return entries
    } catch (_error) {
      return []
    }
  }

  private static parseJsonCookieArray(
    rawItems: Object[],
    entries: CookieJarEntry[],
    seen: Map<string, boolean>,
  ): void {
    for (let i: number = 0; i < rawItems.length; i++) {
      const rawItem: Object = rawItems[i]
      if (rawItem === null || typeof rawItem !== 'object' || Array.isArray(rawItem)) {
        continue
      }
      const item = rawItem as Record<string, Object>
      const rawName: Object | undefined = item.name
      const rawValue: Object | undefined = item.value
      if (rawName === undefined || rawValue === undefined) {
        continue
      }
      CookieJarSettings.appendCookieEntry(entries, seen, `${rawName}`, `${rawValue}`)
    }
  }

  private static parseCookieLine(
    rawLine: string,
    entries: CookieJarEntry[],
    seen: Map<string, boolean>,
  ): void {
    let line: string = rawLine.trim()
    if (line.length === 0) {
      return
    }
    const lower: string = line.toLowerCase()
    if (lower.startsWith('cookie:')) {
      line = line.substring('cookie:'.length).trim()
      CookieJarSettings.parseCookieFragments(line.split(';'), entries, seen, false)
      return
    }
    if (lower.startsWith('set-cookie:')) {
      line = line.substring('set-cookie:'.length).trim()
      const parts: string[] = line.split(';')
      CookieJarSettings.parseCookieFragments([parts.length > 0 ? parts[0] : line], entries, seen, true)
      return
    }
    if (line.indexOf(';') >= 0) {
      CookieJarSettings.parseCookieFragments(line.split(';'), entries, seen, false)
      return
    }
    CookieJarSettings.parseCookieFragments([line], entries, seen, false)
  }

  private static parseCookieFragments(
    fragments: string[],
    entries: CookieJarEntry[],
    seen: Map<string, boolean>,
    setCookieLine: boolean,
  ): void {
    for (let i: number = 0; i < fragments.length; i++) {
      const fragment: string = fragments[i].trim()
      if (fragment.length === 0) {
        continue
      }
      if (!setCookieLine && CookieJarSettings.isCookieAttribute(fragment)) {
        continue
      }
      const eq: number = fragment.indexOf('=')
      if (eq <= 0) {
        continue
      }
      CookieJarSettings.appendCookieEntry(
        entries,
        seen,
        fragment.substring(0, eq).trim(),
        fragment.substring(eq + 1).trim(),
      )
    }
  }

  private static isCookieAttribute(fragment: string): boolean {
    const eq: number = fragment.indexOf('=')
    const name: string = (eq >= 0 ? fragment.substring(0, eq) : fragment).trim().toLowerCase()
    return (
      name === 'path' ||
      name === 'domain' ||
      name === 'expires' ||
      name === 'max-age' ||
      name === 'secure' ||
      name === 'httponly' ||
      name === 'samesite'
    )
  }

  private static appendCookieEntry(
    entries: CookieJarEntry[],
    seen: Map<string, boolean>,
    name: string,
    value: string,
  ): void {
    if (
      name.length <= 0 ||
      value.length <= 0 ||
      name === EhConstants.COOKIE_NW ||
      value === 'mystery' ||
      seen.get(name) === true
    ) {
      return
    }
    entries.push(new CookieJarEntry(name, value))
    seen.set(name, true)
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
    const entries: CookieJarEntry[] = CookieJarSettings.parseCookieEntries(header)
    for (let i: number = 0; i < entries.length; i++) {
      store.set(entries[i].name, entries[i].value)
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
   * Expire EH identity cookies from ArkWeb's own cookie jar. App logout must clear this too; otherwise
   * WebView can still show the forums as logged in even after the native request jar is empty.
   * Cloudflare cookies are deliberately preserved so the next login does not restart CF from zero.
   */
  static expireWebIdentityCookies(): void {
    const targets: string[][] = [
      [EhConstants.EH_BASE_URL, '; Domain=.e-hentai.org'],
      [EhConstants.EH_BASE_URL, ''],
      [EhConstants.FORUMS_BASE_URL, '; Domain=.e-hentai.org'],
      [EhConstants.FORUMS_BASE_URL, ''],
      [EhConstants.EX_BASE_URL, '; Domain=.exhentai.org'],
      [EhConstants.EX_BASE_URL, ''],
    ]
    for (const name of CookieJarSettings.authCookieNames()) {
      for (const target of targets) {
        try {
          webview.WebCookieManager.configCookieSync(
            target[0],
            `${name}=; Path=/${target[1]}; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT`,
            false,
            true,
          )
        } catch (error) {
          DiagnosticLogger.warn('auth', 'web_identity_cookie_expire_failed', (error as Error).message)
        }
      }
    }
    try {
      webview.WebCookieManager.saveCookieSync()
    } catch (_error) {
      webview.WebCookieManager.saveCookieAsync()
    }
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

  static async mergeFromWebCookieManager(context: common.UIAbilityContext): Promise<boolean> {
    try {
      try {
        webview.WebCookieManager.saveCookieSync()
      } catch (_error) {
        await webview.WebCookieManager.saveCookieAsync()
      }
      const ehCookie: string = await webview.WebCookieManager.fetchCookie(EhConstants.EH_BASE_URL)
      const exCookie: string = await webview.WebCookieManager.fetchCookie(EhConstants.EX_BASE_URL)
      const forumCookie: string = await webview.WebCookieManager.fetchCookie(
        EhConstants.FORUMS_BASE_URL,
      )
      const header: string = `${ehCookie}; ${exCookie}; ${forumCookie}`
      const activeMember: string = EhCookieStore.getInstance().get(EhConstants.COOKIE_MEMBER_ID)
      const webMember: string = CookieJarSettings.parseCookieValue(header, EhConstants.COOKIE_MEMBER_ID)
      if (webMember.length > 0 && activeMember.length > 0 && webMember !== activeMember) {
        DiagnosticLogger.warn(
          'auth',
          'web_cookie_merge_skipped',
          `active=${activeMember} web=${webMember}`,
        )
        return false
      }
      CookieJarSettings.applyFromHeader(header)
      await CookieJarSettings.save(context)
      DiagnosticLogger.info(
        'auth',
        'web_cookie_merged',
        `names=${EhCookieStore.getInstance().nameSummary()}`,
      )
      return true
    } catch (error) {
      DiagnosticLogger.warn('auth', 'web_cookie_merge_failed', (error as Error).message)
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
      await UserProfileService.restoreActive(context)
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
    CookieJarSettings.expireWebIdentityCookies()
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
    CookieJarSettings.expireWebIdentityCookies()
    CookieJarSettings.applyFromHeader(bundle)
    await CookieJarSettings.save(context)
    await UserProfileService.restoreActive(context)
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
    const previousMemberId: string = auth.memberId
    const nextMemberId: string = store.get(EhConstants.COOKIE_MEMBER_ID)
    auth.isLogin = store.isLogin()
    auth.hasIgneous = store.get(EhConstants.COOKIE_IGNEOUS).length > 0
    auth.memberId = nextMemberId
    if (!auth.isLogin || previousMemberId !== nextMemberId) {
      auth.nickName = ''
      auth.avatarUrl = ''
    }
  }
}

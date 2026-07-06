import { EhConstants } from '../constants/EhConstants'
import { CookieJarEntry } from '../model/CookieJarEntry'

/**
 * Manual cookie jar — HarmonyOS has no built-in CookieJar for @ohos.net.http, so we keep
 * our own. Every request forces `nw=1` to skip EH's content-warning interstitial. The
 * auth bundle (ipb_member_id/ipb_pass_hash/igneous/sk) is injected once login lands (M3);
 * M1 runs anonymous on the table site. `pass_hash` is sensitive — never log it raw.
 */
export class EhCookieStore {
  private static instance: EhCookieStore
  private cookies: Map<string, string> = new Map<string, string>()

  static getInstance(): EhCookieStore {
    if (!EhCookieStore.instance) {
      EhCookieStore.instance = new EhCookieStore()
    }
    return EhCookieStore.instance
  }

  set(name: string, value: string): void {
    this.cookies.set(name, value)
  }

  get(name: string): string {
    const v: string | undefined = this.cookies.get(name)
    return v !== undefined ? v : ''
  }

  clear(): void {
    this.cookies.clear()
  }

  /** Logged in once both identity cookies are present. */
  isLogin(): boolean {
    return (
      this.get(EhConstants.COOKIE_MEMBER_ID).length > 0 &&
      this.get(EhConstants.COOKIE_PASS_HASH).length > 0
    )
  }

  /** Cookie header for a request; always forces nw=1. */
  header(): string {
    const parts: string[] = ['nw=1']
    this.cookies.forEach((value: string, name: string) => {
      if (name !== EhConstants.COOKIE_NW && value.length > 0) {
        parts.push(`${name}=${value}`)
      }
    })
    return parts.join('; ')
  }

  /** Diagnostic only: cookie names without values. Never include this in user-facing exports as secrets. */
  nameSummary(): string {
    const names: string[] = []
    this.cookies.forEach((value: string, name: string) => {
      if (name !== EhConstants.COOKIE_NW && value.length > 0) {
        names.push(name)
      }
    })
    return names.join(',')
  }

  /** Full cookie entries for user-requested viewing/export only. Values are sensitive. */
  entries(): CookieJarEntry[] {
    const entries: CookieJarEntry[] = []
    this.cookies.forEach((value: string, name: string) => {
      if (name !== EhConstants.COOKIE_NW && value.length > 0) {
        entries.push(new CookieJarEntry(name, value))
      }
    })
    return entries
  }

  /**
   * Every stored cookie as a "name=value; …" string for PERSISTENCE — the COMPLETE jar, not just the
   * known auth bundle. EH gates some galleries (ExHentai-only content shown as "removed or unavailable"
   * on the e-hentai.org URL) on donor/permission cookies whose NAMES we don't enumerate; dropping the
   * unknown cookies made a logged-in donor look unauthenticated and the gallery look hard-deleted. `nw`
   * is excluded (re-forced per request). Values are sensitive — this is fed to Preferences, never logged.
   */
  serializeForPersist(): string {
    const parts: string[] = []
    this.cookies.forEach((value: string, name: string) => {
      if (name !== EhConstants.COOKIE_NW && value.length > 0) {
        parts.push(`${name}=${value}`)
      }
    })
    return parts.join('; ')
  }
}

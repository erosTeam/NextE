import { EhConstants } from '../constants/EhConstants'

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
    return this.get(EhConstants.COOKIE_MEMBER_ID).length > 0 &&
      this.get(EhConstants.COOKIE_PASS_HASH).length > 0
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
}

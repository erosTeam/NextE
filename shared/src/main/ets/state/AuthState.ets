import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Reactive mirror of the auth/login state for UI gating (login button vs "logged in",
 * ExHentai availability). The source of truth for the actual cookies is EhCookieStore (the
 * in-memory jar) + CookieJarSettings (persistence); this holder only carries the booleans/ids
 * the UI reacts to. `memberId` is the non-sensitive user id (safe to show); the pass hash /
 * igneous live ONLY in EhCookieStore and are never mirrored here.
 */
@ObservedV2
export class AuthState {
  @Trace isLogin: boolean = false
  @Trace hasIgneous: boolean = false
  @Trace memberId: string = ''
  @Trace nickName: string = ''
  @Trace avatarUrl: string = ''
  @Trace cookieCount: number = 0
}

const AUTH_KEY: string = 'v2_auth'

export function connectAuth(): AuthState {
  return AppStorageV2.connect(AuthState, AUTH_KEY, () => new AuthState())!
}

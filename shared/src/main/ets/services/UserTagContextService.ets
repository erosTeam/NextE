import { EhUsertag } from '../model/EhMytags'
import { SimpleTag } from '../model/SimpleTag'
import { EhConstants } from '../constants/EhConstants'
import { EhCookieStore } from '../network/EhCookieStore'
import { connectSiteMode } from '../state/SiteModeState'
import { UserTagStore } from '../state/UserTagStore'
import { connectUserTagSignal, UserTagSignal } from '../state/UserTagSignal'

/** Binds My Tags data and inline fallback colors to one authenticated account/site scope. */
export class UserTagRequestContext {
  memberId: string
  passHash: string
  isEx: boolean
  generation: number

  constructor(memberId: string, passHash: string, isEx: boolean, generation: number) {
    this.memberId = memberId
    this.passHash = passHash
    this.isEx = isEx
    this.generation = generation
  }
}

export class UserTagRequestFence {
  /** Exact runtime scope comparison, including anonymous list parsing. */
  static sameScope(left: UserTagRequestContext, right: UserTagRequestContext): boolean {
    return (
      left.memberId === right.memberId &&
      left.passHash === right.passHash &&
      left.isEx === right.isEx
    )
  }

  /** My Tags server data requires a non-empty identity bundle as well as an exact scope match. */
  static matchesAuthenticated(left: UserTagRequestContext, right: UserTagRequestContext): boolean {
    return (
      left.memberId.length > 0 &&
      left.passHash.length > 0 &&
      right.memberId.length > 0 &&
      right.passHash.length > 0 &&
      UserTagRequestFence.sameScope(left, right)
    )
  }
}

/**
 * Owns the write boundary for the plain My Tags lookup cache. A generation changes before account/site
 * transitions, so an older A request cannot apply after A → B → A even when credentials happen to match.
 */
export class UserTagContextService {
  private static generation: number = 0

  static captureActiveRequest(): UserTagRequestContext {
    const cookieStore: EhCookieStore = EhCookieStore.getInstance()
    return new UserTagRequestContext(
      cookieStore.get(EhConstants.COOKIE_MEMBER_ID),
      cookieStore.get(EhConstants.COOKIE_PASS_HASH),
      connectSiteMode().isEx,
      UserTagContextService.generation,
    )
  }

  static isCurrentScope(request: UserTagRequestContext): boolean {
    return (
      request.generation === UserTagContextService.generation &&
      UserTagRequestFence.sameScope(request, UserTagContextService.captureActiveRequest())
    )
  }

  static isCurrentAuthenticated(request: UserTagRequestContext): boolean {
    return (
      request.generation === UserTagContextService.generation &&
      UserTagRequestFence.matchesAuthenticated(request, UserTagContextService.captureActiveRequest())
    )
  }

  /** Clear both the server-backed and inline-derived indexes before a new account/site may write. */
  static reset(): void {
    UserTagContextService.generation = UserTagContextService.generation + 1
    UserTagStore.getInstance().clear()
    const signal: UserTagSignal = connectUserTagSignal()
    signal.version = signal.version + 1
  }

  /** Apply trusted /mytags data only to the context that issued the request. */
  static publishMyTags(request: UserTagRequestContext, tags: EhUsertag[]): boolean {
    if (!UserTagContextService.isCurrentAuthenticated(request)) {
      return false
    }
    UserTagStore.getInstance().setTags(tags)
    const signal: UserTagSignal = connectUserTagSignal()
    signal.version = signal.version + 1
    return true
  }

  /** Keep list-derived fallback colors only while the initiating account/site context is still active. */
  static ingestInlineTags(request: UserTagRequestContext, tags: SimpleTag[]): boolean {
    if (!UserTagContextService.isCurrentScope(request)) {
      return false
    }
    return UserTagStore.getInstance().ingestInlineTags(tags)
  }

  /** Bump visual consumers after a batched inline ingestion, while still verifying the same scope. */
  static notifyInlineTagsChanged(request: UserTagRequestContext): void {
    if (!UserTagContextService.isCurrentScope(request)) {
      return
    }
    const signal: UserTagSignal = connectUserTagSignal()
    signal.version = signal.version + 1
  }
}

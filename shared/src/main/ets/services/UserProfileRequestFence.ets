/**
 * Binds a profile read/capture to the account credentials that started it.
 * Profile data is account-scoped, so a delayed WebView or HTTP response must not update another account.
 */
export class UserProfileRequestContext {
  memberId: string
  passHash: string

  constructor(memberId: string, passHash: string) {
    this.memberId = memberId
    this.passHash = passHash
  }
}

export class UserProfileRequestFence {
  static matches(
    request: UserProfileRequestContext,
    active: UserProfileRequestContext,
  ): boolean {
    return (
      request.memberId.length > 0 &&
      request.passHash.length > 0 &&
      active.memberId.length > 0 &&
      active.passHash.length > 0 &&
      request.memberId === active.memberId &&
      request.passHash === active.passHash
    )
  }

  static matchesProfileUrl(request: UserProfileRequestContext, url: string): boolean {
    if (request.memberId.length === 0) {
      return false
    }
    const match: RegExpExecArray | null = /(?:[?&]showuser=)([^&#]*)/.exec(url)
    return match !== null && match[1] === encodeURIComponent(request.memberId)
  }
}

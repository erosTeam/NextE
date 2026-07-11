/**
 * Binds a uconfig request to the account credentials and site that owned the editable form.
 * A delayed response must not turn one account's settings into another account's write payload.
 */
export class EhProfileSettingsRequestContext {
  memberId: string
  passHash: string
  isEx: boolean

  constructor(memberId: string, passHash: string, isEx: boolean) {
    this.memberId = memberId
    this.passHash = passHash
    this.isEx = isEx
  }
}

export class EhProfileSettingsRequestFence {
  static matches(
    request: EhProfileSettingsRequestContext,
    active: EhProfileSettingsRequestContext,
  ): boolean {
    return (
      request.memberId.length > 0 &&
      request.passHash.length > 0 &&
      active.memberId.length > 0 &&
      active.passHash.length > 0 &&
      request.memberId === active.memberId &&
      request.passHash === active.passHash &&
      request.isEx === active.isEx
    )
  }
}

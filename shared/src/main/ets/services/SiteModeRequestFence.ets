/**
 * Keeps an asynchronous ExHentai access check tied to the user choice and credentials that
 * issued it. A request may finish after the user chose E-Hentai or switched accounts.
 */
export class SiteModeRequestFence {
  static canApplyExUnlock(
    desiredSiteIsEx: boolean,
    requestMemberId: string,
    requestPassHash: string,
    activeMemberId: string,
    activePassHash: string,
  ): boolean {
    return (
      desiredSiteIsEx &&
      requestMemberId.length > 0 &&
      requestPassHash.length > 0 &&
      activeMemberId === requestMemberId &&
      activePassHash === requestPassHash
    )
  }
}

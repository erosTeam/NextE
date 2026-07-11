import { describe, expect, it } from '@ohos/hypium'
import { CookieJarSettings } from 'shared'

function cookie(name: string, value: string): string {
  return `${name}${String.fromCharCode(61)}${value}`
}

export default function cookieJarRefreshIdentityTest(): void {
  describe('CookieJar refresh identity guard', () => {
    it('accepts only a response that still belongs to the account which issued it', 0, (done: Function) => {
      const memberName: string = 'ipb_member_id'
      const igneousName: string = 'igneous'
      const accountA: string = 'account-a'
      const accountB: string = 'account-b'
      const sessionA: string = 'session-a'
      const sessionB: string = 'session-b'
      const igneousA: string = cookie(igneousName, 'fixture-a')
      const responseA: string = `${cookie(memberName, accountA)}; ${igneousA}`
      const responseB: string = `${cookie(memberName, accountB)}; ${cookie(igneousName, 'fixture-b')}`

      expect(CookieJarSettings.shouldApplyIgneousResponse(
        accountA, sessionA, accountA, sessionA, igneousA,
      )).assertEqual(true)
      expect(CookieJarSettings.shouldApplyIgneousResponse(
        accountA, sessionA, accountA, sessionA, responseA,
      )).assertEqual(true)
      expect(CookieJarSettings.shouldApplyIgneousResponse(
        accountA, sessionA, accountB, sessionB, igneousA,
      )).assertEqual(false)
      expect(CookieJarSettings.shouldApplyIgneousResponse(
        accountA, sessionA, accountA, sessionA, responseB,
      )).assertEqual(false)
      expect(CookieJarSettings.shouldApplyIgneousResponse(
        accountA, sessionA, accountA, sessionB, igneousA,
      )).assertEqual(false)
      expect(CookieJarSettings.shouldApplyIgneousResponse('', '', '', '', igneousA)).assertEqual(false)
      done()
    })
  })
}

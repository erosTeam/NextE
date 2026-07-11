import { describe, expect, it } from '@ohos/hypium'
import { EhProfileSettingsRequestContext, EhProfileSettingsRequestFence } from 'shared'

function context(memberId: string, passHash: string, isEx: boolean): EhProfileSettingsRequestContext {
  return new EhProfileSettingsRequestContext(memberId, passHash, isEx)
}

export default function ehProfileSettingsRequestFenceTest(): void {
  describe('EhProfileSettings request fence', () => {
    it('accepts only the same account credentials and site', 0, (done: Function) => {
      const request: EhProfileSettingsRequestContext = context('member-a', 'hash-a', false)
      expect(EhProfileSettingsRequestFence.matches(
        request, context('member-a', 'hash-a', false),
      )).assertEqual(true)
      expect(EhProfileSettingsRequestFence.matches(
        request, context('member-b', 'hash-b', false),
      )).assertEqual(false)
      expect(EhProfileSettingsRequestFence.matches(
        request, context('member-a', 'hash-b', false),
      )).assertEqual(false)
      expect(EhProfileSettingsRequestFence.matches(
        request, context('member-a', 'hash-a', true),
      )).assertEqual(false)
      expect(EhProfileSettingsRequestFence.matches(
        context('', '', false), context('', '', false),
      )).assertEqual(false)
      done()
    })
  })
}

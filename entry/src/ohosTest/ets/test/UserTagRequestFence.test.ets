import { describe, expect, it } from '@ohos/hypium'
import { UserTagRequestContext, UserTagRequestFence } from 'shared'

function context(
  memberId: string,
  passHash: string,
  isEx: boolean,
  generation: number,
): UserTagRequestContext {
  return new UserTagRequestContext(memberId, passHash, isEx, generation)
}

export default function userTagRequestFenceTest(): void {
  describe('UserTag request fence', () => {
    it('requires the same authenticated account and site while comparing scope separately', 0, (done: Function) => {
      const request: UserTagRequestContext = context('member-a', 'hash-a', false, 3)
      expect(UserTagRequestFence.sameScope(
        request, context('member-a', 'hash-a', false, 4),
      )).assertEqual(true)
      expect(UserTagRequestFence.sameScope(
        request, context('member-a', 'hash-a', true, 3),
      )).assertEqual(false)
      expect(UserTagRequestFence.matchesAuthenticated(
        request, context('member-a', 'hash-a', false, 4),
      )).assertEqual(true)
      expect(UserTagRequestFence.matchesAuthenticated(
        request, context('member-b', 'hash-b', false, 3),
      )).assertEqual(false)
      expect(UserTagRequestFence.matchesAuthenticated(
        request, context('member-a', 'hash-b', false, 3),
      )).assertEqual(false)
      expect(UserTagRequestFence.matchesAuthenticated(
        request, context('member-a', 'hash-a', true, 3),
      )).assertEqual(false)
      expect(UserTagRequestFence.matchesAuthenticated(
        context('', '', false, 3), context('', '', false, 3),
      )).assertEqual(false)
      done()
    })
  })
}

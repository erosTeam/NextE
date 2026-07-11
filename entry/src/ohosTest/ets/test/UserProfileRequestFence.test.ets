import { describe, expect, it } from '@ohos/hypium'
import { UserProfileRequestContext, UserProfileRequestFence } from 'shared'

function context(memberId: string, passHash: string): UserProfileRequestContext {
  return new UserProfileRequestContext(memberId, passHash)
}

export default function userProfileRequestFenceTest(): void {
  describe('UserProfile request fence', () => {
    it('accepts only the current account and its own profile URL', 0, (done: Function) => {
      const request: UserProfileRequestContext = context('123', 'hash-a')
      expect(UserProfileRequestFence.matches(request, context('123', 'hash-a'))).assertEqual(true)
      expect(UserProfileRequestFence.matches(request, context('456', 'hash-b'))).assertEqual(false)
      expect(UserProfileRequestFence.matches(request, context('123', 'hash-b'))).assertEqual(false)
      expect(UserProfileRequestFence.matches(context('', ''), context('', ''))).assertEqual(false)
      expect(UserProfileRequestFence.matchesProfileUrl(
        request, 'https://forums.e-hentai.org/index.php?showuser=123',
      )).assertEqual(true)
      expect(UserProfileRequestFence.matchesProfileUrl(
        request, 'https://forums.e-hentai.org/index.php?showuser=1234',
      )).assertEqual(false)
      expect(UserProfileRequestFence.matchesProfileUrl(
        request, 'https://forums.e-hentai.org/index.php?showuser=456',
      )).assertEqual(false)
      done()
    })
  })
}

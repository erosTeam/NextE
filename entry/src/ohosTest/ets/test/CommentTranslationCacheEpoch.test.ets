import { describe, expect, it } from '@ohos/hypium'
import { CommentTranslationCacheEpoch } from 'shared'

export default function commentTranslationCacheEpochTest(): void {
  describe('CommentTranslationCacheEpoch', () => {
    it('makes an explicit cache clear win over older work', 0, (done: Function) => {
      const epoch: CommentTranslationCacheEpoch = new CommentTranslationCacheEpoch()
      const beforeClear: number = epoch.snapshot()
      expect(epoch.isCurrent(beforeClear)).assertEqual(true)
      epoch.advance()
      expect(epoch.isCurrent(beforeClear)).assertEqual(false)
      expect(epoch.isCurrent(epoch.snapshot())).assertEqual(true)
      done()
    })
  })
}

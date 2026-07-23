import { describe, expect, it } from '@ohos/hypium'
import { ReaderComicTranslationAutoPolicy } from 'reader'

export default function readerComicTranslationAutoPolicyTest(): void {
  describe('Reader comic translation auto policy', () => {
    it('always prepares the current page before looking ahead', 0, (done: Function) => {
      expect(ReaderComicTranslationAutoPolicy.selectTarget(4, true, false, true))
        .assertEqual(4)
      done()
    })

    it('prepares exactly the next page after the current page settles', 0, (done: Function) => {
      expect(ReaderComicTranslationAutoPolicy.selectTarget(4, false, true, true))
        .assertEqual(5)
      done()
    })

    it('does not skip over an unsettled current page or extend beyond one page', 0, (done: Function) => {
      expect(ReaderComicTranslationAutoPolicy.selectTarget(4, false, false, true))
        .assertEqual(-1)
      expect(ReaderComicTranslationAutoPolicy.selectTarget(4, false, true, false))
        .assertEqual(-1)
      done()
    })
  })
}

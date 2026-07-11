import { describe, expect, it } from '@ohos/hypium'
import { ReaderImageLoadPresentation } from 'reader'
import { CachedImageFileResult } from 'shared'

function result(
  fromCache: boolean,
  bytes: number = 128,
  filePath: string = '/data/storage/el2/base/reader.jpg',
  displayUri: string = 'file:///data/storage/el2/base/reader.jpg',
): CachedImageFileResult {
  return { filePath, displayUri, bytes, fromCache }
}

export default function readerImageLoadPresentationTest(): void {
  describe('Reader image load presentation', () => {
    it('skips only the artificial completion hold for a complete local cache file', 0, (done: Function) => {
      expect(ReaderImageLoadPresentation.shouldSkipCompletionHold(result(true))).assertEqual(true)
      expect(ReaderImageLoadPresentation.shouldSkipCompletionHold(result(false))).assertEqual(false)
      expect(ReaderImageLoadPresentation.shouldSkipCompletionHold(result(true, 0))).assertEqual(false)
      expect(ReaderImageLoadPresentation.shouldSkipCompletionHold(result(true, 128, ''))).assertEqual(false)
      expect(ReaderImageLoadPresentation.shouldSkipCompletionHold(result(true, 128, '/data/reader.jpg', ''))).assertEqual(false)
      done()
    })
  })
}

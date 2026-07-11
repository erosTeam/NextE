import { describe, expect, it } from '@ohos/hypium'
import { EH_IMAGE_PRIORITY_HIGH, EH_IMAGE_PRIORITY_LOW } from 'shared'
import { ReaderImageLoadPriority } from 'reader'

export default function readerImageLoadPriorityTest(): void {
  describe('Reader image load priority', () => {
    it('keeps the visible page high priority and cached pages low priority', 0, (done: Function) => {
      expect(ReaderImageLoadPriority.forVisible(true)).assertEqual(EH_IMAGE_PRIORITY_HIGH)
      expect(ReaderImageLoadPriority.forVisible(false)).assertEqual(EH_IMAGE_PRIORITY_LOW)
      done()
    })
  })
}

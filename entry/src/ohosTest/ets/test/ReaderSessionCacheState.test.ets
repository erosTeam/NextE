import { describe, expect, it } from '@ohos/hypium'
import { ReaderViewModel } from 'reader'
import { EhGalleryImage } from 'shared'

function seededImage(): EhGalleryImage {
  const image: EhGalleryImage = new EhGalleryImage(1)
  image.imgkey = 'reader-session-state'
  image.sUrl = 'https://example.test/s/reader-session-state/reader-session-state-1'
  return image
}

export default function readerSessionCacheStateTest(): void {
  describe('Reader session cache state updates', () => {
    it('keeps the loaded snapshot reusable after navigation-only state updates', 0, async (done: Function) => {
      const first: ReaderViewModel = new ReaderViewModel()
      await first.init(
        'reader-session-state',
        'token',
        false,
        1,
        0,
        [seededImage()],
        1,
        1,
        [0],
      )
      first.onPageChange(0)
      first.onVerticalScroll(0, 0)
      await first.jumpTo(0)

      const resumed: ReaderViewModel = new ReaderViewModel()
      await resumed.init('reader-session-state', 'token', false, 1, 0)

      expect(resumed.hasPreviewAt(0)).assertEqual(true)
      expect(resumed.imageAt(0).sUrl).assertEqual(seededImage().sUrl)
      expect(resumed.pageIndexSource.totalCount()).assertEqual(1)
      done()
    })
  })
}

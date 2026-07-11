import { describe, expect, it } from '@ohos/hypium'
import { ReaderViewModel } from 'reader'
import { EhGalleryImage } from 'shared'

function seededImage(page: number = 1): EhGalleryImage {
  const image: EhGalleryImage = new EhGalleryImage(page)
  image.imgkey = `reader-session-state-${page}`
  image.sUrl = `https://example.test/s/reader-session-state/reader-session-state-${page}`
  image.imageUrl = `file:///reader-session-state-${page}.jpg`
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

    it('restores sparse snapshot entries by page after later page-state updates', 0, async (done: Function) => {
      const first: ReaderViewModel = new ReaderViewModel()
      const seed: EhGalleryImage[] = [seededImage(1), seededImage(2), seededImage(3)]
      await first.init(
        'reader-session-state-multi',
        'token',
        false,
        3,
        0,
        seed,
        1,
        3,
        [0],
      )
      first.onPageChange(2)
      first.onVerticalScroll(2, 2)

      const resumed: ReaderViewModel = new ReaderViewModel()
      await resumed.init('reader-session-state-multi', 'token', false, 3, 0)

      expect(resumed.pageIndexSource.totalCount()).assertEqual(3)
      expect(resumed.hasPreviewAt(0)).assertEqual(true)
      expect(resumed.hasPreviewAt(1)).assertEqual(true)
      expect(resumed.hasPreviewAt(2)).assertEqual(true)
      expect(resumed.imageAt(2).sUrl).assertEqual(seededImage(3).sUrl)
      expect(resumed.imageAt(2).imageUrl).assertEqual(seededImage(3).imageUrl)
      done()
    })
  })
}

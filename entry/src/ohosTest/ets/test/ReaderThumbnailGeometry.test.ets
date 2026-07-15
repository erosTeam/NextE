import { describe, expect, it } from '@ohos/hypium'
import { ReaderThumbnailGeometry, ReaderThumbnailSize } from 'reader'

function assertNear(actual: number, expected: number, tolerance: number = 0.001): void {
  expect(Math.abs(actual - expected) <= tolerance).assertTrue()
}

export default function readerThumbnailGeometryTest(): void {
  describe('Reader thumbnail geometry', () => {
    it('uses the source aspect instead of a fixed landscape box', 0, () => {
      const size: ReaderThumbnailSize = ReaderThumbnailGeometry.fitHeight(3, 4)

      assertNear(size.width, 88.5)
      assertNear(size.height, 118)
      assertNear(size.width / size.height, 3 / 4)
    })

    it('keeps landscape images proportional without stretching', 0, () => {
      const size: ReaderThumbnailSize = ReaderThumbnailGeometry.fitHeight(4, 3)

      assertNear(size.width, 118 * 4 / 3)
      assertNear(size.width / size.height, 4 / 3)
    })

    it('uses the same portrait fallback as the online sprite component', 0, () => {
      const size: ReaderThumbnailSize = ReaderThumbnailGeometry.fitHeight(0, 0)

      assertNear(size.width, 118 * ReaderThumbnailGeometry.FALLBACK_ASPECT)
      assertNear(size.height, 118)
    })
  })
}

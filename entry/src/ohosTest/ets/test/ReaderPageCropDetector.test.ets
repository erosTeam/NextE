import { describe, expect, it } from '@ohos/hypium'
import { ReaderPageCropBounds, ReaderPageCropDetector } from 'shared'

function fixture(width: number, height: number, border: number, white: boolean): Uint8Array {
  const pixels: Uint8Array = new Uint8Array(width * height * 4)
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      const edge: boolean = x < border || x >= width - border || y < border || y >= height - border
      const offset: number = (y * width + x) * 4
      const value: number = edge ? (white ? 255 : 0) : 112
      pixels[offset] = value
      pixels[offset + 1] = edge ? value : 68
      pixels[offset + 2] = edge ? value : 184
      pixels[offset + 3] = 255
    }
  }
  return pixels
}

function setPixel(
  pixels: Uint8Array,
  width: number,
  x: number,
  y: number,
  r: number,
  g: number,
  b: number,
): void {
  const offset: number = (y * width + x) * 4
  pixels[offset] = r
  pixels[offset + 1] = g
  pixels[offset + 2] = b
  pixels[offset + 3] = 255
}

function assertNear(actual: number, expected: number, tolerance: number = 0.001): void {
  expect(Math.abs(actual - expected) <= tolerance).assertTrue()
}

export default function readerPageCropDetectorTest(): void {
  describe('Reader page crop detector', () => {
    it('detects a white frame while retaining a one-sample safety edge', 0, () => {
      const width: number = 40
      const height: number = 48
      const bounds: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        fixture(width, height, 6, true),
        1200,
        1440,
      )

      expect(bounds.applied()).assertTrue()
      assertNear(bounds.left, 5 / width)
      assertNear(bounds.right, 5 / width)
      assertNear(bounds.top, 5 / height)
      assertNear(bounds.bottom, 5 / height)
      assertNear(bounds.contentWidth(), 900)
    })

    it('detects a black frame', 0, () => {
      const width: number = 40
      const height: number = 48
      const bounds: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        fixture(width, height, 5, false),
      )

      expect(bounds.applied()).assertTrue()
      assertNear(bounds.left, 4 / width)
      assertNear(bounds.top, 4 / height)
    })

    it('keeps an unframed colored page unchanged', 0, () => {
      const width: number = 32
      const height: number = 40
      const pixels: Uint8Array = fixture(width, height, 0, true)
      const bounds: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        pixels,
      )

      expect(bounds.applied()).assertFalse()
    })

    it('falls back on an empty white page instead of collapsing it', 0, () => {
      const width: number = 32
      const height: number = 40
      const pixels: Uint8Array = fixture(width, height, 40, true)
      const bounds: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        pixels,
      )

      expect(bounds.applied()).assertFalse()
    })

    it('preserves every edge when more than one percent contains artwork', 0, () => {
      const width: number = 40
      const height: number = 48
      const topPixels: Uint8Array = fixture(width, height, 6, true)
      setPixel(topPixels, width, 7, 0, 112, 68, 184)
      setPixel(topPixels, width, 8, 0, 112, 68, 184)
      const top: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        topPixels,
      )
      const bottomPixels: Uint8Array = fixture(width, height, 6, true)
      setPixel(bottomPixels, width, 7, height - 1, 112, 68, 184)
      setPixel(bottomPixels, width, 8, height - 1, 112, 68, 184)
      const bottom: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        bottomPixels,
      )
      const leftPixels: Uint8Array = fixture(width, height, 6, true)
      setPixel(leftPixels, width, 0, 7, 112, 68, 184)
      setPixel(leftPixels, width, 0, 8, 112, 68, 184)
      const left: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        leftPixels,
      )
      const rightPixels: Uint8Array = fixture(width, height, 6, true)
      setPixel(rightPixels, width, width - 1, 7, 112, 68, 184)
      setPixel(rightPixels, width, width - 1, 8, 112, 68, 184)
      const right: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        rightPixels,
      )

      expect(top.applied()).assertTrue()
      expect(top.top).assertEqual(0)
      expect(bottom.bottom).assertEqual(0)
      expect(left.left).assertEqual(0)
      expect(right.right).assertEqual(0)
      expect(top.left > 0 && bottom.left > 0).assertTrue()
      expect(left.top > 0 && right.top > 0).assertTrue()
    })

    it('protects continuous-reader seams on middle pages', 0, () => {
      const detected: ReaderPageCropBounds = new ReaderPageCropBounds(
        1000,
        1500,
        0.1,
        0.08,
        0.1,
        0.06,
      )
      const first: ReaderPageCropBounds = detected.forContinuousPage(1, 3)
      const middle: ReaderPageCropBounds = detected.forContinuousPage(2, 3)
      const last: ReaderPageCropBounds = detected.forContinuousPage(3, 3)

      expect(first.top > 0).assertTrue()
      expect(first.bottom).assertEqual(0)
      expect(middle.top).assertEqual(0)
      expect(middle.bottom).assertEqual(0)
      expect(last.top).assertEqual(0)
      expect(last.bottom > 0).assertTrue()
      expect(middle.left > 0 && middle.right > 0).assertTrue()
    })
  })
}

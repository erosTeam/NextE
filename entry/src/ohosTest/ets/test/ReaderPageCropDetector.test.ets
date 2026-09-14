import { describe, expect, it } from '@ohos/hypium'
import {
  ReaderPageCropBounds,
  ReaderPageCropDetector,
  ReaderPageCropStrength,
} from 'shared'

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
  describe('ReaderPageCropDetector', () => {
    it('keeps the legacy one-sample safety edge at conservative strength', 0, () => {
      const width: number = 40
      const height: number = 48
      const bounds: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        fixture(width, height, 6, true),
        1200,
        1440,
        ReaderPageCropStrength.CONSERVATIVE,
      )

      expect(bounds.applied()).assertTrue()
      assertNear(bounds.left, 5 / width)
      assertNear(bounds.right, 5 / width)
      assertNear(bounds.top, 5 / height)
      assertNear(bounds.bottom, 5 / height)
      assertNear(bounds.contentWidth(), 900)
    })

    it('crops the full detected frame at the default standard strength', 0, () => {
      const width: number = 40
      const height: number = 48
      const bounds: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        fixture(width, height, 5, false),
      )

      expect(bounds.applied()).assertTrue()
      assertNear(bounds.left, 5 / width)
      assertNear(bounds.top, 5 / height)
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
      setPixel(topPixels, width, 18, 0, 112, 68, 184)
      setPixel(topPixels, width, 19, 0, 112, 68, 184)
      const top: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        topPixels,
      )
      const bottomPixels: Uint8Array = fixture(width, height, 6, true)
      setPixel(bottomPixels, width, 18, height - 1, 112, 68, 184)
      setPixel(bottomPixels, width, 19, height - 1, 112, 68, 184)
      const bottom: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        bottomPixels,
      )
      const leftPixels: Uint8Array = fixture(width, height, 6, true)
      setPixel(leftPixels, width, 0, 22, 112, 68, 184)
      setPixel(leftPixels, width, 0, 23, 112, 68, 184)
      const left: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width,
        height,
        width * 4,
        leftPixels,
      )
      const rightPixels: Uint8Array = fixture(width, height, 6, true)
      setPixel(rightPixels, width, width - 1, 22, 112, 68, 184)
      setPixel(rightPixels, width, width - 1, 23, 112, 68, 184)
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

    it('standard removes near-white compression residue that conservative leaves', 0, () => {
      const width: number = 40
      const height: number = 48
      const pixels: Uint8Array = fixture(width, height, 6, true)
      for (let y: number = 0; y < height; y++) {
        for (let x: number = 0; x < width; x++) {
          if (x < 6 || x >= width - 6 || y < 6 || y >= height - 6) {
            setPixel(pixels, width, x, y, 225, 225, 225)
          }
        }
      }
      const conservative: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.CONSERVATIVE,
      )
      const standard: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.STANDARD,
      )

      expect(conservative.applied()).assertFalse()
      expect(standard.applied()).assertTrue()
      assertNear(standard.left, 6 / width)
    })

    it('classifies each edge independently', 0, () => {
      const width: number = 40
      const height: number = 48
      const pixels: Uint8Array = fixture(width, height, 0, true)
      for (let y: number = 0; y < 4; y++) {
        for (let x: number = 0; x < width; x++) {
          setPixel(pixels, width, x, y, 255, 255, 255)
        }
      }
      for (let y: number = 0; y < height; y++) {
        for (let x: number = 0; x < 5; x++) {
          setPixel(pixels, width, x, y, 0, 0, 0)
        }
      }
      const bounds: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels,
      )

      assertNear(bounds.left, 5 / width)
      assertNear(bounds.top, 4 / height)
      expect(bounds.right).assertEqual(0)
      expect(bounds.bottom).assertEqual(0)
    })

    it('strong tolerates sparse border noise that standard preserves', 0, () => {
      const width: number = 200
      const height: number = 80
      const pixels: Uint8Array = fixture(width, height, 6, true)
      setPixel(pixels, width, 90, 0, 112, 68, 184)
      setPixel(pixels, width, 110, 0, 112, 68, 184)
      const standard: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.STANDARD,
      )
      const strong: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.STRONG,
      )

      expect(standard.top).assertEqual(0)
      expect(strong.top > 0).assertTrue()
    })

    it('preserves dialogue-box structure outside the former center-only scan band', 0, () => {
      const width: number = 200
      const height: number = 160
      const pixels: Uint8Array = fixture(width, height, 24, true)
      for (let x: number = 8; x < 32; x++) {
        setPixel(pixels, width, x, 0, 24, 24, 24)
      }
      for (let y: number = 8; y < 32; y++) {
        setPixel(pixels, width, 0, y, 24, 24, 24)
      }

      const conservative: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.CONSERVATIVE,
      )
      const standard: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.STANDARD,
      )
      const strong: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.STRONG,
      )

      expect(conservative.top).assertEqual(0)
      expect(conservative.left).assertEqual(0)
      expect(standard.top).assertEqual(0)
      expect(standard.left).assertEqual(0)
      expect(strong.top).assertEqual(0)
      expect(strong.left).assertEqual(0)
      expect(conservative.right > 0 && conservative.bottom > 0).assertTrue()
      expect(standard.right > 0 && standard.bottom > 0).assertTrue()
      expect(strong.right > 0 && strong.bottom > 0).assertTrue()
    })

    it('preserves a thin continuous content line at every strength', 0, () => {
      const width: number = 200
      const height: number = 160
      const pixels: Uint8Array = fixture(width, height, 20, true)
      setPixel(pixels, width, 30, 0, 24, 24, 24)
      setPixel(pixels, width, 31, 0, 24, 24, 24)

      const conservative: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.CONSERVATIVE,
      )
      const standard: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.STANDARD,
      )
      const strong: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, pixels, width, height, ReaderPageCropStrength.STRONG,
      )

      expect(conservative.top).assertEqual(0)
      expect(standard.top).assertEqual(0)
      expect(strong.top).assertEqual(0)
    })

    it('weights high-contrast content above equal-count low-contrast residue', 0, () => {
      const width: number = 400
      const height: number = 160
      const lowContrast: Uint8Array = fixture(width, height, 20, true)
      setPixel(lowContrast, width, 90, 0, 230, 230, 230)
      setPixel(lowContrast, width, 210, 0, 230, 230, 230)
      const highContrast: Uint8Array = fixture(width, height, 20, true)
      setPixel(highContrast, width, 90, 0, 24, 24, 24)
      setPixel(highContrast, width, 210, 0, 24, 24, 24)

      const low: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, lowContrast, width, height, ReaderPageCropStrength.CONSERVATIVE,
      )
      const high: ReaderPageCropBounds = ReaderPageCropDetector.detect(
        width, height, width * 4, highContrast, width, height, ReaderPageCropStrength.CONSERVATIVE,
      )

      expect(low.top > 0).assertTrue()
      expect(high.top).assertEqual(0)
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

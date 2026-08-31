const READER_CROP_MAX_EDGE_FRACTION: number = 0.35
const READER_CROP_MIN_RETAINED_FRACTION: number = 0.25
const READER_CROP_LINE_CONTENT_FRACTION: number = 0.01
const READER_CROP_EDGE_SAMPLE_COUNT: number = 8
const READER_CROP_EDGE_SAMPLE_MAJORITY: number = 5

enum ReaderPageBackgroundKind {
  NONE = 0,
  TRANSPARENT = 1,
  WHITE = 2,
  BLACK = 3,
}

/** Normalized insets into the source image. A zero-valued instance means "render the source unchanged". */
export class ReaderPageCropBounds {
  sourceWidth: number = 0
  sourceHeight: number = 0
  left: number = 0
  top: number = 0
  right: number = 0
  bottom: number = 0

  constructor(
    sourceWidth: number = 0,
    sourceHeight: number = 0,
    left: number = 0,
    top: number = 0,
    right: number = 0,
    bottom: number = 0,
  ) {
    this.sourceWidth = sourceWidth
    this.sourceHeight = sourceHeight
    this.left = ReaderPageCropBounds.saneInset(left)
    this.top = ReaderPageCropBounds.saneInset(top)
    this.right = ReaderPageCropBounds.saneInset(right)
    this.bottom = ReaderPageCropBounds.saneInset(bottom)
  }

  static none(sourceWidth: number = 0, sourceHeight: number = 0): ReaderPageCropBounds {
    return new ReaderPageCropBounds(sourceWidth, sourceHeight)
  }

  private static saneInset(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0
    }
    return Math.min(0.49, value)
  }

  contentWidthFraction(): number {
    return Math.max(0.01, 1 - this.left - this.right)
  }

  contentHeightFraction(): number {
    return Math.max(0.01, 1 - this.top - this.bottom)
  }

  contentWidth(): number {
    return this.sourceWidth * this.contentWidthFraction()
  }

  contentHeight(): number {
    return this.sourceHeight * this.contentHeightFraction()
  }

  applied(): boolean {
    return this.sourceWidth > 0 && this.sourceHeight > 0 &&
      (this.left > 0 || this.top > 0 || this.right > 0 || this.bottom > 0)
  }

  /** Continuous pages keep their shared top/bottom seams unless they are the first/last page. */
  forContinuousPage(page: number, totalPages: number): ReaderPageCropBounds {
    if (!this.applied()) {
      return this
    }
    const allowTop: boolean = page <= 1
    const allowBottom: boolean = totalPages <= 1 || page >= totalPages
    return new ReaderPageCropBounds(
      this.sourceWidth,
      this.sourceHeight,
      this.left,
      allowTop ? this.top : 0,
      this.right,
      allowBottom ? this.bottom : 0,
    )
  }

  serialize(): string {
    return `${this.sourceWidth},${this.sourceHeight},${this.left},${this.top},${this.right},${this.bottom}`
  }

  static parse(value: string): ReaderPageCropBounds {
    const parts: string[] = value.split(',')
    if (parts.length !== 6) {
      return ReaderPageCropBounds.none()
    }
    return new ReaderPageCropBounds(
      Number(parts[0]),
      Number(parts[1]),
      Number(parts[2]),
      Number(parts[3]),
      Number(parts[4]),
      Number(parts[5]),
    )
  }
}

/** Pure detector kept public so conservative edge decisions can be covered with synthetic pixel fixtures. */
export class ReaderPageCropDetector {
  static detect(
    width: number,
    height: number,
    stride: number,
    pixels: Uint8Array,
    sourceWidth: number = width,
    sourceHeight: number = height,
  ): ReaderPageCropBounds {
    if (width < 4 || height < 4 || stride < width * 4 || pixels.length < stride * height ||
      sourceWidth <= 0 || sourceHeight <= 0) {
      return ReaderPageCropBounds.none(sourceWidth, sourceHeight)
    }
    const background: ReaderPageBackgroundKind = ReaderPageCropDetector.detectBackground(
      width,
      height,
      stride,
      pixels,
    )
    if (background === ReaderPageBackgroundKind.NONE) {
      return ReaderPageCropBounds.none(sourceWidth, sourceHeight)
    }

    const maxLeft: number = Math.floor(width * READER_CROP_MAX_EDGE_FRACTION)
    const maxTop: number = Math.floor(height * READER_CROP_MAX_EDGE_FRACTION)
    let left: number = 0
    while (left < maxLeft && ReaderPageCropDetector.columnIsBackground(
      left, width, height, stride, pixels, background,
    )) {
      left++
    }
    let right: number = width - 1
    while (right > width - 1 - maxLeft && ReaderPageCropDetector.columnIsBackground(
      right, width, height, stride, pixels, background,
    )) {
      right--
    }
    let top: number = 0
    while (top < maxTop && ReaderPageCropDetector.rowIsBackground(
      top, width, height, stride, pixels, background,
    )) {
      top++
    }
    let bottom: number = height - 1
    while (bottom > height - 1 - maxTop && ReaderPageCropDetector.rowIsBackground(
      bottom, width, height, stride, pixels, background,
    )) {
      bottom--
    }

    // Reaching the scan cap while the next line is still background means the content boundary was
    // never found. Treat blank pages and exceptionally large uniform areas as uncertain.
    if ((left >= maxLeft && ReaderPageCropDetector.columnIsBackground(
      left, width, height, stride, pixels, background,
    )) || (right <= width - 1 - maxLeft && ReaderPageCropDetector.columnIsBackground(
      right, width, height, stride, pixels, background,
    )) || (top >= maxTop && ReaderPageCropDetector.rowIsBackground(
      top, width, height, stride, pixels, background,
    )) || (bottom <= height - 1 - maxTop && ReaderPageCropDetector.rowIsBackground(
      bottom, width, height, stride, pixels, background,
    ))) {
      return ReaderPageCropBounds.none(sourceWidth, sourceHeight)
    }

    // Retain one sampled pixel on every detected edge. This keeps antialiasing and near-edge artwork.
    if (left > 0) {
      left--
    }
    if (right < width - 1) {
      right++
    }
    if (top > 0) {
      top--
    }
    if (bottom < height - 1) {
      bottom++
    }
    const retainedWidth: number = right - left + 1
    const retainedHeight: number = bottom - top + 1
    if (retainedWidth < width * READER_CROP_MIN_RETAINED_FRACTION ||
      retainedHeight < height * READER_CROP_MIN_RETAINED_FRACTION) {
      return ReaderPageCropBounds.none(sourceWidth, sourceHeight)
    }
    const rightInset: number = width - right - 1
    const bottomInset: number = height - bottom - 1
    if (left <= 0 && top <= 0 && rightInset <= 0 && bottomInset <= 0) {
      return ReaderPageCropBounds.none(sourceWidth, sourceHeight)
    }
    return new ReaderPageCropBounds(
      sourceWidth,
      sourceHeight,
      left / width,
      top / height,
      rightInset / width,
      bottomInset / height,
    )
  }

  private static detectBackground(
    width: number,
    height: number,
    stride: number,
    pixels: Uint8Array,
  ): ReaderPageBackgroundKind {
    const x0: number = 1
    const x1: number = Math.floor(width / 2)
    const x2: number = width - 2
    const y0: number = 1
    const y1: number = Math.floor(height / 2)
    const y2: number = height - 2
    const xs: number[] = [x0, x1, x2, x0, x2, x0, x1, x2]
    const ys: number[] = [y0, y0, y0, y1, y1, y2, y2, y2]
    const counts: number[] = [0, 0, 0, 0]
    for (let i: number = 0; i < READER_CROP_EDGE_SAMPLE_COUNT; i++) {
      const kind: ReaderPageBackgroundKind = ReaderPageCropDetector.pixelKind(
        xs[i], ys[i], stride, pixels,
      )
      counts[kind]++
    }
    let selected: ReaderPageBackgroundKind = ReaderPageBackgroundKind.NONE
    for (let kind: number = ReaderPageBackgroundKind.TRANSPARENT;
      kind <= ReaderPageBackgroundKind.BLACK; kind++) {
      if (counts[kind] >= READER_CROP_EDGE_SAMPLE_MAJORITY) {
        selected = kind as ReaderPageBackgroundKind
        break
      }
    }
    return selected
  }

  private static pixelKind(
    x: number,
    y: number,
    stride: number,
    pixels: Uint8Array,
  ): ReaderPageBackgroundKind {
    const offset: number = y * stride + x * 4
    const r: number = pixels[offset]
    const g: number = pixels[offset + 1]
    const b: number = pixels[offset + 2]
    const a: number = pixels[offset + 3]
    if (a <= 16) {
      return ReaderPageBackgroundKind.TRANSPARENT
    }
    if (r >= 235 && g >= 235 && b >= 235) {
      return ReaderPageBackgroundKind.WHITE
    }
    if (r <= 20 && g <= 20 && b <= 20) {
      return ReaderPageBackgroundKind.BLACK
    }
    return ReaderPageBackgroundKind.NONE
  }

  private static pixelMatchesBackground(
    x: number,
    y: number,
    stride: number,
    pixels: Uint8Array,
    background: ReaderPageBackgroundKind,
  ): boolean {
    return ReaderPageCropDetector.pixelKind(x, y, stride, pixels) === background
  }

  private static rowIsBackground(
    y: number,
    width: number,
    _height: number,
    stride: number,
    pixels: Uint8Array,
    background: ReaderPageBackgroundKind,
  ): boolean {
    const allowedContent: number = Math.max(1, Math.floor(width * READER_CROP_LINE_CONTENT_FRACTION))
    let content: number = 0
    for (let x: number = 0; x < width; x++) {
      if (!ReaderPageCropDetector.pixelMatchesBackground(x, y, stride, pixels, background)) {
        content++
        if (content > allowedContent) {
          return false
        }
      }
    }
    return true
  }

  private static columnIsBackground(
    x: number,
    _width: number,
    height: number,
    stride: number,
    pixels: Uint8Array,
    background: ReaderPageBackgroundKind,
  ): boolean {
    const allowedContent: number = Math.max(1, Math.floor(height * READER_CROP_LINE_CONTENT_FRACTION))
    let content: number = 0
    for (let y: number = 0; y < height; y++) {
      if (!ReaderPageCropDetector.pixelMatchesBackground(x, y, stride, pixels, background)) {
        content++
        if (content > allowedContent) {
          return false
        }
      }
    }
    return true
  }
}

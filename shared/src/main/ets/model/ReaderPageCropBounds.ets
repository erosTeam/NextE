const READER_CROP_MAX_EDGE_FRACTION: number = 0.35
const READER_CROP_MIN_RETAINED_FRACTION: number = 0.25
const READER_CROP_EDGE_SAMPLE_COUNT: number = 5
const READER_CROP_EDGE_SAMPLE_MAJORITY: number = 3
const READER_CROP_STRUCTURAL_CONTENT_RUN: number = 2

export enum ReaderPageCropStrength {
  CONSERVATIVE = 'conservative',
  STANDARD = 'standard',
  STRONG = 'strong',
}

enum ReaderPageBackgroundKind {
  NONE = 0,
  TRANSPARENT = 1,
  WHITE = 2,
  BLACK = 3,
}

class ReaderPageCropProfile {
  whiteFloor: number
  blackCeiling: number
  lineContentFraction: number
  safetySamples: number

  constructor(
    whiteFloor: number,
    blackCeiling: number,
    lineContentFraction: number,
    safetySamples: number,
  ) {
    this.whiteFloor = whiteFloor
    this.blackCeiling = blackCeiling
    this.lineContentFraction = lineContentFraction
    this.safetySamples = safetySamples
  }
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
    strength: string = ReaderPageCropStrength.STANDARD,
  ): ReaderPageCropBounds {
    if (width < 4 || height < 4 || stride < width * 4 || pixels.length < stride * height ||
      sourceWidth <= 0 || sourceHeight <= 0) {
      return ReaderPageCropBounds.none(sourceWidth, sourceHeight)
    }
    const profile: ReaderPageCropProfile = ReaderPageCropDetector.profile(strength)
    const topBackground: ReaderPageBackgroundKind = ReaderPageCropDetector.detectEdgeBackground(
      true, true, width, height, stride, pixels, profile,
    )
    const bottomBackground: ReaderPageBackgroundKind = ReaderPageCropDetector.detectEdgeBackground(
      true, false, width, height, stride, pixels, profile,
    )
    const leftBackground: ReaderPageBackgroundKind = ReaderPageCropDetector.detectEdgeBackground(
      false, true, width, height, stride, pixels, profile,
    )
    const rightBackground: ReaderPageBackgroundKind = ReaderPageCropDetector.detectEdgeBackground(
      false, false, width, height, stride, pixels, profile,
    )
    if (topBackground === ReaderPageBackgroundKind.NONE &&
      bottomBackground === ReaderPageBackgroundKind.NONE &&
      leftBackground === ReaderPageBackgroundKind.NONE &&
      rightBackground === ReaderPageBackgroundKind.NONE) {
      return ReaderPageCropBounds.none(sourceWidth, sourceHeight)
    }

    const maxLeft: number = Math.floor(width * READER_CROP_MAX_EDGE_FRACTION)
    const maxTop: number = Math.floor(height * READER_CROP_MAX_EDGE_FRACTION)
    let left: number = 0
    while (leftBackground !== ReaderPageBackgroundKind.NONE && left < maxLeft &&
      ReaderPageCropDetector.columnIsBackground(
      left, width, height, stride, pixels, leftBackground, profile,
    )) {
      left++
    }
    let right: number = width - 1
    while (rightBackground !== ReaderPageBackgroundKind.NONE && right > width - 1 - maxLeft &&
      ReaderPageCropDetector.columnIsBackground(
      right, width, height, stride, pixels, rightBackground, profile,
    )) {
      right--
    }

    // Resolve the vertical edges first. Horizontal scans must not mistake a confirmed left/right
    // border (which may use a different background color) for page content at the row ends.
    if (left >= maxLeft && ReaderPageCropDetector.columnIsBackground(
      left, width, height, stride, pixels, leftBackground, profile,
    )) {
      left = 0
    }
    if (right <= width - 1 - maxLeft && ReaderPageCropDetector.columnIsBackground(
      right, width, height, stride, pixels, rightBackground, profile,
    )) {
      right = width - 1
    }

    let top: number = 0
    while (topBackground !== ReaderPageBackgroundKind.NONE && top < maxTop &&
      ReaderPageCropDetector.rowIsBackground(
      top, width, height, stride, pixels, topBackground, profile, left, right + 1,
    )) {
      top++
    }
    let bottom: number = height - 1
    while (bottomBackground !== ReaderPageBackgroundKind.NONE && bottom > height - 1 - maxTop &&
      ReaderPageCropDetector.rowIsBackground(
      bottom, width, height, stride, pixels, bottomBackground, profile, left, right + 1,
    )) {
      bottom--
    }

    // If one edge reaches the hard scan cap without finding content, disable only that uncertain
    // edge. A reliable edge on the opposite side can still be cropped.
    if (top >= maxTop && ReaderPageCropDetector.rowIsBackground(
      top, width, height, stride, pixels, topBackground, profile, left, right + 1,
    )) {
      top = 0
    }
    if (bottom <= height - 1 - maxTop && ReaderPageCropDetector.rowIsBackground(
      bottom, width, height, stride, pixels, bottomBackground, profile, left, right + 1,
    )) {
      bottom = height - 1
    }

    if (left > 0 && profile.safetySamples > 0) {
      left = Math.max(0, left - profile.safetySamples)
    }
    if (right < width - 1 && profile.safetySamples > 0) {
      right = Math.min(width - 1, right + profile.safetySamples)
    }
    if (top > 0 && profile.safetySamples > 0) {
      top = Math.max(0, top - profile.safetySamples)
    }
    if (bottom < height - 1 && profile.safetySamples > 0) {
      bottom = Math.min(height - 1, bottom + profile.safetySamples)
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

  static normalizeStrength(strength: string): string {
    if (strength === ReaderPageCropStrength.CONSERVATIVE ||
      strength === ReaderPageCropStrength.STRONG) {
      return strength
    }
    return ReaderPageCropStrength.STANDARD
  }

  private static profile(strength: string): ReaderPageCropProfile {
    const normalized: string = ReaderPageCropDetector.normalizeStrength(strength)
    if (normalized === ReaderPageCropStrength.CONSERVATIVE) {
      return new ReaderPageCropProfile(235, 20, 0.01, 1)
    }
    if (normalized === ReaderPageCropStrength.STRONG) {
      return new ReaderPageCropProfile(200, 55, 0.025, 0)
    }
    return new ReaderPageCropProfile(220, 35, 0.01, 0)
  }

  private static detectEdgeBackground(
    horizontal: boolean,
    leading: boolean,
    width: number,
    height: number,
    stride: number,
    pixels: Uint8Array,
    profile: ReaderPageCropProfile,
  ): ReaderPageBackgroundKind {
    const length: number = horizontal ? width : height
    const positions: number[] = [
      1,
      Math.floor(length / 4),
      Math.floor(length / 2),
      Math.floor(length * 3 / 4),
      length - 2,
    ]
    const fixed: number = leading ? 1 : (horizontal ? height : width) - 2
    const counts: number[] = [0, 0, 0, 0]
    for (let i: number = 0; i < READER_CROP_EDGE_SAMPLE_COUNT; i++) {
      const kind: ReaderPageBackgroundKind = ReaderPageCropDetector.pixelKind(
        horizontal ? positions[i] : fixed,
        horizontal ? fixed : positions[i],
        stride,
        pixels,
        profile,
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
    profile: ReaderPageCropProfile,
  ): ReaderPageBackgroundKind {
    const offset: number = y * stride + x * 4
    const r: number = pixels[offset]
    const g: number = pixels[offset + 1]
    const b: number = pixels[offset + 2]
    const a: number = pixels[offset + 3]
    if (a <= 16) {
      return ReaderPageBackgroundKind.TRANSPARENT
    }
    if (r >= profile.whiteFloor && g >= profile.whiteFloor && b >= profile.whiteFloor) {
      return ReaderPageBackgroundKind.WHITE
    }
    if (r <= profile.blackCeiling && g <= profile.blackCeiling && b <= profile.blackCeiling) {
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
    profile: ReaderPageCropProfile,
  ): boolean {
    return ReaderPageCropDetector.pixelKind(x, y, stride, pixels, profile) === background
  }

  private static pixelContentWeight(
    x: number,
    y: number,
    stride: number,
    pixels: Uint8Array,
    background: ReaderPageBackgroundKind,
    profile: ReaderPageCropProfile,
  ): number {
    if (ReaderPageCropDetector.pixelMatchesBackground(x, y, stride, pixels, background, profile)) {
      return 0
    }
    const offset: number = y * stride + x * 4
    const r: number = pixels[offset]
    const g: number = pixels[offset + 1]
    const b: number = pixels[offset + 2]
    const a: number = pixels[offset + 3]
    let contrast: number = 1
    if (background === ReaderPageBackgroundKind.WHITE) {
      contrast = (765 - r - g - b) / 765
    } else if (background === ReaderPageBackgroundKind.BLACK) {
      contrast = (r + g + b) / 765
    } else if (background === ReaderPageBackgroundKind.TRANSPARENT) {
      contrast = a / 255
    }
    return 1 + Math.max(0, Math.min(1, contrast))
  }

  private static rowIsBackground(
    y: number,
    width: number,
    _height: number,
    stride: number,
    pixels: Uint8Array,
    background: ReaderPageBackgroundKind,
    profile: ReaderPageCropProfile,
    start: number = 0,
    end: number = width,
  ): boolean {
    if (background === ReaderPageBackgroundKind.NONE) {
      return false
    }
    const sampled: number = end - start
    const allowedContent: number = Math.max(1, Math.floor(sampled * profile.lineContentFraction))
    let contentWeight: number = 0
    let contentRun: number = 0
    for (let x: number = start; x < end; x++) {
      const weight: number = ReaderPageCropDetector.pixelContentWeight(
        x, y, stride, pixels, background, profile,
      )
      if (weight > 0) {
        contentWeight += weight
        contentRun++
        if (contentRun >= READER_CROP_STRUCTURAL_CONTENT_RUN || contentWeight > allowedContent) {
          return false
        }
      } else {
        contentRun = 0
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
    profile: ReaderPageCropProfile,
  ): boolean {
    if (background === ReaderPageBackgroundKind.NONE) {
      return false
    }
    const start: number = 0
    const end: number = height
    const sampled: number = end - start
    const allowedContent: number = Math.max(1, Math.floor(sampled * profile.lineContentFraction))
    let contentWeight: number = 0
    let contentRun: number = 0
    for (let y: number = start; y < end; y++) {
      const weight: number = ReaderPageCropDetector.pixelContentWeight(
        x, y, stride, pixels, background, profile,
      )
      if (weight > 0) {
        contentWeight += weight
        contentRun++
        if (contentRun >= READER_CROP_STRUCTURAL_CONTENT_RUN || contentWeight > allowedContent) {
          return false
        }
      } else {
        contentRun = 0
      }
    }
    return true
  }
}

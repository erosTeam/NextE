export class ReaderThumbnailSize {
  width: number = 0
  height: number = 0

  constructor(width: number, height: number) {
    this.width = width
    this.height = height
  }
}

/**
 * Reader strip thumbnails share one geometry contract across online sprites and local full images:
 * the row owns a fixed height, while each item's width follows the image's true aspect ratio.
 */
export class ReaderThumbnailGeometry {
  static readonly DISPLAY_HEIGHT: number = 118
  static readonly FALLBACK_ASPECT: number = 0.7

  static fitHeight(
    sourceWidth: number,
    sourceHeight: number,
    displayHeight: number = ReaderThumbnailGeometry.DISPLAY_HEIGHT,
  ): ReaderThumbnailSize {
    const safeHeight: number = displayHeight > 0 ? displayHeight : ReaderThumbnailGeometry.DISPLAY_HEIGHT
    const aspect: number = sourceWidth > 0 && sourceHeight > 0
      ? sourceWidth / sourceHeight
      : ReaderThumbnailGeometry.FALLBACK_ASPECT
    return new ReaderThumbnailSize(safeHeight * aspect, safeHeight)
  }
}

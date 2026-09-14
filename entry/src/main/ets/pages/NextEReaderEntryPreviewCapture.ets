import { image } from '@kit.ImageKit'
import { ReaderEntryPreviewSource, ReaderEntryRect } from '@reader-kit/ui'

/**
 * NextE shell-owned thumbnail snapshot boundary.
 *
 * Gallery code exposes only a live source identity. The app shell validates
 * source geometry and captures the already-rendered thumbnail; reader-kit
 * receives pixels plus an authorization callback, never a NextE component id.
 */
export class NextEReaderEntryPreviewCapture {
  static rect(uiContext: UIContext, componentId: string): ReaderEntryRect {
    const rect = uiContext.getComponentUtils().getRectangleById(componentId)
    return new ReaderEntryRect(uiContext.px2vp(rect.windowOffset.x), uiContext.px2vp(rect.windowOffset.y),
      uiContext.px2vp(rect.size.width), uiContext.px2vp(rect.size.height))
  }

  static sameRect(left: ReaderEntryRect, right: ReaderEntryRect): boolean {
    return left.valid() && right.valid() && left.x === right.x && left.y === right.y &&
      left.width === right.width && left.height === right.height
  }

  static async capture(uiContext: UIContext, snapshotComponentId: string,
    contentKind: 'whole-page' | 'unknown', authorize: (entryId: number) => boolean,
  ): Promise<ReaderEntryPreviewSource | null> {
    let captured: image.PixelMap | null = null
    try {
      const before = uiContext.getComponentUtils().getRectangleById(snapshotComponentId)
      const pixels = await uiContext.getComponentSnapshot().get(snapshotComponentId,
        { waitUntilRenderFinished: true })
      captured = pixels
      const after = uiContext.getComponentUtils().getRectangleById(snapshotComponentId)
      const size = pixels.getImageInfoSync().size
      const rect = new ReaderEntryRect(uiContext.px2vp(after.windowOffset.x), uiContext.px2vp(after.windowOffset.y),
        uiContext.px2vp(after.size.width), uiContext.px2vp(after.size.height))
      if (!rect.valid() || size.width <= 0 || size.height <= 0 ||
        before.windowOffset.x !== after.windowOffset.x || before.windowOffset.y !== after.windowOffset.y ||
        before.size.width !== after.size.width || before.size.height !== after.size.height) {
        void pixels.release()
        captured = null
        return null
      }
      const preview = new ReaderEntryPreviewSource(pixels,
        new ReaderEntryRect(rect.x, rect.y, rect.width, rect.width * size.height / size.width), authorize, contentKind)
      captured = null
      return preview
    } catch (_error) {
      if (captured !== null) void captured.release()
      return null
    }
  }
}

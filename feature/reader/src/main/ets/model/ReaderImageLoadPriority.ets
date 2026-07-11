import { EH_IMAGE_PRIORITY_HIGH, EH_IMAGE_PRIORITY_LOW } from 'shared'

/**
 * Keeps the Reader's foreground image responsive when ArkUI has also created cached page
 * components. The durable file-cache scheduler promotes a queued low-priority task if the same
 * page becomes visible, so this classification never creates a second byte download.
 */
export class ReaderImageLoadPriority {
  static forVisible(visible: boolean): number {
    return visible ? EH_IMAGE_PRIORITY_HIGH : EH_IMAGE_PRIORITY_LOW
  }
}

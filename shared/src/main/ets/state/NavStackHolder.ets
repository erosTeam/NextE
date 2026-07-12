import { AppStorageV2 } from '@kit.ArkUI'
import { installGalleryDetailDuplicateInterception } from '../navigation/GalleryDetailNavigation'

/**
 * V2-safe holder for the app's single `NavPathStack` (pattern from V2Next).
 *
 * `stack` is never observed as reactive state — consumers use it purely as a method target
 * (pushPathByName / pop); `NavPathStack` self-manages the observation that Navigation binds to.
 * `isSplitMode` is separate, presentation-only state published by the root HDS container for
 * destination-level controls that need the resolved physical mode.
 */
@ObservedV2
export class NavStackHolder {
  @Trace stack: NavPathStack = new NavPathStack()
  @Trace isSplitMode: boolean = false

  constructor() {
    installGalleryDetailDuplicateInterception(this.stack)
  }

  setSplitMode(isSplitMode: boolean): void {
    if (this.isSplitMode === isSplitMode) {
      return
    }
    this.isSplitMode = isSplitMode
  }
}

const NAV_STACK_KEY: string = 'v2:navStack'

export function connectNavStack(): NavStackHolder {
  return AppStorageV2.connect(NavStackHolder, NAV_STACK_KEY, () => new NavStackHolder())!
}

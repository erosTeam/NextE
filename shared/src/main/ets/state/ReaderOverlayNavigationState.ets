import { AppStorageV2 } from '@kit.ArkUI'
import { ReaderParams } from '../model/RouteParams'
import { connectReaderThumbnailTransition } from './ReaderThumbnailTransitionState'

/**
 * Owns Reader's full-window navigation stack independently of the adaptive root HDS navigation.
 *
 * The root split remains mounted and keeps its geometry while Reader is visible. The next open
 * clears this private stack before mounting it again, so close never clears a stack during teardown.
 */
@ObservedV2
export class ReaderOverlayNavigationState {
  @Trace visible: boolean = false
  @Trace stack: NavPathStack = new NavPathStack()
  // Detail observes the start of the exit transition so it can reveal the already-persisted final
  // progress without reacting to Reader's live writes while the overlay is open.
  @Trace closing: boolean = false
  private pendingReader: ReaderParams | null = null
  private pendingReaderAnimated: boolean = true

  open(params: ReaderParams, animated: boolean = true): void {
    this.stack.clear(false)
    this.stack.pushPathByName('ReaderOverlayBackdrop', null, false)
    this.pendingReader = params
    this.pendingReaderAnimated = animated
    this.closing = false
    this.visible = true
  }

  presentPendingReader(): void {
    const params: ReaderParams | null = this.pendingReader
    if (!this.visible || this.closing || params === null) {
      return
    }
    this.pendingReader = null
    this.stack.pushPathByName('Reader', params, this.pendingReaderAnimated)
    this.pendingReaderAnimated = true
  }

  openGestureProbe(): void {
    this.stack.clear(false)
    this.stack.pushPathByName('ReaderGestureProbe', null, false)
    this.pendingReader = null
    this.pendingReaderAnimated = true
    this.closing = false
    this.visible = true
  }

  close(animated: boolean = true): void {
    if (!this.visible || this.closing) {
      return
    }
    this.pendingReader = null
    if (this.stack.getAllPathName().length === 0) {
      this.finishClose()
      return
    }
    this.closing = true
    this.stack.pop(animated)
  }

  finishClose(): void {
    if (!this.closing) {
      return
    }
    this.closing = false
    this.visible = false
    this.stack.clear(false)
    this.pendingReaderAnimated = true
    connectReaderThumbnailTransition().reset()
  }

  reset(): void {
    this.pendingReader = null
    this.pendingReaderAnimated = true
    this.closing = false
    this.visible = false
    this.stack.clear(false)
    connectReaderThumbnailTransition().reset()
  }
}

const READER_OVERLAY_NAVIGATION_KEY: string = 'v2_readerOverlayNavigation'

export function connectReaderOverlayNavigation(): ReaderOverlayNavigationState {
  return AppStorageV2.connect(
    ReaderOverlayNavigationState,
    READER_OVERLAY_NAVIGATION_KEY,
    () => new ReaderOverlayNavigationState(),
  )!
}

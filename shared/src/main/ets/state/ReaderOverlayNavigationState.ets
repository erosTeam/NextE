import { AppStorageV2 } from '@kit.ArkUI'
import { ReaderParams } from '../model/RouteParams'

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
  private pendingReader: ReaderParams | null = null
  private closing: boolean = false

  open(params: ReaderParams): void {
    this.stack.clear(false)
    this.stack.pushPathByName('ReaderOverlayBackdrop', null, false)
    this.pendingReader = params
    this.closing = false
    this.visible = true
  }

  presentPendingReader(): void {
    const params: ReaderParams | null = this.pendingReader
    if (!this.visible || this.closing || params === null) {
      return
    }
    this.pendingReader = null
    this.stack.pushPathByName('Reader', params, true)
  }

  openGestureProbe(): void {
    this.stack.clear(false)
    this.stack.pushPathByName('ReaderGestureProbe', null, false)
    this.pendingReader = null
    this.closing = false
    this.visible = true
  }

  close(): void {
    if (!this.visible || this.closing) {
      return
    }
    this.pendingReader = null
    if (this.stack.getAllPathName().length === 0) {
      this.finishClose()
      return
    }
    this.closing = true
    this.stack.pop(true)
  }

  finishClose(): void {
    if (!this.closing) {
      return
    }
    this.closing = false
    this.visible = false
    this.stack.clear(false)
  }

  reset(): void {
    this.pendingReader = null
    this.closing = false
    this.visible = false
    this.stack.clear(false)
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

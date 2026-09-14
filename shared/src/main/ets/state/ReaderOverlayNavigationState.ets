import { AppStorageV2 } from '@kit.ArkUI'
import { ReaderParams } from '../model/RouteParams'
import { NextEReaderBackend, connectNextEReaderBackendSelection } from './NextEReaderBackendSelectionState'
import { connectReaderThumbnailTransition } from './ReaderThumbnailTransitionState'

/** Host-owned route envelope; reader-kit never chooses the app implementation. */
export class ReaderOverlayRoute {
  params: ReaderParams
  backend: NextEReaderBackend

  constructor(params: ReaderParams, backend: NextEReaderBackend) {
    this.params = params
    this.backend = backend
  }
}

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
  // Overlay lifecycle only. Reader progress publication is gated by Reader presentation ownership;
  // GalleryDetail must not derive its update timing from this closing flag.
  @Trace closing: boolean = false
  private pendingReader: ReaderOverlayRoute | null = null
  private pendingReaderAnimated: boolean = true

  open(params: ReaderParams, animated: boolean = true): void {
    this.stack.clear(false)
    this.stack.pushPathByName('ReaderOverlayBackdrop', null, false)
    // Snapshot the Debug-only rehearsal choice at admission. An open session
    // cannot switch implementation when the settings row changes later. The
    // existing thumbnail-flight coordinator still speaks the legacy Reader's
    // readiness/close protocol, so that active path remains on legacy until a
    // neutral transition host is connected to the shared production route.
    const requested = connectNextEReaderBackendSelection().current()
    const backend = requested === NextEReaderBackend.SHARED && connectReaderThumbnailTransition().active()
      ? NextEReaderBackend.LEGACY
      : requested
    this.pendingReader = new ReaderOverlayRoute(params, backend)
    this.pendingReaderAnimated = animated
    this.closing = false
    this.visible = true
  }

  /** Root-host-only entry after a live shared thumbnail source was claimed. */
  openSharedTransition(params: ReaderParams, animated: boolean = false): void {
    this.stack.clear(false)
    this.stack.pushPathByName('ReaderOverlayBackdrop', null, false)
    this.pendingReader = new ReaderOverlayRoute(params, NextEReaderBackend.SHARED)
    this.pendingReaderAnimated = animated
    this.closing = false
    this.visible = true
  }

  presentPendingReader(): void {
    const route: ReaderOverlayRoute | null = this.pendingReader
    if (!this.visible || this.closing || route === null) {
      return
    }
    this.pendingReader = null
    if (route.backend === NextEReaderBackend.SHARED) {
      this.stack.pushPathByName('ReaderShared', route, this.pendingReaderAnimated)
    } else {
      // Keep the accepted legacy destination contract byte-for-byte: it reads
      // ReaderParams from NavDestinationContext itself.
      this.stack.pushPathByName('Reader', route.params, this.pendingReaderAnimated)
    }
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

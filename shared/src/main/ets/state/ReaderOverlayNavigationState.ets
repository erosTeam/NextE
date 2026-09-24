import { AppStorageV2 } from '@kit.ArkUI'
import { ReaderParams } from '../model/RouteParams'
import { NextEReaderBackend, resolveNextEReaderBackendSelection } from './NextEReaderBackendSelectionState'
import { connectReaderThumbnailTransition } from './ReaderThumbnailTransitionState'

/** Host-owned route envelope; reader-kit never chooses the app implementation. */
export class ReaderOverlayRoute {
  params: ReaderParams
  backend: NextEReaderBackend
  liveSourceEntry: boolean
  epoch: number

  constructor(params: ReaderParams, backend: NextEReaderBackend, liveSourceEntry: boolean = false,
    epoch: number = 0) {
    this.params = params
    this.backend = backend
    this.liveSourceEntry = liveSourceEntry
    this.epoch = epoch
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
  private routeEpoch: number = 0
  private currentReaderEpoch: number = 0

  open(params: ReaderParams, animated: boolean = true, liveSourceEntry: boolean = false): void {
    this.stack.clear(false)
    this.stack.pushPathByName('ReaderOverlayBackdrop', null, false)
    // Snapshot the admission-time authority (durable user choice, or an active
    // rehearsal override) so an open session cannot switch implementation when
    // the settings row changes later. An explicit durable legacy choice stays
    // legacy; durable shared is no longer silently downgraded to legacy just
    // because a thumbnail flight is active (that implicit downgrade was the
    // release tile-entry defect). Claimed production entries, preview-failure
    // fallbacks and their entry logs keep their existing chains unchanged.
    const backend = resolveNextEReaderBackendSelection()
    const liveSource = backend === NextEReaderBackend.SHARED && liveSourceEntry && params.source.isLocal()
    this.currentReaderEpoch = ++this.routeEpoch
    this.pendingReader = new ReaderOverlayRoute(params, backend, liveSource, this.currentReaderEpoch)
    // A retained local source supplies pixels during the default destination push.
    // The Reader's own reveal gate still decides when its original replaces that source.
    this.pendingReaderAnimated = animated
    this.closing = false
    this.visible = true
  }

  /** Root-host-only entry after a live shared thumbnail source was claimed. */
  openSharedTransition(params: ReaderParams, animated: boolean = false): void {
    this.stack.clear(false)
    this.stack.pushPathByName('ReaderOverlayBackdrop', null, false)
    this.currentReaderEpoch = ++this.routeEpoch
    this.pendingReader = new ReaderOverlayRoute(params, NextEReaderBackend.SHARED, false,
      this.currentReaderEpoch)
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
    this.currentReaderEpoch = 0
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

  owns(route: ReaderOverlayRoute): boolean {
    return this.visible && !this.closing && route.epoch > 0 && this.currentReaderEpoch === route.epoch
  }

  finishClose(): void {
    if (!this.closing) {
      return
    }
    this.closing = false
    this.visible = false
    this.currentReaderEpoch = 0
    this.stack.clear(false)
    this.pendingReaderAnimated = true
    connectReaderThumbnailTransition().reset()
  }

  reset(): void {
    this.pendingReader = null
    this.pendingReaderAnimated = true
    this.closing = false
    this.visible = false
    this.currentReaderEpoch = 0
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

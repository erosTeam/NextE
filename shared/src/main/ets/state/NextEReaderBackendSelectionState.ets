import { Want } from '@kit.AbilityKit'
import { AppStorageV2 } from '@kit.ArkUI'

export enum NextEReaderBackend {
  LEGACY = 'legacy',
  SHARED = 'shared',
}

/**
 * Process-local replacement rehearsal selector.
 *
 * It is deliberately separate from durable Reader settings. The overlay host
 * snapshots the value when it admits a route, so changing the selector cannot
 * replace an already-open Reader implementation.
 */
@ObservedV2
export class NextEReaderBackendSelectionState {
  @Trace version: number = 0
  private backend: NextEReaderBackend = NextEReaderBackend.LEGACY

  current(): NextEReaderBackend {
    return this.backend
  }

  selectForRehearsal(backend: NextEReaderBackend, debugBuild: boolean): NextEReaderBackend {
    const accepted = debugBuild && backend === NextEReaderBackend.SHARED
      ? NextEReaderBackend.SHARED
      : NextEReaderBackend.LEGACY
    if (this.backend !== accepted) {
      this.backend = accepted
      this.version += 1
    }
    return this.backend
  }
}

const NEXT_E_READER_BACKEND_SELECTION_KEY: string = 'v2_nextEReaderBackendSelection'

export function connectNextEReaderBackendSelection(): NextEReaderBackendSelectionState {
  return AppStorageV2.connect(
    NextEReaderBackendSelectionState,
    NEXT_E_READER_BACKEND_SELECTION_KEY,
    (): NextEReaderBackendSelectionState => new NextEReaderBackendSelectionState(),
  )!
}

/**
 * Explicit Debug Want only. Every ordinary or release launch returns the
 * process to Legacy, preventing an interrupted rehearsal from leaking into a
 * later normal session.
 */
export function captureNextEReaderBackendWant(want: Want, debugBuild: boolean): void {
  const state = connectNextEReaderBackendSelection()
  const supplied = want.parameters?.['nexte_reader_backend']
  state.selectForRehearsal(
    supplied === NextEReaderBackend.SHARED ? NextEReaderBackend.SHARED : NextEReaderBackend.LEGACY,
    debugBuild,
  )
}

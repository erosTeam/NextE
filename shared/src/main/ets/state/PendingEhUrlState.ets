import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Single-writer command bus for deep-linked / clipboard EH URLs.
 *
 * `EntryAbility.captureIncomingUrl` is the sole writer: it publishes `${timestamp}:${uri}`
 * so every signal is unique and the consumer's @Monitor always fires (even for the same
 * URL twice). `Index` reads it and routes via EhRouteNavigator. This is the canonical
 * V2Next cross-component signalling shape (timestamped payload + @Monitor reactor).
 */
@ObservedV2
export class PendingEhUrlState {
  @Trace signal: string = ''
}

const PENDING_EH_URL_KEY: string = 'v2_pendingEhUrl'

export function connectPendingEhUrl(): PendingEhUrlState {
  return AppStorageV2.connect(PendingEhUrlState, PENDING_EH_URL_KEY, () => new PendingEhUrlState())!
}

/** The ONLY writer of the pending-EH-URL signal. */
export function publishPendingEhUrl(signal: string): void {
  connectPendingEhUrl().signal = signal
}

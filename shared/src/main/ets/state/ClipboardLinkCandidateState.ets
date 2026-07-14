import { AppStorageV2 } from '@kit.ArkUI'

/** One-shot command bus from the foreground clipboard probe to the root HDS prompt owner. */
@ObservedV2
export class ClipboardLinkCandidateState {
  @Trace signal: string = ''
}

const CLIPBOARD_LINK_CANDIDATE_KEY: string = 'v2_clipboardLinkCandidate'

export function connectClipboardLinkCandidate(): ClipboardLinkCandidateState {
  return AppStorageV2.connect(
    ClipboardLinkCandidateState,
    CLIPBOARD_LINK_CANDIDATE_KEY,
    () => new ClipboardLinkCandidateState(),
  )!
}

export function publishClipboardLinkCandidate(url: string): void {
  connectClipboardLinkCandidate().signal = `${Date.now()}:${url}`
}

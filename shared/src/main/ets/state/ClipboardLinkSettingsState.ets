import { AppStorageV2 } from '@kit.ArkUI'

/** Runtime mirror for the opt-in clipboard-link detector and its deduplication cursor. */
@ObservedV2
export class ClipboardLinkSettingsState {
  @Trace enabled: boolean = false
  @Trace lastChangeCount: number = -1
}

const CLIPBOARD_LINK_SETTINGS_KEY: string = 'v2_clipboardLinkSettings'

export function connectClipboardLinkSettings(): ClipboardLinkSettingsState {
  return AppStorageV2.connect(
    ClipboardLinkSettingsState,
    CLIPBOARD_LINK_SETTINGS_KEY,
    () => new ClipboardLinkSettingsState(),
  )!
}

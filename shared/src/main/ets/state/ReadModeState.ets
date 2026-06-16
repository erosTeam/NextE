import { AppStorageV2 } from '@kit.ArkUI'

/** Reader page-turn direction / layout (eros_fe ViewMode). */
export enum ReadMode {
  LTR = 'ltr', // horizontal, page 1 on the left (default)
  RTL = 'rtl', // horizontal, page 1 on the right (manga)
  VERTICAL = 'vertical', // top-to-bottom continuous scroll (webtoon)
}

/**
 * Reactive reader direction. Restored from preferences (ReadModeSettings) at startup; the
 * ReaderPage reads it to switch between the horizontal Swiper (LTR/RTL) and the vertical List.
 */
@ObservedV2
export class ReadModeState {
  @Trace mode: string = ReadMode.LTR
}

const READ_MODE_KEY: string = 'v2:readMode'

export function connectReadMode(): ReadModeState {
  return AppStorageV2.connect(ReadModeState, READ_MODE_KEY, () => new ReadModeState())!
}

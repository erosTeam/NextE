import { AppStorageV2 } from '@kit.ArkUI'

/** Reader page-turn direction / layout (eros_fe ViewMode). */
export enum ReadMode {
  LTR = 'ltr', // horizontal, page 1 on the left (default)
  RTL = 'rtl', // horizontal, page 1 on the right (manga)
  TOP_TO_BOTTOM = 'topToBottom', // vertical page-by-page
  VERTICAL = 'vertical', // top-to-bottom continuous scroll (webtoon)
}

export enum ReadColumnMode {
  SINGLE = 'single',
  ODD_LEFT = 'oddLeft',
  EVEN_LEFT = 'evenLeft',
}

/**
 * Reactive reader direction + horizontal double-page mode. Restored from preferences at startup; the
 * ReaderPage reads it to switch between paged Swiper (LTR/RTL/top-to-bottom), continuous vertical
 * List, and horizontal single/double-page spread.
 */
@ObservedV2
export class ReadModeState {
  @Trace mode: string = ReadMode.LTR
  @Trace doublePageEnabled: boolean = false
  @Trace columnMode: string = ReadColumnMode.SINGLE
  @Trace autoPageSeconds: number = 3
  @Trace preloadPages: number = 2
  @Trace volumeKeyTurn: boolean = false
}

const READ_MODE_KEY: string = 'v2:readMode'

export function connectReadMode(): ReadModeState {
  return AppStorageV2.connect(ReadModeState, READ_MODE_KEY, () => new ReadModeState())!
}

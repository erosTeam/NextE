import { AppStorageV2 } from '@kit.ArkUI'
import { ReaderTapZoneInvert, ReaderTapZoneLayout } from '../utils/ReaderTapZoneResolver'

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

export enum ReadSpreadLayout {
  JOINED = 'joined',
  SPLIT = 'split',
}

export enum ReaderBackgroundMode {
  BLACK = 'black',
  GRAY = 'gray',
  WHITE = 'white',
  AUTO = 'auto',
}

export enum ReaderImageScalingQuality {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high',
}

/**
 * Reader super-resolution backend. Only backends that can execute in the current build belong here;
 * downloadable ncnn models are added after their native runtime and model package are validated.
 */
export enum ReaderSuperResolutionModel {
  NONE = 'none',
  WAIFU2X_PHOTO_NOISE0_2X = 'waifu2xPhotoNoise0_2x',
  WAIFU2X_ART_NOISE0_2X = 'waifu2xArtNoise0_2x',
  WAIFU2X_CUNET_NOISE0_2X = 'waifu2xCunetNoise0_2x',
  REAL_CUGAN_SE_2X_CONSERVATIVE = 'realCuganSe2xConservative',
  REAL_ESRGAN_X2PLUS = 'realEsrganX2plus',
  REAL_ESRGAN_ANIMEVIDEO_V3_X2 = 'realEsrganAnimeVideoV3_2x',
}

export enum ReaderSuperResolutionBackend {
  AUTO = 'auto',
  VULKAN = 'vulkan',
  CPU = 'cpu',
}

export const READER_SUPER_RESOLUTION_MAX_SOURCE_HEIGHT: number = 2000

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
  @Trace spreadLayoutMode: string = ReadSpreadLayout.JOINED
  @Trace autoPageSeconds: number = 3
  @Trace preloadPages: number = 2
  @Trace volumeKeyTurn: boolean = false
  @Trace tapZoneLayout: string = ReaderTapZoneLayout.RIGHT_LEFT
  @Trace tapZoneInvert: string = ReaderTapZoneInvert.NONE
  @Trace backgroundMode: string = ReaderBackgroundMode.BLACK
  @Trace imageScalingQuality: string = ReaderImageScalingQuality.MEDIUM
  @Trace superResolutionEnabled: boolean = false
  @Trace superResolutionModel: string = ReaderSuperResolutionModel.NONE
  @Trace superResolutionBackend: string = ReaderSuperResolutionBackend.AUTO
  @Trace superResolutionMaxHeight: number = READER_SUPER_RESOLUTION_MAX_SOURCE_HEIGHT
  @Trace showPageNumber: boolean = true
  @Trace fullscreen: boolean = true
  @Trace keepScreenOn: boolean = true
  @Trace pageTurnAnimation: boolean = true
}

const READ_MODE_KEY: string = 'v2_readMode'

export function connectReadMode(): ReadModeState {
  return AppStorageV2.connect(ReadModeState, READ_MODE_KEY, () => new ReadModeState())!
}

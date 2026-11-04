import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { AppStorageV2 } from '@kit.ArkUI'
import { ReaderImageEffects } from '@reader-kit/ui'
import { ReaderDisplaySettings, normalizeReaderDisplaySettings, parseReaderDisplaySettings,
  readerDisplayDimOpacity } from '../model/ReaderDisplaySettings'

const STORE_NAME: string = 'nexte_settings'
const KEY_DISPLAY_SETTINGS: string = 'reader.displaySettings'

/** Display preferences are device-local during use and included in manual settings backup.
 * A slider draft and the current sheet geometry are never written to disk. */
@ObservedV2
export class ReaderDisplayState {
  @Trace settings: ReaderDisplaySettings = new ReaderDisplaySettings()
  @Trace preview: ReaderDisplaySettings | null = null
  @Trace filterTabActive: boolean = false
  @Trace filterSheetHeight: number = 0
  private pendingWrite: Promise<void> = Promise.resolve()
  private revision: number = 0
  private loadEpoch: number = 0

  effective(): ReaderDisplaySettings { return this.preview ?? this.settings }

  async load(context: common.UIAbilityContext): Promise<void> {
    const epoch = ++this.loadEpoch
    const revision = this.revision
    try {
      await this.pendingWrite
      const store = await preferences.getPreferences(context, STORE_NAME)
      const value = store.getSync(KEY_DISPLAY_SETTINGS, '') as string
      if (epoch === this.loadEpoch && revision === this.revision) this.settings = parseReaderDisplaySettings(value)
    } catch (_) {
      console.warn('[ReaderDisplay] preferences load failed')
    }
  }

  save(context: common.UIAbilityContext, settings: ReaderDisplaySettings): void {
    this.settings = normalizeReaderDisplaySettings(settings)
    this.revision += 1
    const value = JSON.stringify(this.settings)
    this.pendingWrite = this.pendingWrite.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, STORE_NAME)
      store.putSync(KEY_DISPLAY_SETTINGS, value)
      await store.flush()
    }).catch((): void => { console.warn('[ReaderDisplay] preferences save failed') })
  }

  closePreview(): void {
    this.preview = null
    this.filterTabActive = false
    this.filterSheetHeight = 0
  }
}

export function connectReaderDisplay(): ReaderDisplayState {
  return AppStorageV2.connect(ReaderDisplayState, 'nexte_settings:readerDisplay',
    (): ReaderDisplayState => new ReaderDisplayState())!
}

export function readerImageEffects(settings: ReaderDisplaySettings): ReaderImageEffects {
  const effects = new ReaderImageEffects()
  effects.grayscale = settings.grayscale
  effects.inverted = settings.inverted
  effects.tint = settings.filterEnabled && settings.alpha > 0
  effects.tintColor = `rgba(${settings.red},${settings.green},${settings.blue},${settings.alpha / 255})`
  effects.blendMode = settings.blendMode === 'multiply' ? BlendMode.MODULATE :
    settings.blendMode === 'screen' ? BlendMode.SCREEN : settings.blendMode === 'overlay' ? BlendMode.OVERLAY :
      settings.blendMode === 'lighten' ? BlendMode.LIGHTEN : settings.blendMode === 'darken' ? BlendMode.DARKEN :
        BlendMode.SRC_OVER
  effects.dimOpacity = readerDisplayDimOpacity(settings)
  return effects
}

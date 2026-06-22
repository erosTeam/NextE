import { AppStorageV2 } from '@kit.ArkUI'

export const TAG_TRANSLATION_UPDATE_MANUAL: string = 'manual'
export const TAG_TRANSLATION_UPDATE_EVERY_START: string = 'everyStartApp'

@ObservedV2
export class TagTranslationSettingsState {
  @Trace enabled: boolean = false
  @Trace useCdn: boolean = false
  @Trace updateMode: string = TAG_TRANSLATION_UPDATE_MANUAL
  @Trace version: string = ''
  @Trace rowCount: number = 0
}

const TAG_TRANSLATION_SETTINGS_KEY: string = 'v2:tagTranslationSettings'

export function connectTagTranslationSettings(): TagTranslationSettingsState {
  return AppStorageV2.connect(
    TagTranslationSettingsState,
    TAG_TRANSLATION_SETTINGS_KEY,
    () => new TagTranslationSettingsState(),
  )!
}

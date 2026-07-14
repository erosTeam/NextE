import { AppStorageV2 } from '@kit.ArkUI'

export const TAG_TRANSLATION_UPDATE_MANUAL: string = 'manual'
export const TAG_TRANSLATION_UPDATE_EVERY_START: string = 'everyStartApp'
export const TAG_INTRO_IMAGE_DISABLE: string = 'disable'
export const TAG_INTRO_IMAGE_NON_H: string = 'nonh'
export const TAG_INTRO_IMAGE_R18: string = 'r18'
export const TAG_INTRO_IMAGE_R18G: string = 'r18g'

@ObservedV2
export class TagTranslationSettingsState {
  @Trace enabled: boolean = false
  @Trace useCdn: boolean = false
  @Trace updateMode: string = TAG_TRANSLATION_UPDATE_MANUAL
  @Trace introImageLevel: string = TAG_INTRO_IMAGE_NON_H
  @Trace version: string = ''
  @Trace rowCount: number = 0
}

// AppStorageV2 keys accept only letters, digits, and underscores. This state is connected by every
// rich gallery card, so an invalid key would also emit repeated state-management warnings while scrolling.
const TAG_TRANSLATION_SETTINGS_KEY: string = 'v2_tagTranslationSettings'

export function connectTagTranslationSettings(): TagTranslationSettingsState {
  return AppStorageV2.connect(
    TagTranslationSettingsState,
    TAG_TRANSLATION_SETTINGS_KEY,
    () => new TagTranslationSettingsState(),
  )!
}

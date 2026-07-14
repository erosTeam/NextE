import { AppStorageV2 } from '@kit.ArkUI'

export const COMMENT_TRANSLATION_DISPLAY_REPLACE: string = 'replace'
export const COMMENT_TRANSLATION_DISPLAY_BILINGUAL: string = 'bilingual'

/** Comment translation settings. Settings writer is the only persistent mutator. */
@ObservedV2
export class CommentTranslationSettingsState {
  @Trace enabled: boolean = false
  @Trace autoTranslate: boolean = false
  @Trace displayMode: string = COMMENT_TRANSLATION_DISPLAY_REPLACE
  @Trace useGoogleOnly: boolean = false
  @Trace apiUrl: string = ''
  @Trace apiKey: string = ''
  @Trace model: string = ''
}

const COMMENT_TRANSLATION_SETTINGS_KEY: string = 'v2_commentTranslationSettings'

export function connectCommentTranslationSettings(): CommentTranslationSettingsState {
  return AppStorageV2.connect(
    CommentTranslationSettingsState,
    COMMENT_TRANSLATION_SETTINGS_KEY,
    () => new CommentTranslationSettingsState(),
  )!
}

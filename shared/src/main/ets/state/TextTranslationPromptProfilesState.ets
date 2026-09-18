import { AppStorageV2 } from '@kit.ArkUI'
import {
  TEXT_TRANSLATION_PROMPT_BUILTIN_IDS,
  TextTranslationPromptCatalog,
} from '../services/TextTranslationPromptCatalog'
import {
  TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION,
  TextTranslationPromptProfile,
} from '../model/TextTranslationPromptProfile'

/**
 * V2 mirror of the persisted custom prompt store plus the single shared selection. Only the
 * repository may write; the UI and runtime services read isolated copies.
 */
@ObservedV2
export class TextTranslationPromptProfilesState {
  @Trace customProfiles: TextTranslationPromptProfile[] = []
  @Trace selectedPromptProfileId: string = TextTranslationPromptCatalog.defaultProfileId()

  /** Built-ins first (code-defined), then every custom. Always fresh copies. */
  allProfiles(): TextTranslationPromptProfile[] {
    const profiles: TextTranslationPromptProfile[] = TextTranslationPromptCatalog.builtInProfiles()
    for (let index: number = 0; index < this.customProfiles.length; index++) {
      profiles.push(this.customProfiles[index].copy())
    }
    return profiles
  }

  /** The resolved current selection; an invalid or missing id falls back to standard. */
  selectedProfile(): TextTranslationPromptProfile {
    const found: TextTranslationPromptProfile | null = this.findById(this.selectedPromptProfileId)
    if (found !== null) {
      return found
    }
    return TextTranslationPromptCatalog.defaultProfile()
  }

  findById(promptProfileId: string): TextTranslationPromptProfile | null {
    if (TEXT_TRANSLATION_PROMPT_BUILTIN_IDS.indexOf(promptProfileId) >= 0) {
      return TextTranslationPromptCatalog.findBuiltInById(promptProfileId)
    }
    for (let index: number = 0; index < this.customProfiles.length; index++) {
      if (this.customProfiles[index].promptProfileId === promptProfileId) {
        return this.customProfiles[index].copy()
      }
    }
    return null
  }
}

const TEXT_TRANSLATION_PROMPT_PROFILES_STATE_KEY: string = 'v2_textTranslationPromptProfiles'

export function connectTextTranslationPromptProfiles(): TextTranslationPromptProfilesState {
  return AppStorageV2.connect(
    TextTranslationPromptProfilesState,
    TEXT_TRANSLATION_PROMPT_PROFILES_STATE_KEY,
    () => new TextTranslationPromptProfilesState(),
  )!
}

import {
  TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION,
  TextTranslationPromptProfile,
} from '../model/TextTranslationPromptProfile'
import { AppStrings } from '../i18n/AppStrings'

export const TEXT_TRANSLATION_PROMPT_BUILTIN_STANDARD: string = 'builtin.standard'
export const TEXT_TRANSLATION_PROMPT_BUILTIN_FAITHFUL: string = 'builtin.faithful'
export const TEXT_TRANSLATION_PROMPT_BUILTIN_NATURAL: string = 'builtin.natural'
export const TEXT_TRANSLATION_PROMPT_BUILTIN_PROPER_NOUN_SAFE: string = 'builtin.proper_noun_safe'
export const TEXT_TRANSLATION_PROMPT_BUILTIN_IDS: string[] = [
  TEXT_TRANSLATION_PROMPT_BUILTIN_STANDARD,
  TEXT_TRANSLATION_PROMPT_BUILTIN_FAITHFUL,
  TEXT_TRANSLATION_PROMPT_BUILTIN_NATURAL,
  TEXT_TRANSLATION_PROMPT_BUILTIN_PROPER_NOUN_SAFE,
]

// Independent style notes per built-in (V1, all at revision 1). Changing any style text must
// bump that profile's revision; changing only the localized display name must not.
const BUILTIN_STANDARD_REVISION: number = 1
const BUILTIN_FAITHFUL_REVISION: number = 1
const BUILTIN_NATURAL_REVISION: number = 1
const BUILTIN_PROPER_NOUN_SAFE_REVISION: number = 1

const BUILTIN_STANDARD_STYLE: string =
  'Translate accurately and naturally. Preserve the original tone.'
const BUILTIN_FAITHFUL_STYLE: string =
  'Preserve every detail, qualifier, repetition, uncertainty, and intensity. Do not summarize or omit content.'
const BUILTIN_NATURAL_STYLE: string =
  'Prefer fluent, idiomatic target-language wording over literal syntax while preserving meaning, tone, and intensity.'
const BUILTIN_PROPER_NOUN_SAFE_STYLE: string =
  'Keep uncertain names, handles, titles, group names, product names, and other proper nouns in the source form. ' +
  'Translate or transliterate them only when a conventional target-language form is clear.'

/**
 * Code-defined built-in prompt profiles. They are always read-only, never persisted, and every
 * accessor returns fresh copies so neither the runtime nor a UI draft can mutate the catalog.
 * Display names resolve through localized resources; IDs and revisions are stable code constants.
 */
export class TextTranslationPromptCatalog {
  /** True only for the four ids this catalog actually defines. */
  static isBuiltInId(promptProfileId: string): boolean {
    return TEXT_TRANSLATION_PROMPT_BUILTIN_IDS.indexOf(promptProfileId) >= 0
  }

  static defaultProfileId(): string {
    return TEXT_TRANSLATION_PROMPT_BUILTIN_STANDARD
  }

  static builtInProfiles(): TextTranslationPromptProfile[] {
    const profiles: TextTranslationPromptProfile[] = []
    profiles.push(TextTranslationPromptCatalog.builtIn(
      TEXT_TRANSLATION_PROMPT_BUILTIN_STANDARD,
      'text_translation_prompt_builtin_standard',
      BUILTIN_STANDARD_STYLE,
      BUILTIN_STANDARD_REVISION,
    ))
    profiles.push(TextTranslationPromptCatalog.builtIn(
      TEXT_TRANSLATION_PROMPT_BUILTIN_FAITHFUL,
      'text_translation_prompt_builtin_faithful',
      BUILTIN_FAITHFUL_STYLE,
      BUILTIN_FAITHFUL_REVISION,
    ))
    profiles.push(TextTranslationPromptCatalog.builtIn(
      TEXT_TRANSLATION_PROMPT_BUILTIN_NATURAL,
      'text_translation_prompt_builtin_natural',
      BUILTIN_NATURAL_STYLE,
      BUILTIN_NATURAL_REVISION,
    ))
    profiles.push(TextTranslationPromptCatalog.builtIn(
      TEXT_TRANSLATION_PROMPT_BUILTIN_PROPER_NOUN_SAFE,
      'text_translation_prompt_builtin_proper_noun_safe',
      BUILTIN_PROPER_NOUN_SAFE_STYLE,
      BUILTIN_PROPER_NOUN_SAFE_REVISION,
    ))
    return profiles
  }

  static findBuiltInById(promptProfileId: string): TextTranslationPromptProfile | null {
    const profiles: TextTranslationPromptProfile[] = TextTranslationPromptCatalog.builtInProfiles()
    for (let index: number = 0; index < profiles.length; index++) {
      if (profiles[index].promptProfileId === promptProfileId) {
        return profiles[index]
      }
    }
    return null
  }

  static defaultProfile(): TextTranslationPromptProfile {
    const profile: TextTranslationPromptProfile | null =
      TextTranslationPromptCatalog.findBuiltInById(TextTranslationPromptCatalog.defaultProfileId())
    if (profile === null) {
      throw new Error('Built-in standard prompt profile is missing')
    }
    return profile
  }

  private static builtIn(
    promptProfileId: string,
    displayResourceKey: string,
    styleInstructions: string,
    promptRevision: number,
  ): TextTranslationPromptProfile {
    const profile: TextTranslationPromptProfile = new TextTranslationPromptProfile()
    profile.schemaVersion = TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION
    profile.promptProfileId = promptProfileId
    profile.displayName = AppStrings.get(displayResourceKey)
    profile.styleInstructions = styleInstructions
    profile.promptRevision = promptRevision
    profile.builtIn = true
    profile.createdAt = 0
    profile.updatedAt = 0
    return profile
  }
}

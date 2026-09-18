import {
  TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION,
  TextTranslationPromptProfile,
} from '../model/TextTranslationPromptProfile'

export const MAX_TEXT_TRANSLATION_CUSTOM_PROFILES: number = 32
export const MAX_TEXT_TRANSLATION_PROMPT_ID_CHARS: number = 160
export const MAX_TEXT_TRANSLATION_PROMPT_NAME_CHARS: number = 120
export const MAX_TEXT_TRANSLATION_STYLE_CHARS: number = 8192
export const MAX_TEXT_TRANSLATION_CUSTOM_STORE_CHARS: number = 256 * 1024

/** Fixed, non-extendable boundary for custom prompt profiles and their persisted store. */
export class TextTranslationPromptContract {
  /**
   * The built-in prefix is reserved forever. Custom stores reject any id under it, so a
   * persisted blob can never impersonate a built-in even if the catalog grows or shrinks.
   */
  static isBuiltinId(promptProfileId: string): boolean {
    return typeof promptProfileId === 'string' && promptProfileId.startsWith('builtin.')
  }

  static isValidContentKind(contentKind: string): boolean {
    return contentKind === 'comment' || contentKind === 'gallery_title'
  }

  static validateProfile(profile: TextTranslationPromptProfile): void {
    if (profile.schemaVersion !== TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION ||
      !TextTranslationPromptContract.validIdentifier(profile.promptProfileId, MAX_TEXT_TRANSLATION_PROMPT_ID_CHARS) ||
      !TextTranslationPromptContract.validRequiredText(profile.displayName, MAX_TEXT_TRANSLATION_PROMPT_NAME_CHARS) ||
      !TextTranslationPromptContract.validStyle(profile.styleInstructions) ||
      !TextTranslationPromptContract.positiveInteger(profile.promptRevision) ||
      !TextTranslationPromptContract.nonNegativeInteger(profile.createdAt) ||
      !TextTranslationPromptContract.nonNegativeInteger(profile.updatedAt) ||
      profile.updatedAt < profile.createdAt) {
      throw new Error('Text translation prompt profile is invalid')
    }
  }

  static validateCustomProfile(profile: TextTranslationPromptProfile): void {
    TextTranslationPromptContract.validateProfile(profile)
    if (profile.builtIn) {
      throw new Error('Custom text translation prompt profile must not be built-in')
    }
    if (TextTranslationPromptContract.isBuiltinId(profile.promptProfileId)) {
      throw new Error('Custom text translation prompt profile must not use a built-in ID')
    }
  }

  static validateCustomProfiles(profiles: TextTranslationPromptProfile[]): void {
    if (profiles.length > MAX_TEXT_TRANSLATION_CUSTOM_PROFILES) {
      throw new Error('Too many custom text translation prompt profiles')
    }
    const ids: Set<string> = new Set<string>()
    for (let index: number = 0; index < profiles.length; index++) {
      TextTranslationPromptContract.validateCustomProfile(profiles[index])
      if (ids.has(profiles[index].promptProfileId)) {
        throw new Error('Duplicate custom text translation prompt profile')
      }
      ids.add(profiles[index].promptProfileId)
    }
  }

  static positiveInteger(value: number): boolean {
    return value > 0 && TextTranslationPromptContract.nonNegativeInteger(value)
  }

  private static validIdentifier(value: string, maxChars: number): boolean {
    return value.length > 0 && value.length <= maxChars && value === value.trim() &&
      !TextTranslationPromptContract.containsControlCharacter(value)
  }

  private static validRequiredText(value: string, maxChars: number): boolean {
    return value.length > 0 && value.length <= maxChars && value === value.trim() &&
      !TextTranslationPromptContract.containsControlCharacter(value)
  }

  private static validStyle(value: string): boolean {
    return value.trim().length > 0 && value.length <= MAX_TEXT_TRANSLATION_STYLE_CHARS &&
      !TextTranslationPromptContract.containsStyleControlCharacter(value)
  }

  static nonNegativeInteger(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 &&
      Math.floor(value) === value && value <= Number.MAX_SAFE_INTEGER
  }

  /**
   * The style body is multi-line by design, so we normalize every CR or CRLF down to a single
   * line feed before persisting. That lets a paste handler from a CRLF source through cleanly
   * while still letting validStyle() reject stray CRs that were not part of a line unit.
   */
  static normalizeLineEndings(value: string): string {
    return value.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
  }

  private static containsControlCharacter(value: string): boolean {
    for (let index: number = 0; index < value.length; index++) {
      const code: number = value.charCodeAt(index)
      if (code <= 31 || code === 127) {
        return true
      }
    }
    return false
  }

  /**
   * Style text is multi-line by design: a line feed is content, not dirt. Every other control
   * character (including a lone carriage return) is still rejected, so a persisted style keeps
   * one canonical line ending and cannot smuggle uninspected control bytes past the UI.
   */
  private static containsStyleControlCharacter(value: string): boolean {
    for (let index: number = 0; index < value.length; index++) {
      const code: number = value.charCodeAt(index)
      if (code === 10) {
        continue
      }
      if (code <= 31 || code === 127) {
        return true
      }
    }
    return false
  }
}

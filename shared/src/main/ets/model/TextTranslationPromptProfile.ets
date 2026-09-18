export const TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION: number = 1
export const TEXT_TRANSLATION_CONTENT_COMMENT: string = 'comment'
export const TEXT_TRANSLATION_CONTENT_GALLERY_TITLE: string = 'gallery_title'

/**
 * One selectable translation prompt for short text (comments and gallery titles).
 *
 * Prompts are consumer-owned, not source-owned: the LLM source manages connection,
 * capabilities, and credentials, while this selection owns the style section of the system
 * instructions. The request identity deliberately excludes the display name so renaming a
 * profile never invalidates the translation cache; only a style change (new revision) does.
 */
export class TextTranslationPromptProfile {
  schemaVersion: number = TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION
  promptProfileId: string = ''
  displayName: string = ''
  styleInstructions: string = ''
  promptRevision: number = 1
  builtIn: boolean = false
  createdAt: number = 0
  updatedAt: number = 0

  copy(): TextTranslationPromptProfile {
    const value: TextTranslationPromptProfile = new TextTranslationPromptProfile()
    value.schemaVersion = this.schemaVersion
    value.promptProfileId = this.promptProfileId
    value.displayName = this.displayName
    value.styleInstructions = this.styleInstructions
    value.promptRevision = this.promptRevision
    value.builtIn = this.builtIn
    value.createdAt = this.createdAt
    value.updatedAt = this.updatedAt
    return value
  }

  /** Stable request/cache identity: prompt ID + style revision only, no display name. */
  requestIdentity(): string {
    return JSON.stringify([this.promptProfileId, this.promptRevision])
  }
}

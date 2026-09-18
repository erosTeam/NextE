import { TextTranslationPromptProfile } from '../model/TextTranslationPromptProfile'
import {
  MAX_TEXT_TRANSLATION_CUSTOM_STORE_CHARS,
  TextTranslationPromptContract,
} from './TextTranslationPromptContract'

// Persisted custom entry. The builtIn flag is a runtime property of the in-memory model and is
// deliberately absent from the on-disk shape: a persisted store must not carry it, and a store
// that does is rejected outright.
class RawTextTranslationPromptProfile {
  schemaVersion: number = 0
  promptProfileId: string = ''
  displayName: string = ''
  styleInstructions: string = ''
  promptRevision: number = 0
  createdAt: number = 0
  updatedAt: number = 0
}

/**
 * Encodes/decodes the custom profile store only. Built-ins are code-defined and must never
 * round-trip here; every decoded entry comes back with builtIn === false, and the builtin.
 * prefix is rejected at the contract boundary rather than relying on UI protection.
 */
export class TextTranslationPromptCodec {
  static decode(rawText: string): TextTranslationPromptProfile[] {
    const trimmed: string = rawText.trim()
    if (trimmed.length === 0) {
      return []
    }
    if (trimmed.length > MAX_TEXT_TRANSLATION_CUSTOM_STORE_CHARS) {
      throw new Error('Custom text translation prompt store is too large')
    }
    let parsed: RawTextTranslationPromptProfile[]
    try {
      parsed = JSON.parse(trimmed) as RawTextTranslationPromptProfile[]
    } catch (e) {
      throw new Error('Custom text translation prompt store JSON parse failed: ' + (e as Error).message)
    }
    if (!Array.isArray(parsed)) {
      throw new Error('Custom text translation prompt store is invalid')
    }
    const profiles: TextTranslationPromptProfile[] = []
    for (let index: number = 0; index < parsed.length; index++) {
      profiles.push(TextTranslationPromptCodec.profile(parsed[index]))
    }
    TextTranslationPromptContract.validateCustomProfiles(profiles)
    return TextTranslationPromptCodec.copyProfiles(profiles)
  }

  static encode(profiles: TextTranslationPromptProfile[]): string {
    TextTranslationPromptContract.validateCustomProfiles(profiles)
    const entries: RawTextTranslationPromptProfile[] = []
    for (let index: number = 0; index < profiles.length; index++) {
      const profile: TextTranslationPromptProfile = profiles[index]
      const raw: RawTextTranslationPromptProfile = new RawTextTranslationPromptProfile()
      raw.schemaVersion = profile.schemaVersion
      raw.promptProfileId = profile.promptProfileId
      raw.displayName = profile.displayName
      raw.styleInstructions = profile.styleInstructions
      raw.promptRevision = profile.promptRevision
      raw.createdAt = profile.createdAt
      raw.updatedAt = profile.updatedAt
      entries.push(raw)
    }
    const encoded: string = JSON.stringify(entries)
    if (encoded.length > MAX_TEXT_TRANSLATION_CUSTOM_STORE_CHARS) {
      throw new Error('Custom text translation prompt store is too large')
    }
    return encoded
  }

  static copyProfiles(profiles: TextTranslationPromptProfile[]): TextTranslationPromptProfile[] {
    const copied: TextTranslationPromptProfile[] = []
    for (let index: number = 0; index < profiles.length; index++) {
      copied.push(profiles[index].copy())
    }
    return copied
  }

  private static profile(raw: RawTextTranslationPromptProfile): TextTranslationPromptProfile {
    if (raw === null || typeof raw !== 'object') {
      throw new Error('Custom text translation prompt profile entry is invalid')
    }
    if (JSON.stringify(raw).indexOf('"builtIn"') >= 0) {
      throw new Error('Custom text translation prompt store must not carry a builtIn flag')
    }
    if (typeof raw.schemaVersion !== 'number' || typeof raw.promptProfileId !== 'string' ||
      typeof raw.displayName !== 'string' || typeof raw.styleInstructions !== 'string' ||
      typeof raw.promptRevision !== 'number' ||
      typeof raw.createdAt !== 'number' || typeof raw.updatedAt !== 'number') {
      throw new Error('Custom text translation prompt profile entry is invalid')
    }
    const value: TextTranslationPromptProfile = new TextTranslationPromptProfile()
    value.schemaVersion = raw.schemaVersion
    value.promptProfileId = raw.promptProfileId
    value.displayName = raw.displayName
    value.styleInstructions = raw.styleInstructions
    value.promptRevision = raw.promptRevision
    // The custom store never persists or trusts the built-in flag.
    value.builtIn = false
    value.createdAt = raw.createdAt
    value.updatedAt = raw.updatedAt
    return value
  }
}

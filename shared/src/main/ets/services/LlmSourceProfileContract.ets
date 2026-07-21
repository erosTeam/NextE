import {
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LLM_CONSUMER_MANGA_TRANSLATION,
  LLM_SOURCE_PROFILE_SCHEMA_VERSION,
  LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL,
  LLM_SOURCE_TYPE_OPENAI_COMPATIBLE,
  LlmConsumerBinding,
  LlmSourceProfile,
} from '../model/LlmSourceProfile'

export const MAX_LLM_SOURCE_PROFILES: number = 16
export const MAX_LLM_SOURCE_PROFILE_STORE_CHARS: number = 256 * 1024
export const MAX_LLM_SOURCE_ID_CHARS: number = 160
export const MAX_LLM_SOURCE_NAME_CHARS: number = 120
export const MAX_LLM_SOURCE_URL_CHARS: number = 2048
export const MAX_LLM_MODEL_ID_CHARS: number = 160

export class LlmSourceProfileContract {
  static validateProfile(profile: LlmSourceProfile): void {
    if (profile.schemaVersion !== LLM_SOURCE_PROFILE_SCHEMA_VERSION ||
      !LlmSourceProfileContract.identifier(profile.sourceProfileId, MAX_LLM_SOURCE_ID_CHARS) ||
      !LlmSourceProfileContract.requiredText(profile.displayName, MAX_LLM_SOURCE_NAME_CHARS) ||
      !LlmSourceProfileContract.sourceType(profile.sourceType) ||
      !LlmSourceProfileContract.positiveInteger(profile.sourceRevision) ||
      !LlmSourceProfileContract.optionalHash(profile.accountIdentityHash) ||
      !LlmSourceProfileContract.nonNegativeInteger(profile.createdAt) ||
      !LlmSourceProfileContract.nonNegativeInteger(profile.updatedAt) ||
      profile.updatedAt < profile.createdAt ||
      !LlmSourceProfileContract.hasRequestCapability(profile)) {
      throw new Error('LLM source profile is invalid')
    }
    if (profile.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE) {
      if (!LlmSourceProfileContract.httpUrl(profile.baseUrl)) {
        throw new Error('LLM API source URL is invalid')
      }
      return
    }
    if (profile.baseUrl.length > 0) {
      throw new Error('LLM Codex source must not persist an override URL')
    }
  }

  static validateProfiles(profiles: LlmSourceProfile[]): void {
    if (profiles.length > MAX_LLM_SOURCE_PROFILES) {
      throw new Error('Too many LLM source profiles')
    }
    const ids: Set<string> = new Set<string>()
    for (let index: number = 0; index < profiles.length; index++) {
      LlmSourceProfileContract.validateProfile(profiles[index])
      if (ids.has(profiles[index].sourceProfileId)) {
        throw new Error('Duplicate LLM source profile')
      }
      ids.add(profiles[index].sourceProfileId)
    }
  }

  static validateBinding(binding: LlmConsumerBinding): void {
    if (!LlmSourceProfileContract.consumer(binding.consumerId)) {
      throw new Error('LLM consumer binding is invalid')
    }
    const emptySource: boolean = binding.sourceProfileId.length === 0
    const emptyModel: boolean = binding.modelId.length === 0
    if (emptySource && emptyModel) {
      return
    }
    if (emptySource || emptyModel ||
      !LlmSourceProfileContract.identifier(binding.sourceProfileId, MAX_LLM_SOURCE_ID_CHARS) ||
      !LlmSourceProfileContract.identifier(binding.modelId, MAX_LLM_MODEL_ID_CHARS)) {
      throw new Error('LLM consumer binding is incomplete')
    }
  }

  static canonicalText(value: string, maxChars: number): string {
    if (typeof value !== 'string') {
      return ''
    }
    const normalized: string = value.trim()
    if (normalized.length > maxChars || LlmSourceProfileContract.containsControlCharacter(normalized)) {
      return ''
    }
    return normalized
  }

  static positiveInteger(value: number): boolean {
    return value > 0 && LlmSourceProfileContract.nonNegativeInteger(value)
  }

  static nonNegativeInteger(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 &&
      Math.floor(value) === value && value <= Number.MAX_SAFE_INTEGER
  }

  private static sourceType(value: string): boolean {
    return value === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE ||
      value === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL
  }

  private static consumer(value: string): boolean {
    return value === LLM_CONSUMER_COMMENT_TRANSLATION ||
      value === LLM_CONSUMER_MANGA_TRANSLATION
  }

  private static identifier(value: string, maxChars: number): boolean {
    return value.length > 0 && value.length <= maxChars && value === value.trim() &&
      !LlmSourceProfileContract.containsControlCharacter(value)
  }

  private static requiredText(value: string, maxChars: number): boolean {
    return LlmSourceProfileContract.identifier(value, maxChars)
  }

  private static optionalHash(value: string): boolean {
    return value.length === 0 || /^[a-f0-9]{64}$/.test(value)
  }

  private static httpUrl(value: string): boolean {
    return value.length > 0 && value.length <= MAX_LLM_SOURCE_URL_CHARS && value === value.trim() &&
      !LlmSourceProfileContract.containsControlCharacter(value) &&
      (value.startsWith('https://') || value.startsWith('http://'))
  }

  private static hasRequestCapability(profile: LlmSourceProfile): boolean {
    return profile.capabilities.chatCompletions || profile.capabilities.responses ||
      profile.capabilities.imageOutput
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
}

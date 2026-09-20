import { util } from '@kit.ArkTS'

export const LLM_SOURCE_PROFILE_SCHEMA_VERSION: number = 1
export const LLM_SOURCE_TYPE_OPENAI_COMPATIBLE: string = 'openai_compatible'
export const LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL: string = 'codex_oauth_experimental'
export const LLM_CONSUMER_COMMENT_TRANSLATION: string = 'comment_translation'
export const LLM_CONSUMER_MANGA_TRANSLATION: string = 'manga_translation'
export const LLM_REASONING_EFFORT_NONE: string = 'none'
export const LLM_REASONING_EFFORT_MINIMAL: string = 'minimal'
export const LLM_REASONING_EFFORT_LOW: string = 'low'
export const LLM_REASONING_EFFORT_MEDIUM: string = 'medium'
export const LLM_REASONING_EFFORT_HIGH: string = 'high'
export const LLM_REASONING_EFFORT_XHIGH: string = 'xhigh'
export const LLM_REASONING_EFFORT_MAX: string = 'max'

export class LlmSourceCapabilities {
  chatCompletions: boolean = false
  responses: boolean = false
  imageInput: boolean = false
  imageOutput: boolean = false
  modelCatalog: boolean = false
  usage: boolean = false

  copy(): LlmSourceCapabilities {
    const value: LlmSourceCapabilities = new LlmSourceCapabilities()
    value.chatCompletions = this.chatCompletions
    value.responses = this.responses
    value.imageInput = this.imageInput
    value.imageOutput = this.imageOutput
    value.modelCatalog = this.modelCatalog
    value.usage = this.usage
    return value
  }

  requestIdentity(): string {
    return JSON.stringify([
      this.chatCompletions,
      this.responses,
      this.imageInput,
      this.imageOutput,
      this.modelCatalog,
      this.usage,
    ])
  }
}

/** Provider-neutral metadata. Credentials and account caches never enter this object. */
export class LlmSourceProfile {
  schemaVersion: number = LLM_SOURCE_PROFILE_SCHEMA_VERSION
  sourceProfileId: string = ''
  displayName: string = ''
  sourceType: string = LLM_SOURCE_TYPE_OPENAI_COMPATIBLE
  baseUrl: string = ''
  sourceRevision: number = 0
  capabilities: LlmSourceCapabilities = new LlmSourceCapabilities()
  accountIdentityHash: string = ''
  createdAt: number = 0
  updatedAt: number = 0

  copy(): LlmSourceProfile {
    const value: LlmSourceProfile = new LlmSourceProfile()
    value.schemaVersion = this.schemaVersion
    value.sourceProfileId = this.sourceProfileId
    value.displayName = this.displayName
    value.sourceType = this.sourceType
    value.baseUrl = this.baseUrl
    value.sourceRevision = this.sourceRevision
    value.capabilities = this.capabilities.copy()
    value.accountIdentityHash = this.accountIdentityHash
    value.createdAt = this.createdAt
    value.updatedAt = this.updatedAt
    return value
  }

  requestIdentity(): string {
    return JSON.stringify([
      this.sourceType,
      this.baseUrl,
      this.accountIdentityHash,
      this.capabilities.requestIdentity(),
    ])
  }
}

/** Consumer-owned selection. An empty pair is explicitly unconfigured. */
export class LlmConsumerBinding {
  consumerId: string = ''
  sourceProfileId: string = ''
  modelId: string = ''
  /** Empty means omit the request field and leave the choice to the model. */
  reasoningEffort: string = ''

  copy(): LlmConsumerBinding {
    const value: LlmConsumerBinding = new LlmConsumerBinding()
    value.consumerId = this.consumerId
    value.sourceProfileId = this.sourceProfileId
    value.modelId = this.modelId
    value.reasoningEffort = this.reasoningEffort
    return value
  }

  configured(): boolean {
    return this.sourceProfileId.length > 0 && this.modelId.length > 0
  }
}

export class LlmSourceResolution {
  profile: LlmSourceProfile = new LlmSourceProfile()
  modelId: string = ''
  reasoningEffort: string = ''
}

/**
 * The app deliberately owns this complete menu. It is not inferred from model catalogs because
 * neither Chat Completions nor /v1/models provides a portable capability-enumeration contract.
 */
export function isLlmReasoningEffort(value: string): boolean {
  return value.length === 0 ||
    value === LLM_REASONING_EFFORT_NONE ||
    value === LLM_REASONING_EFFORT_MINIMAL ||
    value === LLM_REASONING_EFFORT_LOW ||
    value === LLM_REASONING_EFFORT_MEDIUM ||
    value === LLM_REASONING_EFFORT_HIGH ||
    value === LLM_REASONING_EFFORT_XHIGH ||
    value === LLM_REASONING_EFFORT_MAX
}

export function supportsCommentTranslation(profile: LlmSourceProfile): boolean {
  if (profile.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE) {
    return profile.capabilities.chatCompletions
  }
  if (profile.sourceType === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL) {
    return profile.capabilities.responses
  }
  return false
}

export function supportsMangaTranslation(
  profile: LlmSourceProfile,
  requireImageInput: boolean = true,
): boolean {
  if (profile.sourceType !== LLM_SOURCE_TYPE_OPENAI_COMPATIBLE &&
    profile.sourceType !== LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL) {
    return false
  }
  return profile.capabilities.responses &&
    (!requireImageInput || profile.capabilities.imageInput)
}

export function generateLlmSourceProfileId(): string {
  return util.generateRandomUUID(true)
}

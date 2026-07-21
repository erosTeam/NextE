import { util } from '@kit.ArkTS'

export const LLM_SOURCE_PROFILE_SCHEMA_VERSION: number = 1
export const LLM_SOURCE_TYPE_OPENAI_COMPATIBLE: string = 'openai_compatible'
export const LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL: string = 'codex_oauth_experimental'
export const LLM_CONSUMER_COMMENT_TRANSLATION: string = 'comment_translation'
export const LLM_CONSUMER_MANGA_TRANSLATION: string = 'manga_translation'

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

  copy(): LlmConsumerBinding {
    const value: LlmConsumerBinding = new LlmConsumerBinding()
    value.consumerId = this.consumerId
    value.sourceProfileId = this.sourceProfileId
    value.modelId = this.modelId
    return value
  }

  configured(): boolean {
    return this.sourceProfileId.length > 0 && this.modelId.length > 0
  }
}

export class LlmSourceResolution {
  profile: LlmSourceProfile = new LlmSourceProfile()
  modelId: string = ''
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

export function generateLlmSourceProfileId(): string {
  return util.generateRandomUUID(true)
}

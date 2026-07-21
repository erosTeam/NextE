import { common } from '@kit.AbilityKit'
import {
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LLM_CONSUMER_MANGA_TRANSLATION,
  LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL,
  LLM_SOURCE_TYPE_OPENAI_COMPATIBLE,
  LlmConsumerBinding,
  LlmSourceProfile,
  LlmSourceResolution,
  supportsCommentTranslation,
} from '../model/LlmSourceProfile'
import { LlmSourceProfileRepository } from '../settings/LlmSourceProfileRepository'
import { LlmSourceSecretStore } from './LlmSourceSecretStore'

export class LlmSourceRuntimeConfig {
  sourceProfileId: string = ''
  sourceRevision: number = 0
  sourceType: string = ''
  baseUrl: string = ''
  modelId: string = ''
  apiKey: string = ''

  requestIdentity(): string {
    return JSON.stringify([
      this.sourceProfileId,
      this.sourceRevision,
      this.sourceType,
      this.modelId,
    ])
  }

  providerId(): string {
    return 'llm-source:' + this.sourceProfileId + ':r' + this.sourceRevision
  }
}

/** Resolves one consumer binding to a capability-checked, request-scoped runtime configuration. */
export class LlmSourceRuntimeResolver {
  static async resolveComment(
    context: common.UIAbilityContext,
  ): Promise<LlmSourceRuntimeConfig> {
    const config: LlmSourceRuntimeConfig = await LlmSourceRuntimeResolver.resolveConsumer(
      context,
      LLM_CONSUMER_COMMENT_TRANSLATION,
    )
    const profile: LlmSourceProfile = LlmSourceRuntimeResolver.profile(config.sourceProfileId)
    if (!supportsCommentTranslation(profile)) {
      throw new Error('Selected LLM source does not support comment translation')
    }
    return config
  }

  static async resolveManga(
    context: common.UIAbilityContext,
  ): Promise<LlmSourceRuntimeConfig> {
    const config: LlmSourceRuntimeConfig = await LlmSourceRuntimeResolver.resolveConsumer(
      context,
      LLM_CONSUMER_MANGA_TRANSLATION,
    )
    const profile: LlmSourceProfile = LlmSourceRuntimeResolver.profile(config.sourceProfileId)
    if (!profile.capabilities.responses || !profile.capabilities.imageInput) {
      throw new Error('Selected LLM source does not support manga translation')
    }
    return config
  }

  static async resolveCatalogSource(
    context: common.UIAbilityContext,
    sourceProfileId: string,
  ): Promise<LlmSourceRuntimeConfig> {
    const profile: LlmSourceProfile = LlmSourceRuntimeResolver.profile(sourceProfileId)
    if (!profile.capabilities.modelCatalog) {
      throw new Error('Selected LLM source does not provide a model catalog')
    }
    return LlmSourceRuntimeResolver.runtimeConfig(context, profile, '')
  }

  static profile(sourceProfileId: string): LlmSourceProfile {
    const profiles: LlmSourceProfile[] = LlmSourceProfileRepository.currentProfiles()
    for (let index: number = 0; index < profiles.length; index++) {
      if (profiles[index].sourceProfileId === sourceProfileId) {
        return profiles[index].copy()
      }
    }
    throw new Error('Selected LLM source is missing')
  }

  private static async resolveConsumer(
    context: common.UIAbilityContext,
    consumerId: string,
  ): Promise<LlmSourceRuntimeConfig> {
    const profiles: LlmSourceProfile[] = LlmSourceProfileRepository.currentProfiles()
    const binding: LlmConsumerBinding = LlmSourceProfileRepository.currentBinding(consumerId)
    const resolution: LlmSourceResolution | null = LlmSourceProfileRepository.resolve(
      profiles,
      binding,
    )
    if (resolution === null) {
      throw new Error('LLM source is not configured')
    }
    return LlmSourceRuntimeResolver.runtimeConfig(
      context,
      resolution.profile,
      resolution.modelId,
    )
  }

  private static async runtimeConfig(
    context: common.UIAbilityContext,
    profile: LlmSourceProfile,
    modelId: string,
  ): Promise<LlmSourceRuntimeConfig> {
    const config: LlmSourceRuntimeConfig = new LlmSourceRuntimeConfig()
    config.sourceProfileId = profile.sourceProfileId
    config.sourceRevision = profile.sourceRevision
    config.sourceType = profile.sourceType
    config.baseUrl = profile.baseUrl
    config.modelId = modelId
    if (profile.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE) {
      config.apiKey = await LlmSourceSecretStore.readApiKey(context, profile.sourceProfileId)
      if (config.apiKey.length === 0) {
        throw new Error('Selected LLM source API key is missing')
      }
    } else if (profile.sourceType !== LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL) {
      throw new Error('Selected LLM source type is unsupported')
    }
    return config
  }
}

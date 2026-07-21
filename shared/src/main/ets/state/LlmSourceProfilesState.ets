import { AppStorageV2 } from '@kit.ArkUI'
import {
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LLM_CONSUMER_MANGA_TRANSLATION,
  LlmConsumerBinding,
  LlmSourceProfile,
} from '../model/LlmSourceProfile'

/** Reactive metadata only. API keys and OAuth tokens must never enter this holder. */
@ObservedV2
export class LlmSourceProfilesState {
  @Trace profiles: LlmSourceProfile[] = []
  @Trace commentBinding: LlmConsumerBinding = LlmSourceProfilesState.emptyBinding(
    LLM_CONSUMER_COMMENT_TRANSLATION,
  )
  @Trace mangaBinding: LlmConsumerBinding = LlmSourceProfilesState.emptyBinding(
    LLM_CONSUMER_MANGA_TRANSLATION,
  )

  findById(sourceProfileId: string): LlmSourceProfile | null {
    for (let index: number = 0; index < this.profiles.length; index++) {
      if (this.profiles[index].sourceProfileId === sourceProfileId) {
        return this.profiles[index]
      }
    }
    return null
  }

  private static emptyBinding(consumerId: string): LlmConsumerBinding {
    const value: LlmConsumerBinding = new LlmConsumerBinding()
    value.consumerId = consumerId
    return value
  }
}

const LLM_SOURCE_PROFILES_STATE_KEY: string = 'v2_llmSourceProfiles'

export function connectLlmSourceProfiles(): LlmSourceProfilesState {
  return AppStorageV2.connect(
    LlmSourceProfilesState,
    LLM_SOURCE_PROFILES_STATE_KEY,
    () => new LlmSourceProfilesState(),
  )!
}

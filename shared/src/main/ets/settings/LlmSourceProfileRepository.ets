import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LLM_CONSUMER_MANGA_TRANSLATION,
  LLM_SOURCE_PROFILE_SCHEMA_VERSION,
  LlmConsumerBinding,
  LlmSourceProfile,
  LlmSourceResolution,
} from '../model/LlmSourceProfile'
import { LlmSourceProfileCodec } from '../services/LlmSourceProfileCodec'
import {
  LlmSourceProfileContract,
  MAX_LLM_MODEL_ID_CHARS,
  MAX_LLM_SOURCE_ID_CHARS,
  MAX_LLM_SOURCE_NAME_CHARS,
  MAX_LLM_SOURCE_URL_CHARS,
} from '../services/LlmSourceProfileContract'
import { LlmSourceSecretStore } from '../services/LlmSourceSecretStore'
import { connectLlmSourceProfiles, LlmSourceProfilesState } from '../state/LlmSourceProfilesState'

class LlmSourcePersistScheduler {
  private writeTail: Promise<void> = Promise.resolve()

  enqueue(write: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.writeTail.then(write, write)
    this.writeTail = next
    return next
  }
}

/** Single durable writer for reusable source metadata and consumer-owned bindings. */
export class LlmSourceProfileRepository {
  private static readonly scheduler: LlmSourcePersistScheduler = new LlmSourcePersistScheduler()

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      LlmSourceProfileRepository.applyState(
        LlmSourceProfileRepository.readProfiles(store),
        LlmSourceProfileRepository.readBinding(store, LLM_CONSUMER_COMMENT_TRANSLATION),
        LlmSourceProfileRepository.readBinding(store, LLM_CONSUMER_MANGA_TRANSLATION),
      )
    } catch (error) {
      DiagnosticLogger.warn('settings', 'llm_source_restore_failed', (error as Error).message)
      LlmSourceProfileRepository.applyState(
        [],
        LlmSourceProfileRepository.emptyBinding(LLM_CONSUMER_COMMENT_TRANSLATION),
        LlmSourceProfileRepository.emptyBinding(LLM_CONSUMER_MANGA_TRANSLATION),
      )
    }
  }

  static currentProfiles(): LlmSourceProfile[] {
    return LlmSourceProfileCodec.copyProfiles(connectLlmSourceProfiles().profiles)
  }

  static currentBinding(consumerId: string): LlmConsumerBinding {
    const state: LlmSourceProfilesState = connectLlmSourceProfiles()
    if (consumerId === LLM_CONSUMER_COMMENT_TRANSLATION) {
      return state.commentBinding.copy()
    }
    if (consumerId === LLM_CONSUMER_MANGA_TRANSLATION) {
      return state.mangaBinding.copy()
    }
    throw new Error('Unknown LLM consumer')
  }

  static upsert(
    context: common.UIAbilityContext,
    candidate: LlmSourceProfile,
  ): Promise<void> {
    const isolated: LlmSourceProfile = candidate.copy()
    return LlmSourceProfileRepository.scheduler.enqueue(async (): Promise<void> => {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const profiles: LlmSourceProfile[] = LlmSourceProfileRepository.readProfiles(store)
      const index: number = LlmSourceProfileRepository.indexOfProfile(
        profiles,
        isolated.sourceProfileId,
      )
      const existing: LlmSourceProfile | null = index < 0 ? null : profiles[index]
      const next: LlmSourceProfile = LlmSourceProfileRepository.prepareForUpsert(
        existing,
        isolated,
        Date.now(),
      )
      if (index < 0) {
        profiles.push(next)
      } else {
        profiles[index] = next
      }
      store.putSync(StorageKeys.LLM_SOURCE_PROFILES, LlmSourceProfileCodec.encode(profiles))
      LlmSourceSecretStore.clearIncompatibleFromStore(
        store,
        next.sourceProfileId,
        next.sourceType,
      )
      store.flushSync()
      LlmSourceProfileRepository.applyProfiles(profiles)
    })
  }

  /** Bindings intentionally survive deletion and then resolve to null; no first-source fallback exists. */
  static remove(
    context: common.UIAbilityContext,
    sourceProfileId: string,
  ): Promise<void> {
    const canonicalId: string = LlmSourceProfileContract.canonicalText(
      sourceProfileId,
      MAX_LLM_SOURCE_ID_CHARS,
    )
    if (canonicalId.length === 0 || canonicalId !== sourceProfileId) {
      return Promise.reject(new Error('LLM source profile ID is invalid'))
    }
    return LlmSourceProfileRepository.scheduler.enqueue(async (): Promise<void> => {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const profiles: LlmSourceProfile[] = LlmSourceProfileRepository.readProfiles(store)
      const remaining: LlmSourceProfile[] = []
      for (let index: number = 0; index < profiles.length; index++) {
        if (profiles[index].sourceProfileId !== canonicalId) {
          remaining.push(profiles[index])
        }
      }
      if (remaining.length === profiles.length) {
        return
      }
      if (remaining.length === 0) {
        store.deleteSync(StorageKeys.LLM_SOURCE_PROFILES)
      } else {
        store.putSync(StorageKeys.LLM_SOURCE_PROFILES, LlmSourceProfileCodec.encode(remaining))
      }
      LlmSourceSecretStore.removeAllFromStore(store, canonicalId)
      store.flushSync()
      LlmSourceProfileRepository.applyProfiles(remaining)
    })
  }

  static saveBinding(
    context: common.UIAbilityContext,
    binding: LlmConsumerBinding,
  ): Promise<void> {
    const isolated: LlmConsumerBinding = binding.copy()
    LlmSourceProfileContract.validateBinding(isolated)
    return LlmSourceProfileRepository.scheduler.enqueue(async (): Promise<void> => {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const profiles: LlmSourceProfile[] = LlmSourceProfileRepository.readProfiles(store)
      if (isolated.configured() &&
        LlmSourceProfileRepository.indexOfProfile(profiles, isolated.sourceProfileId) < 0) {
        throw new Error('LLM source binding references a missing profile')
      }
      const keys: string[] = LlmSourceProfileRepository.bindingKeys(isolated.consumerId)
      if (isolated.configured()) {
        store.putSync(keys[0], isolated.sourceProfileId)
        store.putSync(keys[1], isolated.modelId)
      } else {
        store.deleteSync(keys[0])
        store.deleteSync(keys[1])
      }
      store.flushSync()
      LlmSourceProfileRepository.applyBinding(isolated)
    })
  }

  static resolve(
    profiles: LlmSourceProfile[],
    binding: LlmConsumerBinding,
  ): LlmSourceResolution | null {
    try {
      LlmSourceProfileContract.validateProfiles(profiles)
      LlmSourceProfileContract.validateBinding(binding)
    } catch (_error) {
      return null
    }
    if (!binding.configured()) {
      return null
    }
    const index: number = LlmSourceProfileRepository.indexOfProfile(
      profiles,
      binding.sourceProfileId,
    )
    if (index < 0) {
      return null
    }
    const value: LlmSourceResolution = new LlmSourceResolution()
    value.profile = profiles[index].copy()
    value.modelId = binding.modelId
    return value
  }

  static referencedConsumers(
    sourceProfileId: string,
    bindings: LlmConsumerBinding[],
  ): string[] {
    const consumers: string[] = []
    for (let index: number = 0; index < bindings.length; index++) {
      try {
        LlmSourceProfileContract.validateBinding(bindings[index])
        if (bindings[index].sourceProfileId === sourceProfileId &&
          consumers.indexOf(bindings[index].consumerId) < 0) {
          consumers.push(bindings[index].consumerId)
        }
      } catch (_error) {
        continue
      }
    }
    return consumers
  }

  static prepareForUpsert(
    existing: LlmSourceProfile | null,
    candidate: LlmSourceProfile,
    now: number,
  ): LlmSourceProfile {
    if (!LlmSourceProfileContract.nonNegativeInteger(now)) {
      throw new Error('LLM source update time is invalid')
    }
    const next: LlmSourceProfile = candidate.copy()
    next.schemaVersion = LLM_SOURCE_PROFILE_SCHEMA_VERSION
    next.sourceProfileId = LlmSourceProfileContract.canonicalText(
      next.sourceProfileId,
      MAX_LLM_SOURCE_ID_CHARS,
    )
    next.displayName = LlmSourceProfileContract.canonicalText(
      next.displayName,
      MAX_LLM_SOURCE_NAME_CHARS,
    )
    next.baseUrl = LlmSourceProfileContract.canonicalText(next.baseUrl, MAX_LLM_SOURCE_URL_CHARS)
    next.accountIdentityHash = next.accountIdentityHash.trim().toLowerCase()
    if (existing === null) {
      next.sourceRevision = 1
      next.createdAt = now
      next.updatedAt = now
    } else {
      LlmSourceProfileContract.validateProfile(existing)
      next.sourceRevision = existing.requestIdentity() === next.requestIdentity()
        ? existing.sourceRevision
        : existing.sourceRevision + 1
      next.createdAt = existing.createdAt
      next.updatedAt = Math.max(now, existing.updatedAt + 1)
    }
    LlmSourceProfileContract.validateProfile(next)
    return next
  }

  private static readProfiles(store: preferences.Preferences): LlmSourceProfile[] {
    return LlmSourceProfileCodec.decode(
      store.getSync(StorageKeys.LLM_SOURCE_PROFILES, '') as string,
    )
  }

  private static readBinding(
    store: preferences.Preferences,
    consumerId: string,
  ): LlmConsumerBinding {
    const keys: string[] = LlmSourceProfileRepository.bindingKeys(consumerId)
    const binding: LlmConsumerBinding = new LlmConsumerBinding()
    binding.consumerId = consumerId
    binding.sourceProfileId = LlmSourceProfileContract.canonicalText(
      store.getSync(keys[0], '') as string,
      MAX_LLM_SOURCE_ID_CHARS,
    )
    binding.modelId = LlmSourceProfileContract.canonicalText(
      store.getSync(keys[1], '') as string,
      MAX_LLM_MODEL_ID_CHARS,
    )
    try {
      LlmSourceProfileContract.validateBinding(binding)
      return binding
    } catch (_error) {
      return LlmSourceProfileRepository.emptyBinding(consumerId)
    }
  }

  private static bindingKeys(consumerId: string): string[] {
    if (consumerId === LLM_CONSUMER_COMMENT_TRANSLATION) {
      return [
        StorageKeys.COMMENT_TRANSLATION_LLM_SOURCE_PROFILE,
        StorageKeys.COMMENT_TRANSLATION_LLM_MODEL,
      ]
    }
    if (consumerId === LLM_CONSUMER_MANGA_TRANSLATION) {
      return [
        StorageKeys.COMIC_TRANSLATION_LLM_SOURCE_PROFILE,
        StorageKeys.COMIC_TRANSLATION_LLM_MODEL,
      ]
    }
    throw new Error('Unknown LLM consumer')
  }

  private static indexOfProfile(profiles: LlmSourceProfile[], sourceProfileId: string): number {
    for (let index: number = 0; index < profiles.length; index++) {
      if (profiles[index].sourceProfileId === sourceProfileId) {
        return index
      }
    }
    return -1
  }

  private static applyState(
    profiles: LlmSourceProfile[],
    commentBinding: LlmConsumerBinding,
    mangaBinding: LlmConsumerBinding,
  ): void {
    const state: LlmSourceProfilesState = connectLlmSourceProfiles()
    state.profiles = LlmSourceProfileCodec.copyProfiles(profiles)
    state.commentBinding = commentBinding.copy()
    state.mangaBinding = mangaBinding.copy()
  }

  private static applyProfiles(profiles: LlmSourceProfile[]): void {
    connectLlmSourceProfiles().profiles = LlmSourceProfileCodec.copyProfiles(profiles)
  }

  private static applyBinding(binding: LlmConsumerBinding): void {
    const state: LlmSourceProfilesState = connectLlmSourceProfiles()
    if (binding.consumerId === LLM_CONSUMER_COMMENT_TRANSLATION) {
      state.commentBinding = binding.copy()
      return
    }
    state.mangaBinding = binding.copy()
  }

  private static emptyBinding(consumerId: string): LlmConsumerBinding {
    const value: LlmConsumerBinding = new LlmConsumerBinding()
    value.consumerId = consumerId
    return value
  }
}

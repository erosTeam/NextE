import { LlmSourceCapabilities, LlmSourceProfile } from '../model/LlmSourceProfile'
import {
  LlmSourceProfileContract,
  MAX_LLM_SOURCE_PROFILE_STORE_CHARS,
} from './LlmSourceProfileContract'

class RawLlmSourceCapabilities {
  chatCompletions: boolean = false
  responses: boolean = false
  imageInput: boolean = false
  imageOutput: boolean = false
  modelCatalog: boolean = false
  usage: boolean = false
}

class RawLlmSourceProfile {
  schemaVersion: number = 0
  sourceProfileId: string = ''
  displayName: string = ''
  sourceType: string = ''
  baseUrl: string = ''
  sourceRevision: number = 0
  capabilities: RawLlmSourceCapabilities | null = null
  accountIdentityHash: string = ''
  createdAt: number = 0
  updatedAt: number = 0
}

export class LlmSourceProfileCodec {
  static decode(rawText: string): LlmSourceProfile[] {
    if (rawText.length === 0) {
      return []
    }
    if (rawText.length > MAX_LLM_SOURCE_PROFILE_STORE_CHARS) {
      throw new Error('LLM source profile store is too large')
    }
    const parsed: RawLlmSourceProfile[] = JSON.parse(rawText) as RawLlmSourceProfile[]
    if (!Array.isArray(parsed)) {
      throw new Error('LLM source profile store is invalid')
    }
    const profiles: LlmSourceProfile[] = []
    for (let index: number = 0; index < parsed.length; index++) {
      profiles.push(LlmSourceProfileCodec.profile(parsed[index]))
    }
    LlmSourceProfileContract.validateProfiles(profiles)
    return LlmSourceProfileCodec.copyProfiles(profiles)
  }

  static encode(profiles: LlmSourceProfile[]): string {
    LlmSourceProfileContract.validateProfiles(profiles)
    const encoded: string = JSON.stringify(profiles)
    if (encoded.length > MAX_LLM_SOURCE_PROFILE_STORE_CHARS) {
      throw new Error('LLM source profile store is too large')
    }
    return encoded
  }

  static copyProfiles(profiles: LlmSourceProfile[]): LlmSourceProfile[] {
    const copied: LlmSourceProfile[] = []
    for (let index: number = 0; index < profiles.length; index++) {
      copied.push(profiles[index].copy())
    }
    return copied
  }

  private static profile(raw: RawLlmSourceProfile): LlmSourceProfile {
    if (raw === null || typeof raw !== 'object' || raw.capabilities === null ||
      typeof raw.capabilities !== 'object') {
      throw new Error('LLM source profile entry is invalid')
    }
    const value: LlmSourceProfile = new LlmSourceProfile()
    value.schemaVersion = raw.schemaVersion
    value.sourceProfileId = raw.sourceProfileId
    value.displayName = raw.displayName
    value.sourceType = raw.sourceType
    value.baseUrl = raw.baseUrl
    value.sourceRevision = raw.sourceRevision
    value.capabilities = LlmSourceProfileCodec.capabilities(raw.capabilities)
    value.accountIdentityHash = raw.accountIdentityHash
    value.createdAt = raw.createdAt
    value.updatedAt = raw.updatedAt
    return value
  }

  private static capabilities(raw: RawLlmSourceCapabilities): LlmSourceCapabilities {
    if (typeof raw.chatCompletions !== 'boolean' || typeof raw.responses !== 'boolean' ||
      typeof raw.imageInput !== 'boolean' || typeof raw.imageOutput !== 'boolean' ||
      typeof raw.modelCatalog !== 'boolean' || typeof raw.usage !== 'boolean') {
      throw new Error('LLM source capabilities are invalid')
    }
    const value: LlmSourceCapabilities = new LlmSourceCapabilities()
    value.chatCompletions = raw.chatCompletions
    value.responses = raw.responses
    value.imageInput = raw.imageInput
    value.imageOutput = raw.imageOutput
    value.modelCatalog = raw.modelCatalog
    value.usage = raw.usage
    return value
  }
}

import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { CodexOAuthTokenSet } from '../model/ComicTranslationProvider'
import { LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL } from '../model/LlmSourceProfile'
import {
  CODEX_OAUTH_TOKEN_STORE_MAX_CHARS,
  CodexOAuthTokenCodec,
} from './CodexOAuthTokenCodec'
import {
  LlmSourceProfileContract,
  MAX_LLM_SOURCE_ID_CHARS,
  MAX_LLM_SOURCE_PROFILES,
} from './LlmSourceProfileContract'

const MAX_LLM_API_KEY_CHARS: number = 16 * 1024
const MAX_LLM_API_KEY_MAP_CHARS: number = 512 * 1024
const MAX_LLM_CODEX_TOKEN_MAP_CHARS: number = 8 * 1024 * 1024
const MAX_LLM_CACHE_MAP_CHARS: number = 8 * 1024 * 1024

type SecretStringMap = Record<string, string>

/** Device persistence for source-scoped credentials. No method logs secret values. */
export class LlmSourceSecretStore {
  static async readApiKey(
    context: common.UIAbilityContext,
    sourceProfileId: string,
  ): Promise<string> {
    LlmSourceSecretStore.validateSourceId(sourceProfileId)
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const values: SecretStringMap = LlmSourceSecretStore.decodeStringMap(
      store.getSync(StorageKeys.LLM_SOURCE_API_KEYS, '') as string,
      MAX_LLM_API_KEY_MAP_CHARS,
      MAX_LLM_API_KEY_CHARS,
    )
    return values[sourceProfileId] === undefined
      ? ''
      : LlmSourceSecretStore.credential(values[sourceProfileId], MAX_LLM_API_KEY_CHARS, false)
  }

  static async saveApiKey(
    context: common.UIAbilityContext,
    sourceProfileId: string,
    apiKey: string,
  ): Promise<void> {
    LlmSourceSecretStore.validateSourceId(sourceProfileId)
    const canonical: string = LlmSourceSecretStore.credential(apiKey, MAX_LLM_API_KEY_CHARS, false)
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    let values: SecretStringMap = LlmSourceSecretStore.decodeStringMap(
      store.getSync(StorageKeys.LLM_SOURCE_API_KEYS, '') as string,
      MAX_LLM_API_KEY_MAP_CHARS,
      MAX_LLM_API_KEY_CHARS,
    )
    if (canonical.length === 0) {
      values = LlmSourceSecretStore.withoutKey(values, sourceProfileId)
    } else {
      values[sourceProfileId] = canonical
    }
    LlmSourceSecretStore.writeMap(
      store,
      StorageKeys.LLM_SOURCE_API_KEYS,
      values,
      MAX_LLM_API_KEY_MAP_CHARS,
      MAX_LLM_API_KEY_CHARS,
    )
    store.flushSync()
  }

  static async readCodexTokens(
    context: common.UIAbilityContext,
    sourceProfileId: string,
  ): Promise<CodexOAuthTokenSet | null> {
    LlmSourceSecretStore.validateSourceId(sourceProfileId)
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const values: SecretStringMap = LlmSourceSecretStore.decodeStringMap(
      store.getSync(StorageKeys.LLM_SOURCE_CODEX_OAUTH_TOKENS, '') as string,
      MAX_LLM_CODEX_TOKEN_MAP_CHARS,
      CODEX_OAUTH_TOKEN_STORE_MAX_CHARS,
    )
    return values[sourceProfileId] === undefined
      ? null
      : CodexOAuthTokenCodec.parse(values[sourceProfileId])
  }

  static async saveCodexTokens(
    context: common.UIAbilityContext,
    sourceProfileId: string,
    tokens: CodexOAuthTokenSet,
  ): Promise<void> {
    LlmSourceSecretStore.validateSourceId(sourceProfileId)
    const encodedTokens: string = CodexOAuthTokenCodec.serialize(tokens)
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const values: SecretStringMap = LlmSourceSecretStore.decodeStringMap(
      store.getSync(StorageKeys.LLM_SOURCE_CODEX_OAUTH_TOKENS, '') as string,
      MAX_LLM_CODEX_TOKEN_MAP_CHARS,
      CODEX_OAUTH_TOKEN_STORE_MAX_CHARS,
    )
    values[sourceProfileId] = encodedTokens
    LlmSourceSecretStore.writeMap(
      store,
      StorageKeys.LLM_SOURCE_CODEX_OAUTH_TOKENS,
      values,
      MAX_LLM_CODEX_TOKEN_MAP_CHARS,
      CODEX_OAUTH_TOKEN_STORE_MAX_CHARS,
    )
    store.flushSync()
  }

  static async clearCodexTokens(
    context: common.UIAbilityContext,
    sourceProfileId: string,
  ): Promise<void> {
    LlmSourceSecretStore.validateSourceId(sourceProfileId)
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    LlmSourceSecretStore.removeFromMap(
      store,
      StorageKeys.LLM_SOURCE_CODEX_OAUTH_TOKENS,
      sourceProfileId,
      MAX_LLM_CODEX_TOKEN_MAP_CHARS,
      CODEX_OAUTH_TOKEN_STORE_MAX_CHARS,
    )
    store.flushSync()
  }

  static clearIncompatibleFromStore(
    store: preferences.Preferences,
    sourceProfileId: string,
    sourceType: string,
  ): void {
    if (sourceType === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL) {
      LlmSourceSecretStore.removeFromMap(
        store,
        StorageKeys.LLM_SOURCE_API_KEYS,
        sourceProfileId,
        MAX_LLM_API_KEY_MAP_CHARS,
        MAX_LLM_API_KEY_CHARS,
      )
      return
    }
    LlmSourceSecretStore.removeFromMap(
      store,
      StorageKeys.LLM_SOURCE_CODEX_OAUTH_TOKENS,
      sourceProfileId,
      MAX_LLM_CODEX_TOKEN_MAP_CHARS,
      CODEX_OAUTH_TOKEN_STORE_MAX_CHARS,
    )
  }

  static removeAllFromStore(
    store: preferences.Preferences,
    sourceProfileId: string,
  ): void {
    LlmSourceSecretStore.removeFromMap(
      store,
      StorageKeys.LLM_SOURCE_API_KEYS,
      sourceProfileId,
      MAX_LLM_API_KEY_MAP_CHARS,
      MAX_LLM_API_KEY_CHARS,
    )
    LlmSourceSecretStore.removeFromMap(
      store,
      StorageKeys.LLM_SOURCE_CODEX_OAUTH_TOKENS,
      sourceProfileId,
      MAX_LLM_CODEX_TOKEN_MAP_CHARS,
      CODEX_OAUTH_TOKEN_STORE_MAX_CHARS,
    )
    LlmSourceSecretStore.removeFromMap(
      store,
      StorageKeys.LLM_SOURCE_MODEL_CATALOG_CACHE,
      sourceProfileId,
      MAX_LLM_CACHE_MAP_CHARS,
      MAX_LLM_CACHE_MAP_CHARS,
    )
    LlmSourceSecretStore.removeFromMap(
      store,
      StorageKeys.LLM_SOURCE_USAGE_CACHE,
      sourceProfileId,
      MAX_LLM_CACHE_MAP_CHARS,
      MAX_LLM_CACHE_MAP_CHARS,
    )
  }

  static decodeStringMap(rawText: string, maxStoreChars: number, maxValueChars: number): SecretStringMap {
    const values: SecretStringMap = {}
    if (rawText.length === 0) {
      return values
    }
    if (rawText.length > maxStoreChars) {
      throw new Error('LLM source secret store is too large')
    }
    const raw: SecretStringMap = JSON.parse(rawText) as SecretStringMap
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      throw new Error('LLM source secret store is invalid')
    }
    const keys: string[] = Object.keys(raw)
    if (keys.length > MAX_LLM_SOURCE_PROFILES) {
      throw new Error('LLM source secret store has too many records')
    }
    for (let index: number = 0; index < keys.length; index++) {
      LlmSourceSecretStore.validateSourceId(keys[index])
      if (typeof raw[keys[index]] !== 'string' || raw[keys[index]].length > maxValueChars) {
        throw new Error('LLM source secret record is invalid')
      }
      values[keys[index]] = raw[keys[index]]
    }
    return values
  }

  static encodeStringMap(values: SecretStringMap, maxStoreChars: number, maxValueChars: number): string {
    const keys: string[] = Object.keys(values).sort()
    if (keys.length > MAX_LLM_SOURCE_PROFILES) {
      throw new Error('LLM source secret store has too many records')
    }
    const canonical: SecretStringMap = {}
    for (let index: number = 0; index < keys.length; index++) {
      LlmSourceSecretStore.validateSourceId(keys[index])
      if (typeof values[keys[index]] !== 'string' || values[keys[index]].length > maxValueChars) {
        throw new Error('LLM source secret record is invalid')
      }
      canonical[keys[index]] = values[keys[index]]
    }
    const encoded: string = JSON.stringify(canonical)
    if (encoded.length > maxStoreChars) {
      throw new Error('LLM source secret store is too large')
    }
    return encoded
  }

  private static removeFromMap(
    store: preferences.Preferences,
    storageKey: string,
    sourceProfileId: string,
    maxStoreChars: number,
    maxValueChars: number,
  ): void {
    const values: SecretStringMap = LlmSourceSecretStore.decodeStringMap(
      store.getSync(storageKey, '') as string,
      maxStoreChars,
      maxValueChars,
    )
    if (values[sourceProfileId] === undefined) {
      return
    }
    const remaining: SecretStringMap = LlmSourceSecretStore.withoutKey(values, sourceProfileId)
    LlmSourceSecretStore.writeMap(store, storageKey, remaining, maxStoreChars, maxValueChars)
  }

  private static writeMap(
    store: preferences.Preferences,
    storageKey: string,
    values: SecretStringMap,
    maxStoreChars: number,
    maxValueChars: number,
  ): void {
    if (Object.keys(values).length === 0) {
      store.deleteSync(storageKey)
      return
    }
    store.putSync(
      storageKey,
      LlmSourceSecretStore.encodeStringMap(values, maxStoreChars, maxValueChars),
    )
  }

  private static withoutKey(values: SecretStringMap, removedKey: string): SecretStringMap {
    const remaining: SecretStringMap = {}
    const keys: string[] = Object.keys(values)
    for (let index: number = 0; index < keys.length; index++) {
      if (keys[index] !== removedKey) {
        remaining[keys[index]] = values[keys[index]]
      }
    }
    return remaining
  }

  private static validateSourceId(sourceProfileId: string): void {
    if (sourceProfileId.length === 0 ||
      LlmSourceProfileContract.canonicalText(sourceProfileId, MAX_LLM_SOURCE_ID_CHARS) !==
        sourceProfileId) {
      throw new Error('LLM source secret reference is invalid')
    }
  }

  private static credential(value: string, maxChars: number, required: boolean): string {
    if (typeof value !== 'string' || value.length > maxChars || value !== value.trim()) {
      throw new Error('LLM source credential is invalid')
    }
    if (required && value.length === 0) {
      throw new Error('LLM source credential is incomplete')
    }
    for (let index: number = 0; index < value.length; index++) {
      const code: number = value.charCodeAt(index)
      if (code <= 31 || code === 127) {
        throw new Error('LLM source credential is invalid')
      }
    }
    return value
  }
}

import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { preferences } from '@kit.ArkData'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH,
  COMIC_TRANSLATION_PROVIDER_OPENAI_API,
  CodexOAuthTokenSet,
} from '../model/ComicTranslationProvider'
import {
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LLM_CONSUMER_MANGA_TRANSLATION,
  LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL,
  LLM_SOURCE_TYPE_OPENAI_COMPATIBLE,
  LlmConsumerBinding,
  LlmSourceCapabilities,
  LlmSourceProfile,
} from '../model/LlmSourceProfile'
import { LlmSourceProfileRepository } from '../settings/LlmSourceProfileRepository'
import { CodexOAuthTokenCodec } from './CodexOAuthTokenCodec'
import { ComicTranslationCodexUsageService } from './ComicTranslationCodexUsageService'
import { LlmSourceProfileCodec } from './LlmSourceProfileCodec'
import {
  LlmSourceProfileContract,
  MAX_LLM_MODEL_ID_CHARS,
  MAX_LLM_SOURCE_PROFILES,
} from './LlmSourceProfileContract'
import { LlmSourceSecretStore } from './LlmSourceSecretStore'

export const LLM_SOURCE_MIGRATION_VERSION: number = 1

const DEFAULT_COMMENT_API_URL: string = 'https://api.openai.com'
const DEFAULT_COMMENT_MODEL: string = 'gpt-4o-mini'
const DEFAULT_MANGA_API_URL: string = 'https://api.openai.com/v1'
const DEFAULT_MANGA_API_MODEL: string = 'gpt-4o-mini'
const LEGACY_API_KEY_MAX_CHARS: number = 16 * 1024

type MigrationStringMap = Record<string, string>

export class LegacyCommentLlmSettings {
  present: boolean = false
  apiUrl: string = ''
  apiKey: string = ''
  model: string = ''
}

export class LegacyMangaLlmSettings {
  provider: string = COMIC_TRANSLATION_PROVIDER_OPENAI_API
  apiPresent: boolean = false
  apiBaseUrl: string = ''
  apiKey: string = ''
  apiModel: string = ''
  codexPresent: boolean = false
  codexModel: string = ''
  codexTokenText: string = ''
  codexUsageCacheText: string = ''
}

export class LlmSourceMigrationInput {
  profiles: LlmSourceProfile[] = []
  apiKeys: MigrationStringMap = {}
  codexTokens: MigrationStringMap = {}
  usageCaches: MigrationStringMap = {}
  commentBinding: LlmConsumerBinding = LlmSourceMigrationPlanner.emptyBinding(
    LLM_CONSUMER_COMMENT_TRANSLATION,
  )
  mangaBinding: LlmConsumerBinding = LlmSourceMigrationPlanner.emptyBinding(
    LLM_CONSUMER_MANGA_TRANSLATION,
  )
  comment: LegacyCommentLlmSettings = new LegacyCommentLlmSettings()
  manga: LegacyMangaLlmSettings = new LegacyMangaLlmSettings()
  now: number = 0
}

export class LlmSourceMigrationPlan {
  profiles: LlmSourceProfile[] = []
  apiKeys: MigrationStringMap = {}
  codexTokens: MigrationStringMap = {}
  usageCaches: MigrationStringMap = {}
  commentBinding: LlmConsumerBinding = LlmSourceMigrationPlanner.emptyBinding(
    LLM_CONSUMER_COMMENT_TRANSLATION,
  )
  mangaBinding: LlmConsumerBinding = LlmSourceMigrationPlanner.emptyBinding(
    LLM_CONSUMER_MANGA_TRANSLATION,
  )
}

class LegacyApiTarget {
  valid: boolean = false
  baseUrl: string = ''
  apiKey: string = ''
  model: string = ''
  comment: boolean = false
  manga: boolean = false
}

/** Pure, deterministic planner. It never logs or persists a credential. */
export class LlmSourceMigrationPlanner {
  static plan(input: LlmSourceMigrationInput): LlmSourceMigrationPlan {
    if (!LlmSourceProfileContract.nonNegativeInteger(input.now)) {
      throw new Error('LLM source migration time is invalid')
    }
    LlmSourceProfileContract.validateProfiles(input.profiles)
    LlmSourceProfileContract.validateBinding(input.commentBinding)
    LlmSourceProfileContract.validateBinding(input.mangaBinding)
    LlmSourceSecretStore.encodeApiKeyMap(input.apiKeys)
    LlmSourceSecretStore.encodeCodexTokenMap(input.codexTokens)
    LlmSourceSecretStore.encodeCacheMap(input.usageCaches)

    const output: LlmSourceMigrationPlan = new LlmSourceMigrationPlan()
    output.profiles = LlmSourceProfileCodec.copyProfiles(input.profiles)
    output.apiKeys = LlmSourceMigrationPlanner.copyMap(input.apiKeys)
    output.codexTokens = LlmSourceMigrationPlanner.copyMap(input.codexTokens)
    output.usageCaches = LlmSourceMigrationPlanner.copyMap(input.usageCaches)
    output.commentBinding = input.commentBinding.copy()
    output.mangaBinding = input.mangaBinding.copy()

    const commentTarget: LegacyApiTarget = LlmSourceMigrationPlanner.commentTarget(input.comment)
    const mangaTarget: LegacyApiTarget = LlmSourceMigrationPlanner.mangaTarget(input.manga)
    let commentSourceId: string = ''
    let mangaApiSourceId: string = ''
    if (commentTarget.valid && mangaTarget.valid &&
      commentTarget.baseUrl === mangaTarget.baseUrl &&
      commentTarget.apiKey === mangaTarget.apiKey) {
      const sharedTarget: LegacyApiTarget = new LegacyApiTarget()
      sharedTarget.valid = true
      sharedTarget.baseUrl = commentTarget.baseUrl
      sharedTarget.apiKey = commentTarget.apiKey
      sharedTarget.comment = true
      sharedTarget.manga = true
      commentSourceId = LlmSourceMigrationPlanner.ensureApiSource(
        output,
        sharedTarget,
        'migrated-shared-api',
        '翻译 API（迁移）',
        input.now,
      )
      mangaApiSourceId = commentSourceId
    } else {
      if (commentTarget.valid) {
        commentSourceId = LlmSourceMigrationPlanner.ensureApiSource(
          output,
          commentTarget,
          'migrated-comment-api',
          '评论翻译 API（迁移）',
          input.now,
        )
      }
      if (mangaTarget.valid) {
        mangaApiSourceId = LlmSourceMigrationPlanner.ensureApiSource(
          output,
          mangaTarget,
          'migrated-manga-api',
          '漫画翻译 API（迁移）',
          input.now,
        )
      }
    }

    const codexSourceId: string = LlmSourceMigrationPlanner.ensureCodexSource(
      output,
      input.manga,
      input.now,
    )
    if (!output.commentBinding.configured() && commentSourceId.length > 0) {
      output.commentBinding = LlmSourceMigrationPlanner.binding(
        LLM_CONSUMER_COMMENT_TRANSLATION,
        commentSourceId,
        commentTarget.model,
      )
    }
    if (!output.mangaBinding.configured()) {
      if (input.manga.provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH &&
        codexSourceId.length > 0) {
        const codexModel: string = LlmSourceProfileContract.canonicalText(
          input.manga.codexModel,
          MAX_LLM_MODEL_ID_CHARS,
        )
        if (codexModel.length > 0) {
          output.mangaBinding = LlmSourceMigrationPlanner.binding(
            LLM_CONSUMER_MANGA_TRANSLATION,
            codexSourceId,
            codexModel,
          )
        }
      } else if (input.manga.provider === COMIC_TRANSLATION_PROVIDER_OPENAI_API &&
        mangaApiSourceId.length > 0) {
        output.mangaBinding = LlmSourceMigrationPlanner.binding(
          LLM_CONSUMER_MANGA_TRANSLATION,
          mangaApiSourceId,
          mangaTarget.model,
        )
      }
    }
    LlmSourceProfileContract.validateProfiles(output.profiles)
    LlmSourceProfileContract.validateBinding(output.commentBinding)
    LlmSourceProfileContract.validateBinding(output.mangaBinding)
    LlmSourceSecretStore.encodeApiKeyMap(output.apiKeys)
    LlmSourceSecretStore.encodeCodexTokenMap(output.codexTokens)
    LlmSourceSecretStore.encodeCacheMap(output.usageCaches)
    return output
  }

  static emptyBinding(consumerId: string): LlmConsumerBinding {
    const value: LlmConsumerBinding = new LlmConsumerBinding()
    value.consumerId = consumerId
    return value
  }

  private static commentTarget(legacy: LegacyCommentLlmSettings): LegacyApiTarget {
    const target: LegacyApiTarget = new LegacyApiTarget()
    target.comment = true
    if (!legacy.present || !LlmSourceMigrationPlanner.validCredential(legacy.apiKey)) {
      return target
    }
    target.baseUrl = LlmSourceMigrationPlanner.canonicalApiBase(
      legacy.apiUrl,
      DEFAULT_COMMENT_API_URL,
    )
    target.apiKey = legacy.apiKey
    target.model = LlmSourceProfileContract.canonicalText(
      legacy.model.length > 0 ? legacy.model : DEFAULT_COMMENT_MODEL,
      MAX_LLM_MODEL_ID_CHARS,
    )
    target.valid = target.baseUrl.length > 0 && target.model.length > 0
    return target
  }

  private static mangaTarget(legacy: LegacyMangaLlmSettings): LegacyApiTarget {
    const target: LegacyApiTarget = new LegacyApiTarget()
    target.manga = true
    if (!legacy.apiPresent || !LlmSourceMigrationPlanner.validCredential(legacy.apiKey)) {
      return target
    }
    target.baseUrl = LlmSourceMigrationPlanner.canonicalApiBase(
      legacy.apiBaseUrl,
      DEFAULT_MANGA_API_URL,
    )
    target.apiKey = legacy.apiKey
    target.model = LlmSourceProfileContract.canonicalText(
      legacy.apiModel.length > 0 ? legacy.apiModel : DEFAULT_MANGA_API_MODEL,
      MAX_LLM_MODEL_ID_CHARS,
    )
    target.valid = target.baseUrl.length > 0 && target.model.length > 0
    return target
  }

  private static canonicalApiBase(value: string, fallback: string): string {
    let normalized: string = LlmSourceProfileContract.canonicalText(
      value.length > 0 ? value : fallback,
      2048,
    )
    normalized = normalized.replace(/\/+$/, '')
    if (normalized.toLowerCase().endsWith('/responses')) {
      normalized = normalized.substring(0, normalized.length - '/responses'.length)
      normalized = normalized.replace(/\/+$/, '')
    }
    if (normalized.toLowerCase().endsWith('/v1')) {
      normalized = normalized.substring(0, normalized.length - '/v1'.length)
      normalized = normalized.replace(/\/+$/, '')
    }
    if (!normalized.startsWith('https://') && !normalized.startsWith('http://')) {
      return ''
    }
    return normalized
  }

  private static ensureApiSource(
    output: LlmSourceMigrationPlan,
    target: LegacyApiTarget,
    preferredId: string,
    displayName: string,
    now: number,
  ): string {
    let index: number = LlmSourceMigrationPlanner.findApiSource(output, target)
    if (index >= 0) {
      const existing: LlmSourceProfile = output.profiles[index]
      const candidate: LlmSourceProfile = existing.copy()
      LlmSourceMigrationPlanner.mergeApiCapabilities(candidate.capabilities, target)
      if (candidate.requestIdentity() !== existing.requestIdentity()) {
        output.profiles[index] = LlmSourceProfileRepository.prepareForUpsert(
          existing,
          candidate,
          now,
        )
      }
      if (target.apiKey.length > 0) {
        output.apiKeys[existing.sourceProfileId] = target.apiKey
      }
      return existing.sourceProfileId
    }
    const sourceId: string = LlmSourceMigrationPlanner.allocateId(output.profiles, preferredId)
    const candidate: LlmSourceProfile = new LlmSourceProfile()
    candidate.sourceProfileId = sourceId
    candidate.displayName = displayName
    candidate.sourceType = LLM_SOURCE_TYPE_OPENAI_COMPATIBLE
    candidate.baseUrl = target.baseUrl
    LlmSourceMigrationPlanner.mergeApiCapabilities(candidate.capabilities, target)
    const prepared: LlmSourceProfile = LlmSourceProfileRepository.prepareForUpsert(
      null,
      candidate,
      now,
    )
    output.profiles.push(prepared)
    if (target.apiKey.length > 0) {
      output.apiKeys[sourceId] = target.apiKey
    }
    return sourceId
  }

  private static findApiSource(
    output: LlmSourceMigrationPlan,
    target: LegacyApiTarget,
  ): number {
    for (let index: number = 0; index < output.profiles.length; index++) {
      const profile: LlmSourceProfile = output.profiles[index]
      const storedKey: string = output.apiKeys[profile.sourceProfileId] === undefined
        ? ''
        : output.apiKeys[profile.sourceProfileId]
      if (profile.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE &&
        LlmSourceMigrationPlanner.canonicalApiBase(profile.baseUrl, '') === target.baseUrl &&
        storedKey === target.apiKey) {
        return index
      }
    }
    return -1
  }

  private static ensureCodexSource(
    output: LlmSourceMigrationPlan,
    legacy: LegacyMangaLlmSettings,
    now: number,
  ): string {
    if (!legacy.codexPresent) {
      return ''
    }
    const tokens: CodexOAuthTokenSet | null = CodexOAuthTokenCodec.parse(legacy.codexTokenText)
    const encodedTokens: string = tokens === null ? '' : CodexOAuthTokenCodec.serialize(tokens)
    const accountHash: string = tokens === null || tokens.accountId.length === 0
      ? ''
      : LlmSourceMigrationPlanner.hashIdentity(tokens.accountId)
    let index: number = LlmSourceMigrationPlanner.findCodexSource(
      output,
      encodedTokens,
      accountHash,
    )
    let sourceId: string = ''
    if (index >= 0) {
      const existing: LlmSourceProfile = output.profiles[index]
      const candidate: LlmSourceProfile = existing.copy()
      candidate.capabilities.responses = true
      candidate.capabilities.imageInput = true
      candidate.capabilities.modelCatalog = true
      candidate.capabilities.usage = true
      if (candidate.accountIdentityHash.length === 0 && accountHash.length > 0) {
        candidate.accountIdentityHash = accountHash
      }
      if (candidate.requestIdentity() !== existing.requestIdentity()) {
        output.profiles[index] = LlmSourceProfileRepository.prepareForUpsert(
          existing,
          candidate,
          now,
        )
      }
      sourceId = existing.sourceProfileId
    } else {
      sourceId = LlmSourceMigrationPlanner.allocateId(
        output.profiles,
        'migrated-manga-codex',
      )
      const candidate: LlmSourceProfile = new LlmSourceProfile()
      candidate.sourceProfileId = sourceId
      candidate.displayName = 'Codex（迁移）'
      candidate.sourceType = LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL
      candidate.accountIdentityHash = accountHash
      candidate.capabilities.responses = true
      candidate.capabilities.imageInput = true
      candidate.capabilities.modelCatalog = true
      candidate.capabilities.usage = true
      output.profiles.push(LlmSourceProfileRepository.prepareForUpsert(null, candidate, now))
    }
    if (encodedTokens.length > 0) {
      output.codexTokens[sourceId] = encodedTokens
    }
    if (tokens !== null && tokens.accountId.length > 0 &&
      ComicTranslationCodexUsageService.parseCached(
        legacy.codexUsageCacheText,
        tokens.accountId,
      ) !== null) {
      output.usageCaches[sourceId] = legacy.codexUsageCacheText
    }
    return sourceId
  }

  private static findCodexSource(
    output: LlmSourceMigrationPlan,
    encodedTokens: string,
    accountHash: string,
  ): number {
    for (let index: number = 0; index < output.profiles.length; index++) {
      const profile: LlmSourceProfile = output.profiles[index]
      if (profile.sourceType !== LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL) {
        continue
      }
      const storedTokens: string = output.codexTokens[profile.sourceProfileId] === undefined
        ? ''
        : output.codexTokens[profile.sourceProfileId]
      if (encodedTokens.length > 0 && storedTokens === encodedTokens) {
        return index
      }
      if (accountHash.length > 0 && profile.accountIdentityHash === accountHash) {
        return index
      }
      if (profile.sourceProfileId === 'migrated-manga-codex' &&
        encodedTokens.length === 0 && accountHash.length === 0) {
        return index
      }
    }
    return -1
  }

  private static mergeApiCapabilities(
    capabilities: LlmSourceCapabilities,
    target: LegacyApiTarget,
  ): void {
    if (target.comment) {
      capabilities.chatCompletions = true
    }
    if (target.manga) {
      capabilities.responses = true
      capabilities.imageInput = true
    }
    capabilities.modelCatalog = true
  }

  private static allocateId(profiles: LlmSourceProfile[], preferredId: string): string {
    if (profiles.length >= MAX_LLM_SOURCE_PROFILES) {
      throw new Error('No room for migrated LLM source profile')
    }
    if (!LlmSourceMigrationPlanner.containsProfile(profiles, preferredId)) {
      return preferredId
    }
    for (let suffix: number = 2; suffix <= MAX_LLM_SOURCE_PROFILES + 1; suffix++) {
      const candidate: string = preferredId + '-' + suffix
      if (!LlmSourceMigrationPlanner.containsProfile(profiles, candidate)) {
        return candidate
      }
    }
    throw new Error('No stable ID for migrated LLM source profile')
  }

  private static containsProfile(profiles: LlmSourceProfile[], sourceProfileId: string): boolean {
    for (let index: number = 0; index < profiles.length; index++) {
      if (profiles[index].sourceProfileId === sourceProfileId) {
        return true
      }
    }
    return false
  }

  private static binding(
    consumerId: string,
    sourceProfileId: string,
    modelId: string,
  ): LlmConsumerBinding {
    const value: LlmConsumerBinding = new LlmConsumerBinding()
    value.consumerId = consumerId
    value.sourceProfileId = sourceProfileId
    value.modelId = modelId
    LlmSourceProfileContract.validateBinding(value)
    return value
  }

  private static validCredential(value: string): boolean {
    if (typeof value !== 'string' || value.length > LEGACY_API_KEY_MAX_CHARS ||
      value !== value.trim()) {
      return false
    }
    for (let index: number = 0; index < value.length; index++) {
      const code: number = value.charCodeAt(index)
      if (code <= 31 || code === 127) {
        return false
      }
    }
    return true
  }

  private static hashIdentity(value: string): string {
    const encoded: Uint8Array = new util.TextEncoder().encodeInto(value)
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: encoded })
    const bytes: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }

  private static copyMap(values: MigrationStringMap): MigrationStringMap {
    const output: MigrationStringMap = {}
    const keys: string[] = Object.keys(values)
    for (let index: number = 0; index < keys.length; index++) {
      output[keys[index]] = values[keys[index]]
    }
    return output
  }
}

/** One-shot device migration. Old keys remain untouched until all consumers use shared resolution. */
export class LlmSourceMigrationService {
  static async migrateIfNeeded(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const currentVersion: number = LlmSourceMigrationService.safeVersion(
        store.getSync(StorageKeys.LLM_SOURCE_MIGRATION_VERSION, 0),
      )
      if (currentVersion >= LLM_SOURCE_MIGRATION_VERSION) {
        return false
      }
      const all: Record<string, preferences.ValueType> =
        store.getAllSync() as Record<string, preferences.ValueType>
      const input: LlmSourceMigrationInput = LlmSourceMigrationService.readInput(store, all)
      const plan: LlmSourceMigrationPlan = LlmSourceMigrationPlanner.plan(input)
      LlmSourceMigrationService.writePlan(store, plan)
      store.putSync(StorageKeys.LLM_SOURCE_MIGRATION_VERSION, LLM_SOURCE_MIGRATION_VERSION)
      store.flushSync()
      return true
    } catch (error) {
      DiagnosticLogger.warn('settings', 'llm_source_migration_failed', (error as Error).message)
      return false
    }
  }

  private static readInput(
    store: preferences.Preferences,
    all: Record<string, preferences.ValueType>,
  ): LlmSourceMigrationInput {
    const input: LlmSourceMigrationInput = new LlmSourceMigrationInput()
    input.profiles = LlmSourceProfileCodec.decode(
      store.getSync(StorageKeys.LLM_SOURCE_PROFILES, '') as string,
    )
    input.apiKeys = LlmSourceSecretStore.decodeApiKeyMap(
      store.getSync(StorageKeys.LLM_SOURCE_API_KEYS, '') as string,
    )
    input.codexTokens = LlmSourceSecretStore.decodeCodexTokenMap(
      store.getSync(StorageKeys.LLM_SOURCE_CODEX_OAUTH_TOKENS, '') as string,
    )
    input.usageCaches = LlmSourceSecretStore.decodeCacheMap(
      store.getSync(StorageKeys.LLM_SOURCE_USAGE_CACHE, '') as string,
    )
    input.commentBinding = LlmSourceMigrationService.readBinding(
      store,
      LLM_CONSUMER_COMMENT_TRANSLATION,
    )
    input.mangaBinding = LlmSourceMigrationService.readBinding(
      store,
      LLM_CONSUMER_MANGA_TRANSLATION,
    )
    const keys: string[] = Object.keys(all)
    input.comment.present = LlmSourceMigrationService.hasAny(keys, [
      StorageKeys.COMMENT_TRANSLATION_API_URL,
      StorageKeys.COMMENT_TRANSLATION_API_KEY,
      StorageKeys.COMMENT_TRANSLATION_MODEL,
    ])
    input.comment.apiUrl = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMMENT_TRANSLATION_API_URL,
      '',
    )
    input.comment.apiKey = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMMENT_TRANSLATION_API_KEY,
      '',
    )
    input.comment.model = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMMENT_TRANSLATION_MODEL,
      '',
    )

    const providerPresent: boolean = keys.indexOf(StorageKeys.COMIC_TRANSLATION_PROVIDER) >= 0
    const rawProvider: string = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMIC_TRANSLATION_PROVIDER,
      COMIC_TRANSLATION_PROVIDER_OPENAI_API,
    )
    input.manga.provider = rawProvider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH
      ? COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH
      : COMIC_TRANSLATION_PROVIDER_OPENAI_API
    input.manga.apiPresent = LlmSourceMigrationService.hasAny(keys, [
      StorageKeys.COMIC_TRANSLATION_API_URL,
      StorageKeys.COMIC_TRANSLATION_API_KEY,
      StorageKeys.COMIC_TRANSLATION_API_MODEL,
    ]) || (providerPresent && input.manga.provider === COMIC_TRANSLATION_PROVIDER_OPENAI_API)
    input.manga.apiBaseUrl = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMIC_TRANSLATION_API_URL,
      '',
    )
    input.manga.apiKey = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMIC_TRANSLATION_API_KEY,
      '',
    )
    input.manga.apiModel = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMIC_TRANSLATION_API_MODEL,
      '',
    )
    input.manga.codexPresent = input.manga.provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH ||
      LlmSourceMigrationService.hasAny(keys, [
        StorageKeys.COMIC_TRANSLATION_CODEX_MODEL,
        StorageKeys.COMIC_TRANSLATION_CODEX_OAUTH_TOKEN,
      ])
    input.manga.codexModel = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMIC_TRANSLATION_CODEX_MODEL,
      '',
    )
    input.manga.codexTokenText = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMIC_TRANSLATION_CODEX_OAUTH_TOKEN,
      '',
    )
    input.manga.codexUsageCacheText = LlmSourceMigrationService.readString(
      store,
      StorageKeys.COMIC_TRANSLATION_CODEX_USAGE_CACHE,
      '',
    )
    input.now = Date.now()
    return input
  }

  private static readBinding(
    store: preferences.Preferences,
    consumerId: string,
  ): LlmConsumerBinding {
    const binding: LlmConsumerBinding = LlmSourceMigrationPlanner.emptyBinding(consumerId)
    if (consumerId === LLM_CONSUMER_COMMENT_TRANSLATION) {
      binding.sourceProfileId = LlmSourceMigrationService.readString(
        store,
        StorageKeys.COMMENT_TRANSLATION_LLM_SOURCE_PROFILE,
        '',
      )
      binding.modelId = LlmSourceMigrationService.readString(
        store,
        StorageKeys.COMMENT_TRANSLATION_LLM_MODEL,
        '',
      )
    } else {
      binding.sourceProfileId = LlmSourceMigrationService.readString(
        store,
        StorageKeys.COMIC_TRANSLATION_LLM_SOURCE_PROFILE,
        '',
      )
      binding.modelId = LlmSourceMigrationService.readString(
        store,
        StorageKeys.COMIC_TRANSLATION_LLM_MODEL,
        '',
      )
    }
    try {
      LlmSourceProfileContract.validateBinding(binding)
      return binding
    } catch (_error) {
      return LlmSourceMigrationPlanner.emptyBinding(consumerId)
    }
  }

  private static writePlan(
    store: preferences.Preferences,
    plan: LlmSourceMigrationPlan,
  ): void {
    LlmSourceMigrationService.putOrDelete(
      store,
      StorageKeys.LLM_SOURCE_PROFILES,
      plan.profiles.length === 0 ? '' : LlmSourceProfileCodec.encode(plan.profiles),
    )
    LlmSourceMigrationService.putOrDelete(
      store,
      StorageKeys.LLM_SOURCE_API_KEYS,
      LlmSourceSecretStore.encodeApiKeyMap(plan.apiKeys),
    )
    LlmSourceMigrationService.putOrDelete(
      store,
      StorageKeys.LLM_SOURCE_CODEX_OAUTH_TOKENS,
      LlmSourceSecretStore.encodeCodexTokenMap(plan.codexTokens),
    )
    LlmSourceMigrationService.putOrDelete(
      store,
      StorageKeys.LLM_SOURCE_USAGE_CACHE,
      LlmSourceSecretStore.encodeCacheMap(plan.usageCaches),
    )
    LlmSourceMigrationService.writeBinding(store, plan.commentBinding)
    LlmSourceMigrationService.writeBinding(store, plan.mangaBinding)
  }

  private static writeBinding(
    store: preferences.Preferences,
    binding: LlmConsumerBinding,
  ): void {
    let sourceKey: string = StorageKeys.COMMENT_TRANSLATION_LLM_SOURCE_PROFILE
    let modelKey: string = StorageKeys.COMMENT_TRANSLATION_LLM_MODEL
    if (binding.consumerId === LLM_CONSUMER_MANGA_TRANSLATION) {
      sourceKey = StorageKeys.COMIC_TRANSLATION_LLM_SOURCE_PROFILE
      modelKey = StorageKeys.COMIC_TRANSLATION_LLM_MODEL
    }
    if (binding.configured()) {
      store.putSync(sourceKey, binding.sourceProfileId)
      store.putSync(modelKey, binding.modelId)
      return
    }
    store.deleteSync(sourceKey)
    store.deleteSync(modelKey)
  }

  private static putOrDelete(
    store: preferences.Preferences,
    key: string,
    value: string,
  ): void {
    if (value.length === 0 || value === '{}') {
      store.deleteSync(key)
      return
    }
    store.putSync(key, value)
  }

  private static hasAny(keys: string[], candidates: string[]): boolean {
    for (let index: number = 0; index < candidates.length; index++) {
      if (keys.indexOf(candidates[index]) >= 0) {
        return true
      }
    }
    return false
  }

  private static safeVersion(value: preferences.ValueType): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0
      ? Math.floor(value)
      : 0
  }

  private static readString(
    store: preferences.Preferences,
    key: string,
    fallback: string,
  ): string {
    const value: preferences.ValueType = store.getSync(key, fallback)
    return typeof value === 'string' ? value : fallback
  }
}

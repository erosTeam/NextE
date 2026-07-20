import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH,
  COMIC_TRANSLATION_PROVIDER_OPENAI_API,
  CodexOAuthTokenSet,
  ComicTranslationProviderSettingsSnapshot,
} from '../model/ComicTranslationProvider'
import { connectComicTranslationProviderSettings } from '../state/ComicTranslationProviderSettingsState'

const CODEX_OAUTH_TOKEN_STORE_MAX_CHARS: number = 512 * 1024
const CODEX_OAUTH_TOKEN_MAX_CHARS: number = 128 * 1024
const CODEX_OAUTH_ACCOUNT_ID_MAX_CHARS: number = 160

class RawCodexOAuthTokenSet {
  accessToken: string = ''
  refreshToken: string = ''
  idToken: string = ''
  accountId: string = ''
  expiresAt: number = 0
  lastRefreshAt: number = 0
}

export class ComicTranslationProviderSettings {
  static readonly API_URL_MAX_CHARS: number = 2048
  static readonly API_KEY_MAX_CHARS: number = 16 * 1024
  static readonly MODEL_ID_MAX_CHARS: number = 160

  static normalizeProvider(provider: string): string {
    return provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH
      ? COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH
      : COMIC_TRANSLATION_PROVIDER_OPENAI_API
  }

  static current(): ComicTranslationProviderSettingsSnapshot {
    const state = connectComicTranslationProviderSettings()
    const snapshot: ComicTranslationProviderSettingsSnapshot =
      new ComicTranslationProviderSettingsSnapshot()
    snapshot.provider = ComicTranslationProviderSettings.normalizeProvider(state.provider)
    snapshot.apiBaseUrl = state.apiBaseUrl
    snapshot.apiKey = state.apiKey
    snapshot.apiModel = state.apiModel
    snapshot.codexModel = state.codexModel
    return snapshot
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const snapshot: ComicTranslationProviderSettingsSnapshot =
        new ComicTranslationProviderSettingsSnapshot()
      snapshot.provider = ComicTranslationProviderSettings.normalizeProvider(
        store.getSync(StorageKeys.COMIC_TRANSLATION_PROVIDER, snapshot.provider) as string,
      )
      snapshot.apiBaseUrl = store.getSync(
        StorageKeys.COMIC_TRANSLATION_API_URL,
        snapshot.apiBaseUrl,
      ) as string
      snapshot.apiKey = store.getSync(StorageKeys.COMIC_TRANSLATION_API_KEY, '') as string
      snapshot.apiModel = store.getSync(
        StorageKeys.COMIC_TRANSLATION_API_MODEL,
        snapshot.apiModel,
      ) as string
      snapshot.codexModel = store.getSync(StorageKeys.COMIC_TRANSLATION_CODEX_MODEL, '') as string
      ComicTranslationProviderSettings.apply(snapshot)
      ComicTranslationProviderSettings.applyCodexStatus(
        ComicTranslationProviderSettings.parseCodexTokens(
          store.getSync(StorageKeys.COMIC_TRANSLATION_CODEX_OAUTH_TOKEN, '') as string,
        ),
      )
    } catch (error) {
      DiagnosticLogger.warn('settings', 'comic_translation_provider_restore_failed', (error as Error).message)
      ComicTranslationProviderSettings.apply(new ComicTranslationProviderSettingsSnapshot())
      ComicTranslationProviderSettings.applyCodexStatus(null)
    }
  }

  static async save(
    context: common.UIAbilityContext,
    snapshot: ComicTranslationProviderSettingsSnapshot,
  ): Promise<void> {
    ComicTranslationProviderSettings.normalizeSnapshot(snapshot)
    ComicTranslationProviderSettings.apply(snapshot)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.COMIC_TRANSLATION_PROVIDER, snapshot.provider)
      store.putSync(StorageKeys.COMIC_TRANSLATION_API_URL, snapshot.apiBaseUrl)
      store.putSync(StorageKeys.COMIC_TRANSLATION_API_KEY, snapshot.apiKey)
      store.putSync(StorageKeys.COMIC_TRANSLATION_API_MODEL, snapshot.apiModel)
      store.putSync(StorageKeys.COMIC_TRANSLATION_CODEX_MODEL, snapshot.codexModel)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'comic_translation_provider_save_failed', (error as Error).message)
    }
  }

  static normalizeSnapshot(snapshot: ComicTranslationProviderSettingsSnapshot): void {
    snapshot.provider = ComicTranslationProviderSettings.normalizeProvider(snapshot.provider)
    snapshot.apiBaseUrl = ComicTranslationProviderSettings.boundedSetting(
      snapshot.apiBaseUrl,
      ComicTranslationProviderSettings.API_URL_MAX_CHARS,
    )
    snapshot.apiKey = ComicTranslationProviderSettings.boundedSetting(
      snapshot.apiKey,
      ComicTranslationProviderSettings.API_KEY_MAX_CHARS,
    )
    snapshot.apiModel = ComicTranslationProviderSettings.boundedSetting(
      snapshot.apiModel,
      ComicTranslationProviderSettings.MODEL_ID_MAX_CHARS,
    )
    snapshot.codexModel = ComicTranslationProviderSettings.boundedSetting(
      snapshot.codexModel,
      ComicTranslationProviderSettings.MODEL_ID_MAX_CHARS,
    )
  }

  static async readCodexTokens(context: common.UIAbilityContext): Promise<CodexOAuthTokenSet | null> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      return ComicTranslationProviderSettings.parseCodexTokens(
        store.getSync(StorageKeys.COMIC_TRANSLATION_CODEX_OAUTH_TOKEN, '') as string,
      )
    } catch (error) {
      DiagnosticLogger.warn('settings', 'comic_translation_codex_token_read_failed', (error as Error).message)
      return null
    }
  }

  static async saveCodexTokens(
    context: common.UIAbilityContext,
    tokens: CodexOAuthTokenSet,
  ): Promise<void> {
    if (tokens.accessToken.length === 0 || tokens.refreshToken.length === 0) {
      throw new Error('Codex OAuth token response is incomplete')
    }
    if (!ComicTranslationProviderSettings.isValidCodexTokens(tokens)) {
      throw new Error('Codex OAuth token set is invalid')
    }
    const encoded: string = JSON.stringify(tokens)
    if (encoded.length > CODEX_OAUTH_TOKEN_STORE_MAX_CHARS) {
      throw new Error('Codex OAuth token set is invalid')
    }
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.putSync(StorageKeys.COMIC_TRANSLATION_CODEX_OAUTH_TOKEN, encoded)
    store.flushSync()
    ComicTranslationProviderSettings.applyCodexStatus(tokens)
  }

  static async clearCodexTokens(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.deleteSync(StorageKeys.COMIC_TRANSLATION_CODEX_OAUTH_TOKEN)
    store.flushSync()
    ComicTranslationProviderSettings.applyCodexStatus(null)
  }

  private static apply(snapshot: ComicTranslationProviderSettingsSnapshot): void {
    ComicTranslationProviderSettings.normalizeSnapshot(snapshot)
    const state = connectComicTranslationProviderSettings()
    state.provider = ComicTranslationProviderSettings.normalizeProvider(snapshot.provider)
    state.apiBaseUrl = snapshot.apiBaseUrl
    state.apiKey = snapshot.apiKey
    state.apiModel = snapshot.apiModel
    state.codexModel = snapshot.codexModel
  }

  private static applyCodexStatus(tokens: CodexOAuthTokenSet | null): void {
    const state = connectComicTranslationProviderSettings()
    state.codexConnected = tokens !== null &&
      tokens.accessToken.length > 0 && tokens.refreshToken.length > 0
    state.codexAccountId = tokens === null ? '' : tokens.accountId
  }

  static parseCodexTokens(rawText: string): CodexOAuthTokenSet | null {
    if (rawText.trim().length === 0 || rawText.length > CODEX_OAUTH_TOKEN_STORE_MAX_CHARS) {
      return null
    }
    try {
      const raw: RawCodexOAuthTokenSet = JSON.parse(rawText) as RawCodexOAuthTokenSet
      if (typeof raw.accessToken !== 'string' || raw.accessToken.length === 0 ||
        typeof raw.refreshToken !== 'string' || raw.refreshToken.length === 0) {
        return null
      }
      const tokens: CodexOAuthTokenSet = new CodexOAuthTokenSet()
      tokens.accessToken = raw.accessToken
      tokens.refreshToken = raw.refreshToken
      tokens.idToken = typeof raw.idToken === 'string' ? raw.idToken : ''
      tokens.accountId = typeof raw.accountId === 'string' ? raw.accountId : ''
      tokens.expiresAt = ComicTranslationProviderSettings.safeTimestamp(raw.expiresAt)
      tokens.lastRefreshAt = ComicTranslationProviderSettings.safeTimestamp(raw.lastRefreshAt)
      return ComicTranslationProviderSettings.isValidCodexTokens(tokens) ? tokens : null
    } catch (_error) {
      return null
    }
  }

  static isValidCodexTokens(tokens: CodexOAuthTokenSet): boolean {
    return ComicTranslationProviderSettings.validCredential(tokens.accessToken, true) &&
      ComicTranslationProviderSettings.validCredential(tokens.refreshToken, true) &&
      ComicTranslationProviderSettings.validCredential(tokens.idToken, false) &&
      ComicTranslationProviderSettings.validAccountId(tokens.accountId) &&
      ComicTranslationProviderSettings.validTimestamp(tokens.expiresAt) &&
      ComicTranslationProviderSettings.validTimestamp(tokens.lastRefreshAt)
  }

  private static validCredential(value: string, required: boolean): boolean {
    if (typeof value !== 'string' || value.length > CODEX_OAUTH_TOKEN_MAX_CHARS ||
      value !== value.trim()) {
      return false
    }
    if (required && value.length === 0) {
      return false
    }
    return !ComicTranslationProviderSettings.containsControlCharacter(value)
  }

  private static validAccountId(value: string): boolean {
    return typeof value === 'string' && value.length <= CODEX_OAUTH_ACCOUNT_ID_MAX_CHARS &&
      value === value.trim() && !ComicTranslationProviderSettings.containsControlCharacter(value)
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

  private static boundedSetting(value: string | null | undefined, maxChars: number): string {
    if (typeof value !== 'string') {
      return ''
    }
    const normalized: string = value.trim()
    if (normalized.length > maxChars ||
      ComicTranslationProviderSettings.containsControlCharacter(normalized)) {
      return ''
    }
    return normalized
  }

  private static validTimestamp(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 &&
      Math.floor(value) === value && value <= Number.MAX_SAFE_INTEGER
  }

  private static safeTimestamp(value: number | null | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 &&
      value <= Number.MAX_SAFE_INTEGER
      ? Math.floor(value)
      : 0
  }
}

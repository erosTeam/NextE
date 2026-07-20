import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { CodexOAuthTokenSet } from '../model/ComicTranslationProvider'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'
import { ExperimentalCodexOAuthService } from './ExperimentalCodexOAuthService'

const CODEX_USAGE_URL: string = 'https://chatgpt.com/backend-api/wham/usage'
const CODEX_USAGE_CONNECT_TIMEOUT_MS: number = 15000
const CODEX_USAGE_READ_TIMEOUT_MS: number = 20000
const CODEX_USAGE_MAX_BODY_CHARS: number = 512 * 1024
const FIVE_HOUR_WINDOW_SECONDS: number = 5 * 60 * 60
const WEEKLY_WINDOW_SECONDS: number = 7 * 24 * 60 * 60

class RawCodexUsageWindow {
  used_percent: number | string | null = null
  limit_window_seconds: number | string | null = null
  window_minutes: number | string | null = null
  reset_at: number | string | null = null
}

class RawCodexRateLimit {
  primary_window: RawCodexUsageWindow | null = null
  secondary_window: RawCodexUsageWindow | null = null
}

class RawCodexUsageEnvelope {
  plan_type: string = ''
  rate_limit: RawCodexRateLimit | null = null
}

class RawCachedCodexUsageSnapshot {
  planType: string = ''
  primary: CodexUsageWindow | null = null
  secondary: CodexUsageWindow | null = null
  fiveHour: CodexUsageWindow | null = null
  weekly: CodexUsageWindow | null = null
  fetchedAtMs: number = 0
}

class RawCodexUsageCacheEnvelope {
  accountId: string = ''
  snapshot: RawCachedCodexUsageSnapshot | null = null
}

export class CodexUsageWindow {
  usedPercent: number = 0
  windowSeconds: number = 0
  resetsAtMs: number = 0
}

export class CodexUsageSnapshot {
  planType: string = ''
  primary: CodexUsageWindow | null = null
  secondary: CodexUsageWindow | null = null
  fiveHour: CodexUsageWindow | null = null
  weekly: CodexUsageWindow | null = null
  fetchedAtMs: number = 0
}

export interface CodexUsageHttpTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse>
}

export class DefaultCodexUsageHttpTransport implements CodexUsageHttpTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    return AxiosHttpClient.requestText(
      url,
      method,
      headers,
      body,
      connectTimeoutMs,
      readTimeoutMs,
    )
  }
}

/** Queries the same undocumented account usage surface as current Codex clients. */
export class ComicTranslationCodexUsageService {
  static async fetch(
    context: common.UIAbilityContext,
    transport: CodexUsageHttpTransport = new DefaultCodexUsageHttpTransport(),
  ): Promise<CodexUsageSnapshot> {
    let tokens: CodexOAuthTokenSet = await ExperimentalCodexOAuthService.usableTokens(context)
    let response: AxiosTextResponse = await ComicTranslationCodexUsageService.request(tokens, transport)
    if (response.statusCode === 401) {
      tokens = await ExperimentalCodexOAuthService.usableTokens(context, true)
      response = await ComicTranslationCodexUsageService.request(tokens, transport)
    }
    if (response.statusCode !== 200) {
      throw new Error('Codex usage query failed (HTTP ' + response.statusCode + ')')
    }
    return ComicTranslationCodexUsageService.parse(response.body)
  }

  static async cached(
    context: common.UIAbilityContext,
    accountId: string,
  ): Promise<CodexUsageSnapshot | null> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      return ComicTranslationCodexUsageService.parseCached(
        store.getSync(StorageKeys.COMIC_TRANSLATION_CODEX_USAGE_CACHE, '') as string,
        accountId,
      )
    } catch (error) {
      DiagnosticLogger.warn('comic-translation', 'codex_usage_cache_read_failed', (error as Error).message)
      return null
    }
  }

  static async saveCached(
    context: common.UIAbilityContext,
    accountId: string,
    snapshot: CodexUsageSnapshot,
  ): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(
        StorageKeys.COMIC_TRANSLATION_CODEX_USAGE_CACHE,
        ComicTranslationCodexUsageService.serializeCached(accountId, snapshot),
      )
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('comic-translation', 'codex_usage_cache_write_failed', (error as Error).message)
    }
  }

  static async clearCached(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.deleteSync(StorageKeys.COMIC_TRANSLATION_CODEX_USAGE_CACHE)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('comic-translation', 'codex_usage_cache_clear_failed', (error as Error).message)
    }
  }

  static serializeCached(accountId: string, snapshot: CodexUsageSnapshot): string {
    const envelope: RawCodexUsageCacheEnvelope = new RawCodexUsageCacheEnvelope()
    envelope.accountId = accountId.trim()
    const cached: RawCachedCodexUsageSnapshot = new RawCachedCodexUsageSnapshot()
    cached.planType = snapshot.planType
    cached.primary = snapshot.primary
    cached.secondary = snapshot.secondary
    cached.fiveHour = snapshot.fiveHour
    cached.weekly = snapshot.weekly
    cached.fetchedAtMs = snapshot.fetchedAtMs
    envelope.snapshot = cached
    return JSON.stringify(envelope)
  }

  static parseCached(rawText: string, expectedAccountId: string): CodexUsageSnapshot | null {
    if (rawText.trim().length === 0) {
      return null
    }
    try {
      const envelope: RawCodexUsageCacheEnvelope =
        JSON.parse(rawText) as RawCodexUsageCacheEnvelope
      if (typeof envelope.accountId !== 'string' ||
        envelope.accountId !== expectedAccountId.trim() || envelope.snapshot === null ||
        typeof envelope.snapshot !== 'object') {
        return null
      }
      const snapshot: CodexUsageSnapshot = new CodexUsageSnapshot()
      snapshot.planType = typeof envelope.snapshot.planType === 'string'
        ? envelope.snapshot.planType.trim()
        : ''
      snapshot.primary = ComicTranslationCodexUsageService.cachedWindow(envelope.snapshot.primary)
      snapshot.secondary = ComicTranslationCodexUsageService.cachedWindow(envelope.snapshot.secondary)
      snapshot.fiveHour = ComicTranslationCodexUsageService.cachedWindow(envelope.snapshot.fiveHour)
      snapshot.weekly = ComicTranslationCodexUsageService.cachedWindow(envelope.snapshot.weekly)
      snapshot.fetchedAtMs = ComicTranslationCodexUsageService.safeTimestamp(
        envelope.snapshot.fetchedAtMs,
      )
      if (snapshot.fiveHour === null && snapshot.weekly === null) {
        return null
      }
      return snapshot
    } catch (_error) {
      return null
    }
  }

  static parse(rawText: string): CodexUsageSnapshot {
    if (rawText.length === 0 || rawText.length > CODEX_USAGE_MAX_BODY_CHARS) {
      throw new Error('Codex usage response size is invalid')
    }
    const envelope: RawCodexUsageEnvelope = JSON.parse(rawText) as RawCodexUsageEnvelope
    if (envelope.rate_limit === null || typeof envelope.rate_limit !== 'object') {
      throw new Error('Codex usage response has no rate limit')
    }
    const snapshot: CodexUsageSnapshot = new CodexUsageSnapshot()
    snapshot.planType = typeof envelope.plan_type === 'string' ? envelope.plan_type.trim() : ''
    snapshot.primary = ComicTranslationCodexUsageService.parseWindow(
      envelope.rate_limit.primary_window,
    )
    snapshot.secondary = ComicTranslationCodexUsageService.parseWindow(
      envelope.rate_limit.secondary_window,
    )
    if (snapshot.primary === null && snapshot.secondary === null) {
      throw new Error('Codex usage response has no limit windows')
    }
    snapshot.fiveHour = ComicTranslationCodexUsageService.windowByDuration(
      snapshot.primary,
      snapshot.secondary,
      FIVE_HOUR_WINDOW_SECONDS,
    )
    snapshot.weekly = ComicTranslationCodexUsageService.windowByDuration(
      snapshot.primary,
      snapshot.secondary,
      WEEKLY_WINDOW_SECONDS,
    )
    snapshot.fetchedAtMs = Date.now()
    return snapshot
  }

  private static windowByDuration(
    primary: CodexUsageWindow | null,
    secondary: CodexUsageWindow | null,
    expectedSeconds: number,
  ): CodexUsageWindow | null {
    if (primary !== null && primary.windowSeconds === expectedSeconds) {
      return primary
    }
    if (secondary !== null && secondary.windowSeconds === expectedSeconds) {
      return secondary
    }
    return null
  }

  private static request(
    tokens: CodexOAuthTokenSet,
    transport: CodexUsageHttpTransport,
  ): Promise<AxiosTextResponse> {
    if (tokens.accountId.length > 0) {
      return transport.requestText(
        CODEX_USAGE_URL,
        'GET',
        {
          'User-Agent': 'codex_cli_rs/0.0.0 (NextE experimental)',
          'Accept': 'application/json',
          'Authorization': 'Bearer ' + tokens.accessToken,
          'ChatGPT-Account-ID': tokens.accountId,
          'originator': 'codex_cli_rs',
        },
        '',
        CODEX_USAGE_CONNECT_TIMEOUT_MS,
        CODEX_USAGE_READ_TIMEOUT_MS,
      )
    }
    return transport.requestText(
      CODEX_USAGE_URL,
      'GET',
      {
        'User-Agent': 'codex_cli_rs/0.0.0 (NextE experimental)',
        'Accept': 'application/json',
        'Authorization': 'Bearer ' + tokens.accessToken,
        'originator': 'codex_cli_rs',
      },
      '',
      CODEX_USAGE_CONNECT_TIMEOUT_MS,
      CODEX_USAGE_READ_TIMEOUT_MS,
    )
  }

  private static parseWindow(raw: RawCodexUsageWindow | null): CodexUsageWindow | null {
    if (raw === null || typeof raw !== 'object') {
      return null
    }
    const window: CodexUsageWindow = new CodexUsageWindow()
    window.usedPercent = ComicTranslationCodexUsageService.clampedPercent(raw.used_percent)
    const seconds: number = ComicTranslationCodexUsageService.safeNumber(
      raw.limit_window_seconds,
    )
    const minutes: number = ComicTranslationCodexUsageService.safeNumber(raw.window_minutes)
    window.windowSeconds = seconds > 0 ? Math.floor(seconds) : Math.floor(minutes * 60)
    window.resetsAtMs = ComicTranslationCodexUsageService.epochMs(raw.reset_at)
    if (window.windowSeconds <= 0 && window.resetsAtMs <= 0) {
      return null
    }
    return window
  }

  private static cachedWindow(raw: CodexUsageWindow | null): CodexUsageWindow | null {
    if (raw === null || typeof raw !== 'object') {
      return null
    }
    const window: CodexUsageWindow = new CodexUsageWindow()
    window.usedPercent = ComicTranslationCodexUsageService.clampedPercent(raw.usedPercent)
    window.windowSeconds = Math.max(
      0,
      Math.floor(ComicTranslationCodexUsageService.safeNumber(raw.windowSeconds)),
    )
    window.resetsAtMs = ComicTranslationCodexUsageService.safeTimestamp(raw.resetsAtMs)
    if (window.windowSeconds <= 0 && window.resetsAtMs <= 0) {
      return null
    }
    return window
  }

  private static clampedPercent(value: number | string | null): number {
    const parsed: number = ComicTranslationCodexUsageService.safeNumber(value)
    return Math.min(100, Math.max(0, parsed))
  }

  private static safeNumber(value: number | string | null | undefined): number {
    const parsed: number = typeof value === 'number' ? value : Number(value)
    return Number.isFinite(parsed) ? parsed : 0
  }

  private static epochMs(value: number | string | null): number {
    const parsed: number = ComicTranslationCodexUsageService.safeNumber(value)
    if (parsed <= 0) {
      return 0
    }
    return Math.floor(parsed > 100000000000 ? parsed : parsed * 1000)
  }

  private static safeTimestamp(value: number | null | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0
      ? Math.floor(value)
      : 0
  }
}

import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import {
  CodexOAuthAuthorizationExchange,
  CodexOAuthDeviceSession,
  CodexOAuthPollResult,
  CodexOAuthTokenSet,
} from '../model/ComicTranslationProvider'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'
import { ComicTranslationProviderSettings } from '../settings/ComicTranslationProviderSettings'
import { CodexOAuthTokenCodec } from './CodexOAuthTokenCodec'
import { LlmSourceSecretStore } from './LlmSourceSecretStore'

const CODEX_OAUTH_ISSUER: string = 'https://auth.openai.com'
const CODEX_OAUTH_DEVICE_CODE_URL: string = CODEX_OAUTH_ISSUER + '/api/accounts/deviceauth/usercode'
const CODEX_OAUTH_DEVICE_TOKEN_URL: string = CODEX_OAUTH_ISSUER + '/api/accounts/deviceauth/token'
const CODEX_OAUTH_TOKEN_URL: string = CODEX_OAUTH_ISSUER + '/oauth/token'
const CODEX_OAUTH_REDIRECT_URL: string = CODEX_OAUTH_ISSUER + '/deviceauth/callback'
const CODEX_OAUTH_VERIFICATION_URL: string = CODEX_OAUTH_ISSUER + '/codex/device'
const CODEX_OAUTH_CLIENT_ID: string = 'app_EMoamEEZ73f0CkXaXp7hrann'
const CODEX_OAUTH_SESSION_TTL_MS: number = 15 * 60 * 1000
const CODEX_OAUTH_REFRESH_SKEW_MS: number = 2 * 60 * 1000
const CODEX_OAUTH_CONNECT_TIMEOUT_MS: number = 15000
const CODEX_OAUTH_READ_TIMEOUT_MS: number = 20000
const CODEX_OAUTH_MAX_BODY_CHARS: number = 512 * 1024
const CODEX_OAUTH_USER_CODE_MAX_CHARS: number = 128
const CODEX_OAUTH_DEVICE_AUTH_ID_MAX_CHARS: number = 4096
const CODEX_OAUTH_EXCHANGE_FIELD_MAX_CHARS: number = 4096
const CODEX_OAUTH_MAX_POLL_INTERVAL_SECONDS: number = 60
const CODEX_OAUTH_MAX_TOKEN_LIFETIME_SECONDS: number = 30 * 24 * 60 * 60
const CODEX_OAUTH_USER_AGENT: string = 'NextE/1.2.4 experimental-codex-oauth'

class DeviceCodeResponse {
  user_code: string = ''
  device_auth_id: string = ''
  interval: number | string = 5
}

class DeviceTokenResponse {
  authorization_code: string = ''
  code_verifier: string = ''
}

class OAuthTokenResponse {
  access_token: string = ''
  refresh_token: string = ''
  id_token: string = ''
  expires_in: number | string = 0
}

export interface CodexOAuthHttpTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse>
}

export class DefaultCodexOAuthHttpTransport implements CodexOAuthHttpTransport {
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
      CODEX_OAUTH_MAX_BODY_CHARS,
    )
  }
}

/**
 * Experimental compatibility implementation of the Codex CLI device-code flow.
 * This is not a Platform API authentication mechanism and may stop working when the private backend changes.
 */
export class ExperimentalCodexOAuthService {
  static async requestDeviceCode(
    transport: CodexOAuthHttpTransport = new DefaultCodexOAuthHttpTransport(),
  ): Promise<CodexOAuthDeviceSession> {
    const response: AxiosTextResponse = await transport.requestText(
      CODEX_OAUTH_DEVICE_CODE_URL,
      'POST',
      ExperimentalCodexOAuthService.jsonHeaders(),
      JSON.stringify({ client_id: CODEX_OAUTH_CLIENT_ID }),
      CODEX_OAUTH_CONNECT_TIMEOUT_MS,
      CODEX_OAUTH_READ_TIMEOUT_MS,
    )
    ExperimentalCodexOAuthService.requireBoundedResponse(response.body)
    if (response.statusCode !== 200) {
      throw new Error('Codex device login request failed (HTTP ' + response.statusCode + ')')
    }
    const raw: DeviceCodeResponse | null = JSON.parse(response.body) as DeviceCodeResponse | null
    const userCode: string = raw === null ? '' : ExperimentalCodexOAuthService.boundedField(
      raw.user_code,
      CODEX_OAUTH_USER_CODE_MAX_CHARS,
    )
    const deviceAuthId: string = raw === null ? '' : ExperimentalCodexOAuthService.boundedField(
      raw.device_auth_id,
      CODEX_OAUTH_DEVICE_AUTH_ID_MAX_CHARS,
    )
    if (userCode.length === 0 || deviceAuthId.length === 0) {
      throw new Error('Codex device login returned an incomplete code')
    }
    const session: CodexOAuthDeviceSession = new CodexOAuthDeviceSession()
    session.userCode = userCode
    session.deviceAuthId = deviceAuthId
    session.verificationUrl = CODEX_OAUTH_VERIFICATION_URL
    const interval: number | string | null = raw === null ? 5 : raw.interval
    session.pollIntervalSeconds = Math.min(
      CODEX_OAUTH_MAX_POLL_INTERVAL_SECONDS,
      Math.max(3, ExperimentalCodexOAuthService.safeInteger(interval, 5)),
    )
    session.expiresAt = Date.now() + CODEX_OAUTH_SESSION_TTL_MS
    return session
  }

  static async pollDeviceCodeOnce(
    session: CodexOAuthDeviceSession,
    transport: CodexOAuthHttpTransport = new DefaultCodexOAuthHttpTransport(),
  ): Promise<CodexOAuthPollResult> {
    ExperimentalCodexOAuthService.requireValidSession(session)
    const response: AxiosTextResponse = await transport.requestText(
      CODEX_OAUTH_DEVICE_TOKEN_URL,
      'POST',
      ExperimentalCodexOAuthService.jsonHeaders(),
      JSON.stringify({
        device_auth_id: session.deviceAuthId,
        user_code: session.userCode,
      }),
      CODEX_OAUTH_CONNECT_TIMEOUT_MS,
      CODEX_OAUTH_READ_TIMEOUT_MS,
    )
    ExperimentalCodexOAuthService.requireBoundedResponse(response.body)
    const result: CodexOAuthPollResult = new CodexOAuthPollResult()
    if (response.statusCode === 403 || response.statusCode === 404) {
      result.pending = true
      return result
    }
    if (response.statusCode !== 200) {
      throw new Error('Codex device login polling failed (HTTP ' + response.statusCode + ')')
    }
    const raw: DeviceTokenResponse | null = JSON.parse(response.body) as DeviceTokenResponse | null
    const authorizationCode: string = raw === null ? '' : ExperimentalCodexOAuthService.boundedField(
      raw.authorization_code,
      CODEX_OAUTH_EXCHANGE_FIELD_MAX_CHARS,
    )
    const codeVerifier: string = raw === null ? '' : ExperimentalCodexOAuthService.boundedField(
      raw.code_verifier,
      CODEX_OAUTH_EXCHANGE_FIELD_MAX_CHARS,
    )
    if (authorizationCode.length === 0 || codeVerifier.length === 0) {
      throw new Error('Codex device login returned an incomplete authorization')
    }
    const exchange: CodexOAuthAuthorizationExchange = new CodexOAuthAuthorizationExchange()
    exchange.authorizationCode = authorizationCode
    exchange.codeVerifier = codeVerifier
    result.pending = false
    result.exchange = exchange
    return result
  }

  static async completeDeviceLogin(
    context: common.UIAbilityContext,
    session: CodexOAuthDeviceSession,
    transport: CodexOAuthHttpTransport = new DefaultCodexOAuthHttpTransport(),
  ): Promise<CodexOAuthTokenSet> {
    const tokens: CodexOAuthTokenSet = await ExperimentalCodexOAuthService.completeLogin(
      session,
      transport,
    )
    await ComicTranslationProviderSettings.saveCodexTokens(context, tokens)
    return tokens.copy()
  }

  static async completeSourceDeviceLogin(
    context: common.UIAbilityContext,
    sourceProfileId: string,
    session: CodexOAuthDeviceSession,
    transport: CodexOAuthHttpTransport = new DefaultCodexOAuthHttpTransport(),
  ): Promise<CodexOAuthTokenSet> {
    const tokens: CodexOAuthTokenSet = await ExperimentalCodexOAuthService.completeLogin(
      session,
      transport,
    )
    await LlmSourceSecretStore.saveCodexTokens(context, sourceProfileId, tokens)
    return tokens.copy()
  }

  static async usableTokens(
    context: common.UIAbilityContext,
    forceRefresh: boolean = false,
    transport: CodexOAuthHttpTransport = new DefaultCodexOAuthHttpTransport(),
  ): Promise<CodexOAuthTokenSet> {
    const stored: CodexOAuthTokenSet | null =
      await ComicTranslationProviderSettings.readCodexTokens(context)
    if (stored === null) {
      throw new Error('Codex login is required')
    }
    const inferredExpiry: number = stored.expiresAt > 0
      ? stored.expiresAt
      : ExperimentalCodexOAuthService.jwtExpiry(stored.accessToken)
    if (!forceRefresh && (inferredExpiry === 0 || inferredExpiry > Date.now() + CODEX_OAUTH_REFRESH_SKEW_MS)) {
      return stored.copy()
    }
    const refreshed: CodexOAuthTokenSet =
      await ExperimentalCodexOAuthService.refresh(stored, transport)
    await ComicTranslationProviderSettings.saveCodexTokens(context, refreshed)
    return refreshed.copy()
  }

  static async usableSourceTokens(
    context: common.UIAbilityContext,
    sourceProfileId: string,
    forceRefresh: boolean = false,
    transport: CodexOAuthHttpTransport = new DefaultCodexOAuthHttpTransport(),
  ): Promise<CodexOAuthTokenSet> {
    const stored: CodexOAuthTokenSet | null = await LlmSourceSecretStore.readCodexTokens(
      context,
      sourceProfileId,
    )
    if (stored === null) {
      throw new Error('Codex login is required')
    }
    const inferredExpiry: number = stored.expiresAt > 0
      ? stored.expiresAt
      : ExperimentalCodexOAuthService.jwtExpiry(stored.accessToken)
    if (!forceRefresh &&
      (inferredExpiry === 0 || inferredExpiry > Date.now() + CODEX_OAUTH_REFRESH_SKEW_MS)) {
      return stored.copy()
    }
    const refreshed: CodexOAuthTokenSet = await ExperimentalCodexOAuthService.refresh(
      stored,
      transport,
    )
    await LlmSourceSecretStore.saveCodexTokens(context, sourceProfileId, refreshed)
    return refreshed.copy()
  }

  static extractAccountId(token: string): string {
    return ExperimentalCodexOAuthService.jwtStringClaim(token, 'chatgpt_account_id')
  }

  static jwtExpiry(token: string): number {
    const payload: string = ExperimentalCodexOAuthService.jwtPayload(token)
    if (payload.length === 0) {
      return 0
    }
    const match: RegExpExecArray | null = /"exp"\s*:\s*(\d+)/.exec(payload)
    if (match === null) {
      return 0
    }
    const seconds: number = Number(match[1])
    const milliseconds: number = seconds * 1000
    return Number.isFinite(milliseconds) && milliseconds > 0 &&
      milliseconds <= Number.MAX_SAFE_INTEGER
      ? Math.floor(milliseconds)
      : 0
  }

  private static async exchangeAuthorization(
    exchange: CodexOAuthAuthorizationExchange,
    transport: CodexOAuthHttpTransport,
  ): Promise<CodexOAuthTokenSet> {
    const body: string = ExperimentalCodexOAuthService.formBody([
      ['grant_type', 'authorization_code'],
      ['code', exchange.authorizationCode],
      ['redirect_uri', CODEX_OAUTH_REDIRECT_URL],
      ['client_id', CODEX_OAUTH_CLIENT_ID],
      ['code_verifier', exchange.codeVerifier],
    ])
    const response: AxiosTextResponse = await transport.requestText(
      CODEX_OAUTH_TOKEN_URL,
      'POST',
      ExperimentalCodexOAuthService.formHeaders(),
      body,
      CODEX_OAUTH_CONNECT_TIMEOUT_MS,
      CODEX_OAUTH_READ_TIMEOUT_MS,
    )
    ExperimentalCodexOAuthService.requireBoundedResponse(response.body)
    if (response.statusCode !== 200) {
      throw new Error('Codex token exchange failed (HTTP ' + response.statusCode + ')')
    }
    return ExperimentalCodexOAuthService.parseTokenResponse(response.body, '')
  }

  private static async refresh(
    current: CodexOAuthTokenSet,
    transport: CodexOAuthHttpTransport,
  ): Promise<CodexOAuthTokenSet> {
    if (current.refreshToken.length === 0) {
      throw new Error('Codex refresh token is missing')
    }
    const body: string = ExperimentalCodexOAuthService.formBody([
      ['grant_type', 'refresh_token'],
      ['refresh_token', current.refreshToken],
      ['client_id', CODEX_OAUTH_CLIENT_ID],
    ])
    const response: AxiosTextResponse = await transport.requestText(
      CODEX_OAUTH_TOKEN_URL,
      'POST',
      ExperimentalCodexOAuthService.formHeaders(),
      body,
      CODEX_OAUTH_CONNECT_TIMEOUT_MS,
      CODEX_OAUTH_READ_TIMEOUT_MS,
    )
    ExperimentalCodexOAuthService.requireBoundedResponse(response.body)
    if (response.statusCode !== 200) {
      throw new Error('Codex token refresh failed (HTTP ' + response.statusCode + ')')
    }
    return ExperimentalCodexOAuthService.parseTokenResponse(response.body, current.refreshToken)
  }

  private static parseTokenResponse(rawText: string, fallbackRefreshToken: string): CodexOAuthTokenSet {
    const raw: OAuthTokenResponse | null = JSON.parse(rawText) as OAuthTokenResponse | null
    if (raw === null || typeof raw.access_token !== 'string' || raw.access_token.length === 0) {
      throw new Error('Codex token response is missing an access token')
    }
    const refreshToken: string = typeof raw.refresh_token === 'string' && raw.refresh_token.length > 0
      ? raw.refresh_token
      : fallbackRefreshToken
    if (refreshToken.length === 0) {
      throw new Error('Codex token response is missing a refresh token')
    }
    const tokens: CodexOAuthTokenSet = new CodexOAuthTokenSet()
    tokens.accessToken = raw.access_token
    tokens.refreshToken = refreshToken
    tokens.idToken = typeof raw.id_token === 'string' ? raw.id_token : ''
    tokens.accountId = ExperimentalCodexOAuthService.extractAccountId(tokens.accessToken)
    if (tokens.accountId.length === 0) {
      tokens.accountId = ExperimentalCodexOAuthService.extractAccountId(tokens.idToken)
    }
    if (!CodexOAuthTokenCodec.isValid(tokens)) {
      throw new Error('Codex OAuth token response is invalid')
    }
    const now: number = Date.now()
    const expiresIn: number = Math.min(
      CODEX_OAUTH_MAX_TOKEN_LIFETIME_SECONDS,
      ExperimentalCodexOAuthService.safeInteger(raw.expires_in, 0),
    )
    const jwtExpiresAt: number = ExperimentalCodexOAuthService.jwtExpiry(tokens.accessToken)
    tokens.expiresAt = expiresIn > 0
      ? now + expiresIn * 1000
      : Math.min(jwtExpiresAt, now + CODEX_OAUTH_MAX_TOKEN_LIFETIME_SECONDS * 1000)
    tokens.lastRefreshAt = now
    if (!CodexOAuthTokenCodec.isValid(tokens)) {
      throw new Error('Codex OAuth token response is invalid')
    }
    return tokens
  }

  private static requireBoundedResponse(rawText: string): void {
    if (rawText.length > CODEX_OAUTH_MAX_BODY_CHARS) {
      throw new Error('Codex OAuth response size is invalid')
    }
  }

  private static async completeLogin(
    session: CodexOAuthDeviceSession,
    transport: CodexOAuthHttpTransport,
  ): Promise<CodexOAuthTokenSet> {
    ExperimentalCodexOAuthService.requireValidSession(session)
    while (Date.now() < session.expiresAt) {
      await ExperimentalCodexOAuthService.delay(session.pollIntervalSeconds * 1000)
      const result: CodexOAuthPollResult =
        await ExperimentalCodexOAuthService.pollDeviceCodeOnce(session, transport)
      if (result.pending) {
        continue
      }
      if (result.exchange === null) {
        throw new Error('Codex device login exchange is missing')
      }
      return ExperimentalCodexOAuthService.exchangeAuthorization(result.exchange, transport)
    }
    throw new Error('Codex device login timed out')
  }

  private static requireValidSession(session: CodexOAuthDeviceSession): void {
    const now: number = Date.now()
    const userCode: string = ExperimentalCodexOAuthService.boundedField(
      session.userCode,
      CODEX_OAUTH_USER_CODE_MAX_CHARS,
    )
    const deviceAuthId: string = ExperimentalCodexOAuthService.boundedField(
      session.deviceAuthId,
      CODEX_OAUTH_DEVICE_AUTH_ID_MAX_CHARS,
    )
    if (userCode !== session.userCode || deviceAuthId !== session.deviceAuthId ||
      !Number.isFinite(session.expiresAt) || Math.floor(session.expiresAt) !== session.expiresAt ||
      now >= session.expiresAt || session.expiresAt > now + CODEX_OAUTH_SESSION_TTL_MS ||
      session.pollIntervalSeconds < 3 ||
      session.pollIntervalSeconds > CODEX_OAUTH_MAX_POLL_INTERVAL_SECONDS ||
      Math.floor(session.pollIntervalSeconds) !== session.pollIntervalSeconds) {
      throw new Error('Codex device login session expired')
    }
  }

  private static boundedField(value: string | null | undefined, maxChars: number): string {
    if (typeof value !== 'string') {
      return ''
    }
    const normalized: string = value.trim()
    if (normalized.length === 0 || normalized.length > maxChars) {
      return ''
    }
    for (let index: number = 0; index < normalized.length; index++) {
      const code: number = normalized.charCodeAt(index)
      if (code <= 31 || code === 127) {
        return ''
      }
    }
    return normalized
  }

  private static jwtStringClaim(token: string, claimName: string): string {
    const payload: string = ExperimentalCodexOAuthService.jwtPayload(token)
    if (payload.length === 0) {
      return ''
    }
    const pattern: RegExp = new RegExp(
      '"' + claimName + '"\\s*:\\s*("(?:\\\\.|[^"\\\\])*")',
    )
    const match: RegExpExecArray | null = pattern.exec(payload)
    if (match === null) {
      return ''
    }
    try {
      const value: string = JSON.parse(match[1]) as string
      return typeof value === 'string' ? value : ''
    } catch (_error) {
      return ''
    }
  }

  private static jwtPayload(token: string): string {
    const parts: string[] = token.split('.')
    if (parts.length < 2 || parts[1].length === 0) {
      return ''
    }
    let encoded: string = parts[1].replace(/-/g, '+').replace(/_/g, '/')
    while (encoded.length % 4 !== 0) {
      encoded += '='
    }
    try {
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(encoded)
      return util.TextDecoder.create('utf-8').decodeToString(bytes)
    } catch (_error) {
      return ''
    }
  }

  private static formBody(entries: string[][]): string {
    const parts: string[] = []
    for (let index: number = 0; index < entries.length; index++) {
      const entry: string[] = entries[index]
      if (entry.length === 2) {
        parts.push(encodeURIComponent(entry[0]) + '=' + encodeURIComponent(entry[1]))
      }
    }
    return parts.join('&')
  }

  private static jsonHeaders(): Record<string, string> {
    return {
      'User-Agent': CODEX_OAUTH_USER_AGENT,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    }
  }

  private static formHeaders(): Record<string, string> {
    return {
      'User-Agent': CODEX_OAUTH_USER_AGENT,
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    }
  }

  private static safeInteger(value: number | string | null | undefined, fallback: number): number {
    const parsed: number = typeof value === 'number' ? value : Number(value)
    return Number.isFinite(parsed) && parsed >= 0 && parsed <= Number.MAX_SAFE_INTEGER
      ? Math.floor(parsed)
      : fallback
  }

  private static delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => resolve(), milliseconds)
    })
  }
}

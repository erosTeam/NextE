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
    const raw: DeviceCodeResponse = JSON.parse(response.body) as DeviceCodeResponse
    if (typeof raw.user_code !== 'string' || raw.user_code.length === 0 ||
      typeof raw.device_auth_id !== 'string' || raw.device_auth_id.length === 0) {
      throw new Error('Codex device login returned an incomplete code')
    }
    const session: CodexOAuthDeviceSession = new CodexOAuthDeviceSession()
    session.userCode = raw.user_code
    session.deviceAuthId = raw.device_auth_id
    session.verificationUrl = CODEX_OAUTH_VERIFICATION_URL
    session.pollIntervalSeconds = Math.max(
      3,
      ExperimentalCodexOAuthService.safeInteger(raw.interval, 5),
    )
    session.expiresAt = Date.now() + CODEX_OAUTH_SESSION_TTL_MS
    return session
  }

  static async pollDeviceCodeOnce(
    session: CodexOAuthDeviceSession,
    transport: CodexOAuthHttpTransport = new DefaultCodexOAuthHttpTransport(),
  ): Promise<CodexOAuthPollResult> {
    if (session.deviceAuthId.length === 0 || session.userCode.length === 0 ||
      Date.now() >= session.expiresAt) {
      throw new Error('Codex device login session expired')
    }
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
    const raw: DeviceTokenResponse = JSON.parse(response.body) as DeviceTokenResponse
    if (typeof raw.authorization_code !== 'string' || raw.authorization_code.length === 0 ||
      typeof raw.code_verifier !== 'string' || raw.code_verifier.length === 0) {
      throw new Error('Codex device login returned an incomplete authorization')
    }
    const exchange: CodexOAuthAuthorizationExchange = new CodexOAuthAuthorizationExchange()
    exchange.authorizationCode = raw.authorization_code
    exchange.codeVerifier = raw.code_verifier
    result.pending = false
    result.exchange = exchange
    return result
  }

  static async completeDeviceLogin(
    context: common.UIAbilityContext,
    session: CodexOAuthDeviceSession,
    transport: CodexOAuthHttpTransport = new DefaultCodexOAuthHttpTransport(),
  ): Promise<CodexOAuthTokenSet> {
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
      const tokens: CodexOAuthTokenSet =
        await ExperimentalCodexOAuthService.exchangeAuthorization(result.exchange, transport)
      await ComicTranslationProviderSettings.saveCodexTokens(context, tokens)
      return tokens.copy()
    }
    throw new Error('Codex device login timed out')
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
    return Number.isFinite(seconds) && seconds > 0 ? Math.floor(seconds * 1000) : 0
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
    const raw: OAuthTokenResponse = JSON.parse(rawText) as OAuthTokenResponse
    if (typeof raw.access_token !== 'string' || raw.access_token.length === 0) {
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
    const expiresIn: number = ExperimentalCodexOAuthService.safeInteger(raw.expires_in, 0)
    tokens.expiresAt = expiresIn > 0
      ? Date.now() + expiresIn * 1000
      : ExperimentalCodexOAuthService.jwtExpiry(tokens.accessToken)
    tokens.lastRefreshAt = Date.now()
    return tokens
  }

  private static requireBoundedResponse(rawText: string): void {
    if (rawText.length > CODEX_OAUTH_MAX_BODY_CHARS) {
      throw new Error('Codex OAuth response size is invalid')
    }
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
    return Number.isFinite(parsed) && parsed >= 0 ? Math.floor(parsed) : fallback
  }

  private static delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => resolve(), milliseconds)
    })
  }
}

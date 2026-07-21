import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { EhConstants } from '../constants/EhConstants'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'
import { MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH } from './MangaTranslatorUiSidecarProtocol'

const AUTH_MAX_RESPONSE_CHARS: number = 64 * 1024
const AUTH_MAX_TOKEN_CHARS: number = 8192
const AUTH_MIN_USERNAME_CHARS: number = 2
const AUTH_MAX_USERNAME_CHARS: number = 50
const AUTH_MIN_PASSWORD_CHARS: number = 6
const AUTH_MAX_PASSWORD_CHARS: number = 2048

class MangaTranslatorUiLoginRequest {
  username: string = ''
  password: string = ''
}

class MangaTranslatorUiLoginResponse {
  success: boolean = false
  token: string = ''
  must_change_password: boolean = false
}

class MangaTranslatorUiSessionCacheEntry {
  credentialHash: string = ''
  token: string = ''
}

export class MangaTranslatorUiSessionRequest {
  baseUrl: string = ''
  username: string = ''
  password: string = ''
  legacySessionToken: string = ''
  connectTimeoutMs: number = 15000
  readTimeoutMs: number = 15000

  hasAccount(): boolean {
    return this.username.length > 0 && this.password.length > 0
  }
}

export interface MangaTranslatorUiSidecarSessionTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse>
}

export class DefaultMangaTranslatorUiSidecarSessionTransport implements
  MangaTranslatorUiSidecarSessionTransport {
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
      AUTH_MAX_RESPONSE_CHARS,
    )
  }
}

export interface MangaTranslatorUiSidecarSessionProvider {
  acquire(request: MangaTranslatorUiSessionRequest): Promise<string>
  invalidate(request: MangaTranslatorUiSessionRequest, rejectedToken: string): void
}

export class DefaultMangaTranslatorUiSidecarSessionProvider implements
  MangaTranslatorUiSidecarSessionProvider {
  acquire(request: MangaTranslatorUiSessionRequest): Promise<string> {
    return MangaTranslatorUiSidecarSessionService.acquire(request)
  }

  invalidate(request: MangaTranslatorUiSessionRequest, rejectedToken: string): void {
    MangaTranslatorUiSidecarSessionService.invalidate(request, rejectedToken)
  }
}

/** Keeps rotating session tokens in memory and logs in again only after an authenticated 401. */
export class MangaTranslatorUiSidecarSessionService {
  private static sessions: Map<string, MangaTranslatorUiSessionCacheEntry> = new Map()
  private static inFlight: Map<string, Promise<string>> = new Map()

  static async acquire(
    request: MangaTranslatorUiSessionRequest,
    transport: MangaTranslatorUiSidecarSessionTransport =
      new DefaultMangaTranslatorUiSidecarSessionTransport(),
  ): Promise<string> {
    MangaTranslatorUiSidecarSessionService.validateRequest(request)
    if (!request.hasAccount()) {
      return request.legacySessionToken
    }
    const cacheKey: string = MangaTranslatorUiSidecarSessionService.cacheKey(request)
    const credentialHash: string = MangaTranslatorUiSidecarSessionService.credentialHash(request)
    const cached: MangaTranslatorUiSessionCacheEntry | undefined =
      MangaTranslatorUiSidecarSessionService.sessions.get(cacheKey)
    if (cached !== undefined && cached.credentialHash === credentialHash) {
      return cached.token
    }
    const flightKey: string = cacheKey + ':' + credentialHash
    const existing: Promise<string> | undefined =
      MangaTranslatorUiSidecarSessionService.inFlight.get(flightKey)
    if (existing !== undefined) {
      return await existing
    }
    const pending: Promise<string> = MangaTranslatorUiSidecarSessionService.login(
      request,
      credentialHash,
      cacheKey,
      transport,
    )
    MangaTranslatorUiSidecarSessionService.inFlight.set(flightKey, pending)
    try {
      return await pending
    } finally {
      const current: Promise<string> | undefined =
        MangaTranslatorUiSidecarSessionService.inFlight.get(flightKey)
      if (current === pending) {
        MangaTranslatorUiSidecarSessionService.inFlight.delete(flightKey)
      }
    }
  }

  static invalidate(request: MangaTranslatorUiSessionRequest, rejectedToken: string): void {
    if (!request.hasAccount()) {
      return
    }
    const cacheKey: string = MangaTranslatorUiSidecarSessionService.cacheKey(request)
    const cached: MangaTranslatorUiSessionCacheEntry | undefined =
      MangaTranslatorUiSidecarSessionService.sessions.get(cacheKey)
    if (cached !== undefined && cached.token === rejectedToken) {
      MangaTranslatorUiSidecarSessionService.sessions.delete(cacheKey)
    }
  }

  static clearCachedSessions(): void {
    MangaTranslatorUiSidecarSessionService.sessions.clear()
    MangaTranslatorUiSidecarSessionService.inFlight.clear()
  }

  private static async login(
    request: MangaTranslatorUiSessionRequest,
    credentialHash: string,
    cacheKey: string,
    transport: MangaTranslatorUiSidecarSessionTransport,
  ): Promise<string> {
    const login: MangaTranslatorUiLoginRequest = new MangaTranslatorUiLoginRequest()
    login.username = request.username
    login.password = request.password
    const response: AxiosTextResponse = await transport.requestText(
      request.baseUrl + MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH,
      'POST',
      {
        'User-Agent': EhConstants.USER_AGENT,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      JSON.stringify(login),
      request.connectTimeoutMs,
      request.readTimeoutMs,
    )
    if (response.statusCode !== 200 || response.body.length <= 0 ||
      response.body.length > AUTH_MAX_RESPONSE_CHARS) {
      throw new Error('Manga rendering service login failed')
    }
    let envelope: MangaTranslatorUiLoginResponse
    try {
      envelope = JSON.parse(response.body) as MangaTranslatorUiLoginResponse
    } catch (_error) {
      throw new Error('Manga rendering service returned invalid login data')
    }
    if (envelope === null || typeof envelope !== 'object' || envelope.success !== true ||
      typeof envelope.token !== 'string' || envelope.token.length <= 0 ||
      envelope.token.length > AUTH_MAX_TOKEN_CHARS || /[\r\n]/.test(envelope.token)) {
      throw new Error('Manga rendering service login failed')
    }
    if (envelope.must_change_password === true) {
      throw new Error('Manga rendering service requires a password change')
    }
    const entry: MangaTranslatorUiSessionCacheEntry = new MangaTranslatorUiSessionCacheEntry()
    entry.credentialHash = credentialHash
    entry.token = envelope.token
    MangaTranslatorUiSidecarSessionService.sessions.set(cacheKey, entry)
    return entry.token
  }

  private static validateRequest(request: MangaTranslatorUiSessionRequest): void {
    const hasUsername: boolean = request.username.length > 0
    const hasPassword: boolean = request.password.length > 0
    if (request.baseUrl.length <= 0 || /[\r\n]/.test(request.baseUrl) ||
      hasUsername !== hasPassword ||
      (request.legacySessionToken.length > 0 && hasUsername) ||
      request.legacySessionToken.length > AUTH_MAX_TOKEN_CHARS ||
      /[\r\n]/.test(request.legacySessionToken) ||
      request.legacySessionToken.includes('\u0000')) {
      throw new Error('Manga rendering service authentication is invalid')
    }
    if (hasUsername && (request.username.length < AUTH_MIN_USERNAME_CHARS ||
      request.username.length > AUTH_MAX_USERNAME_CHARS ||
      request.username !== request.username.trim() || /[\r\n\t]/.test(request.username) ||
      request.username.includes('\u0000') ||
      request.password.length < AUTH_MIN_PASSWORD_CHARS ||
      request.password.length > AUTH_MAX_PASSWORD_CHARS ||
      request.password.includes('\u0000'))) {
      throw new Error('Manga rendering service authentication is invalid')
    }
    if (!hasUsername && request.legacySessionToken.length === 0) {
      throw new Error('Manga rendering service account is not configured')
    }
  }

  private static cacheKey(request: MangaTranslatorUiSessionRequest): string {
    return request.baseUrl + ':' + MangaTranslatorUiSidecarSessionService.digest(request.username)
  }

  private static credentialHash(request: MangaTranslatorUiSessionRequest): string {
    return MangaTranslatorUiSidecarSessionService.digest(request.username + '\n' + request.password)
  }

  private static digest(value: string): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: new util.TextEncoder().encodeInto(value) })
    const bytes: Uint8Array = md.digestSync().data
    let output: string = ''
    for (let index: number = 0; index < bytes.length; index++) {
      output += bytes[index].toString(16).padStart(2, '0')
    }
    return output
  }
}

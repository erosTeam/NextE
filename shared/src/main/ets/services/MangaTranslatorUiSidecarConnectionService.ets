import { EhConstants } from '../constants/EhConstants'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'
import { MangaTranslatorUiSidecarConfig } from './MangaTranslatorUiSidecarBackend'
import {
  MANGA_TRANSLATOR_UI_AUTH_CHECK_PATH,
  MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH,
  MANGA_TRANSLATOR_UI_EXPORT_PATH,
  MANGA_TRANSLATOR_UI_IMPORT_PATH,
  MANGA_TRANSLATOR_UI_PROTOCOL_REVISION,
} from './MangaTranslatorUiSidecarProtocol'
import {
  MangaTranslatorUiSessionRequest,
  MangaTranslatorUiSidecarSessionTransport,
  MangaTranslatorUiSidecarSessionService,
} from './MangaTranslatorUiSidecarSessionService'

const OPENAPI_PATH: string = '/openapi.json'
const CONNECTION_MAX_BODY_CHARS: number = 2 * 1024 * 1024
const CONNECTION_TIMEOUT_MS: number = 15000

class SidecarOpenApiPath {
  post: Object | null = null
  get: Object | null = null
}

class SidecarOpenApiEnvelope {
  paths: Record<string, SidecarOpenApiPath> = {}
}

class SidecarAuthCheckEnvelope {
  valid: boolean = false
}

export class MangaTranslatorUiSidecarConnectionResult {
  protocolRevision: number = MANGA_TRANSLATOR_UI_PROTOCOL_REVISION
}

export interface MangaTranslatorUiSidecarConnectionTransport extends
  MangaTranslatorUiSidecarSessionTransport {}

export class DefaultMangaTranslatorUiSidecarConnectionTransport implements
  MangaTranslatorUiSidecarConnectionTransport {
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
      CONNECTION_MAX_BODY_CHARS,
    )
  }
}

/** Probes the pinned export/import capability without uploading a manga image. */
export class MangaTranslatorUiSidecarConnectionService {
  static async check(
    config: MangaTranslatorUiSidecarConfig,
    transport: MangaTranslatorUiSidecarConnectionTransport =
      new DefaultMangaTranslatorUiSidecarConnectionTransport(),
  ): Promise<MangaTranslatorUiSidecarConnectionResult> {
    const baseUrl: string = config.validatedBaseUrl()
    const headers: Record<string, string> = {
      'User-Agent': EhConstants.USER_AGENT,
      'Accept': 'application/json',
    }
    const response: AxiosTextResponse = await transport.requestText(
      baseUrl + OPENAPI_PATH,
      'GET',
      headers,
      '',
      CONNECTION_TIMEOUT_MS,
      CONNECTION_TIMEOUT_MS,
    )
    if (response.statusCode !== 200) {
      throw new Error('Manga rendering service check failed (HTTP ' + response.statusCode + ')')
    }
    MangaTranslatorUiSidecarConnectionService.requireCapabilities(response.body)
    const sessionRequest: MangaTranslatorUiSessionRequest = config.sessionRequest(baseUrl)
    const sessionToken: string = await MangaTranslatorUiSidecarSessionService.acquire(
      sessionRequest,
      transport,
    )
    const authResponse: AxiosTextResponse = await transport.requestText(
      baseUrl + MANGA_TRANSLATOR_UI_AUTH_CHECK_PATH,
      'GET',
      {
        'User-Agent': EhConstants.USER_AGENT,
        'Accept': 'application/json',
        'X-Session-Token': sessionToken,
      },
      '',
      CONNECTION_TIMEOUT_MS,
      CONNECTION_TIMEOUT_MS,
    )
    MangaTranslatorUiSidecarConnectionService.requireAuthenticated(authResponse)
    return new MangaTranslatorUiSidecarConnectionResult()
  }

  static requireCapabilities(rawText: string): void {
    if (rawText.length === 0 || rawText.length > CONNECTION_MAX_BODY_CHARS) {
      throw new Error('Manga rendering service capability response size is invalid')
    }
    let envelope: SidecarOpenApiEnvelope
    try {
      envelope = JSON.parse(rawText) as SidecarOpenApiEnvelope
    } catch (_error) {
      throw new Error('Manga rendering service returned invalid capability JSON')
    }
    if (envelope.paths === null || typeof envelope.paths !== 'object' ||
      !MangaTranslatorUiSidecarConnectionService.hasPost(envelope, MANGA_TRANSLATOR_UI_EXPORT_PATH) ||
      !MangaTranslatorUiSidecarConnectionService.hasPost(envelope, MANGA_TRANSLATOR_UI_IMPORT_PATH) ||
      !MangaTranslatorUiSidecarConnectionService.hasPost(envelope, MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH) ||
      !MangaTranslatorUiSidecarConnectionService.hasGet(envelope, MANGA_TRANSLATOR_UI_AUTH_CHECK_PATH)) {
      throw new Error('Manga rendering service does not support the pinned export/import protocol')
    }
  }

  private static requireAuthenticated(response: AxiosTextResponse): void {
    if (response.statusCode !== 200 || response.body.length <= 0 ||
      response.body.length > CONNECTION_MAX_BODY_CHARS) {
      throw new Error('Manga rendering service authentication check failed')
    }
    let envelope: SidecarAuthCheckEnvelope
    try {
      envelope = JSON.parse(response.body) as SidecarAuthCheckEnvelope
    } catch (_error) {
      throw new Error('Manga rendering service returned invalid authentication data')
    }
    if (envelope === null || typeof envelope !== 'object' || envelope.valid !== true) {
      throw new Error('Manga rendering service session is invalid')
    }
  }

  private static hasPost(envelope: SidecarOpenApiEnvelope, path: string): boolean {
    const item: SidecarOpenApiPath | undefined = envelope.paths[path]
    return item !== undefined && item !== null && typeof item === 'object' &&
      item.post !== undefined && item.post !== null && typeof item.post === 'object'
  }

  private static hasGet(envelope: SidecarOpenApiEnvelope, path: string): boolean {
    const item: SidecarOpenApiPath | undefined = envelope.paths[path]
    return item !== undefined && item !== null && typeof item === 'object' &&
      item.get !== undefined && item.get !== null && typeof item.get === 'object'
  }
}

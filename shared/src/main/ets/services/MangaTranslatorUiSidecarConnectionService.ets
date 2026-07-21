import { EhConstants } from '../constants/EhConstants'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'
import { MangaTranslatorUiSidecarConfig } from './MangaTranslatorUiSidecarBackend'
import {
  MANGA_TRANSLATOR_UI_EXPORT_PATH,
  MANGA_TRANSLATOR_UI_IMPORT_PATH,
  MANGA_TRANSLATOR_UI_PROTOCOL_REVISION,
} from './MangaTranslatorUiSidecarProtocol'

const OPENAPI_PATH: string = '/openapi.json'
const CONNECTION_MAX_BODY_CHARS: number = 2 * 1024 * 1024
const CONNECTION_TIMEOUT_MS: number = 15000

class SidecarOpenApiPath {
  post: Object | null = null
}

class SidecarOpenApiEnvelope {
  paths: Record<string, SidecarOpenApiPath> = {}
}

export class MangaTranslatorUiSidecarConnectionResult {
  protocolRevision: number = MANGA_TRANSLATOR_UI_PROTOCOL_REVISION
}

export interface MangaTranslatorUiSidecarConnectionTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse>
}

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
    if (config.sessionToken.length > 0) {
      headers['X-Session-Token'] = config.sessionToken
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
      !MangaTranslatorUiSidecarConnectionService.hasPost(envelope, MANGA_TRANSLATOR_UI_IMPORT_PATH)) {
      throw new Error('Manga rendering service does not support the pinned export/import protocol')
    }
  }

  private static hasPost(envelope: SidecarOpenApiEnvelope, path: string): boolean {
    const item: SidecarOpenApiPath | undefined = envelope.paths[path]
    return item !== undefined && item !== null && typeof item === 'object' &&
      item.post !== undefined && item.post !== null && typeof item.post === 'object'
  }
}

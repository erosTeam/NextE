import { common } from '@kit.AbilityKit'
import { EhConstants } from '../constants/EhConstants'
import {
  COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH,
  CodexOAuthTokenSet,
  ComicTranslationProviderSettingsSnapshot,
} from '../model/ComicTranslationProvider'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'
import { ComicTranslationProviderSettings } from '../settings/ComicTranslationProviderSettings'
import { ExperimentalCodexOAuthService } from './ExperimentalCodexOAuthService'

const CODEX_MODELS_URL: string =
  'https://chatgpt.com/backend-api/codex/models?client_version=1.0.0'
const MODEL_CATALOG_CONNECT_TIMEOUT_MS: number = 15000
const MODEL_CATALOG_READ_TIMEOUT_MS: number = 20000
const MODEL_CATALOG_MAX_BODY_CHARS: number = 2 * 1024 * 1024
const MODEL_CATALOG_MAX_ENTRIES: number = 512
const MODEL_IDENTIFIER_MAX_CHARS: number = 160

class ApiModelEntry {
  id: string = ''
}

class ApiModelsEnvelope {
  data: ApiModelEntry[] = []
}

class CodexModelEntry {
  slug: string = ''
  supported_in_api: boolean | null = null
  visibility: string = ''
  priority: number | string | null = null
}

class CodexModelsEnvelope {
  models: CodexModelEntry[] = []
}

class RankedModel {
  id: string = ''
  priority: number = 10000
}

export interface ComicModelCatalogHttpTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse>
}

export class DefaultComicModelCatalogHttpTransport implements ComicModelCatalogHttpTransport {
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
      MODEL_CATALOG_MAX_BODY_CHARS,
    )
  }
}

/** Queries each provider's account-scoped model catalog without inventing a shared static allowlist. */
export class ComicTranslationModelCatalogService {
  static async fetchConfigured(
    context: common.UIAbilityContext,
    transport: ComicModelCatalogHttpTransport = new DefaultComicModelCatalogHttpTransport(),
  ): Promise<string[]> {
    const settings: ComicTranslationProviderSettingsSnapshot =
      ComicTranslationProviderSettings.current()
    if (settings.provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH) {
      return ComicTranslationModelCatalogService.fetchCodex(context, transport)
    }
    return ComicTranslationModelCatalogService.fetchApi(settings, transport)
  }

  static parseApiModels(rawText: string): string[] {
    ComicTranslationModelCatalogService.requireBoundedBody(rawText)
    const envelope: ApiModelsEnvelope = JSON.parse(rawText) as ApiModelsEnvelope
    if (!Array.isArray(envelope.data)) {
      throw new Error('Model catalog returned no data array')
    }
    ComicTranslationModelCatalogService.requireBoundedEntries(envelope.data.length)
    const models: string[] = []
    for (let index: number = 0; index < envelope.data.length; index++) {
      const item: ApiModelEntry | null = envelope.data[index]
      const id: string = item === null
        ? ''
        : ComicTranslationModelCatalogService.normalizeModelId(item.id)
      if (id.length > 0 && models.indexOf(id) < 0) {
        models.push(id)
      }
    }
    models.sort()
    return models
  }

  static parseCodexModels(rawText: string): string[] {
    ComicTranslationModelCatalogService.requireBoundedBody(rawText)
    const envelope: CodexModelsEnvelope = JSON.parse(rawText) as CodexModelsEnvelope
    if (!Array.isArray(envelope.models)) {
      throw new Error('Codex model catalog returned no models array')
    }
    ComicTranslationModelCatalogService.requireBoundedEntries(envelope.models.length)
    const ranked: RankedModel[] = []
    for (let index: number = 0; index < envelope.models.length; index++) {
      const item: CodexModelEntry | null = envelope.models[index]
      if (item === null) {
        continue
      }
      const slug: string = ComicTranslationModelCatalogService.normalizeModelId(item.slug)
      const visibility: string = typeof item.visibility === 'string'
        ? item.visibility.trim().toLowerCase()
        : ''
      if (slug.length === 0 || item.supported_in_api === false ||
        visibility === 'hide' || visibility === 'hidden') {
        continue
      }
      if (ComicTranslationModelCatalogService.containsRanked(ranked, slug)) {
        continue
      }
      const model: RankedModel = new RankedModel()
      model.id = slug
      model.priority = ComicTranslationModelCatalogService.safePriority(item.priority)
      ranked.push(model)
    }
    ranked.sort((left: RankedModel, right: RankedModel): number => {
      if (left.priority !== right.priority) {
        return left.priority - right.priority
      }
      return left.id.localeCompare(right.id)
    })
    const models: string[] = []
    for (let index: number = 0; index < ranked.length; index++) {
      models.push(ranked[index].id)
    }
    return models
  }

  private static async fetchApi(
    settings: ComicTranslationProviderSettingsSnapshot,
    transport: ComicModelCatalogHttpTransport,
  ): Promise<string[]> {
    if (settings.apiKey.length === 0) {
      throw new Error('OpenAI API key is missing')
    }
    const response: AxiosTextResponse = await transport.requestText(
      ComicTranslationModelCatalogService.apiModelsUrl(settings.apiBaseUrl),
      'GET',
      {
        'User-Agent': EhConstants.USER_AGENT,
        'Accept': 'application/json',
        'Authorization': 'Bearer ' + settings.apiKey,
      },
      '',
      MODEL_CATALOG_CONNECT_TIMEOUT_MS,
      MODEL_CATALOG_READ_TIMEOUT_MS,
    )
    if (response.statusCode !== 200) {
      throw new Error('OpenAI model catalog failed (HTTP ' + response.statusCode + ')')
    }
    return ComicTranslationModelCatalogService.parseApiModels(response.body)
  }

  private static async fetchCodex(
    context: common.UIAbilityContext,
    transport: ComicModelCatalogHttpTransport,
  ): Promise<string[]> {
    let tokens: CodexOAuthTokenSet = await ExperimentalCodexOAuthService.usableTokens(context)
    let response: AxiosTextResponse = await ComicTranslationModelCatalogService.requestCodex(
      tokens,
      transport,
    )
    if (response.statusCode === 401) {
      tokens = await ExperimentalCodexOAuthService.usableTokens(context, true)
      response = await ComicTranslationModelCatalogService.requestCodex(tokens, transport)
    }
    if (response.statusCode !== 200) {
      throw new Error('Codex model catalog failed (HTTP ' + response.statusCode + ')')
    }
    return ComicTranslationModelCatalogService.parseCodexModels(response.body)
  }

  private static requestCodex(
    tokens: CodexOAuthTokenSet,
    transport: ComicModelCatalogHttpTransport,
  ): Promise<AxiosTextResponse> {
    const headers: Record<string, string> = {
      'User-Agent': 'codex_cli_rs/0.0.0 (NextE experimental)',
      'Accept': 'application/json',
      'Authorization': 'Bearer ' + tokens.accessToken,
      'originator': 'codex_cli_rs',
    }
    if (tokens.accountId.length > 0) {
      headers['ChatGPT-Account-ID'] = tokens.accountId
    }
    return transport.requestText(
      CODEX_MODELS_URL,
      'GET',
      headers,
      '',
      MODEL_CATALOG_CONNECT_TIMEOUT_MS,
      MODEL_CATALOG_READ_TIMEOUT_MS,
    )
  }

  private static apiModelsUrl(baseUrl: string): string {
    let normalized: string = baseUrl.trim().replace(/\/+$/, '')
    if (!normalized.toLowerCase().startsWith('https://')) {
      throw new Error('Comic provider base URL must use HTTPS')
    }
    if (normalized.endsWith('/responses')) {
      normalized = normalized.substring(0, normalized.length - '/responses'.length)
    }
    if (normalized.endsWith('/models')) {
      return normalized
    }
    if (normalized.endsWith('/v1')) {
      return normalized + '/models'
    }
    return normalized + '/v1/models'
  }

  private static requireBoundedBody(rawText: string): void {
    if (rawText.length === 0 || rawText.length > MODEL_CATALOG_MAX_BODY_CHARS) {
      throw new Error('Model catalog response size is invalid')
    }
  }

  private static requireBoundedEntries(entryCount: number): void {
    if (entryCount > MODEL_CATALOG_MAX_ENTRIES) {
      throw new Error('Model catalog entry count is invalid')
    }
  }

  private static normalizeModelId(value: string | null | undefined): string {
    if (typeof value !== 'string') {
      return ''
    }
    const normalized: string = value.trim()
    if (normalized.length === 0 || normalized.length > MODEL_IDENTIFIER_MAX_CHARS) {
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

  private static containsRanked(models: RankedModel[], id: string): boolean {
    for (let index: number = 0; index < models.length; index++) {
      if (models[index].id === id) {
        return true
      }
    }
    return false
  }

  private static safePriority(value: number | string | null): number {
    const parsed: number = typeof value === 'number' ? value : Number(value)
    return Number.isFinite(parsed) ? Math.floor(parsed) : 10000
  }
}

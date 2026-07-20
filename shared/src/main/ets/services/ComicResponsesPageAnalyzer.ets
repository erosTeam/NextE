import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { EhConstants } from '../constants/EhConstants'
import {
  COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH,
  CodexOAuthTokenSet,
  ComicTranslationProviderSettingsSnapshot,
} from '../model/ComicTranslationProvider'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'
import { ComicTranslationProviderSettings } from '../settings/ComicTranslationProviderSettings'
import { ComicPageAnalysisParser } from './ComicPageAnalysisParser'
import {
  ComicPageAnalysisRequest,
  ComicPageAnalysisResult,
  ComicPageAnalyzer,
  ComicPageAnalyzerCapabilities,
} from './ComicPageAnalyzer'
import { ComicResponsesProtocol } from './ComicResponsesProtocol'
import { ExperimentalCodexOAuthService } from './ExperimentalCodexOAuthService'

const COMIC_RESPONSES_PROMPT_VERSION: string = 'comic-page-responses-v1'
const COMIC_RESPONSES_MAX_IMAGE_BYTES: number = 20 * 1024 * 1024
const COMIC_RESPONSES_CONNECT_TIMEOUT_MS: number = 20000
const COMIC_RESPONSES_READ_TIMEOUT_MS: number = 120000
const CODEX_RESPONSES_BASE_URL: string = 'https://chatgpt.com/backend-api/codex'
const CODEX_RESPONSES_ORIGINATOR: string = 'codex_cli_rs'
const CODEX_RESPONSES_USER_AGENT: string = 'codex_cli_rs/0.0.0 (NextE experimental)'

interface ResponsesInputText {
  type: string
  text: string
}

interface ResponsesInputImage {
  type: string
  image_url: string
  detail: string
}

type ResponsesInputContent = ResponsesInputText | ResponsesInputImage

class ResponsesInputMessage {
  role: string = 'user'
  content: ResponsesInputContent[] = []
}

class PublicResponsesRequestBody {
  model: string = ''
  input: ResponsesInputMessage[] = []
  stream: boolean = false
  store: boolean = false
  max_output_tokens: number = 8192
}

class CodexResponsesReasoning {
}

class CodexResponsesRequestBody {
  model: string = ''
  instructions: string = ''
  input: ResponsesInputMessage[] = []
  tool_choice: string = 'auto'
  parallel_tool_calls: boolean = false
  reasoning: CodexResponsesReasoning | null = null
  store: boolean = false
  stream: boolean = true
  include: string[] = []
}

export class ComicResponsesRequestBuilder {
  static build(
    model: string,
    prompt: string,
    imageDataUrl: string,
    eventStream: boolean,
    codexCompatibility: boolean,
  ): string {
    const message: ResponsesInputMessage = new ResponsesInputMessage()
    const promptItem: ResponsesInputText = {
      type: 'input_text',
      text: prompt,
    }
    const imageItem: ResponsesInputImage = {
      type: 'input_image',
      image_url: imageDataUrl,
      detail: 'high',
    }
    message.content = [promptItem, imageItem]
    if (codexCompatibility) {
      const body: CodexResponsesRequestBody = new CodexResponsesRequestBody()
      body.model = model
      body.input = [message]
      return JSON.stringify(body)
    }
    const body: PublicResponsesRequestBody = new PublicResponsesRequestBody()
    body.model = model
    body.stream = eventStream
    body.input = [message]
    return JSON.stringify(body)
  }
}

export interface ComicResponsesHttpTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse>
}

export class DefaultComicResponsesHttpTransport implements ComicResponsesHttpTransport {
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

export class ComicProviderHttpError extends Error {
  readonly statusCode: number
  readonly detailCode: string

  constructor(statusCode: number, responseBody: string = '') {
    super('Comic provider request failed (HTTP ' + statusCode + ')')
    this.statusCode = statusCode
    this.detailCode = ComicProviderHttpError.classifyResponse(responseBody)
  }

  static classifyResponse(responseBody: string): string {
    const normalized: string = responseBody.toLowerCase()
    const fields: string[] = [
      'max_output_tokens',
      'instructions',
      'tools',
      'tool_choice',
      'parallel_tool_calls',
      'reasoning',
      'include',
      'store',
      'stream',
      'input',
      'image_url',
      'model',
      'text',
      'prompt_cache_key',
    ]
    let category: string = ''
    if (normalized.includes('unsupported') || normalized.includes('unrecognized') ||
      normalized.includes('unknown field') || normalized.includes('not permitted') ||
      normalized.includes('extra_forbidden')) {
      category = 'unsupported'
    } else if (normalized.includes('missing') || normalized.includes('required')) {
      category = 'missing'
    } else if (normalized.includes('invalid') || normalized.includes('expected')) {
      category = 'invalid'
    }
    if (category.length === 0) {
      return ''
    }
    for (let index: number = 0; index < fields.length; index++) {
      if (normalized.includes(fields[index])) {
        return category + '_' + fields[index]
      }
    }
    return category + '_request'
  }
}

class ComicResponsesCallConfig {
  providerId: string = ''
  baseUrl: string = ''
  model: string = ''
  accessToken: string = ''
  accountId: string = ''
  eventStream: boolean = false
  codexCompatibility: boolean = false
}

class ComicResponsesPageAnalyzerCore {
  private readonly transport: ComicResponsesHttpTransport

  constructor(transport: ComicResponsesHttpTransport) {
    this.transport = transport
  }

  async analyze(
    request: ComicPageAnalysisRequest,
    config: ComicResponsesCallConfig,
  ): Promise<ComicPageAnalysisResult> {
    if (config.accessToken.length === 0) {
      throw new Error('Comic translation provider credential is missing')
    }
    if (config.model.length === 0) {
      throw new Error('Comic translation provider model is missing')
    }
    const body: string = ComicResponsesRequestBuilder.build(
      config.model,
      ComicResponsesProtocol.buildPrompt(request),
      ComicResponsesPageAnalyzerCore.imageDataUrl(request),
      config.eventStream,
      config.codexCompatibility,
    )
    const response: AxiosTextResponse = await this.transport.requestText(
      ComicResponsesPageAnalyzerCore.responsesUrl(config.baseUrl),
      'POST',
      ComicResponsesPageAnalyzerCore.headers(config),
      body,
      COMIC_RESPONSES_CONNECT_TIMEOUT_MS,
      COMIC_RESPONSES_READ_TIMEOUT_MS,
    )
    if (response.statusCode !== 200) {
      throw new ComicProviderHttpError(response.statusCode, response.body)
    }
    const providerJson: string = ComicResponsesProtocol.extractAssistantJson(
      response.body,
      config.eventStream,
    )
    return ComicPageAnalysisParser.parse(
      request,
      providerJson,
      config.providerId,
      config.model,
      COMIC_RESPONSES_PROMPT_VERSION,
    )
  }

  static capabilities(): ComicPageAnalyzerCapabilities {
    const capabilities: ComicPageAnalyzerCapabilities = new ComicPageAnalyzerCapabilities()
    capabilities.transcript = true
    capabilities.readingOrder = true
    capabilities.geometry = false
    capabilities.speakerAssociation = false
    capabilities.mask = false
    capabilities.contextAwareTranslation = true
    return capabilities
  }

  private static imageDataUrl(request: ComicPageAnalysisRequest): string {
    const mimeType: string = request.imagePreparationProfile.mimeType.trim().toLowerCase()
    if (mimeType !== 'image/jpeg' && mimeType !== 'image/png' &&
      mimeType !== 'image/webp' && mimeType !== 'image/gif') {
      throw new Error('Comic provider image MIME type is unsupported')
    }
    let file: fileIo.File | null = null
    try {
      const stat: fileIo.Stat = fileIo.statSync(request.imageFilePath)
      if (stat.size <= 0 || stat.size > COMIC_RESPONSES_MAX_IMAGE_BYTES) {
        throw new Error('Comic provider image file size is invalid')
      }
      file = fileIo.openSync(request.imageFilePath, fileIo.OpenMode.READ_ONLY)
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size)
      const read: number = fileIo.readSync(file.fd, buffer, { length: stat.size })
      if (read !== stat.size) {
        throw new Error('Comic provider image file read was incomplete')
      }
      const encoded: string = new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer))
      return 'data:' + mimeType + ';base64,' + encoded
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static headers(config: ComicResponsesCallConfig): Record<string, string> {
    if (config.codexCompatibility) {
      if (config.accountId.length > 0) {
        return {
          'User-Agent': CODEX_RESPONSES_USER_AGENT,
          'Accept': 'text/event-stream',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + config.accessToken,
          'originator': CODEX_RESPONSES_ORIGINATOR,
          'ChatGPT-Account-ID': config.accountId,
        }
      }
      return {
        'User-Agent': CODEX_RESPONSES_USER_AGENT,
        'Accept': 'text/event-stream',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + config.accessToken,
        'originator': CODEX_RESPONSES_ORIGINATOR,
      }
    }
    return {
      'User-Agent': EhConstants.USER_AGENT,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + config.accessToken,
    }
  }

  private static responsesUrl(baseUrl: string): string {
    const normalized: string = baseUrl.trim().replace(/\/+$/, '')
    if (normalized.length === 0) {
      throw new Error('Comic provider base URL is missing')
    }
    if (!normalized.toLowerCase().startsWith('https://')) {
      throw new Error('Comic provider base URL must use HTTPS')
    }
    if (normalized.endsWith('/responses')) {
      return normalized
    }
    if (normalized.endsWith('/v1') || normalized.endsWith('/codex')) {
      return normalized + '/responses'
    }
    return normalized + '/v1/responses'
  }
}

export class OpenAiApiComicPageAnalyzer implements ComicPageAnalyzer {
  private readonly config: ComicResponsesCallConfig
  private readonly core: ComicResponsesPageAnalyzerCore

  constructor(
    baseUrl: string,
    apiKey: string,
    model: string,
    transport: ComicResponsesHttpTransport = new DefaultComicResponsesHttpTransport(),
  ) {
    this.config = new ComicResponsesCallConfig()
    this.config.providerId = 'openai-responses-api'
    this.config.baseUrl = baseUrl
    this.config.accessToken = apiKey
    this.config.model = model
    this.core = new ComicResponsesPageAnalyzerCore(transport)
  }

  providerId(): string {
    return this.config.providerId
  }

  modelId(): string {
    return this.config.model
  }

  analysisPromptVersion(): string {
    return COMIC_RESPONSES_PROMPT_VERSION
  }

  capabilities(): ComicPageAnalyzerCapabilities {
    return ComicResponsesPageAnalyzerCore.capabilities()
  }

  analyze(request: ComicPageAnalysisRequest): Promise<ComicPageAnalysisResult> {
    return this.core.analyze(request, this.config)
  }
}

export class ExperimentalCodexComicPageAnalyzer implements ComicPageAnalyzer {
  private readonly context: common.UIAbilityContext
  private readonly model: string
  private readonly core: ComicResponsesPageAnalyzerCore

  constructor(
    context: common.UIAbilityContext,
    model: string,
    transport: ComicResponsesHttpTransport = new DefaultComicResponsesHttpTransport(),
  ) {
    this.context = context
    this.model = model
    this.core = new ComicResponsesPageAnalyzerCore(transport)
  }

  providerId(): string {
    return 'codex-oauth-experimental'
  }

  modelId(): string {
    return this.model
  }

  analysisPromptVersion(): string {
    return COMIC_RESPONSES_PROMPT_VERSION
  }

  capabilities(): ComicPageAnalyzerCapabilities {
    return ComicResponsesPageAnalyzerCore.capabilities()
  }

  async analyze(request: ComicPageAnalysisRequest): Promise<ComicPageAnalysisResult> {
    let tokens: CodexOAuthTokenSet = await ExperimentalCodexOAuthService.usableTokens(this.context)
    try {
      return await this.core.analyze(request, this.callConfig(tokens))
    } catch (error) {
      if (!(error instanceof ComicProviderHttpError) || error.statusCode !== 401) {
        throw error as Error
      }
      tokens = await ExperimentalCodexOAuthService.usableTokens(this.context, true)
      return this.core.analyze(request, this.callConfig(tokens))
    }
  }

  private callConfig(tokens: CodexOAuthTokenSet): ComicResponsesCallConfig {
    const config: ComicResponsesCallConfig = new ComicResponsesCallConfig()
    config.providerId = this.providerId()
    config.baseUrl = CODEX_RESPONSES_BASE_URL
    config.model = this.model
    config.accessToken = tokens.accessToken
    config.accountId = tokens.accountId
    config.eventStream = true
    config.codexCompatibility = true
    return config
  }
}

export class ComicPageAnalyzerFactory {
  static create(
    context: common.UIAbilityContext,
    transport: ComicResponsesHttpTransport = new DefaultComicResponsesHttpTransport(),
  ): ComicPageAnalyzer {
    const settings: ComicTranslationProviderSettingsSnapshot =
      ComicTranslationProviderSettings.current()
    if (settings.provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH) {
      if (settings.codexModel.length === 0) {
        throw new Error('Codex model must be selected explicitly')
      }
      return new ExperimentalCodexComicPageAnalyzer(context, settings.codexModel, transport)
    }
    if (settings.apiKey.length === 0) {
      throw new Error('OpenAI API key is missing')
    }
    if (settings.apiModel.length === 0) {
      throw new Error('OpenAI API model is missing')
    }
    return new OpenAiApiComicPageAnalyzer(
      settings.apiBaseUrl,
      settings.apiKey,
      settings.apiModel,
      transport,
    )
  }
}

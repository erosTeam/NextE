import { common } from '@kit.AbilityKit'
import { CodexOAuthTokenSet } from '../model/ComicTranslationProvider'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL,
  LLM_SOURCE_TYPE_OPENAI_COMPATIBLE,
} from '../model/LlmSourceProfile'
import {
  ComicTextTranslationRequest,
  ComicTextTranslationResult,
  ComicTextTranslator,
} from './ComicVisualTranslationBackend'
import {
  CODEX_RESPONSES_BASE_URL,
  ComicProviderHttpError,
  ComicResponsesCallConfig,
  ComicResponsesHttpTransport,
  ComicResponsesLabeledImage,
  ComicResponsesProviderCore,
  DefaultComicResponsesHttpTransport,
} from './ComicResponsesPageAnalyzer'
import { ComicResponsesImagePayload } from './ComicResponsesImagePayload'
import {
  ComicResponsesRegionImage,
  ComicResponsesRegionImagePayload,
} from './ComicResponsesRegionImagePayload'
import { ComicResponsesTextTranslationProtocol } from './ComicResponsesTextTranslationProtocol'
import { ExperimentalCodexOAuthService } from './ExperimentalCodexOAuthService'
import { LlmSourceRuntimeConfig, LlmSourceRuntimeResolver } from './LlmSourceRuntimeResolver'

export const COMIC_RESPONSES_TEXT_TRANSLATION_PROMPT_VERSION: string =
  'comic-text-responses-v4'

class ComicResponsesTextTranslatorCore {
  private readonly providerCore: ComicResponsesProviderCore

  constructor(transport: ComicResponsesHttpTransport) {
    this.providerCore = new ComicResponsesProviderCore(transport)
  }

  async translate(
    request: ComicTextTranslationRequest,
    config: ComicResponsesCallConfig,
    sourceRevision: number,
  ): Promise<ComicTextTranslationResult> {
    const startedAt: number = Date.now()
    const prompt: string = ComicResponsesTextTranslationProtocol.buildPrompt(request)
    const imageDataUrl: string = ComicResponsesImagePayload.dataUrl(
      request.source.imageFilePath,
      request.source.imageHash,
    )
    const crops: ComicResponsesRegionImage[] =
      await ComicResponsesRegionImagePayload.build(request)
    const additionalImages: ComicResponsesLabeledImage[] = []
    for (let index: number = 0; index < crops.length; index++) {
      const input: ComicResponsesLabeledImage = new ComicResponsesLabeledImage()
      input.label = 'Region crop blockId=' + crops[index].blockId
      input.imageDataUrl = crops[index].dataUrl
      additionalImages.push(input)
    }
    let cropDataUrlChars: number = 0
    let cropBytes: number = 0
    let cropPixels: number = 0
    for (let index: number = 0; index < crops.length; index++) {
      cropDataUrlChars += crops[index].dataUrl.length
      cropBytes += crops[index].byteLength
      cropPixels += crops[index].width * crops[index].height
    }
    const payloadPreparedAt: number = Date.now()
    DiagnosticLogger.info(
      'comic-translation',
      'text_request_payload',
      `page=${request.source.pageIndex} source=${request.source.imageWidth}x${request.source.imageHeight} ` +
        `blocks=${request.document.blocks.length} promptChars=${prompt.length} ` +
        `fullImageChars=${imageDataUrl.length} crops=${crops.length} ` +
        `cropChars=${cropDataUrlChars} cropBytes=${cropBytes} cropPixels=${cropPixels} ` +
        `prepare=${payloadPreparedAt - startedAt}ms`,
    )
    const providerJson: string = await this.providerCore.requestJson(
      prompt,
      imageDataUrl,
      config,
      additionalImages,
    )
    DiagnosticLogger.info(
      'comic-translation',
      'text_request_timing',
      `page=${request.source.pageIndex} prepare=${payloadPreparedAt - startedAt}ms ` +
        `provider=${Date.now() - payloadPreparedAt}ms total=${Date.now() - startedAt}ms`,
    )
    try {
      return ComicResponsesTextTranslationProtocol.parse(
        request,
        providerJson,
        config.providerId,
        sourceRevision,
        config.model,
        COMIC_RESPONSES_TEXT_TRANSLATION_PROMPT_VERSION,
      )
    } catch (error) {
      throw ComicResponsesProviderCore.stageError('output', error as Error)
    }
  }
}

export class OpenAiApiComicTextTranslator implements ComicTextTranslator {
  private readonly config: ComicResponsesCallConfig
  private readonly revision: number
  private readonly core: ComicResponsesTextTranslatorCore

  constructor(
    baseUrl: string,
    apiKey: string,
    model: string,
    transport: ComicResponsesHttpTransport = new DefaultComicResponsesHttpTransport(),
    sourceProfileId: string = 'openai-responses-api',
    sourceRevision: number = 1,
  ) {
    this.config = new ComicResponsesCallConfig()
    this.config.providerId = sourceProfileId
    this.config.baseUrl = baseUrl
    this.config.accessToken = apiKey
    this.config.model = model
    this.revision = sourceRevision
    this.core = new ComicResponsesTextTranslatorCore(transport)
  }

  sourceProfileId(): string {
    return this.config.providerId
  }

  sourceRevision(): number {
    return this.revision
  }

  modelId(): string {
    return this.config.model
  }

  promptVersion(): string {
    return COMIC_RESPONSES_TEXT_TRANSLATION_PROMPT_VERSION
  }

  contextFingerprint(request: ComicTextTranslationRequest): string {
    return ComicResponsesTextTranslationProtocol.contextFingerprint(request)
  }

  translate(request: ComicTextTranslationRequest): Promise<ComicTextTranslationResult> {
    return this.core.translate(request, this.config, this.revision)
  }
}

export class ExperimentalCodexComicTextTranslator implements ComicTextTranslator {
  private readonly context: common.UIAbilityContext
  private readonly model: string
  private readonly profileId: string
  private readonly revision: number
  private readonly core: ComicResponsesTextTranslatorCore

  constructor(
    context: common.UIAbilityContext,
    model: string,
    transport: ComicResponsesHttpTransport = new DefaultComicResponsesHttpTransport(),
    sourceProfileId: string = 'codex-oauth-experimental',
    sourceRevision: number = 1,
  ) {
    this.context = context
    this.model = model
    this.profileId = sourceProfileId
    this.revision = sourceRevision
    this.core = new ComicResponsesTextTranslatorCore(transport)
  }

  sourceProfileId(): string {
    return this.profileId
  }

  sourceRevision(): number {
    return this.revision
  }

  modelId(): string {
    return this.model
  }

  promptVersion(): string {
    return COMIC_RESPONSES_TEXT_TRANSLATION_PROMPT_VERSION
  }

  contextFingerprint(request: ComicTextTranslationRequest): string {
    return ComicResponsesTextTranslationProtocol.contextFingerprint(request)
  }

  async translate(request: ComicTextTranslationRequest): Promise<ComicTextTranslationResult> {
    let tokens: CodexOAuthTokenSet = await ExperimentalCodexOAuthService.usableSourceTokens(
      this.context,
      this.profileId,
    )
    try {
      return await this.core.translate(request, this.callConfig(tokens), this.revision)
    } catch (error) {
      if (!(error instanceof ComicProviderHttpError) || error.statusCode !== 401) {
        throw error as Error
      }
      tokens = await ExperimentalCodexOAuthService.usableSourceTokens(
        this.context,
        this.profileId,
        true,
      )
      return this.core.translate(request, this.callConfig(tokens), this.revision)
    }
  }

  private callConfig(tokens: CodexOAuthTokenSet): ComicResponsesCallConfig {
    const config: ComicResponsesCallConfig = new ComicResponsesCallConfig()
    config.providerId = this.profileId
    config.baseUrl = CODEX_RESPONSES_BASE_URL
    config.model = this.model
    config.accessToken = tokens.accessToken
    config.accountId = tokens.accountId
    config.eventStream = true
    config.codexCompatibility = true
    return config
  }
}

export class ComicTextTranslatorFactory {
  static async create(
    context: common.UIAbilityContext,
    transport: ComicResponsesHttpTransport = new DefaultComicResponsesHttpTransport(),
  ): Promise<ComicTextTranslator> {
    const runtime: LlmSourceRuntimeConfig = await LlmSourceRuntimeResolver.resolveManga(context)
    if (runtime.sourceType === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL) {
      return new ExperimentalCodexComicTextTranslator(
        context,
        runtime.modelId,
        transport,
        runtime.sourceProfileId,
        runtime.sourceRevision,
      )
    }
    if (runtime.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE) {
      return new OpenAiApiComicTextTranslator(
        runtime.baseUrl,
        runtime.apiKey,
        runtime.modelId,
        transport,
        runtime.sourceProfileId,
        runtime.sourceRevision,
      )
    }
    throw new Error('Selected LLM source type is unsupported')
  }
}

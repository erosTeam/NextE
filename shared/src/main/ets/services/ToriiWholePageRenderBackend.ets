import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { ComicGlossaryTerm, ComicGlossaryTermStatus } from '../model/ComicTranslation'
import { ComicRenderedPage } from '../model/ComicVisualTranslation'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { AxiosBinaryResponse, AxiosHttpClient } from '../network/AxiosHttpClient'
import {
  TORII_FONT_MA_SHAN_ZHENG,
  TORII_FONT_NOTO,
  TORII_FONT_WILDWORDS,
  ToriiFontCatalog,
  ToriiTranslatorModelCatalog,
} from '../settings/ComicVisualProviderSettings'
import {
  ComicVisualPageSource,
  ComicWholePageRenderBackend,
  ComicWholePageRenderRequest,
} from './ComicVisualTranslationBackend'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'
import {
  ToriiWholePageContextScope,
  ToriiWholePageContextStore,
} from './ToriiWholePageContextStore'

export const TORII_WHOLE_PAGE_ENDPOINT: string =
  'https://api.toriitranslate.com/api/v2/upload'
export const TORII_WHOLE_PAGE_SOURCE_REVISION: number = 2
export const TORII_WHOLE_PAGE_PROMPT_VERSION: string = 'torii-whole-page-v3'
export const TORII_WHOLE_PAGE_RENDER_PROFILE_ID: string = 'torii-whole-page-v2'
export const TORII_WHOLE_PAGE_SOURCE_TREATMENT_PROFILE_ID: string =
  'torii-cloud-inpaint-v1'
export const TORII_WHOLE_PAGE_LAYOUT_PROFILE_ID: string = 'torii-cloud-layout-v2'

const MAX_TORII_SOURCE_IMAGE_BYTES: number = 20 * 1024 * 1024
const MAX_TORII_MULTIPART_BYTES: number = 24 * 1024 * 1024
const MAX_TORII_RESPONSE_BYTES: number = 96 * 1024 * 1024
const MAX_TORII_RENDERED_IMAGE_BYTES: number = 80 * 1024 * 1024
const MAX_TORII_NORMALIZE_PIXELS: number = 40 * 1024 * 1024
const MAX_TORII_ERROR_DETAIL_CHARS: number = 512
const MAX_TORII_CONTEXT_CHARS: number = 10000
const TORII_CONNECT_TIMEOUT_MS: number = 15000
const TORII_READ_TIMEOUT_MS: number = 5 * 60 * 1000
const RENDER_CACHE_DIR: string = 'comic-translated-pages'

class ToriiMultipartPart {
  name: string = ''
  fileName: string = ''
  contentType: string = ''
  bytes: Uint8Array = new Uint8Array(0)
}

class ToriiSourceImage {
  bytes: Uint8Array = new Uint8Array(0)
  mimeType: string = ''
  fileName: string = ''
}

class ToriiPngDimensions {
  width: number = 0
  height: number = 0
}

class ToriiDecodedImage {
  mimeType: string = ''
  bytes: Uint8Array = new Uint8Array(0)
}

export class ToriiWholePageConfig {
  toriiApiKey: string = ''
  modelId: string = ''
  fontId: string = TORII_FONT_NOTO

  assertValid(): void {
    ToriiWholePageConfig.validateKey(this.toriiApiKey)
    if (ToriiTranslatorModelCatalog.find(this.modelId) === null ||
      (this.fontId !== TORII_FONT_NOTO && this.fontId !== TORII_FONT_WILDWORDS &&
        this.fontId !== TORII_FONT_MA_SHAN_ZHENG)) {
      throw new Error('Torii whole-page configuration is invalid')
    }
  }

  sourceProfileId(): string {
    this.assertValid()
    return `torii-whole-page:managed:${ToriiWholePageConfig.sha256Text(
      `${this.toriiApiKey}\n${this.fontId}`,
    ).substring(0, 16)}`
  }

  private static validateKey(value: string): void {
    if (value.length === 0 || value.length > 8192 || value !== value.trim() ||
      /[\r\n\t]/.test(value) || value.includes('\u0000')) {
      throw new Error('Torii API credential is invalid')
    }
  }

  private static sha256Text(value: string): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: new util.TextEncoder().encodeInto(value) })
    return ToriiWholePageRenderBackend.toHex(md.digestSync().data)
  }
}

export class ToriiWholePageTransportRequest {
  url: string = TORII_WHOLE_PAGE_ENDPOINT
  headers: Record<string, string> = {}
  body: Uint8Array = new Uint8Array(0)
  maxResponseBytes: number = MAX_TORII_RESPONSE_BYTES
  connectTimeoutMs: number = TORII_CONNECT_TIMEOUT_MS
  readTimeoutMs: number = TORII_READ_TIMEOUT_MS
}

export class ToriiWholePageTransportResponse {
  statusCode: number = 0
  body: Uint8Array = new Uint8Array(0)
  rawHeader: string = ''
}

export interface ToriiWholePageTransport {
  post(request: ToriiWholePageTransportRequest): Promise<ToriiWholePageTransportResponse>
}

export class DefaultToriiWholePageTransport implements ToriiWholePageTransport {
  async post(request: ToriiWholePageTransportRequest): Promise<ToriiWholePageTransportResponse> {
    const body: ArrayBuffer = request.body.buffer.slice(
      request.body.byteOffset,
      request.body.byteOffset + request.body.byteLength,
    )
    const response: AxiosBinaryResponse = await AxiosHttpClient.requestBinaryWithBody(
      request.url,
      'POST',
      request.headers,
      body,
      request.maxResponseBytes,
      request.connectTimeoutMs,
      request.readTimeoutMs,
    )
    const output: ToriiWholePageTransportResponse = new ToriiWholePageTransportResponse()
    output.statusCode = response.statusCode
    output.rawHeader = response.rawHeader
    if (response.bytes !== null) {
      output.body = new Uint8Array(response.bytes)
    }
    return output
  }
}

/** Independent Torii one-call image translator. It never exposes or reuses Torii sub-stages. */
export class ToriiWholePageRenderBackend implements ComicWholePageRenderBackend {
  private readonly context: common.UIAbilityContext
  private readonly config: ToriiWholePageConfig
  private readonly contextStore: ToriiWholePageContextStore
  private readonly transport: ToriiWholePageTransport

  constructor(
    context: common.UIAbilityContext,
    config: ToriiWholePageConfig,
    contextStore: ToriiWholePageContextStore,
    transport: ToriiWholePageTransport = new DefaultToriiWholePageTransport(),
  ) {
    config.assertValid()
    this.context = context
    this.config = config
    this.contextStore = contextStore
    this.transport = transport
  }

  sourceProfileId(): string {
    return this.config.sourceProfileId()
  }

  sourceRevision(): number {
    return TORII_WHOLE_PAGE_SOURCE_REVISION
  }

  modelId(): string {
    return this.config.modelId
  }

  promptVersion(): string {
    return TORII_WHOLE_PAGE_PROMPT_VERSION
  }

  contextFingerprint(request: ComicWholePageRenderRequest): string {
    const context: string = ToriiWholePageRenderBackend.providerContext(request)
    return ToriiWholePageRenderBackend.sha256Text(JSON.stringify([
      request.source.projectId,
      `${request.source.pageIndex}`,
      request.context.sourceLanguage,
      request.context.targetLanguage,
      context,
      ToriiWholePageRenderBackend.customPrompt(request),
      this.config.fontId,
      this.sourceProfileId(),
      this.modelId(),
      this.promptVersion(),
    ]))
  }

  contextScope(
    projectId: string,
    pageIndex: number,
    targetLanguage: string,
  ): ToriiWholePageContextScope {
    const scope: ToriiWholePageContextScope = new ToriiWholePageContextScope()
    scope.projectId = projectId
    scope.pageIndex = pageIndex
    scope.targetLanguage = targetLanguage
    scope.sourceProfileId = this.sourceProfileId()
    scope.sourceRevision = this.sourceRevision()
    scope.modelId = this.modelId()
    scope.promptVersion = this.promptVersion()
    scope.assertValid()
    return scope
  }

  async render(request: ComicWholePageRenderRequest): Promise<ComicRenderedPage> {
    ComicVisualTranslationContract.validateWholePageRenderRequest(request)
    if (!ToriiFontCatalog.supports(
      this.config.fontId,
      request.context.targetLanguage,
    ) ||
      request.identity.translationSourceProfileId !== this.sourceProfileId() ||
      request.identity.translationSourceRevision !== this.sourceRevision() ||
      request.identity.translationModelId !== this.modelId() ||
      request.identity.translationPromptVersion !== this.promptVersion() ||
      request.identity.translationContextFingerprint !== this.contextFingerprint(request) ||
      request.identity.renderBackendId !== this.sourceProfileId() ||
      request.identity.renderTargetMimeType !== 'image/png') {
      throw new Error('Torii whole-page render identity is invalid')
    }
    const source: ToriiSourceImage = ToriiWholePageRenderBackend.readSourceImage(request.source)
    const boundary: string = 'NextE' + util.generateRandomUUID(true).replace(/-/g, '')
    const parts: ToriiMultipartPart[] = this.parts(request, source)
    const body: Uint8Array = ToriiWholePageRenderBackend.multipart(boundary, parts)
    const transportRequest: ToriiWholePageTransportRequest =
      new ToriiWholePageTransportRequest()
    transportRequest.headers = {
      'Authorization': `Bearer ${this.config.toriiApiKey}`,
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'Accept': 'application/json',
    }
    transportRequest.body = body
    DiagnosticLogger.info(
      'comic-translation',
      'torii_whole_page_request',
      `target=${ToriiWholePageRenderBackend.targetLanguage(request.context.targetLanguage)} ` +
        `model=${this.modelId()} font=${this.config.fontId} bodyBytes=${body.length}`,
    )
    const response: ToriiWholePageTransportResponse =
      await this.transport.post(transportRequest)
    const responseText: string = ToriiWholePageRenderBackend.responseText(response)
    const successHeader: string = ToriiWholePageRenderBackend.headerValue(
      response.rawHeader,
      'success',
    )
    const contentType: string = ToriiWholePageRenderBackend.headerValue(
      response.rawHeader,
      'content-type',
    )
    const contentEncoding: string = ToriiWholePageRenderBackend.headerValue(
      response.rawHeader,
      'content-encoding',
    )
    DiagnosticLogger.info(
      'comic-translation',
      'torii_whole_page_response',
      `status=${response.statusCode} success=${successHeader || 'missing'} ` +
        `type=${contentType || 'missing'} encoding=${contentEncoding || 'identity'} ` +
        `bodyBytes=${response.body.length}`,
    )
    if (response.statusCode < 200 || response.statusCode > 299) {
      DiagnosticLogger.warn(
        'comic-translation',
        'torii_whole_page_failure',
        this.safeErrorDetail(responseText),
      )
      throw new Error(
        `Torii whole-page request failed with HTTP ${response.statusCode}${
          this.errorSuffix(responseText)}`,
      )
    }
    if (successHeader.toLowerCase() !== 'true') {
      throw new Error(
        `Torii whole-page request did not confirm success (${successHeader || 'missing'})${
          this.errorSuffix(responseText)}`,
      )
    }
    const dataUrl: string | null = ToriiWholePageRenderBackend.jsonStringField(
      responseText,
      'image',
    )
    if (dataUrl === null || !dataUrl.startsWith('data:image/')) {
      throw new Error(
        `Torii whole-page response is missing a PNG image (` +
          `${ToriiWholePageRenderBackend.responseShape(responseText, dataUrl, contentType)})`,
      )
    }
    const decoded: ToriiDecodedImage = ToriiWholePageRenderBackend.decodeImageDataUrl(dataUrl)
    const bytes: Uint8Array = await ToriiWholePageRenderBackend.normalizeRenderedPng(
      this.context,
      decoded,
      request.source.imageWidth,
      request.source.imageHeight,
    )
    const dimensions: ToriiPngDimensions = await ToriiWholePageRenderBackend.validatePng(
      bytes,
      request.source.imageWidth,
      request.source.imageHeight,
    )
    const artifactHash: string = ToriiWholePageRenderBackend.sha256(bytes)
    const path: string = ToriiWholePageRenderBackend.persistRenderedPage(
      this.context,
      request.identity.cacheKey(),
      artifactHash,
      bytes,
    )
    const now: number = Date.now()
    const page: ComicRenderedPage = new ComicRenderedPage()
    page.identity = request.identity.copy()
    page.artifactHash = artifactHash
    page.mimeType = 'image/png'
    page.width = dimensions.width
    page.height = dimensions.height
    page.byteLength = bytes.length
    page.localFilePath = path
    page.createdAt = now
    page.lastAccessAt = now
    ComicVisualTranslationContract.validateRenderedPage(request.identity, page)
    const returnedContext: string | null = ToriiWholePageRenderBackend.jsonStringField(
      responseText,
      'context',
    )
    if (returnedContext !== null && returnedContext.trim().length > 0) {
      await this.contextStore.save(
        this.contextScope(
          request.source.projectId,
          request.source.pageIndex,
          request.context.targetLanguage,
        ),
        returnedContext,
      )
    }
    return page
  }

  private parts(
    request: ComicWholePageRenderRequest,
    source: ToriiSourceImage,
  ): ToriiMultipartPart[] {
    const parts: ToriiMultipartPart[] = []
    parts.push(ToriiWholePageRenderBackend.filePart(source))
    parts.push(ToriiWholePageRenderBackend.textPart(
      'target_lang',
      ToriiWholePageRenderBackend.targetLanguage(request.context.targetLanguage),
    ))
    parts.push(ToriiWholePageRenderBackend.textPart('translator', this.modelId()))
    parts.push(ToriiWholePageRenderBackend.textPart('font', this.config.fontId))
    parts.push(ToriiWholePageRenderBackend.textPart('text_align', 'auto'))
    parts.push(ToriiWholePageRenderBackend.textPart('stroke_disabled', 'false'))
    parts.push(ToriiWholePageRenderBackend.textPart('min_font_size', '6'))
    parts.push(ToriiWholePageRenderBackend.textPart('bubbles_only', 'false'))
    parts.push(ToriiWholePageRenderBackend.textPart(
      'custom_prompt',
      ToriiWholePageRenderBackend.customPrompt(request),
    ))
    parts.push(ToriiWholePageRenderBackend.textPart(
      'context',
      ToriiWholePageRenderBackend.providerContext(request),
    ))
    return parts
  }

  private static customPrompt(request: ComicWholePageRenderRequest): string {
    const style: string = request.context.styleGuide.trim()
    const prefix: string = 'Translate every visible comic text into ' +
      request.context.targetLanguage +
      '. Keep character names, forms of address, tone, and references consistent. ' +
      'Preserve the original horizontal or vertical reading direction and do not alter artwork.'
    let value: string = style.length > 0 ? `${prefix} ${style}` : prefix
    value = ToriiWholePageRenderBackend.appendGlossary(
      value,
      request.context.glossary,
      ComicGlossaryTermStatus.LOCKED,
    )
    value = ToriiWholePageRenderBackend.appendGlossary(
      value,
      request.context.glossary,
      ComicGlossaryTermStatus.PROVISIONAL,
    )
    return value.substring(0, Math.min(value.length, 1000))
  }

  private static appendGlossary(
    current: string,
    glossary: ComicGlossaryTerm[],
    status: ComicGlossaryTermStatus,
  ): string {
    let output: string = current
    for (let index: number = 0; index < glossary.length; index++) {
      const term: ComicGlossaryTerm = glossary[index]
      if (term.status !== status) {
        continue
      }
      const source: string = term.sourceTerm.trim()
      const target: string = term.targetTerm.trim()
      if (source.length === 0 || target.length === 0) {
        continue
      }
      const entry: string = ` Glossary: ${source} => ${target}.`
      if (output.length + entry.length > 1000) {
        continue
      }
      output += entry
    }
    return output
  }

  private static providerContext(request: ComicWholePageRenderRequest): string {
    const context: string = request.context.rollingSummary.trim()
    if (context.length === 0) {
      return 'None'
    }
    if (context.length > MAX_TORII_CONTEXT_CHARS || context.includes('\u0000')) {
      throw new Error('Torii whole-page context is invalid')
    }
    return context
  }

  private static targetLanguage(value: string): string {
    const normalized: string = value.trim().toLowerCase().replace('_', '-')
    if (normalized === 'zh-cn' || normalized === 'zh-hans') {
      return 'zh-cn'
    }
    if (normalized === 'zh-tw' || normalized === 'zh-hant') {
      return 'zh-tw'
    }
    if (!/^[a-z]{2,3}(?:-[a-z]{2,8})?$/.test(normalized)) {
      throw new Error('Torii target language is invalid')
    }
    return normalized
  }

  private static textPart(name: string, value: string): ToriiMultipartPart {
    const part: ToriiMultipartPart = new ToriiMultipartPart()
    part.name = name
    part.bytes = new util.TextEncoder().encodeInto(value)
    return part
  }

  private static filePart(source: ToriiSourceImage): ToriiMultipartPart {
    const part: ToriiMultipartPart = new ToriiMultipartPart()
    part.name = 'file'
    part.fileName = source.fileName
    part.contentType = source.mimeType
    part.bytes = source.bytes
    return part
  }

  private static multipart(boundary: string, parts: ToriiMultipartPart[]): Uint8Array {
    if (!/^[A-Za-z0-9]{16,80}$/.test(boundary)) {
      throw new Error('Torii multipart boundary is invalid')
    }
    const chunks: Uint8Array[] = []
    let total: number = 0
    for (let index: number = 0; index < parts.length; index++) {
      const part: ToriiMultipartPart = parts[index]
      if (!/^[a-z0-9_-]{1,80}$/.test(part.name) ||
        (part.fileName.length > 0 && !/^[a-z0-9.-]{1,80}$/.test(part.fileName))) {
        throw new Error('Torii multipart part is invalid')
      }
      let header: string = `--${boundary}\r\nContent-Disposition: form-data; name="${part.name}"`
      if (part.fileName.length > 0) {
        header += `; filename="${part.fileName}"`
      }
      header += '\r\n'
      if (part.contentType.length > 0) {
        header += `Content-Type: ${part.contentType}\r\n`
      }
      header += '\r\n'
      const headerBytes: Uint8Array = new util.TextEncoder().encodeInto(header)
      const suffix: Uint8Array = new util.TextEncoder().encodeInto('\r\n')
      chunks.push(headerBytes, part.bytes, suffix)
      total += headerBytes.length + part.bytes.length + suffix.length
    }
    const ending: Uint8Array = new util.TextEncoder().encodeInto(`--${boundary}--\r\n`)
    chunks.push(ending)
    total += ending.length
    if (total <= 0 || total > MAX_TORII_MULTIPART_BYTES) {
      throw new Error('Torii multipart request size is invalid')
    }
    const output: Uint8Array = new Uint8Array(total)
    let offset: number = 0
    for (let index: number = 0; index < chunks.length; index++) {
      output.set(chunks[index], offset)
      offset += chunks[index].length
    }
    return output
  }

  private static readSourceImage(source: ComicVisualPageSource): ToriiSourceImage {
    const stat: fileIo.Stat = fileIo.statSync(source.imageFilePath)
    if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_TORII_SOURCE_IMAGE_BYTES) {
      throw new Error('Torii source image file size is invalid')
    }
    const bytes: Uint8Array = ToriiWholePageRenderBackend.readExact(
      source.imageFilePath,
      Math.floor(stat.size),
    )
    if (ToriiWholePageRenderBackend.sha256(bytes) !== source.imageHash) {
      throw new Error('Torii source image identity changed before upload')
    }
    const output: ToriiSourceImage = new ToriiSourceImage()
    output.bytes = bytes
    if (ToriiWholePageRenderBackend.isPng(bytes)) {
      output.mimeType = 'image/png'
      output.fileName = 'page.png'
    } else if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
      bytes[2] === 0xff) {
      output.mimeType = 'image/jpeg'
      output.fileName = 'page.jpg'
    } else if (bytes.length >= 12 &&
      ToriiWholePageRenderBackend.asciiAt(bytes, 0, 'RIFF') &&
      ToriiWholePageRenderBackend.asciiAt(bytes, 8, 'WEBP')) {
      output.mimeType = 'image/webp'
      output.fileName = 'page.webp'
    } else {
      throw new Error('Torii source image format is unsupported')
    }
    return output
  }

  private static responseText(response: ToriiWholePageTransportResponse): string {
    if (response.body.length <= 0 || response.body.length > MAX_TORII_RESPONSE_BYTES) {
      throw new Error('Torii whole-page response size is invalid')
    }
    return util.TextDecoder.create('utf-8', { ignoreBOM: true })
      .decodeToString(response.body)
  }

  private errorSuffix(body: string): string {
    const detail: string | null = ToriiWholePageRenderBackend.jsonStringField(body, 'error') ??
      ToriiWholePageRenderBackend.jsonStringField(body, 'message') ??
      ToriiWholePageRenderBackend.jsonStringField(body, 'detail')
    const code: string = ToriiWholePageRenderBackend.safeProviderFailureCode(body)
    const bounded: string = this.safeErrorDetail(
      detail === null || detail.trim().length === 0 ? body : detail,
    )
    return bounded.length > 0 ? `: ${code}: ${bounded}` : `: ${code}`
  }

  private safeErrorDetail(value: string): string {
    let sanitized: string = value
    const secrets: string[] = [
      this.config.toriiApiKey,
    ]
    for (let index: number = 0; index < secrets.length; index++) {
      if (secrets[index].length > 0) {
        sanitized = sanitized.split(secrets[index]).join('<redacted>')
      }
    }
    sanitized = sanitized.replace(/https?:\/\/[^\s"'<>]+/gi, '<url>')
      .replace(/[A-Za-z0-9_+=\-]{24,}/g, '<token>')
      .replace(/[\r\n\t]+/g, ' ')
      .trim()
    return sanitized.substring(0, MAX_TORII_ERROR_DETAIL_CHARS)
  }

  private static safeProviderFailureCode(body: string): string {
    const normalized: string = body.toLowerCase()
    if (normalized.includes('401') || normalized.includes('unauthorized') ||
      normalized.includes('authentication') || normalized.includes('api key')) {
      return 'upstream_authentication_failed'
    }
    if (normalized.includes('403') || normalized.includes('forbidden')) {
      return 'upstream_forbidden'
    }
    if (normalized.includes('404') || normalized.includes('not found')) {
      return 'upstream_not_found'
    }
    if (normalized.includes('429') || normalized.includes('rate limit')) {
      return 'upstream_rate_limited'
    }
    if (normalized.includes('model')) {
      return 'upstream_model_rejected'
    }
    if (normalized.includes('timeout')) {
      return 'upstream_timeout'
    }
    if (normalized.includes('connect') || normalized.includes('dns') ||
      normalized.includes('ssl') || normalized.includes('certificate')) {
      return 'upstream_connection_failed'
    }
    return 'upstream_request_failed'
  }

  private static responseShape(
    body: string,
    imageValue: string | null,
    contentType: string,
  ): string {
    const bodyKind: string = body.trimStart().startsWith('{') ? 'json-object' :
      body.trimStart().startsWith('[') ? 'json-array' : 'non-json'
    let imageKind: string = 'missing'
    if (imageValue !== null) {
      if (imageValue.length === 0) {
        imageKind = 'empty'
      } else if (imageValue.startsWith('data:')) {
        const commaIndex: number = imageValue.indexOf(',')
        const metadata: string = commaIndex > 0
          ? imageValue.substring(5, Math.min(commaIndex, 85))
          : 'invalid-data-url'
        imageKind = `data:${metadata}`
      } else if (imageValue.startsWith('iVBOR')) {
        imageKind = 'raw-png-base64'
      } else {
        imageKind = 'string'
      }
    }
    const safeContentType: string = /^[A-Za-z0-9+./;=_ -]{1,100}$/.test(contentType)
      ? contentType
      : 'invalid'
    return `type=${safeContentType || 'missing'},body=${bodyKind},image=${imageKind}`
  }

  private static decodeImageDataUrl(value: string): ToriiDecodedImage {
    const commaIndex: number = value.indexOf(',')
    if (commaIndex <= 0 || value !== value.trim()) {
      throw new Error('Torii whole-page image payload is invalid')
    }
    const metadata: string = value.substring(0, commaIndex).toLowerCase()
    const output: ToriiDecodedImage = new ToriiDecodedImage()
    if (metadata === 'data:image/png;base64') {
      output.mimeType = 'image/png'
    } else if (metadata === 'data:image/jpeg;base64' ||
      metadata === 'data:image/jpg;base64') {
      output.mimeType = 'image/jpeg'
    } else if (metadata === 'data:image/webp;base64') {
      output.mimeType = 'image/webp'
    } else {
      throw new Error('Torii whole-page image MIME type is unsupported')
    }
    const encoded: string = value.substring(commaIndex + 1)
    if (encoded.length <= 0 || encoded.length > Math.ceil(
      MAX_TORII_RENDERED_IMAGE_BYTES * 4 / 3,
    ) + 4) {
      throw new Error('Torii whole-page image payload size is invalid')
    }
    try {
      output.bytes = new util.Base64Helper().decodeSync(encoded)
    } catch (_error) {
      throw new Error('Torii whole-page image payload is invalid')
    }
    const matchesMime: boolean = output.mimeType === 'image/png'
      ? ToriiWholePageRenderBackend.isPng(output.bytes)
      : output.mimeType === 'image/jpeg'
        ? ToriiWholePageRenderBackend.isJpeg(output.bytes)
        : ToriiWholePageRenderBackend.isWebp(output.bytes)
    if (!matchesMime) {
      throw new Error('Torii whole-page image MIME type does not match its bytes')
    }
    return output
  }

  private static async normalizeRenderedPng(
    context: common.UIAbilityContext,
    decoded: ToriiDecodedImage,
    expectedWidth: number,
    expectedHeight: number,
  ): Promise<Uint8Array> {
    if (decoded.mimeType === 'image/png') {
      return decoded.bytes
    }
    if (expectedWidth * expectedHeight > MAX_TORII_NORMALIZE_PIXELS) {
      throw new Error('Torii whole-page image is too large to normalize on this device')
    }
    const temporaryPath: string = `${context.cacheDir}/torii-normalized-` +
      `${util.generateRandomUUID(true)}.png`
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    let outputFile: fileIo.File | null = null
    try {
      const buffer: ArrayBuffer = decoded.bytes.buffer.slice(
        decoded.bytes.byteOffset,
        decoded.bytes.byteOffset + decoded.bytes.byteLength,
      )
      source = image.createImageSource(buffer)
      pixelMap = await source.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      })
      const info: image.ImageInfo = await pixelMap.getImageInfo()
      if (info.size.width !== expectedWidth || info.size.height !== expectedHeight) {
        throw new Error('Torii whole-page result dimensions do not match the source')
      }
      packer = image.createImagePacker()
      outputFile = fileIo.openSync(
        temporaryPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      await packer.packToFile(pixelMap, outputFile.fd, { format: 'image/png', quality: 100 })
      fileIo.closeSync(outputFile)
      outputFile = null
      const stat: fileIo.Stat = fileIo.statSync(temporaryPath)
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_TORII_RENDERED_IMAGE_BYTES) {
        throw new Error('Torii normalized PNG size is invalid')
      }
      return ToriiWholePageRenderBackend.readExact(temporaryPath, Math.floor(stat.size))
    } catch (error) {
      const message: string = (error as Error).message
      if (message === 'Torii whole-page result dimensions do not match the source' ||
        message === 'Torii normalized PNG size is invalid') {
        throw error as Error
      }
      throw new Error('Torii whole-page image cannot be normalized to PNG')
    } finally {
      if (outputFile !== null) {
        fileIo.closeSync(outputFile)
      }
      if (packer !== undefined) {
        await packer.release()
      }
      if (pixelMap !== undefined) {
        await pixelMap.release()
      }
      if (source !== undefined) {
        await source.release()
      }
      ToriiWholePageRenderBackend.removeFile(temporaryPath)
    }
  }

  private static headerValue(rawHeader: string, name: string): string {
    if (rawHeader.trim().length === 0 || name.trim().length === 0) {
      return ''
    }
    try {
      const headers: Record<string, Object> = JSON.parse(rawHeader) as Record<string, Object>
      const expected: string = name.toLowerCase()
      const names: string[] = Object.keys(headers)
      for (let index: number = 0; index < names.length; index++) {
        if (names[index].toLowerCase() !== expected) {
          continue
        }
        const value: Object | undefined = headers[names[index]]
        return value === undefined || value === null ? '' : `${value}`.trim()
      }
    } catch (_error) {
    }
    return ''
  }

  /** Extracts a bounded JSON string field without materializing Torii's unused inpainted image. */
  private static jsonStringField(body: string, field: string): string | null {
    const needle: string = `"${field}"`
    let index: number = body.indexOf(needle)
    if (index < 0) {
      return null
    }
    index = body.indexOf(':', index + needle.length)
    if (index < 0) {
      throw new Error('Torii whole-page JSON response is invalid')
    }
    index++
    while (index < body.length && /\s/.test(body.charAt(index))) {
      index++
    }
    if (body.charAt(index) !== '"') {
      if (body.substring(index, index + 4) === 'null') {
        return null
      }
      throw new Error('Torii whole-page JSON field is invalid')
    }
    const start: number = index
    index++
    let escaped: boolean = false
    while (index < body.length) {
      const character: string = body.charAt(index)
      if (!escaped && character === '"') {
        try {
          return JSON.parse(body.substring(start, index + 1)) as string
        } catch (_error) {
          throw new Error('Torii whole-page JSON string is invalid')
        }
      }
      if (!escaped && character === '\\') {
        escaped = true
      } else {
        escaped = false
      }
      index++
    }
    throw new Error('Torii whole-page JSON response is truncated')
  }

  private static async validatePng(
    bytes: Uint8Array,
    expectedWidth: number,
    expectedHeight: number,
  ): Promise<ToriiPngDimensions> {
    if (bytes.length <= 0 || bytes.length > MAX_TORII_RENDERED_IMAGE_BYTES ||
      !ToriiWholePageRenderBackend.isPng(bytes) ||
      !ToriiWholePageRenderBackend.asciiAt(bytes, 12, 'IHDR')) {
      throw new Error('Torii whole-page result is not a PNG image')
    }
    const dimensions: ToriiPngDimensions = new ToriiPngDimensions()
    dimensions.width = ToriiWholePageRenderBackend.u32be(bytes, 16)
    dimensions.height = ToriiWholePageRenderBackend.u32be(bytes, 20)
    if (dimensions.width !== expectedWidth || dimensions.height !== expectedHeight) {
      throw new Error('Torii whole-page result dimensions do not match the source')
    }
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    try {
      const buffer: ArrayBuffer = bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength,
      )
      source = image.createImageSource(buffer)
      pixelMap = await source.createPixelMap({
        editable: false,
        desiredSize: { width: 1, height: 1 },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      })
      const info: image.ImageInfo = await pixelMap.getImageInfo()
      if (info.size.width <= 0 || info.size.height <= 0) {
        throw new Error('decoded dimensions are invalid')
      }
    } catch (_error) {
      throw new Error('Torii whole-page PNG cannot be decoded')
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release()
      }
      if (source !== undefined) {
        await source.release()
      }
    }
    return dimensions
  }

  private static persistRenderedPage(
    context: common.UIAbilityContext,
    identityKey: string,
    artifactHash: string,
    bytes: Uint8Array,
  ): string {
    const dir: string = `${context.cacheDir}/${RENDER_CACHE_DIR}`
    ToriiWholePageRenderBackend.ensureDir(dir)
    const identityHash: string = ToriiWholePageRenderBackend.sha256Text(identityKey)
    const path: string = `${dir}/${identityHash}-${artifactHash}.png`
    if (fileIo.accessSync(path)) {
      const stat: fileIo.Stat = fileIo.statSync(path)
      if (stat.isFile() && Math.floor(stat.size) === bytes.length) {
        return path
      }
      ToriiWholePageRenderBackend.removeFile(path)
    }
    const partial: string = `${path}.part-${util.generateRandomUUID(true)}`
    try {
      ToriiWholePageRenderBackend.writeExact(partial, bytes)
      fileIo.renameSync(partial, path)
      return path
    } catch (error) {
      ToriiWholePageRenderBackend.removeFile(partial)
      throw error as Error
    }
  }

  private static readExact(path: string, length: number): Uint8Array {
    const output: Uint8Array = new Uint8Array(length)
    let file: fileIo.File | null = null
    let offset: number = 0
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      while (offset < length) {
        const buffer: ArrayBuffer = new ArrayBuffer(length - offset)
        const read: number = fileIo.readSync(file.fd, buffer, { length: buffer.byteLength })
        if (read <= 0) {
          throw new Error('Torii source image read is incomplete')
        }
        output.set(new Uint8Array(buffer, 0, read), offset)
        offset += read
      }
      return output
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static writeExact(path: string, bytes: Uint8Array): void {
    let file: fileIo.File | null = null
    let offset: number = 0
    try {
      file = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      while (offset < bytes.length) {
        const buffer: ArrayBuffer = bytes.buffer.slice(
          bytes.byteOffset + offset,
          bytes.byteOffset + bytes.byteLength,
        )
        const written: number = fileIo.writeSync(file.fd, buffer, { length: buffer.byteLength })
        if (written <= 0) {
          throw new Error('Torii rendered image write failed')
        }
        offset += written
      }
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static ensureDir(path: string): void {
    try {
      fileIo.mkdirSync(path, true)
    } catch (error) {
      if (!fileIo.accessSync(path)) {
        throw error as Error
      }
    }
  }

  private static removeFile(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_error) {}
  }

  private static isPng(bytes: Uint8Array): boolean {
    const signature: number[] = [137, 80, 78, 71, 13, 10, 26, 10]
    if (bytes.length < 24) {
      return false
    }
    for (let index: number = 0; index < signature.length; index++) {
      if (bytes[index] !== signature[index]) {
        return false
      }
    }
    return true
  }

  private static isJpeg(bytes: Uint8Array): boolean {
    return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
      bytes[2] === 0xff
  }

  private static isWebp(bytes: Uint8Array): boolean {
    return bytes.length >= 12 &&
      ToriiWholePageRenderBackend.asciiAt(bytes, 0, 'RIFF') &&
      ToriiWholePageRenderBackend.asciiAt(bytes, 8, 'WEBP')
  }

  private static asciiAt(bytes: Uint8Array, offset: number, expected: string): boolean {
    if (offset < 0 || offset + expected.length > bytes.length) {
      return false
    }
    for (let index: number = 0; index < expected.length; index++) {
      if (bytes[offset + index] !== expected.charCodeAt(index)) {
        return false
      }
    }
    return true
  }

  private static u32be(bytes: Uint8Array, offset: number): number {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw new Error('Torii PNG header is truncated')
    }
    return ((bytes[offset] << 24) | (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) | bytes[offset + 3]) >>> 0
  }

  private static sha256(bytes: Uint8Array): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: bytes })
    return ToriiWholePageRenderBackend.toHex(md.digestSync().data)
  }

  private static sha256Text(value: string): string {
    return ToriiWholePageRenderBackend.sha256(new util.TextEncoder().encodeInto(value))
  }

  static toHex(bytes: Uint8Array): string {
    const parts: string[] = []
    for (let index: number = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}

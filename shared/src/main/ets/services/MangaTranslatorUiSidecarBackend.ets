import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import {
  ComicRenderedPage,
  ComicRegionAnalysisResult,
} from '../model/ComicVisualTranslation'
import { AxiosBinaryResponse, AxiosHttpClient } from '../network/AxiosHttpClient'
import {
  ComicRegionAnalysisRequest,
  ComicRegionRenderBackend,
  ComicRegionRenderRequest,
  ComicVisualPageSource,
} from './ComicVisualTranslationBackend'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'
import {
  MangaTranslatorUiExportFiles,
  MangaTranslatorUiSidecarArchive,
} from './MangaTranslatorUiSidecarArchive'
import {
  MANGA_TRANSLATOR_UI_BACKEND_ID,
  MANGA_TRANSLATOR_UI_EXPORT_PATH,
  MANGA_TRANSLATOR_UI_IMPORT_PATH,
  MANGA_TRANSLATOR_UI_PROFILE_ID,
  MANGA_TRANSLATOR_UI_PROTOCOL_REVISION,
  MANGA_TRANSLATOR_UI_VISUAL_ONLY_CONFIG_JSON,
  MangaTranslatorUiSidecarProtocol,
} from './MangaTranslatorUiSidecarProtocol'
import {
  DefaultMangaTranslatorUiSidecarSessionProvider,
  MangaTranslatorUiSessionRequest,
  MangaTranslatorUiSidecarSessionProvider,
} from './MangaTranslatorUiSidecarSessionService'

const MAX_SOURCE_IMAGE_BYTES: number = 40 * 1024 * 1024
const MAX_MULTIPART_BODY_BYTES: number = 48 * 1024 * 1024
const MAX_EXPORT_RESPONSE_BYTES: number = 6 * 1024 * 1024
const MAX_RENDER_RESPONSE_BYTES: number = 80 * 1024 * 1024
const MAX_CONFIG_JSON_BYTES: number = 64 * 1024
const MAX_BASE_URL_CHARS: number = 2048
const MAX_AUTHORIZATION_CHARS: number = 8192
const MAX_AUTH_USERNAME_CHARS: number = 50
const MAX_AUTH_PASSWORD_CHARS: number = 2048
const MIN_TIMEOUT_MS: number = 1000
const MAX_TIMEOUT_MS: number = 10 * 60 * 1000
const RENDER_CACHE_DIR: string = 'comic-translated-pages'

class SidecarMultipartPart {
  name: string = ''
  fileName: string = ''
  contentType: string = ''
  bytes: Uint8Array = new Uint8Array(0)
}

class SidecarSourceImage {
  bytes: Uint8Array = new Uint8Array(0)
  mimeType: string = ''
  fileName: string = ''
}

class PngDimensions {
  width: number = 0
  height: number = 0
}

export class MangaTranslatorUiSidecarConfig {
  baseUrl: string = ''
  sessionToken: string = ''
  username: string = ''
  password: string = ''
  translationConfigJson: string = MANGA_TRANSLATOR_UI_VISUAL_ONLY_CONFIG_JSON
  connectTimeoutMs: number = 15000
  readTimeoutMs: number = 5 * 60 * 1000

  validatedBaseUrl(): string {
    const value: string = this.baseUrl.trim()
    if (value.length <= 0 || value.length > MAX_BASE_URL_CHARS || value !== this.baseUrl ||
      /[\r\n\t ]/.test(value)) {
      throw new Error('Manga translator UI base URL is invalid')
    }
    const match: RegExpExecArray | null = /^(https?):\/\/([^/?#]+)(\/[^?#]*)?$/.exec(value)
    if (match === null || match[2].includes('@')) {
      throw new Error('Manga translator UI base URL is invalid')
    }
    MangaTranslatorUiSidecarConfig.validateAuthority(match[2])
    if (match[1] === 'http' && !MangaTranslatorUiSidecarConfig.isPrivateAuthority(match[2])) {
      throw new Error('Public Manga translator UI services require HTTPS')
    }
    MangaTranslatorUiSidecarConfig.validateAuthentication(
      this.sessionToken,
      this.username,
      this.password,
    )
    MangaTranslatorUiSidecarConfig.validateConfigJson(this.translationConfigJson)
    MangaTranslatorUiSidecarConfig.validateTimeout(this.connectTimeoutMs)
    MangaTranslatorUiSidecarConfig.validateTimeout(this.readTimeoutMs)
    let output: string = value
    while (output.endsWith('/')) {
      output = output.substring(0, output.length - 1)
    }
    return output
  }

  private static validateAuthority(authority: string): void {
    const hostAndPort: string[] = MangaTranslatorUiSidecarConfig.hostAndPort(authority)
    const host: string = hostAndPort[0]
    if (host.length <= 0 || /[^a-zA-Z0-9.:[\]-]/.test(host)) {
      throw new Error('Manga translator UI host is invalid')
    }
    if (hostAndPort[1].length > 0) {
      const port: number = Number.parseInt(hostAndPort[1], 10)
      if (!/^\d+$/.test(hostAndPort[1]) || port <= 0 || port > 65535) {
        throw new Error('Manga translator UI port is invalid')
      }
    }
  }

  private static isPrivateAuthority(authority: string): boolean {
    const host: string = MangaTranslatorUiSidecarConfig.hostAndPort(authority)[0].toLowerCase()
    if (host === 'localhost' || host.endsWith('.localhost') || host === '[::1]') {
      return true
    }
    const match: RegExpExecArray | null = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host)
    if (match === null) {
      return false
    }
    const first: number = Number.parseInt(match[1], 10)
    const second: number = Number.parseInt(match[2], 10)
    const third: number = Number.parseInt(match[3], 10)
    const fourth: number = Number.parseInt(match[4], 10)
    if (first > 255 || second > 255 || third > 255 || fourth > 255) {
      return false
    }
    return first === 10 || first === 127 ||
      (first === 172 && second >= 16 && second <= 31) ||
      (first === 192 && second === 168) ||
      (first === 169 && second === 254)
  }

  private static hostAndPort(authority: string): string[] {
    if (authority.startsWith('[')) {
      const close: number = authority.indexOf(']')
      if (close <= 1 || (close + 1 < authority.length && authority.charAt(close + 1) !== ':')) {
        throw new Error('Manga translator UI IPv6 host is invalid')
      }
      const result: string[] = [authority.substring(0, close + 1), '']
      if (close + 1 < authority.length) {
        result[1] = authority.substring(close + 2)
      }
      return result
    }
    const firstColon: number = authority.indexOf(':')
    const lastColon: number = authority.lastIndexOf(':')
    if (firstColon !== lastColon) {
      throw new Error('Manga translator UI IPv6 host must use brackets')
    }
    if (lastColon < 0) {
      return [authority, '']
    }
    return [authority.substring(0, lastColon), authority.substring(lastColon + 1)]
  }

  hasAccountCredentials(): boolean {
    return this.username.length > 0 && this.password.length > 0
  }

  sessionRequest(baseUrl: string = this.validatedBaseUrl()): MangaTranslatorUiSessionRequest {
    const request: MangaTranslatorUiSessionRequest = new MangaTranslatorUiSessionRequest()
    request.baseUrl = baseUrl
    request.username = this.username
    request.password = this.password
    request.legacySessionToken = this.sessionToken
    request.connectTimeoutMs = this.connectTimeoutMs
    request.readTimeoutMs = Math.min(this.readTimeoutMs, 15000)
    return request
  }

  private static validateAuthentication(
    sessionToken: string,
    username: string,
    password: string,
  ): void {
    const hasUsername: boolean = username.length > 0
    const hasPassword: boolean = password.length > 0
    if (sessionToken.length > MAX_AUTHORIZATION_CHARS || /[\r\n]/.test(sessionToken) ||
      hasUsername !== hasPassword || (sessionToken.length > 0 && hasUsername) ||
      username.length > MAX_AUTH_USERNAME_CHARS || password.length > MAX_AUTH_PASSWORD_CHARS ||
      /[\r\n\t]/.test(username)) {
      throw new Error('Manga translator UI authorization value is invalid')
    }
  }

  private static validateConfigJson(value: string): void {
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(value)
    if (bytes.length <= 0 || bytes.length > MAX_CONFIG_JSON_BYTES ||
      value !== MANGA_TRANSLATOR_UI_VISUAL_ONLY_CONFIG_JSON) {
      throw new Error('Manga translator UI config must use the pinned visual-only profile')
    }
    try {
      const parsed: Object = JSON.parse(value) as Object
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('not an object')
      }
    } catch (_error) {
      throw new Error('Manga translator UI config JSON is invalid')
    }
  }

  private static validateTimeout(value: number): void {
    if (!Number.isFinite(value) || Math.floor(value) !== value ||
      value < MIN_TIMEOUT_MS || value > MAX_TIMEOUT_MS) {
      throw new Error('Manga translator UI timeout is invalid')
    }
  }
}

export class MangaTranslatorUiSidecarTransportRequest {
  url: string = ''
  headers: Record<string, string> = {}
  body: Uint8Array = new Uint8Array(0)
  maxResponseBytes: number = 0
  connectTimeoutMs: number = 0
  readTimeoutMs: number = 0
}

export class MangaTranslatorUiSidecarTransportResponse {
  statusCode: number = 0
  body: Uint8Array = new Uint8Array(0)
}

export interface MangaTranslatorUiSidecarTransport {
  post(request: MangaTranslatorUiSidecarTransportRequest):
    Promise<MangaTranslatorUiSidecarTransportResponse>
}

export class DefaultMangaTranslatorUiSidecarTransport implements MangaTranslatorUiSidecarTransport {
  async post(
    request: MangaTranslatorUiSidecarTransportRequest,
  ): Promise<MangaTranslatorUiSidecarTransportResponse> {
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
    const output: MangaTranslatorUiSidecarTransportResponse =
      new MangaTranslatorUiSidecarTransportResponse()
    output.statusCode = response.statusCode
    if (response.bytes !== null) {
      output.body = new Uint8Array(response.bytes)
    }
    return output
  }
}

export class MangaTranslatorUiSidecarBackend implements ComicRegionRenderBackend {
  private readonly context: common.UIAbilityContext
  private readonly config: MangaTranslatorUiSidecarConfig
  private readonly transport: MangaTranslatorUiSidecarTransport
  private readonly sessionProvider: MangaTranslatorUiSidecarSessionProvider

  constructor(
    context: common.UIAbilityContext,
    config: MangaTranslatorUiSidecarConfig,
    transport: MangaTranslatorUiSidecarTransport = new DefaultMangaTranslatorUiSidecarTransport(),
    sessionProvider: MangaTranslatorUiSidecarSessionProvider =
      new DefaultMangaTranslatorUiSidecarSessionProvider(),
  ) {
    this.context = context
    this.config = config
    this.transport = transport
    this.sessionProvider = sessionProvider
  }

  backendId(): string {
    return MANGA_TRANSLATOR_UI_BACKEND_ID
  }

  profileId(): string {
    return MANGA_TRANSLATOR_UI_PROFILE_ID
  }

  protocolRevision(): number {
    return MANGA_TRANSLATOR_UI_PROTOCOL_REVISION
  }

  async analyze(request: ComicRegionAnalysisRequest): Promise<ComicRegionAnalysisResult> {
    ComicVisualTranslationContract.validateRegionAnalysisRequest(request)
    const source: SidecarSourceImage = MangaTranslatorUiSidecarBackend.readSourceImage(request.source)
    const response: MangaTranslatorUiSidecarTransportResponse = await this.postMultipart(
      MANGA_TRANSLATOR_UI_EXPORT_PATH,
      MangaTranslatorUiSidecarBackend.exportParts(this.config.translationConfigJson, source),
      MAX_EXPORT_RESPONSE_BYTES,
    )
    MangaTranslatorUiSidecarBackend.requireSuccess(response, MAX_EXPORT_RESPONSE_BYTES, 'export')
    const files: MangaTranslatorUiExportFiles = await MangaTranslatorUiSidecarArchive.extract(
      this.context,
      response.body,
    )
    return MangaTranslatorUiSidecarProtocol.parseExport(
      request,
      files.translationJson,
      files.originalText,
    )
  }

  async render(request: ComicRegionRenderRequest): Promise<ComicRenderedPage> {
    ComicVisualTranslationContract.validateStagedRenderRequest(request)
    if (request.identity.renderBackendId !== this.backendId() ||
      request.identity.regionBackendId !== this.backendId() ||
      request.identity.regionProfileId !== this.profileId() ||
      request.adapterTemplate.protocolRevision !== this.protocolRevision()) {
      throw new Error('Manga translator UI render profile identity is invalid')
    }
    const source: SidecarSourceImage = MangaTranslatorUiSidecarBackend.readSourceImage(request.source)
    const importJson: Uint8Array = MangaTranslatorUiSidecarProtocol.buildImportJson(
      request.document,
      request.translations,
      request.adapterTemplate,
    )
    const response: MangaTranslatorUiSidecarTransportResponse = await this.postMultipart(
      MANGA_TRANSLATOR_UI_IMPORT_PATH,
      MangaTranslatorUiSidecarBackend.importParts(
        this.config.translationConfigJson,
        source,
        importJson,
      ),
      MAX_RENDER_RESPONSE_BYTES,
    )
    MangaTranslatorUiSidecarBackend.requireSuccess(response, MAX_RENDER_RESPONSE_BYTES, 'render')
    const dimensions: PngDimensions = await MangaTranslatorUiSidecarBackend.validatePng(
      response.body,
      request.source.imageWidth,
      request.source.imageHeight,
    )
    const artifactHash: string = MangaTranslatorUiSidecarBackend.sha256(response.body)
    const path: string = MangaTranslatorUiSidecarBackend.persistRenderedPage(
      this.context,
      request.identity.cacheKey(),
      artifactHash,
      response.body,
    )
    const now: number = Date.now()
    const page: ComicRenderedPage = new ComicRenderedPage()
    page.identity = request.identity.copy()
    page.artifactHash = artifactHash
    page.mimeType = 'image/png'
    page.width = dimensions.width
    page.height = dimensions.height
    page.byteLength = response.body.length
    page.localFilePath = path
    page.createdAt = now
    page.lastAccessAt = now
    ComicVisualTranslationContract.validateRenderedPage(request.identity, page)
    return page
  }

  private async postMultipart(
    path: string,
    parts: SidecarMultipartPart[],
    maxResponseBytes: number,
  ): Promise<MangaTranslatorUiSidecarTransportResponse> {
    const baseUrl: string = this.config.validatedBaseUrl()
    const boundary: string = 'NextE' + util.generateRandomUUID(true).replace(/-/g, '')
    const body: Uint8Array = MangaTranslatorUiSidecarBackend.multipart(boundary, parts)
    const sessionRequest: MangaTranslatorUiSessionRequest = this.config.sessionRequest(baseUrl)
    let sessionToken: string = await this.sessionProvider.acquire(sessionRequest)
    let response: MangaTranslatorUiSidecarTransportResponse = await this.postMultipartOnce(
      baseUrl + path,
      boundary,
      body,
      maxResponseBytes,
      sessionToken,
    )
    if (response.statusCode === 401 && this.config.hasAccountCredentials()) {
      this.sessionProvider.invalidate(sessionRequest, sessionToken)
      sessionToken = await this.sessionProvider.acquire(sessionRequest)
      response = await this.postMultipartOnce(
        baseUrl + path,
        boundary,
        body,
        maxResponseBytes,
        sessionToken,
      )
    }
    return response
  }

  private async postMultipartOnce(
    url: string,
    boundary: string,
    body: Uint8Array,
    maxResponseBytes: number,
    sessionToken: string,
  ): Promise<MangaTranslatorUiSidecarTransportResponse> {
    const request: MangaTranslatorUiSidecarTransportRequest =
      new MangaTranslatorUiSidecarTransportRequest()
    request.url = url
    request.headers = {
      'Accept': 'application/octet-stream, application/zip, image/png',
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'Content-Length': `${body.length}`,
      'X-Session-Token': sessionToken,
    }
    request.body = body
    request.maxResponseBytes = maxResponseBytes
    request.connectTimeoutMs = this.config.connectTimeoutMs
    request.readTimeoutMs = this.config.readTimeoutMs
    return await this.transport.post(request)
  }

  private static exportParts(
    configJson: string,
    source: SidecarSourceImage,
  ): SidecarMultipartPart[] {
    return [
      MangaTranslatorUiSidecarBackend.filePart(
        'image',
        source.fileName,
        source.mimeType,
        source.bytes,
      ),
      MangaTranslatorUiSidecarBackend.textPart('config', configJson),
    ]
  }

  private static importParts(
    configJson: string,
    source: SidecarSourceImage,
    importJson: Uint8Array,
  ): SidecarMultipartPart[] {
    return [
      MangaTranslatorUiSidecarBackend.filePart(
        'image',
        source.fileName,
        source.mimeType,
        source.bytes,
      ),
      MangaTranslatorUiSidecarBackend.filePart(
        'json_file',
        'translation.json',
        'application/json',
        importJson,
      ),
      MangaTranslatorUiSidecarBackend.textPart('config', configJson),
    ]
  }

  private static textPart(name: string, value: string): SidecarMultipartPart {
    const part: SidecarMultipartPart = new SidecarMultipartPart()
    part.name = name
    part.bytes = new util.TextEncoder().encodeInto(value)
    return part
  }

  private static filePart(
    name: string,
    fileName: string,
    contentType: string,
    bytes: Uint8Array,
  ): SidecarMultipartPart {
    const part: SidecarMultipartPart = new SidecarMultipartPart()
    part.name = name
    part.fileName = fileName
    part.contentType = contentType
    part.bytes = bytes
    return part
  }

  private static multipart(boundary: string, parts: SidecarMultipartPart[]): Uint8Array {
    if (!/^[A-Za-z0-9]+$/.test(boundary) || parts.length <= 0 || parts.length > 4) {
      throw new Error('Manga translator UI multipart boundary is invalid')
    }
    const encoder: util.TextEncoder = new util.TextEncoder()
    const chunks: Uint8Array[] = []
    let total: number = 0
    for (let index: number = 0; index < parts.length; index++) {
      const part: SidecarMultipartPart = parts[index]
      if (!/^[a-z_]+$/.test(part.name) || /[\r\n"]/.test(part.fileName) ||
        /[\r\n]/.test(part.contentType)) {
        throw new Error('Manga translator UI multipart part is invalid')
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
      const headerBytes: Uint8Array = encoder.encodeInto(header)
      const tailBytes: Uint8Array = encoder.encodeInto('\r\n')
      chunks.push(headerBytes)
      chunks.push(part.bytes)
      chunks.push(tailBytes)
      total += headerBytes.length + part.bytes.length + tailBytes.length
    }
    const closing: Uint8Array = encoder.encodeInto(`--${boundary}--\r\n`)
    total += closing.length
    if (total <= 0 || total > MAX_MULTIPART_BODY_BYTES) {
      throw new Error('Manga translator UI multipart body is too large')
    }
    const output: Uint8Array = new Uint8Array(total)
    let offset: number = 0
    for (let index: number = 0; index < chunks.length; index++) {
      output.set(chunks[index], offset)
      offset += chunks[index].length
    }
    output.set(closing, offset)
    return output
  }

  private static readSourceImage(source: ComicVisualPageSource): SidecarSourceImage {
    ComicVisualTranslationContract.validateSource(source)
    if (!fileIo.accessSync(source.imageFilePath)) {
      throw new Error('Manga translator UI source image is missing')
    }
    const stat: fileIo.Stat = fileIo.statSync(source.imageFilePath)
    const length: number = Math.floor(stat.size)
    if (!stat.isFile() || length <= 0 || length > MAX_SOURCE_IMAGE_BYTES) {
      throw new Error('Manga translator UI source image size is invalid')
    }
    const bytes: Uint8Array = MangaTranslatorUiSidecarBackend.readExact(
      source.imageFilePath,
      length,
    )
    if (MangaTranslatorUiSidecarBackend.sha256(bytes) !== source.imageHash) {
      throw new Error('Manga translator UI source image hash changed')
    }
    const value: SidecarSourceImage = new SidecarSourceImage()
    value.bytes = bytes
    value.mimeType = MangaTranslatorUiSidecarBackend.imageMime(bytes)
    value.fileName = value.mimeType === 'image/png' ? 'source.png' :
      value.mimeType === 'image/jpeg' ? 'source.jpg' : 'source.webp'
    return value
  }

  private static imageMime(bytes: Uint8Array): string {
    if (MangaTranslatorUiSidecarBackend.isPng(bytes)) {
      return 'image/png'
    }
    if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
      return 'image/jpeg'
    }
    if (bytes.length >= 12 && MangaTranslatorUiSidecarBackend.asciiAt(bytes, 0, 'RIFF') &&
      MangaTranslatorUiSidecarBackend.asciiAt(bytes, 8, 'WEBP')) {
      return 'image/webp'
    }
    throw new Error('Manga translator UI source image format is unsupported')
  }

  private static async validatePng(
    bytes: Uint8Array,
    expectedWidth: number,
    expectedHeight: number,
  ): Promise<PngDimensions> {
    if (bytes.length <= 0 || bytes.length > MAX_RENDER_RESPONSE_BYTES ||
      !MangaTranslatorUiSidecarBackend.isPng(bytes) ||
      !MangaTranslatorUiSidecarBackend.asciiAt(bytes, 12, 'IHDR')) {
      throw new Error('Manga translator UI render response is not a PNG image')
    }
    const dimensions: PngDimensions = new PngDimensions()
    dimensions.width = MangaTranslatorUiSidecarBackend.u32be(bytes, 16)
    dimensions.height = MangaTranslatorUiSidecarBackend.u32be(bytes, 20)
    if (dimensions.width <= 0 || dimensions.height <= 0 ||
      dimensions.width > 100000 || dimensions.height > 100000) {
      throw new Error('Manga translator UI rendered PNG dimensions are invalid')
    }
    if (dimensions.width !== expectedWidth || dimensions.height !== expectedHeight) {
      throw new Error('Manga translator UI rendered image dimensions do not match the source')
    }
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    try {
      const buffer: ArrayBuffer = bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength,
      )
      source = image.createImageSource(buffer)
      const options: image.DecodingOptions = {
        editable: false,
        desiredSize: { width: 1, height: 1 },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      }
      pixelMap = await source.createPixelMap(options)
      const info: image.ImageInfo = await pixelMap.getImageInfo()
      if (info.size.width <= 0 || info.size.height <= 0) {
        throw new Error('decoded dimensions are invalid')
      }
    } catch (_error) {
      throw new Error('Manga translator UI rendered PNG cannot be decoded')
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
      throw new Error('Manga translator UI PNG header is truncated')
    }
    return ((bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3]) >>> 0
  }

  private static requireSuccess(
    response: MangaTranslatorUiSidecarTransportResponse,
    maxBytes: number,
    operation: string,
  ): void {
    if (response.statusCode < 200 || response.statusCode > 299) {
      const detail: string = MangaTranslatorUiSidecarBackend.boundedErrorDetail(response.body)
      const suffix: string = detail.length > 0 ? `: ${detail}` : ''
      throw new Error(
        `Manga translator UI ${operation} failed with HTTP ${response.statusCode}${suffix}`,
      )
    }
    if (response.body.length <= 0 || response.body.length > maxBytes) {
      throw new Error(`Manga translator UI ${operation} response size is invalid`)
    }
  }

  private static boundedErrorDetail(body: Uint8Array): string {
    if (body.length <= 0) {
      return ''
    }
    try {
      const bounded: Uint8Array = body.slice(0, Math.min(body.length, 1024))
      const decoded: string = util.TextDecoder.create('utf-8', { ignoreBOM: true })
        .decodeToString(bounded)
      return decoded.replace(/[\r\n\t]+/g, ' ').trim().slice(0, 512)
    } catch (_error) {
      return ''
    }
  }

  private static readExact(path: string, length: number): Uint8Array {
    const output: Uint8Array = new Uint8Array(length)
    let file: fileIo.File | null = null
    let offset: number = 0
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      while (offset < length) {
        const chunk: ArrayBuffer = new ArrayBuffer(length - offset)
        const read: number = fileIo.readSync(file.fd, chunk, { length: chunk.byteLength })
        if (read <= 0) {
          throw new Error('Manga translator UI source image is truncated')
        }
        output.set(new Uint8Array(chunk, 0, read), offset)
        offset += read
      }
      return output
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static persistRenderedPage(
    context: common.UIAbilityContext,
    identityKey: string,
    artifactHash: string,
    bytes: Uint8Array,
  ): string {
    const dir: string = `${context.cacheDir}/${RENDER_CACHE_DIR}`
    MangaTranslatorUiSidecarBackend.ensureDir(dir)
    const identityHash: string = MangaTranslatorUiSidecarBackend.sha256(
      new util.TextEncoder().encodeInto(identityKey),
    )
    const path: string = `${dir}/${identityHash}-${artifactHash}.png`
    if (fileIo.accessSync(path)) {
      const stat: fileIo.Stat = fileIo.statSync(path)
      if (stat.isFile() && Math.floor(stat.size) === bytes.length) {
        return path
      }
      MangaTranslatorUiSidecarBackend.removeFile(path)
    }
    const partial: string = `${path}.part-${util.generateRandomUUID(true)}`
    try {
      MangaTranslatorUiSidecarBackend.writeExact(partial, bytes)
      fileIo.renameSync(partial, path)
      return path
    } catch (error) {
      MangaTranslatorUiSidecarBackend.removeFile(partial)
      throw error as Error
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
        const chunk: ArrayBuffer = bytes.buffer.slice(
          bytes.byteOffset + offset,
          bytes.byteOffset + bytes.byteLength,
        )
        const written: number = fileIo.writeSync(file.fd, chunk, { length: chunk.byteLength })
        if (written <= 0) {
          throw new Error('Manga translator UI rendered image write failed')
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

  private static sha256(value: Uint8Array): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: value })
    const digest: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < digest.length; index++) {
      parts.push(digest[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}

import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import {
  ComicBlockTranslation,
  ComicTranslationBatch,
} from '../model/ComicVisualTranslation'
import { ComicPageAnalysisContext } from './ComicPageAnalyzer'
import {
  ComicTextTranslationRequest,
  ComicTextTranslationResult,
  ComicTextTranslator,
  ComicVisualPageSource,
} from './ComicVisualTranslationBackend'
import { ComicTextTranslatorFactory } from './ComicResponsesTextTranslator'
import { ComicTranslationDocumentCodec } from './ComicTranslationPersistentRepository'
import { ComicTranslationErrorClassifier } from './ComicTranslationErrorClassifier'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'

const PROBE_SCHEMA_VERSION: number = 1
const PROBE_ROOT_NAME: string = 'comic-live-translation-probes'
const REQUEST_FILE_NAME: string = 'request.json'
const RESPONSE_FILE_NAME: string = 'response.json'
const STATUS_FILE_NAME: string = 'status.json'
const PENDING_FILE_NAME: string = 'pending.json'
const MAX_PROBE_PAYLOAD_CHARS: number = 4 * 1024 * 1024
const MAX_TEXT_CHARS: number = 8192
const MAX_IDENTIFIER_CHARS: number = 160
const MAX_PAGE_SUMMARY_CHARS: number = 4096

class RawProbeSource {
  projectId: string = ''
  pageIndex: number = -1
  imageFilePath: string = ''
  imageHash: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
}

class RawProbeContext {
  sourceLanguage: string = ''
  targetLanguage: string = ''
  rollingSummary: string = ''
  styleGuide: string = ''
  glossaryRevision: number = 0
  styleGuideRevision: number = 0
  contextRevision: number = 0
}

class RawProbeRequest {
  schemaVersion: number = 0
  probeId: string = ''
  source: RawProbeSource = new RawProbeSource()
  documentPayload: string = ''
  context: RawProbeContext = new RawProbeContext()
  requestedTranslationRevision: number = 0
}

class RawProbeBlockTranslation {
  blockId: string = ''
  translatedText: string = ''
}

class RawProbeBatch {
  projectId: string = ''
  pageIndex: number = -1
  sourceImageHash: string = ''
  targetLanguage: string = ''
  sourceProfileId: string = ''
  sourceRevision: number = 0
  modelId: string = ''
  promptVersion: string = ''
  contextFingerprint: string = ''
  glossaryRevision: number = 0
  translationRevision: number = 0
  blocks: RawProbeBlockTranslation[] = []
}

class RawProbeResponse {
  schemaVersion: number = 0
  probeId: string = ''
  requestHash: string = ''
  elapsedMs: number = 0
  pageSummary: string = ''
  batch: RawProbeBatch = new RawProbeBatch()
}

class RawProbeStatus {
  schemaVersion: number = PROBE_SCHEMA_VERSION
  probeId: string = ''
  state: string = ''
  errorCode: string = ''
  elapsedMs: number = 0
}

class RawPendingProbe {
  schemaVersion: number = PROBE_SCHEMA_VERSION
  probeId: string = ''
}

export class ComicTranslationDebugProbeResult {
  result: ComicTextTranslationResult = new ComicTextTranslationResult()
  elapsedMs: number = 0
}

/**
 * File-backed, debug-build-only bridge used by device A/B tests.
 *
 * Test code exchanges a provider-neutral request and result through the application cache. The
 * selected LLM profile and every credential remain owned and read by the main application process.
 */
export class ComicTranslationDebugProbeService {
  static exportRequest(
    context: common.UIAbilityContext,
    probeId: string,
    request: ComicTextTranslationRequest,
  ): void {
    ComicTranslationDebugProbeService.validateProbeId(probeId)
    ComicTranslationDebugProbeService.validateRequest(context, request)
    const raw: RawProbeRequest =
      ComicTranslationDebugProbeService.rawRequest(probeId, request)
    const payload: string = ComicTranslationDebugProbeService.encode(raw)
    const directory: string = ComicTranslationDebugProbeService.directory(context, probeId)
    ComicTranslationDebugProbeService.ensureDirectory(directory)
    ComicTranslationDebugProbeService.writeAtomic(`${directory}/${REQUEST_FILE_NAME}`, payload)
    ComicTranslationDebugProbeService.writeStatus(context, probeId, 'exported', '', 0)
    const pending: RawPendingProbe = new RawPendingProbe()
    pending.probeId = probeId
    ComicTranslationDebugProbeService.writeAtomic(
      `${ComicTranslationDebugProbeService.root(context)}/${PENDING_FILE_NAME}`,
      ComicTranslationDebugProbeService.encode(pending),
    )
  }

  static async executePending(context: common.UIAbilityContext): Promise<boolean> {
    if (!ComicTranslationDebugProbeService.debugBuild(context)) {
      return false
    }
    const path: string = `${ComicTranslationDebugProbeService.root(context)}/${PENDING_FILE_NAME}`
    if (!fileIo.accessSync(path)) {
      return false
    }
    const pending: RawPendingProbe =
      JSON.parse(ComicTranslationDebugProbeService.readBounded(path)) as RawPendingProbe
    if (pending.schemaVersion !== PROBE_SCHEMA_VERSION ||
      !ComicTranslationDebugProbeService.safeIdentifier(pending.probeId)) {
      throw new Error('Comic translation pending debug probe is invalid')
    }
    fileIo.unlinkSync(path)
    await ComicTranslationDebugProbeService.execute(context, pending.probeId)
    return true
  }

  static async execute(
    context: common.UIAbilityContext,
    probeId: string,
  ): Promise<void> {
    ComicTranslationDebugProbeService.validateProbeId(probeId)
    if (!ComicTranslationDebugProbeService.debugBuild(context)) {
      throw new Error('Comic translation debug probe is unavailable')
    }
    const startedAt: number = Date.now()
    ComicTranslationDebugProbeService.writeStatus(context, probeId, 'translating', '', 0)
    try {
      const raw: RawProbeRequest =
        ComicTranslationDebugProbeService.readRawRequest(context, probeId)
      const request: ComicTextTranslationRequest =
        ComicTranslationDebugProbeService.request(context, raw)
      const translator: ComicTextTranslator = await ComicTextTranslatorFactory.create(context)
      const result: ComicTextTranslationResult = await translator.translate(request)
      ComicVisualTranslationContract.validateTranslationBatch(request.document, result.batch)
      const elapsedMs: number = Math.max(0, Date.now() - startedAt)
      const response: RawProbeResponse =
        ComicTranslationDebugProbeService.rawResponse(
          probeId,
          ComicTranslationDebugProbeService.requestHash(raw),
          result,
          elapsedMs,
        )
      const directory: string = ComicTranslationDebugProbeService.directory(context, probeId)
      ComicTranslationDebugProbeService.writeAtomic(
        `${directory}/${RESPONSE_FILE_NAME}`,
        ComicTranslationDebugProbeService.encode(response),
      )
      ComicTranslationDebugProbeService.writeStatus(
        context,
        probeId,
        'ready',
        '',
        elapsedMs,
      )
    } catch (error) {
      const elapsedMs: number = Math.max(0, Date.now() - startedAt)
      const code: string = ComicTranslationErrorClassifier.classify(error as Error)
      ComicTranslationDebugProbeService.writeStatus(
        context,
        probeId,
        'failed',
        code,
        elapsedMs,
      )
      throw error as Error
    }
  }

  static importResult(
    context: common.UIAbilityContext,
    probeId: string,
    request: ComicTextTranslationRequest,
  ): ComicTranslationDebugProbeResult {
    ComicTranslationDebugProbeService.validateProbeId(probeId)
    ComicTranslationDebugProbeService.validateRequest(context, request)
    const expectedRaw: RawProbeRequest =
      ComicTranslationDebugProbeService.rawRequest(probeId, request)
    const path: string =
      `${ComicTranslationDebugProbeService.directory(context, probeId)}/${RESPONSE_FILE_NAME}`
    const payload: string = ComicTranslationDebugProbeService.readBounded(path)
    const raw: RawProbeResponse = JSON.parse(payload) as RawProbeResponse
    if (raw.schemaVersion !== PROBE_SCHEMA_VERSION || raw.probeId !== probeId ||
      raw.requestHash !== ComicTranslationDebugProbeService.requestHash(expectedRaw) ||
      !ComicTranslationDebugProbeService.nonNegativeInteger(raw.elapsedMs) ||
      typeof raw.pageSummary !== 'string' ||
      raw.pageSummary.length > MAX_PAGE_SUMMARY_CHARS) {
      throw new Error('Comic translation debug probe response is invalid')
    }
    const result: ComicTranslationDebugProbeResult = new ComicTranslationDebugProbeResult()
    result.result.batch = ComicTranslationDebugProbeService.batch(raw.batch)
    result.result.pageSummary = raw.pageSummary
    result.elapsedMs = raw.elapsedMs
    ComicVisualTranslationContract.validateTranslationBatch(
      request.document,
      result.result.batch,
    )
    return result
  }

  private static rawRequest(
    probeId: string,
    request: ComicTextTranslationRequest,
  ): RawProbeRequest {
    const raw: RawProbeRequest = new RawProbeRequest()
    raw.schemaVersion = PROBE_SCHEMA_VERSION
    raw.probeId = probeId
    raw.source.projectId = request.source.projectId
    raw.source.pageIndex = request.source.pageIndex
    raw.source.imageFilePath = request.source.imageFilePath
    raw.source.imageHash = request.source.imageHash
    raw.source.imageWidth = request.source.imageWidth
    raw.source.imageHeight = request.source.imageHeight
    raw.documentPayload = ComicTranslationDocumentCodec.encode(request.document)
    raw.context.sourceLanguage = request.context.sourceLanguage
    raw.context.targetLanguage = request.context.targetLanguage
    raw.context.rollingSummary = request.context.rollingSummary
    raw.context.styleGuide = request.context.styleGuide
    raw.context.glossaryRevision = request.context.glossaryRevision
    raw.context.styleGuideRevision = request.context.styleGuideRevision
    raw.context.contextRevision = request.context.contextRevision
    raw.requestedTranslationRevision = request.requestedTranslationRevision
    return raw
  }

  private static request(
    context: common.UIAbilityContext,
    raw: RawProbeRequest,
  ): ComicTextTranslationRequest {
    if (raw.schemaVersion !== PROBE_SCHEMA_VERSION ||
      !ComicTranslationDebugProbeService.safeIdentifier(raw.probeId)) {
      throw new Error('Comic translation debug probe request identity is invalid')
    }
    const request: ComicTextTranslationRequest = new ComicTextTranslationRequest()
    request.source = ComicTranslationDebugProbeService.source(raw.source)
    request.document = ComicTranslationDocumentCodec.decode(
      ComicTranslationDebugProbeService.requiredText(
        raw.documentPayload,
        MAX_PROBE_PAYLOAD_CHARS,
      ),
    )
    const probeContext: ComicPageAnalysisContext = new ComicPageAnalysisContext()
    probeContext.sourceLanguage = ComicTranslationDebugProbeService.identifier(
      raw.context.sourceLanguage,
    )
    probeContext.targetLanguage = ComicTranslationDebugProbeService.identifier(
      raw.context.targetLanguage,
    )
    probeContext.rollingSummary = ComicTranslationDebugProbeService.text(
      raw.context.rollingSummary,
      MAX_PAGE_SUMMARY_CHARS,
    )
    probeContext.styleGuide = ComicTranslationDebugProbeService.text(
      raw.context.styleGuide,
      MAX_TEXT_CHARS,
    )
    probeContext.glossaryRevision =
      ComicTranslationDebugProbeService.integer(raw.context.glossaryRevision)
    probeContext.styleGuideRevision =
      ComicTranslationDebugProbeService.integer(raw.context.styleGuideRevision)
    probeContext.contextRevision =
      ComicTranslationDebugProbeService.integer(raw.context.contextRevision)
    request.context = probeContext
    request.requestedTranslationRevision =
      ComicTranslationDebugProbeService.positiveInteger(raw.requestedTranslationRevision)
    ComicTranslationDebugProbeService.validateRequest(context, request)
    return request
  }

  private static source(raw: RawProbeSource): ComicVisualPageSource {
    const source: ComicVisualPageSource = new ComicVisualPageSource()
    source.projectId = ComicTranslationDebugProbeService.identifier(raw.projectId)
    source.pageIndex = ComicTranslationDebugProbeService.integer(raw.pageIndex)
    source.imageFilePath = ComicTranslationDebugProbeService.requiredText(
      raw.imageFilePath,
      MAX_PROBE_PAYLOAD_CHARS,
    )
    source.imageHash = ComicTranslationDebugProbeService.requiredText(raw.imageHash, 64)
    source.imageWidth = ComicTranslationDebugProbeService.positiveInteger(raw.imageWidth)
    source.imageHeight = ComicTranslationDebugProbeService.positiveInteger(raw.imageHeight)
    return source
  }

  private static batch(raw: RawProbeBatch): ComicTranslationBatch {
    if (!Array.isArray(raw.blocks) || raw.blocks.length > 512) {
      throw new Error('Comic translation debug probe batch is invalid')
    }
    const batch: ComicTranslationBatch = new ComicTranslationBatch()
    batch.projectId = ComicTranslationDebugProbeService.identifier(raw.projectId)
    batch.pageIndex = ComicTranslationDebugProbeService.integer(raw.pageIndex)
    batch.sourceImageHash =
      ComicTranslationDebugProbeService.requiredText(raw.sourceImageHash, 64)
    batch.targetLanguage = ComicTranslationDebugProbeService.identifier(raw.targetLanguage)
    batch.sourceProfileId = ComicTranslationDebugProbeService.identifier(raw.sourceProfileId)
    batch.sourceRevision = ComicTranslationDebugProbeService.positiveInteger(raw.sourceRevision)
    batch.modelId = ComicTranslationDebugProbeService.identifier(raw.modelId)
    batch.promptVersion = ComicTranslationDebugProbeService.identifier(raw.promptVersion)
    batch.contextFingerprint =
      ComicTranslationDebugProbeService.requiredText(raw.contextFingerprint, 64)
    batch.glossaryRevision = ComicTranslationDebugProbeService.integer(raw.glossaryRevision)
    batch.translationRevision =
      ComicTranslationDebugProbeService.positiveInteger(raw.translationRevision)
    for (let index: number = 0; index < raw.blocks.length; index++) {
      const block: ComicBlockTranslation = new ComicBlockTranslation()
      block.blockId = ComicTranslationDebugProbeService.identifier(raw.blocks[index].blockId)
      block.translatedText = ComicTranslationDebugProbeService.requiredText(
        raw.blocks[index].translatedText,
        MAX_TEXT_CHARS,
      )
      batch.blocks.push(block)
    }
    return batch
  }

  private static rawResponse(
    probeId: string,
    requestHash: string,
    result: ComicTextTranslationResult,
    elapsedMs: number,
  ): RawProbeResponse {
    const raw: RawProbeResponse = new RawProbeResponse()
    raw.schemaVersion = PROBE_SCHEMA_VERSION
    raw.probeId = probeId
    raw.requestHash = requestHash
    raw.elapsedMs = elapsedMs
    raw.pageSummary = result.pageSummary
    raw.batch = result.batch.copy() as RawProbeBatch
    return raw
  }

  private static readRawRequest(
    context: common.UIAbilityContext,
    probeId: string,
  ): RawProbeRequest {
    const path: string =
      `${ComicTranslationDebugProbeService.directory(context, probeId)}/${REQUEST_FILE_NAME}`
    const raw: RawProbeRequest =
      JSON.parse(ComicTranslationDebugProbeService.readBounded(path)) as RawProbeRequest
    if (raw.probeId !== probeId) {
      throw new Error('Comic translation debug probe request does not match')
    }
    return raw
  }

  private static validateRequest(
    context: common.UIAbilityContext,
    request: ComicTextTranslationRequest,
  ): void {
    ComicVisualTranslationContract.validateTextTranslationRequest(request)
    const root: string = `${context.getApplicationContext().cacheDir}/`
    if (!request.source.imageFilePath.startsWith(root) ||
      request.source.imageFilePath.includes('/../') ||
      !fileIo.accessSync(request.source.imageFilePath)) {
      throw new Error('Comic translation debug probe source path is unsafe')
    }
    if (request.context.glossary.length > 0 ||
      request.context.translationMemory.length > 0 ||
      request.context.previousPages.length > 0) {
      throw new Error('Comic translation debug probe context is unsupported')
    }
  }

  private static requestHash(raw: RawProbeRequest): string {
    const payload: string = ComicTranslationDebugProbeService.encode(raw)
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: new util.TextEncoder().encodeInto(payload) })
    const digest: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < digest.length; index++) {
      parts.push(digest[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }

  private static writeStatus(
    context: common.UIAbilityContext,
    probeId: string,
    state: string,
    errorCode: string,
    elapsedMs: number,
  ): void {
    const status: RawProbeStatus = new RawProbeStatus()
    status.probeId = probeId
    status.state = state
    status.errorCode = errorCode
    status.elapsedMs = elapsedMs
    const directory: string = ComicTranslationDebugProbeService.directory(context, probeId)
    ComicTranslationDebugProbeService.ensureDirectory(directory)
    ComicTranslationDebugProbeService.writeAtomic(
      `${directory}/${STATUS_FILE_NAME}`,
      ComicTranslationDebugProbeService.encode(status),
    )
  }

  private static directory(context: common.UIAbilityContext, probeId: string): string {
    ComicTranslationDebugProbeService.validateProbeId(probeId)
    return `${ComicTranslationDebugProbeService.root(context)}/${probeId}`
  }

  private static root(context: common.UIAbilityContext): string {
    const root: string =
      `${context.getApplicationContext().cacheDir}/${PROBE_ROOT_NAME}`
    ComicTranslationDebugProbeService.ensureDirectory(root)
    return root
  }

  private static ensureDirectory(path: string): void {
    if (!fileIo.accessSync(path)) {
      fileIo.mkdirSync(path, true)
    }
  }

  private static writeAtomic(path: string, payload: string): void {
    const partial: string = `${path}.partial`
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(payload)
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(
        partial,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      const written: number =
        fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
      if (written !== bytes.byteLength) {
        throw new Error('Comic translation debug probe write was incomplete')
      }
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
    fileIo.renameSync(partial, path)
  }

  private static readBounded(path: string): string {
    const payload: string = fileIo.readTextSync(path)
    if (payload.length <= 0 || payload.length > MAX_PROBE_PAYLOAD_CHARS) {
      throw new Error('Comic translation debug probe payload size is invalid')
    }
    return payload
  }

  private static encode(value: Object): string {
    const payload: string = JSON.stringify(value)
    if (payload.length <= 0 || payload.length > MAX_PROBE_PAYLOAD_CHARS) {
      throw new Error('Comic translation debug probe payload size is invalid')
    }
    return payload
  }

  private static validateProbeId(probeId: string): void {
    if (!ComicTranslationDebugProbeService.safeIdentifier(probeId)) {
      throw new Error('Comic translation debug probe id is invalid')
    }
  }

  private static safeIdentifier(value: string): boolean {
    return typeof value === 'string' &&
      /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value)
  }

  private static identifier(value: string): string {
    if (typeof value !== 'string' || value.length <= 0 ||
      value.length > MAX_IDENTIFIER_CHARS ||
      !/^[A-Za-z0-9][A-Za-z0-9._:/-]*$/.test(value)) {
      throw new Error('Comic translation debug probe identifier is invalid')
    }
    return value
  }

  private static requiredText(value: string, maxChars: number): string {
    if (typeof value !== 'string' || value.trim().length <= 0 || value.length > maxChars) {
      throw new Error('Comic translation debug probe text is invalid')
    }
    return value
  }

  private static text(value: string, maxChars: number): string {
    if (typeof value !== 'string' || value.length > maxChars) {
      throw new Error('Comic translation debug probe text is invalid')
    }
    return value
  }

  private static integer(value: number): number {
    if (!ComicTranslationDebugProbeService.nonNegativeInteger(value)) {
      throw new Error('Comic translation debug probe integer is invalid')
    }
    return value
  }

  private static positiveInteger(value: number): number {
    if (!ComicTranslationDebugProbeService.nonNegativeInteger(value) || value <= 0) {
      throw new Error('Comic translation debug probe positive integer is invalid')
    }
    return value
  }

  private static nonNegativeInteger(value: number): boolean {
    return Number.isFinite(value) && value >= 0 && Math.floor(value) === value
  }

  private static debugBuild(context: common.UIAbilityContext): boolean {
    return context.applicationInfo.debug ||
      context.applicationInfo.appProvisionType === 'debug'
  }
}

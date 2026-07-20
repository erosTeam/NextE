import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  ComicGlossaryTerm,
  ComicGlossaryTermProvenance,
  ComicGlossaryTermStatus,
  ComicImagePreparationProfile,
  ComicPageDocument,
} from '../model/ComicTranslation'
import {
  ComicPageAnalysisContext,
  ComicPageAnalysisRequest,
  ComicPageAnalysisResult,
  ComicPageAnalyzer,
  ComicPreviousPageContext,
} from './ComicPageAnalyzer'
import { ComicPageAnalyzerFactory, ComicProviderHttpError } from './ComicResponsesPageAnalyzer'
import {
  ComicTranslationAccuracySnapshot,
  ComicTranslationEvaluationSnapshot,
  ComicTranslationEvaluator,
  ComicTranslationReferenceBlock,
  ComicTranslationReferencePage,
} from './ComicTranslationEvaluation'

const LIVE_EVALUATION_MANIFEST: string = 'comic_translation_live_eval_manifest.json'
const LIVE_EVALUATION_SCHEMA_VERSION: number = 1
const LIVE_EVALUATION_EXPECTED_PAGES: number = 2
const LIVE_EVALUATION_TEMP_PREFIX: string = 'comic_translation_live_eval_'

class RawLiveEvaluationBlock {
  sourceVariants: string[] = []
  requiredTranslationTerms: string[] = []
}

class RawLiveEvaluationPage {
  pageIndex: number = -1
  rawFile: string = ''
  sha256: string = ''
  mimeType: string = ''
  width: number = 0
  height: number = 0
  blocks: RawLiveEvaluationBlock[] = []
}

class RawLiveEvaluationManifest {
  schemaVersion: number = 0
  fixtureSetId: string = ''
  projectId: string = ''
  sourceLanguage: string = ''
  targetLanguage: string = ''
  provenance: string = ''
  pages: RawLiveEvaluationPage[] = []
}

export class ComicTranslationLiveEvaluationPageReport {
  pageIndex: number = -1
  imageHash: string = ''
  imageBytes: number = 0
  elapsedMs: number = 0
  structuredOutputValid: boolean = false
  accuracyPassed: boolean = false
  expectedBlocks: number = 0
  actualBlocks: number = 0
  matchedSourceBlocks: number = 0
  missingSourceBlocks: number = 0
  unexpectedSourceBlocks: number = 0
  readingOrderErrors: number = 0
  requiredTranslationTermErrors: number = 0
  translatedBlocks: number = 0
  warningSignals: number = 0
  errorCode: string = ''
}

export class ComicTranslationLiveEvaluationReport {
  fixtureSetId: string = ''
  providerId: string = ''
  modelId: string = ''
  startedAtMs: number = 0
  finishedAtMs: number = 0
  totalImageBytes: number = 0
  pages: ComicTranslationLiveEvaluationPageReport[] = []
  errorCode: string = ''

  elapsedMs(): number {
    return Math.max(0, this.finishedAtMs - this.startedAtMs)
  }

  completedPages(): number {
    let count: number = 0
    for (let index: number = 0; index < this.pages.length; index++) {
      if (this.pages[index].structuredOutputValid) {
        count++
      }
    }
    return count
  }

  matchedBlocks(): number {
    let count: number = 0
    for (let index: number = 0; index < this.pages.length; index++) {
      count = count + this.pages[index].matchedSourceBlocks
    }
    return count
  }

  expectedBlocks(): number {
    let count: number = 0
    for (let index: number = 0; index < this.pages.length; index++) {
      count = count + this.pages[index].expectedBlocks
    }
    return count
  }

  passed(): boolean {
    if (this.errorCode.length > 0 || this.pages.length !== LIVE_EVALUATION_EXPECTED_PAGES) {
      return false
    }
    for (let index: number = 0; index < this.pages.length; index++) {
      if (!this.pages[index].structuredOutputValid || !this.pages[index].accuracyPassed) {
        return false
      }
    }
    return true
  }
}

/** Explicit, user-confirmed provider evaluation against bundled original pages. */
export class ComicTranslationLiveEvaluationService {
  private static running: boolean = false

  static isRunning(): boolean {
    return ComicTranslationLiveEvaluationService.running
  }

  static async run(context: common.UIAbilityContext): Promise<ComicTranslationLiveEvaluationReport> {
    if (ComicTranslationLiveEvaluationService.running) {
      throw new Error('Comic provider evaluation is already running')
    }
    ComicTranslationLiveEvaluationService.running = true
    const report: ComicTranslationLiveEvaluationReport = new ComicTranslationLiveEvaluationReport()
    report.startedAtMs = Date.now()
    try {
      const analyzer: ComicPageAnalyzer = ComicPageAnalyzerFactory.create(context)
      report.providerId = analyzer.providerId()
      report.modelId = analyzer.modelId()
      const manifest: RawLiveEvaluationManifest =
        await ComicTranslationLiveEvaluationService.loadManifest(context)
      report.fixtureSetId = manifest.fixtureSetId
      let previous: ComicPreviousPageContext | null = null
      for (let index: number = 0; index < manifest.pages.length; index++) {
        const rawPage: RawLiveEvaluationPage = manifest.pages[index]
        const pageReport: ComicTranslationLiveEvaluationPageReport =
          new ComicTranslationLiveEvaluationPageReport()
        pageReport.pageIndex = rawPage.pageIndex
        pageReport.imageHash = rawPage.sha256
        report.pages.push(pageReport)
        const bytes: Uint8Array = await context.resourceManager.getRawFileContent(rawPage.rawFile)
        pageReport.imageBytes = bytes.byteLength
        report.totalImageBytes = report.totalImageBytes + bytes.byteLength
        if (ComicTranslationLiveEvaluationService.sha256(bytes) !== rawPage.sha256) {
          pageReport.errorCode = 'fixture_hash_mismatch'
          report.errorCode = pageReport.errorCode
          break
        }
        const tempPath: string = ComicTranslationLiveEvaluationService.writeTempPage(
          context,
          rawPage,
          bytes,
        )
        const pageStartedAt: number = Date.now()
        try {
          const request: ComicPageAnalysisRequest = ComicTranslationLiveEvaluationService.request(
            manifest,
            rawPage,
            tempPath,
            previous,
          )
          const result: ComicPageAnalysisResult = await analyzer.analyze(request)
          const reference: ComicTranslationReferencePage =
            ComicTranslationLiveEvaluationService.reference(manifest, rawPage)
          const accuracy: ComicTranslationAccuracySnapshot =
            ComicTranslationEvaluator.accuracy(result.document, reference)
          const structural: ComicTranslationEvaluationSnapshot =
            ComicTranslationEvaluator.snapshot(result.document)
          ComicTranslationLiveEvaluationService.applyAccuracy(pageReport, accuracy, structural)
          if (!accuracy.passed()) {
            DiagnosticLogger.warn(
              'comic-translation',
              'live_evaluation_accuracy_failed',
              `page=${rawPage.pageIndex} matched=${accuracy.matchedSourceBlocks}/${accuracy.expectedBlocks} ` +
                `actual=${accuracy.actualBlocks} missing=${accuracy.missingSourceBlocks} ` +
                `unexpected=${accuracy.unexpectedSourceBlocks} order=${accuracy.readingOrderErrors} ` +
                `term=${accuracy.requiredTranslationTermErrors} ` +
                `issues=${ComicTranslationLiveEvaluationService.accuracyIssueSummary(accuracy)}`,
            )
          }
          previous = ComicTranslationLiveEvaluationService.previousContext(result.document)
        } catch (error) {
          pageReport.errorCode = ComicTranslationLiveEvaluationService.classifyError(error as Error)
          report.errorCode = pageReport.errorCode
        } finally {
          pageReport.elapsedMs = Math.max(0, Date.now() - pageStartedAt)
          ComicTranslationLiveEvaluationService.deleteTempPage(tempPath)
        }
        if (pageReport.errorCode.length > 0) {
          break
        }
      }
    } catch (error) {
      report.errorCode = ComicTranslationLiveEvaluationService.classifyError(error as Error)
    } finally {
      report.finishedAtMs = Date.now()
      ComicTranslationLiveEvaluationService.running = false
      DiagnosticLogger.info(
        'comic-translation',
        'live_evaluation_finished',
        `provider=${report.providerId} model=${report.modelId} ` +
          `pages=${report.completedPages()}/${LIVE_EVALUATION_EXPECTED_PAGES} ` +
          `matched=${report.matchedBlocks()}/${report.expectedBlocks()} ` +
          `bytes=${report.totalImageBytes} elapsedMs=${report.elapsedMs()} ` +
          `outcome=${report.passed() ? 'passed' : report.errorCode || 'accuracy_failed'}`,
      )
    }
    return report
  }

  private static async loadManifest(
    context: common.UIAbilityContext,
  ): Promise<RawLiveEvaluationManifest> {
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent(LIVE_EVALUATION_MANIFEST)
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
    const manifest: RawLiveEvaluationManifest =
      JSON.parse(decoder.decodeToString(bytes)) as RawLiveEvaluationManifest
    if (manifest.schemaVersion !== LIVE_EVALUATION_SCHEMA_VERSION ||
      manifest.fixtureSetId.trim().length === 0 || manifest.projectId.trim().length === 0 ||
      manifest.sourceLanguage.trim().length === 0 || manifest.targetLanguage.trim().length === 0 ||
      !Array.isArray(manifest.pages) || manifest.pages.length !== LIVE_EVALUATION_EXPECTED_PAGES) {
      throw new Error('Comic live evaluation manifest is invalid')
    }
    for (let index: number = 0; index < manifest.pages.length; index++) {
      ComicTranslationLiveEvaluationService.validatePage(manifest.pages[index], index)
    }
    return manifest
  }

  private static validatePage(rawPage: RawLiveEvaluationPage, expectedIndex: number): void {
    if (rawPage.pageIndex !== expectedIndex || rawPage.rawFile.indexOf('/') >= 0 ||
      !rawPage.rawFile.startsWith(LIVE_EVALUATION_TEMP_PREFIX) ||
      !rawPage.rawFile.endsWith('.jpg') || !/^[a-f0-9]{64}$/.test(rawPage.sha256) ||
      rawPage.mimeType !== 'image/jpeg' || rawPage.width <= 0 || rawPage.height <= 0 ||
      !Array.isArray(rawPage.blocks) || rawPage.blocks.length === 0) {
      throw new Error('Comic live evaluation page manifest is invalid')
    }
    for (let index: number = 0; index < rawPage.blocks.length; index++) {
      const block: RawLiveEvaluationBlock = rawPage.blocks[index]
      if (!Array.isArray(block.sourceVariants) || block.sourceVariants.length === 0 ||
        !Array.isArray(block.requiredTranslationTerms)) {
        throw new Error('Comic live evaluation block manifest is invalid')
      }
    }
  }

  private static request(
    manifest: RawLiveEvaluationManifest,
    rawPage: RawLiveEvaluationPage,
    imageFilePath: string,
    previous: ComicPreviousPageContext | null,
  ): ComicPageAnalysisRequest {
    const profile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
    profile.profileId = 'live-eval-original-jpeg-v1'
    profile.mimeType = rawPage.mimeType
    profile.preparedWidth = rawPage.width
    profile.preparedHeight = rawPage.height
    profile.tileCount = 1

    const term: ComicGlossaryTerm = new ComicGlossaryTerm()
    term.sourceTerm = '優'
    term.targetTerm = '优'
    term.status = ComicGlossaryTermStatus.LOCKED
    term.provenance = ComicGlossaryTermProvenance.USER
    term.firstSeenPageIndex = 0
    term.updatedRevision = 1

    const analysisContext: ComicPageAnalysisContext = new ComicPageAnalysisContext()
    analysisContext.sourceLanguage = manifest.sourceLanguage
    analysisContext.targetLanguage = manifest.targetLanguage
    analysisContext.styleGuide = 'Use concise natural Chinese and keep names consistent across pages.'
    analysisContext.glossaryRevision = 1
    analysisContext.styleGuideRevision = 1
    analysisContext.contextRevision = previous === null ? 1 : 2
    analysisContext.glossary.push(term)
    if (previous !== null) {
      analysisContext.previousPages.push(previous.copy())
      analysisContext.rollingSummary = previous.pageSummary
    }

    const request: ComicPageAnalysisRequest = new ComicPageAnalysisRequest()
    request.projectId = manifest.projectId
    request.pageIndex = rawPage.pageIndex
    request.imageFilePath = imageFilePath
    request.imageHash = rawPage.sha256
    request.sourceWidth = rawPage.width
    request.sourceHeight = rawPage.height
    request.requestedAnalysisRevision = 1
    request.requestedTranslationRevision = 1
    request.imagePreparationProfile = profile
    request.context = analysisContext
    return request
  }

  private static reference(
    manifest: RawLiveEvaluationManifest,
    rawPage: RawLiveEvaluationPage,
  ): ComicTranslationReferencePage {
    const reference: ComicTranslationReferencePage = new ComicTranslationReferencePage()
    reference.projectId = manifest.projectId
    reference.pageIndex = rawPage.pageIndex
    reference.imageHash = rawPage.sha256
    for (let index: number = 0; index < rawPage.blocks.length; index++) {
      const rawBlock: RawLiveEvaluationBlock = rawPage.blocks[index]
      const block: ComicTranslationReferenceBlock = new ComicTranslationReferenceBlock()
      for (let variantIndex: number = 0; variantIndex < rawBlock.sourceVariants.length; variantIndex++) {
        block.sourceVariants.push(rawBlock.sourceVariants[variantIndex])
      }
      for (let termIndex: number = 0;
        termIndex < rawBlock.requiredTranslationTerms.length;
        termIndex++) {
        block.requiredTranslationTerms.push(rawBlock.requiredTranslationTerms[termIndex])
      }
      reference.blocks.push(block)
    }
    return reference
  }

  private static applyAccuracy(
    report: ComicTranslationLiveEvaluationPageReport,
    accuracy: ComicTranslationAccuracySnapshot,
    structural: ComicTranslationEvaluationSnapshot,
  ): void {
    report.structuredOutputValid = true
    report.accuracyPassed = accuracy.passed()
    report.expectedBlocks = accuracy.expectedBlocks
    report.actualBlocks = accuracy.actualBlocks
    report.matchedSourceBlocks = accuracy.matchedSourceBlocks
    report.missingSourceBlocks = accuracy.missingSourceBlocks
    report.unexpectedSourceBlocks = accuracy.unexpectedSourceBlocks
    report.readingOrderErrors = accuracy.readingOrderErrors
    report.requiredTranslationTermErrors = accuracy.requiredTranslationTermErrors
    report.translatedBlocks = structural.translatedBlocks
    report.warningSignals = structural.warningSignals
  }

  private static accuracyIssueSummary(accuracy: ComicTranslationAccuracySnapshot): string {
    const items: string[] = []
    for (let index: number = 0; index < accuracy.issues.length; index++) {
      const issue = accuracy.issues[index]
      items.push(`${issue.code}@r${issue.referenceIndex}:d${issue.documentIndex}`)
    }
    return items.join(',')
  }

  private static previousContext(document: ComicPageDocument): ComicPreviousPageContext {
    const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
    previous.pageIndex = document.pageIndex
    const source: string[] = []
    const translated: string[] = []
    for (let index: number = 0; index < document.blocks.length; index++) {
      if (document.blocks[index].sourceText.trim().length > 0) {
        source.push(document.blocks[index].sourceText.trim())
      }
      if (document.blocks[index].translatedText.trim().length > 0) {
        translated.push(document.blocks[index].translatedText.trim())
      }
    }
    previous.sourceText = source.join('\n')
    previous.translatedText = translated.join('\n')
    previous.pageSummary = document.pageSummary
    return previous
  }

  private static writeTempPage(
    context: common.UIAbilityContext,
    rawPage: RawLiveEvaluationPage,
    bytes: Uint8Array,
  ): string {
    const path: string = `${context.cacheDir}/${LIVE_EVALUATION_TEMP_PREFIX}${rawPage.pageIndex}.jpg`
    let file: fileIo.File | null = null
    let completed: boolean = false
    try {
      file = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      const written: number = fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
      if (written !== bytes.byteLength) {
        throw new Error('Comic live evaluation fixture write was incomplete')
      }
      completed = true
      return path
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
      if (!completed) {
        ComicTranslationLiveEvaluationService.deleteTempPage(path)
      }
    }
  }

  private static deleteTempPage(path: string): void {
    if (!path.includes('/' + LIVE_EVALUATION_TEMP_PREFIX) || !path.endsWith('.jpg')) {
      return
    }
    try {
      fileIo.unlinkSync(path)
    } catch (_error) {
    }
  }

  private static sha256(bytes: Uint8Array): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: bytes })
    const digest: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < digest.length; index++) {
      parts.push(digest[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }

  static classifyError(error: Error): string {
    if (error instanceof ComicProviderHttpError) {
      if (error.detailCode.length > 0) {
        return `http_${error.statusCode}_${error.detailCode}`
      }
      return `http_${error.statusCode}`
    }
    const message: string = error.message.toLowerCase()
    if (message.includes('project identity mismatch')) {
      return 'output_identity_project'
    }
    if (message.includes('page identity mismatch')) {
      return 'output_identity_page'
    }
    if (message.includes('image identity mismatch')) {
      return 'output_identity_image'
    }
    if (message.includes('image width mismatch') || message.includes('image height mismatch')) {
      return 'output_identity_dimensions'
    }
    if (message.includes('hastext')) {
      return 'output_has_text_invalid'
    }
    if (message.includes('reading order')) {
      return 'output_reading_order_invalid'
    }
    if (message.includes('quality signal')) {
      return 'output_quality_signal_invalid'
    }
    if (message.includes('block')) {
      return 'output_block_invalid'
    }
    if (message.includes('polygon')) {
      return 'output_geometry_invalid'
    }
    if (message.includes('source origin') || message.includes('translation origin')) {
      return 'output_origin_invalid'
    }
    if (message.includes('payload size')) {
      return 'output_payload_size_invalid'
    }
    if (message.includes('stream failed')) {
      return 'provider_stream_failed'
    }
    if (message.includes('timeout') || message.includes('network') || message.includes('dns') ||
      message.includes('socket') || message.includes('connection') || message.includes('certificate')) {
      return 'provider_transport_failed'
    }
    if (message.includes('credential') || message.includes('api key') ||
      message.includes('model') || message.includes('base url')) {
      return 'provider_configuration'
    }
    if (message.includes('manifest') || message.includes('fixture') || message.includes('rawfile')) {
      return 'fixture_invalid'
    }
    if (message.includes('response') || message.includes('schema') ||
      message.includes('document') || message.includes('json')) {
      return 'structured_output_invalid'
    }
    return 'provider_request_failed'
  }
}

import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { DiagnosticsRedactor } from '../diagnostics/DiagnosticsRedactor'
import {
  COMIC_VISUAL_ROUTE_TORII,
  ComicVisualProviderSettings,
  ComicVisualProviderSettingsSnapshot,
} from '../settings/ComicVisualProviderSettings'
import { ComicTranslationErrorClassifier } from './ComicTranslationErrorClassifier'
import {
  ComicTranslationReaderPageInput,
  ComicTranslationRuntimeService,
} from './ComicTranslationRuntimeService'
import { ComicVisualTranslationRunResult } from './ComicVisualTranslationOrchestrator'

const LIVE_EVALUATION_MANIFEST: string = 'comic_translation_live_eval_manifest.json'
const LIVE_EVALUATION_SCHEMA_VERSION: number = 1
const LIVE_EVALUATION_EXPECTED_PAGES: number = 2
const LIVE_EVALUATION_TEMP_PREFIX: string = 'comic_translation_torii_live_eval_'

class RawToriiLiveEvaluationPage {
  pageIndex: number = -1
  rawFile: string = ''
  sha256: string = ''
  mimeType: string = ''
  width: number = 0
  height: number = 0
}

class RawToriiLiveEvaluationManifest {
  schemaVersion: number = 0
  fixtureSetId: string = ''
  projectId: string = ''
  sourceLanguage: string = ''
  targetLanguage: string = ''
  pages: RawToriiLiveEvaluationPage[] = []
}

export class ToriiWholePageLiveEvaluationPageReport {
  pageIndex: number = -1
  sourceRawFile: string = ''
  sourceHash: string = ''
  sourceBytes: number = 0
  artifactHash: string = ''
  artifactBytes: number = 0
  artifactPath: string = ''
  width: number = 0
  height: number = 0
  elapsedMs: number = 0
  errorCode: string = ''
  errorDetail: string = ''

  completed(): boolean {
    return this.errorCode.length === 0 && /^[a-f0-9]{64}$/.test(this.artifactHash) &&
      this.artifactBytes > 0 && this.artifactPath.length > 0 &&
      this.width > 0 && this.height > 0
  }
}

export class ToriiWholePageLiveEvaluationReport {
  fixtureSetId: string = ''
  providerId: string = 'torii-whole-page'
  modelId: string = ''
  startedAtMs: number = 0
  finishedAtMs: number = 0
  totalSourceBytes: number = 0
  totalArtifactBytes: number = 0
  pages: ToriiWholePageLiveEvaluationPageReport[] = []
  errorCode: string = ''
  errorDetail: string = ''
  failedPageIndex: number = -1

  elapsedMs(): number {
    return Math.max(0, this.finishedAtMs - this.startedAtMs)
  }

  completedPages(): number {
    let count: number = 0
    for (let index: number = 0; index < this.pages.length; index++) {
      if (this.pages[index].completed()) {
        count++
      }
    }
    return count
  }

  passed(): boolean {
    return this.errorCode.length === 0 &&
      this.pages.length === LIVE_EVALUATION_EXPECTED_PAGES &&
      this.completedPages() === LIVE_EVALUATION_EXPECTED_PAGES
  }
}

/** Explicit Torii whole-page evaluation against bundled original pages. */
export class ToriiWholePageLiveEvaluationService {
  private static running: boolean = false

  static isRunning(): boolean {
    return ToriiWholePageLiveEvaluationService.running
  }

  static async run(
    context: common.UIAbilityContext,
  ): Promise<ToriiWholePageLiveEvaluationReport> {
    if (ToriiWholePageLiveEvaluationService.running) {
      throw new Error('Torii whole-page evaluation is already running')
    }
    ToriiWholePageLiveEvaluationService.running = true
    const report: ToriiWholePageLiveEvaluationReport =
      new ToriiWholePageLiveEvaluationReport()
    report.startedAtMs = Date.now()
    try {
      const settings: ComicVisualProviderSettingsSnapshot =
        await ComicVisualProviderSettings.load(context)
      if (settings.route !== COMIC_VISUAL_ROUTE_TORII) {
        throw new Error('Torii whole-page route is not selected')
      }
      report.modelId = settings.toriiModelId
      const manifest: RawToriiLiveEvaluationManifest =
        await ToriiWholePageLiveEvaluationService.loadManifest(context)
      report.fixtureSetId = manifest.fixtureSetId
      for (let index: number = 0; index < manifest.pages.length; index++) {
        const rawPage: RawToriiLiveEvaluationPage = manifest.pages[index]
        const pageReport: ToriiWholePageLiveEvaluationPageReport =
          new ToriiWholePageLiveEvaluationPageReport()
        pageReport.pageIndex = rawPage.pageIndex
        pageReport.sourceRawFile = rawPage.rawFile
        pageReport.sourceHash = rawPage.sha256
        report.pages.push(pageReport)
        const bytes: Uint8Array = await context.resourceManager.getRawFileContent(
          rawPage.rawFile,
        )
        pageReport.sourceBytes = bytes.byteLength
        report.totalSourceBytes += bytes.byteLength
        if (ToriiWholePageLiveEvaluationService.sha256(bytes) !== rawPage.sha256) {
          pageReport.errorCode = 'fixture_hash_mismatch'
          report.errorCode = pageReport.errorCode
          break
        }
        const tempPath: string = ToriiWholePageLiveEvaluationService.writeTempPage(
          context,
          rawPage,
          bytes,
          report.startedAtMs,
        )
        const pageStartedAt: number = Date.now()
        try {
          const input: ComicTranslationReaderPageInput =
            new ComicTranslationReaderPageInput()
          input.projectId = manifest.projectId
          input.pageIndex = rawPage.pageIndex
          input.imageFilePath = tempPath
          input.imageWidth = rawPage.width
          input.imageHeight = rawPage.height
          input.sourceLanguage = manifest.sourceLanguage
          input.targetLanguage = manifest.targetLanguage
          const result: ComicVisualTranslationRunResult =
            await ComicTranslationRuntimeService.runReaderPage(context, input)
          pageReport.artifactHash = result.renderedPage.artifactHash
          pageReport.artifactBytes = result.renderedPage.byteLength
          pageReport.artifactPath = result.renderedPage.localFilePath
          pageReport.width = result.renderedPage.width
          pageReport.height = result.renderedPage.height
          report.totalArtifactBytes += result.renderedPage.byteLength
          DiagnosticLogger.info(
            'comic-translation',
            'torii_live_page_ready',
            `page=${rawPage.pageIndex} model=${report.modelId} ` +
              `source=${rawPage.sha256.substring(0, 12)} ` +
              `artifact=${result.renderedPage.artifactHash.substring(0, 12)} ` +
              `bytes=${result.renderedPage.byteLength}`,
          )
        } catch (error) {
          const failure: Error = error as Error
          pageReport.errorCode = ToriiWholePageLiveEvaluationService.classifyError(
            failure,
          )
          pageReport.errorDetail = DiagnosticsRedactor.sanitizeString(failure.message)
          report.errorCode = pageReport.errorCode
          report.errorDetail = pageReport.errorDetail
          report.failedPageIndex = rawPage.pageIndex
          DiagnosticLogger.warn(
            'comic-translation',
            'torii_live_page_failed',
            `page=${rawPage.pageIndex} code=${pageReport.errorCode} ` +
              `elapsedMs=${Math.max(0, Date.now() - pageStartedAt)} ` +
              `error=${failure.message}`,
          )
        } finally {
          pageReport.elapsedMs = Math.max(0, Date.now() - pageStartedAt)
          ToriiWholePageLiveEvaluationService.deleteTempPage(tempPath)
        }
        if (pageReport.errorCode.length > 0) {
          break
        }
      }
    } catch (error) {
      const failure: Error = error as Error
      report.errorCode = ToriiWholePageLiveEvaluationService.classifyError(failure)
      report.errorDetail = DiagnosticsRedactor.sanitizeString(failure.message)
      DiagnosticLogger.warn(
        'comic-translation',
        'torii_live_setup_failed',
        `code=${report.errorCode} error=${failure.message}`,
      )
    } finally {
      report.finishedAtMs = Date.now()
      ToriiWholePageLiveEvaluationService.running = false
      DiagnosticLogger.info(
        'comic-translation',
        'torii_live_evaluation_finished',
        `provider=${report.providerId} model=${report.modelId} ` +
          `pages=${report.completedPages()}/${LIVE_EVALUATION_EXPECTED_PAGES} ` +
          `sourceBytes=${report.totalSourceBytes} artifactBytes=${report.totalArtifactBytes} ` +
          `elapsedMs=${report.elapsedMs()} ` +
          `outcome=${report.passed() ? 'passed' : report.errorCode || 'failed'}`,
      )
    }
    return report
  }

  private static async loadManifest(
    context: common.UIAbilityContext,
  ): Promise<RawToriiLiveEvaluationManifest> {
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent(
      LIVE_EVALUATION_MANIFEST,
    )
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
    const manifest: RawToriiLiveEvaluationManifest =
      JSON.parse(decoder.decodeToString(bytes)) as RawToriiLiveEvaluationManifest
    if (manifest.schemaVersion !== LIVE_EVALUATION_SCHEMA_VERSION ||
      manifest.fixtureSetId.trim().length === 0 || manifest.projectId.trim().length === 0 ||
      manifest.sourceLanguage.trim().length === 0 ||
      manifest.targetLanguage.trim().length === 0 ||
      !Array.isArray(manifest.pages) ||
      manifest.pages.length !== LIVE_EVALUATION_EXPECTED_PAGES) {
      throw new Error('Torii live evaluation manifest is invalid')
    }
    for (let index: number = 0; index < manifest.pages.length; index++) {
      ToriiWholePageLiveEvaluationService.validatePage(manifest.pages[index], index)
    }
    return manifest
  }

  private static validatePage(
    rawPage: RawToriiLiveEvaluationPage,
    expectedIndex: number,
  ): void {
    if (rawPage.pageIndex !== expectedIndex || rawPage.rawFile.indexOf('/') >= 0 ||
      !rawPage.rawFile.startsWith('comic_translation_live_eval_page_') ||
      !rawPage.rawFile.endsWith('.jpg') || !/^[a-f0-9]{64}$/.test(rawPage.sha256) ||
      rawPage.mimeType !== 'image/jpeg' || rawPage.width <= 0 || rawPage.height <= 0) {
      throw new Error('Torii live evaluation page manifest is invalid')
    }
  }

  private static writeTempPage(
    context: common.UIAbilityContext,
    rawPage: RawToriiLiveEvaluationPage,
    bytes: Uint8Array,
    runId: number,
  ): string {
    const path: string = `${context.cacheDir}/${LIVE_EVALUATION_TEMP_PREFIX}${runId}_${rawPage.pageIndex}.jpg`
    let file: fileIo.File | null = null
    let completed: boolean = false
    try {
      file = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      const written: number = fileIo.writeSync(
        file.fd,
        bytes.buffer,
        { length: bytes.byteLength },
      )
      if (written !== bytes.byteLength) {
        throw new Error('Torii live evaluation fixture write was incomplete')
      }
      completed = true
      return path
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
      if (!completed) {
        ToriiWholePageLiveEvaluationService.deleteTempPage(path)
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

  private static classifyError(error: Error): string {
    return ComicTranslationErrorClassifier.classify(error)
  }
}

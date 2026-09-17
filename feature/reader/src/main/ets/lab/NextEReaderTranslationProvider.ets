import { common } from '@kit.AbilityKit'
import {
  ReaderAsset, ReaderAssetKind, ReaderAssetProvider, ReaderCancellation, ReaderImageInformation,
  ReaderOriginalAssetPlan, ReaderPage,
  ReaderProcessedAssetVariant, ReaderVariantAssetPlan,
} from '@reader-kit/core'
import { ReaderFileInformation } from '@reader-kit/ui'
import {
  ComicTranslationErrorClassifier, ComicTranslationReaderPageInput, ComicTranslationRuntimeService,
  ComicVisualTranslationRunResult,
} from 'shared'
import { NextEReaderCropSource } from './NextEReaderCropSource'
import { connectNextEReaderTranslationProbe } from './NextEReaderTranslationProbe'

export class NextEReaderTranslationConfiguration {
  enabled: boolean
  projectId: string
  targetLanguage: string
  sourceLanguage: string
  settingsRevision: number

  constructor(enabled: boolean, projectId: string, targetLanguage: string, sourceLanguage: string,
    settingsRevision: number) {
    this.enabled = enabled
    this.projectId = projectId
    this.targetLanguage = targetLanguage
    this.sourceLanguage = sourceLanguage
    this.settingsRevision = settingsRevision
  }

  identity(): string {
    if (!this.enabled || this.projectId.length === 0 || this.targetLanguage.length === 0 ||
      this.sourceLanguage.length === 0 || !Number.isSafeInteger(this.settingsRevision) || this.settingsRevision < 0) return ''
    return JSON.stringify([this.targetLanguage, this.sourceLanguage, this.settingsRevision])
  }

  resultMatches(page: ReaderPage, result: ComicVisualTranslationRunResult): boolean {
    const value = result.renderedPage.identity
    return value.projectId === this.projectId && value.pageIndex === page.sourceIndex &&
      value.targetLanguage === this.targetLanguage
  }
}

class NextEReaderTranslationPlan implements ReaderVariantAssetPlan {
  page: ReaderPage
  variant: ReaderProcessedAssetVariant = 'translated'
  identity: string
  private path: string
  private originalAvailable: boolean
  private cropStrength: () => string

  constructor(page: ReaderPage, identity: string, path: string, originalAvailable: boolean,
    cropStrength: () => string = (): string => '') {
    this.page = page.copy()
    this.identity = identity
    this.path = path
    this.originalAvailable = originalAvailable
    this.cropStrength = cropStrength
  }

  async load(cancellation: ReaderCancellation, _forceReload: boolean): Promise<ReaderAsset> {
    cancellation.check()
    const facts = new ReaderImageInformation()
    facts.variant = 'translated'
    facts.originalAvailable = this.originalAvailable
    const asset = new ReaderAsset(`file://${this.path}`, () => {}, new ReaderFileInformation(this.path, facts))
    asset.crop = new NextEReaderCropSource(this.path, 'reader-shared-translation', this.cropStrength)
    asset.originalAvailable = this.originalAvailable
    return asset
  }
}

/** NextE owns translation identity, runtime invocation and generated-file lifetime. */
export class NextEReaderTranslationProvider implements ReaderAssetProvider {
  cancellationMode: 'consumer-only' | 'transport'
  informationSupported: boolean
  prepareOriginal?: (page: ReaderPage, cancellation: ReaderCancellation) => Promise<ReaderOriginalAssetPlan>
  private provider: ReaderAssetProvider
  private context: common.UIAbilityContext
  private configuration: (page: ReaderPage) => NextEReaderTranslationConfiguration
  private sourcePaths: Map<string, string> = new Map<string, string>()
  private failureCodes: Map<number, string> = new Map<number, string>()
  private cropStrength: () => string

  constructor(context: common.UIAbilityContext, provider: ReaderAssetProvider,
    configuration: (page: ReaderPage) => NextEReaderTranslationConfiguration,
    cropStrength: () => string = (): string => '') {
    this.context = context
    this.provider = provider
    this.configuration = configuration
    this.cropStrength = cropStrength
    this.cancellationMode = provider.cancellationMode
    this.informationSupported = provider.informationSupported === true
    if (provider.prepareOriginal !== undefined) {
      this.prepareOriginal = (page: ReaderPage, cancellation: ReaderCancellation): Promise<ReaderOriginalAssetPlan> => {
        cancellation.check()
        if (this.provider.prepareOriginal === undefined) throw new Error('reader_original_unavailable')
        return this.provider.prepareOriginal(page, cancellation)
      }
    }
  }

  async load(page: ReaderPage, kind: ReaderAssetKind, cancellation: ReaderCancellation,
    forceReload: boolean): Promise<ReaderAsset> {
    const asset = await this.provider.load(page, kind, cancellation, forceReload)
    if (kind === 'original') {
      const path = NextEReaderTranslationProvider.localPath(asset.uri)
      if (path.length > 0) this.sourcePaths.set(this.pageIdentity(page), path)
      else this.sourcePaths.delete(this.pageIdentity(page))
    }
    return asset
  }

  async prepareVariant(page: ReaderPage, variant: ReaderProcessedAssetVariant, identity: string,
    cancellation: ReaderCancellation): Promise<ReaderVariantAssetPlan> {
    if (variant !== 'translated') {
      if (this.provider.prepareVariant === undefined) throw new Error('reader_variant_unavailable')
      return this.provider.prepareVariant(page, variant, identity, cancellation)
    }
    cancellation.check()
    const configuration = this.configuration(page)
    if (configuration.identity().length === 0 || configuration.identity() !== identity) {
      throw new Error('reader_translation_configuration_unavailable')
    }
    const sourcePath = this.sourcePaths.get(this.pageIdentity(page)) ?? ''
    if (sourcePath.length === 0) throw new Error('reader_translation_source_unavailable')
    const probe = connectNextEReaderTranslationProbe()
    const work = page.unit.work
    const detach = cancellation.onCancel((): void => {
      probe.deliver(this.context, work, page.sourceIndex, 'cancelled', identity)
    })
    try {
      // Debug-only local seam: prove apply/failure/recovery without a configured production service.
      const probePath = probe.result(this.context, work)
      if (probePath.length > 0) {
        probe.deliver(this.context, work, page.sourceIndex, 'prepare', identity)
        await probe.pauseBeforeResult(this.context, work, page.sourceIndex, cancellation)
        cancellation.check()
        if (probe.unavailable(this.context, work, page.sourceIndex)) {
          this.failureCodes.set(page.sourceIndex, 'local_visual_unavailable')
          throw new Error('reader_translation_probe_unavailable')
        }
        this.failureCodes.delete(page.sourceIndex)
        probe.deliver(this.context, work, page.sourceIndex, 'applied', identity)
        return new NextEReaderTranslationPlan(page, identity, probePath,
          this.provider.prepareOriginal !== undefined, this.cropStrength)
      }
      const input = new ComicTranslationReaderPageInput()
      input.projectId = configuration.projectId
      input.pageIndex = page.sourceIndex
      input.imageFilePath = sourcePath
      input.imageWidth = page.width
      input.imageHeight = page.height
      input.sourceLanguage = configuration.sourceLanguage
      input.targetLanguage = configuration.targetLanguage
      let result: ComicVisualTranslationRunResult
      try {
        result = await ComicTranslationRuntimeService.runReaderPage(this.context, input)
      } catch (error) {
        this.failureCodes.set(page.sourceIndex, ComicTranslationErrorClassifier.classify(error as Error))
        throw error as Error
      }
      this.failureCodes.delete(page.sourceIndex)
      cancellation.check()
      if (this.configuration(page).identity() !== identity || !configuration.resultMatches(page, result) ||
        result.renderedPage.localFilePath.length === 0) throw new Error('reader_translation_result_stale')
      probe.deliver(this.context, work, page.sourceIndex, 'applied', identity)
      return new NextEReaderTranslationPlan(page, identity, result.renderedPage.localFilePath,
        this.provider.prepareOriginal !== undefined, this.cropStrength)
    } catch (error) {
      probe.deliver(this.context, work, page.sourceIndex, 'unavailable', identity)
      throw error as Error
    } finally {
      detach()
    }
  }

  /** Last classified translation failure for one source page; empty when none is recorded. */
  lastFailureCode(sourceIndex: number): string {
    return this.failureCodes.get(sourceIndex) ?? ''
  }

  private pageIdentity(page: ReaderPage): string {
    return JSON.stringify([page.unit.scope, page.unit.work, page.unit.unit, page.key, page.sourceIndex])
  }

  private static localPath(uri: string): string {
    return uri.startsWith('file://') ? uri.substring('file://'.length) : ''
  }
}

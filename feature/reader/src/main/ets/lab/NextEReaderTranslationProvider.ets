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
  private saveUri: string

  constructor(page: ReaderPage, identity: string, path: string, originalAvailable: boolean,
    cropStrength: () => string = (): string => '', saveUri: string = '') {
    this.page = page.copy()
    this.identity = identity
    this.path = path
    this.originalAvailable = originalAvailable
    this.cropStrength = cropStrength
    this.saveUri = saveUri
  }

  async load(cancellation: ReaderCancellation, _forceReload: boolean): Promise<ReaderAsset> {
    cancellation.check()
    const facts = new ReaderImageInformation()
    facts.variant = 'translated'
    facts.originalAvailable = this.originalAvailable
    const asset = new ReaderAsset(`file://${this.path}`, () => {}, new ReaderFileInformation(this.path, facts))
    asset.saveUri = this.saveUri
    asset.crop = new NextEReaderCropSource(this.path, 'reader-shared-translation', this.cropStrength)
    asset.originalAvailable = this.originalAvailable
    return asset
  }
}

class NextEReaderTranslationTask {
  cancellation: ReaderCancellation = new ReaderCancellation()
  runtimeStarted: boolean = false
  promise: Promise<ReaderVariantAssetPlan> | null = null
  private consumers: ReaderCancellation[] = []

  join(consumer: ReaderCancellation): () => void {
    this.consumers.push(consumer)
    return consumer.onCancel((): void => {
      // An already running provider may have consumed quota. Keep its result reusable;
      // each caller still checks its own cancellation before publishing anything.
      if (!this.runtimeStarted && this.consumers.every((value): boolean => value.isCancelled())) {
        this.cancellation.cancel()
      }
    })
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
  private sourceRevisions: Map<string, number> = new Map<string, number>()
  private failureCodes: Map<number, string> = new Map<number, string>()
  private cropStrength: () => string
  private saveUriForPage: (page: ReaderPage) => string
  private preloadSource: ((page: ReaderPage, cancellation: ReaderCancellation) => Promise<ReaderAsset>) | null
  private tasks: Map<string, NextEReaderTranslationTask> = new Map()
  private queue: Promise<void> = Promise.resolve()

  constructor(context: common.UIAbilityContext, provider: ReaderAssetProvider,
    configuration: (page: ReaderPage) => NextEReaderTranslationConfiguration,
    cropStrength: () => string = (): string => '',
    saveUriForPage: (page: ReaderPage) => string = (_page: ReaderPage): string => '',
    preloadSource: ((page: ReaderPage, cancellation: ReaderCancellation) => Promise<ReaderAsset>) | null = null) {
    this.context = context
    this.provider = provider
    this.configuration = configuration
    this.cropStrength = cropStrength
    this.saveUriForPage = saveUriForPage
    this.preloadSource = preloadSource
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
    forceReload: boolean, onProgress?: (loaded: number, total: number) => void): Promise<ReaderAsset> {
    const asset = await this.provider.load(page, kind, cancellation, forceReload, onProgress)
    if (kind === 'original') {
      const path = NextEReaderTranslationProvider.localPath(asset.uri)
      const key = this.pageIdentity(page)
      if (forceReload || this.sourcePaths.get(key) !== path) {
        this.sourceRevisions.set(key, (this.sourceRevisions.get(key) ?? 0) + 1)
      }
      if (path.length > 0 && asset.notice === null) this.sourcePaths.set(key, path)
      else this.sourcePaths.delete(key)
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
    if (this.configuration(page).identity().length === 0 || this.configuration(page).identity() !== identity) {
      throw new Error('reader_translation_configuration_unavailable')
    }
    let sourceAsset: ReaderAsset | null = null
    let sourceWidth = page.width
    let sourceHeight = page.height
    try {
      if (this.preloadSource !== null) {
        // Keep our own file lease through the serial model lane; a navigation may
        // release the visible asset while this native/provider task is still running.
        sourceAsset = await this.preloadSource(page, cancellation)
        cancellation.check()
        const path = NextEReaderTranslationProvider.localPath(sourceAsset.uri)
        if (sourceAsset.notice !== null || path.length === 0) throw new Error('reader_translation_source_unavailable')
        // Catalog dimensions can still be zero for an undisplayed page. Read only
        // the retained file header; no native presentation or full-image decode.
        if (sourceAsset.information !== null) {
          const facts = await sourceAsset.information.read()
          cancellation.check()
          sourceWidth = facts.width
          sourceHeight = facts.height
        }
        this.sourcePaths.set(this.pageIdentity(page), path)
      }
      const sourcePath = this.sourcePaths.get(this.pageIdentity(page)) ?? ''
      if (sourcePath.length === 0) throw new Error('reader_translation_source_unavailable')
      const key = JSON.stringify([this.pageIdentity(page), identity, sourcePath,
        this.sourceRevisions.get(this.pageIdentity(page)) ?? 0])
      let task = this.tasks.get(key)
      const created = task === undefined || task.cancellation.isCancelled()
      if (created) {
        task = new NextEReaderTranslationTask()
        this.tasks.set(key, task)
      }
      const owned = task!
      const detach = owned.join(cancellation)
      if (created) {
        owned.promise = this.queue.then((): Promise<ReaderVariantAssetPlan> =>
          this.translate(page, identity, sourcePath, owned, sourceWidth, sourceHeight))
        this.queue = owned.promise.then((): void => {}, (): void => {})
        const retire = (): void => { if (this.tasks.get(key) === owned) this.tasks.delete(key) }
        void owned.promise.then(retire, retire)
      }
      try {
        const plan = await owned.promise!
        cancellation.check()
        if (this.configuration(page).identity() !== identity) throw new Error('reader_translation_result_stale')
        return plan
      } finally {
        detach()
      }
    } finally {
      sourceAsset?.release()
    }
  }

  private async translate(page: ReaderPage, identity: string, sourcePath: string,
    task: NextEReaderTranslationTask, sourceWidth: number, sourceHeight: number): Promise<ReaderVariantAssetPlan> {
    const cancellation = task.cancellation
    cancellation.check()
    const configuration = this.configuration(page)
    if (configuration.identity().length === 0 || configuration.identity() !== identity) {
      throw new Error('reader_translation_configuration_unavailable')
    }
    if (sourcePath.length === 0) throw new Error('reader_translation_source_unavailable')
    const saveUri = this.saveUriForPage(page)
    if (saveUri.length === 0) throw new Error('reader_translation_save_source_unavailable')
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
          this.provider.prepareOriginal !== undefined, this.cropStrength, saveUri)
      }
      const input = new ComicTranslationReaderPageInput()
      input.projectId = configuration.projectId
      input.pageIndex = page.sourceIndex
      input.imageFilePath = sourcePath
      input.imageWidth = sourceWidth
      input.imageHeight = sourceHeight
      input.sourceLanguage = configuration.sourceLanguage
      input.targetLanguage = configuration.targetLanguage
      let result: ComicVisualTranslationRunResult
      try {
        cancellation.check()
        task.runtimeStarted = true
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
        this.provider.prepareOriginal !== undefined, this.cropStrength, saveUri)
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

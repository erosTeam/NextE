import { common } from '@kit.AbilityKit'
import {
  ReaderAsset, ReaderAssetKind, ReaderAssetProvider, ReaderCancellation, ReaderImageInformation,
  ReaderImageCropBounds, ReaderImageCropSource, ReaderOriginalAssetPlan, ReaderPage,
  ReaderProcessedAssetVariant, ReaderVariantAssetPlan,
} from '@reader-kit/core'
import { ReaderFileInformation } from '@reader-kit/ui'
import { ReaderPageCropService, ReaderSuperResolutionResult, readerSuperResolutionProcess,
  readerSuperResolutionReleaseOwner } from 'shared'

class NextEReaderVariantCropSource implements ReaderImageCropSource {
  private static sequence: number = 0
  private path: string
  private identity: string

  constructor(path: string) {
    this.path = path
    this.identity = `reader-shared-variant:${++NextEReaderVariantCropSource.sequence}`
  }

  async read(): Promise<ReaderImageCropBounds> {
    const bounds = await ReaderPageCropService.detect(this.path, this.identity)
    return new ReaderImageCropBounds(bounds.left, bounds.top, bounds.right, bounds.bottom)
  }
}

export class NextEReaderSuperResolutionConfiguration {
  enabled: boolean
  model: string
  backend: string
  maxSourceHeight: number

  constructor(enabled: boolean, model: string, backend: string, maxSourceHeight: number) {
    this.enabled = enabled
    this.model = model
    this.backend = backend
    this.maxSourceHeight = maxSourceHeight
  }

  identity(): string {
    return `nexte-super-resolution:${this.model}:${this.backend}:${this.maxSourceHeight}`
  }
}

class NextEReaderSuperResolutionPlan implements ReaderVariantAssetPlan {
  page: ReaderPage
  variant: ReaderProcessedAssetVariant = 'enhanced'
  identity: string
  private path: string
  private ownerKey: string
  private originalAvailable: boolean

  constructor(page: ReaderPage, identity: string, path: string, ownerKey: string, originalAvailable: boolean) {
    this.page = page.copy()
    this.identity = identity
    this.path = path
    this.ownerKey = ownerKey
    this.originalAvailable = originalAvailable
  }

  async load(cancellation: ReaderCancellation, _forceReload: boolean): Promise<ReaderAsset> {
    cancellation.check()
    const facts = new ReaderImageInformation()
    facts.variant = 'enhanced'
    facts.originalAvailable = this.originalAvailable
    const asset = new ReaderAsset(`file://${this.path}`,
      (): void => { readerSuperResolutionReleaseOwner(this.ownerKey) },
      new ReaderFileInformation(this.path, facts))
    asset.crop = new NextEReaderVariantCropSource(this.path)
    asset.originalAvailable = this.originalAvailable
    return asset
  }
}

/**
 * NextE owns enhancement configuration, source-file discovery and service lifetime.
 * reader-kit receives only an exact resolved plan for the currently displayed page.
 */
export class NextEReaderSuperResolutionProvider implements ReaderAssetProvider {
  private static sequence: number = 0
  cancellationMode: 'consumer-only' | 'transport'
  informationSupported: boolean
  prepareOriginal?: (page: ReaderPage, cancellation: ReaderCancellation) => Promise<ReaderOriginalAssetPlan>
  private provider: ReaderAssetProvider
  private context: common.UIAbilityContext
  private configuration: () => NextEReaderSuperResolutionConfiguration
  private sourcePaths: Map<string, string> = new Map<string, string>()
  private ownerPrefix: string

  constructor(context: common.UIAbilityContext, provider: ReaderAssetProvider,
    configuration: () => NextEReaderSuperResolutionConfiguration) {
    this.context = context
    this.provider = provider
    this.configuration = configuration
    this.cancellationMode = provider.cancellationMode
    this.informationSupported = provider.informationSupported === true
    this.ownerPrefix = `reader-shared:${++NextEReaderSuperResolutionProvider.sequence}`
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
      const path = NextEReaderSuperResolutionProvider.localPath(asset.uri)
      if (path.length > 0) this.sourcePaths.set(this.pageIdentity(page), path)
      else this.sourcePaths.delete(this.pageIdentity(page))
    }
    return asset
  }

  async prepareVariant(page: ReaderPage, variant: ReaderProcessedAssetVariant, identity: string,
    cancellation: ReaderCancellation): Promise<ReaderVariantAssetPlan> {
    cancellation.check()
    const configuration = this.configuration()
    if (variant !== 'enhanced' || !configuration.enabled || configuration.identity() !== identity) {
      throw new Error('reader_variant_unavailable')
    }
    const sourcePath = this.sourcePaths.get(this.pageIdentity(page)) ?? ''
    if (sourcePath.length === 0) throw new Error('reader_variant_source_unavailable')
    const sourceKey = `${page.unit.scope}:${page.unit.work}:${page.unit.unit}:${page.key}:${page.sourceIndex}`
    const ownerKey = `${this.ownerPrefix}:${page.unit.scope}:${page.unit.work}:${page.unit.unit}:${page.key}:${identity}`
    const detach = cancellation.onCancel((): void => {
      readerSuperResolutionReleaseOwner(ownerKey)
    })
    let retained: boolean = false
    try {
      const result: ReaderSuperResolutionResult = await readerSuperResolutionProcess(
        this.context, sourcePath, sourceKey, (_state): void => {}, ownerKey)
      cancellation.check()
      const current = this.configuration()
      if (!current.enabled || current.identity() !== identity || !result.applied) {
        throw new Error(`reader_variant_not_applied:${result.reason}`)
      }
      const path = result.filePath.length > 0
        ? result.filePath
        : NextEReaderSuperResolutionProvider.localPath(result.displayUri)
      if (path.length === 0) throw new Error('reader_variant_output_unavailable')
      retained = true
      return new NextEReaderSuperResolutionPlan(page, identity, path, ownerKey,
        this.provider.prepareOriginal !== undefined)
    } finally {
      detach()
      if (!retained) readerSuperResolutionReleaseOwner(ownerKey)
    }
  }

  private pageIdentity(page: ReaderPage): string {
    return JSON.stringify([page.unit.scope, page.unit.work, page.unit.unit, page.key, page.sourceIndex])
  }

  private static localPath(uri: string): string {
    return uri.startsWith('file://') ? uri.substring('file://'.length) : ''
  }
}

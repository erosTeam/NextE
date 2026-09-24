import { common } from '@kit.AbilityKit'
import { image } from '@kit.ImageKit'
import {
  ReaderAsset, ReaderAssetKind, ReaderAssetProvider, ReaderCancellation, ReaderImageInformation,
  ReaderOriginalAssetPlan, ReaderPage, ReaderUnitKey,
  ReaderProcessedAssetVariant, ReaderVariantAssetPlan,
} from '@reader-kit/core'
import { ReaderFileInformation } from '@reader-kit/ui'
import { ReaderSuperResolutionResult, readerSuperResolutionProcess, readerSuperResolutionReleaseOwner } from 'shared'
import { NextEReaderCropSource } from './NextEReaderCropSource'

export class NextEReaderSuperResolutionInformation {
  identity: string
  model: string
  applied: boolean
  reason: string

  constructor(identity: string, model: string, applied: boolean, reason: string) {
    this.identity = identity
    this.model = model
    this.applied = applied
    this.reason = reason
  }

  copy(): NextEReaderSuperResolutionInformation {
    return new NextEReaderSuperResolutionInformation(this.identity, this.model, this.applied, this.reason)
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

type NextEReaderSourceEligibility = 'pending' | 'applicable' | 'height-limit'

class NextEReaderEligibilityRecord {
  path: string
  maxHeight: number
  status: NextEReaderSourceEligibility

  constructor(path: string, maxHeight: number, status: NextEReaderSourceEligibility) {
    this.path = path
    this.maxHeight = maxHeight
    this.status = status
  }
}

class NextEReaderSuperResolutionPlan implements ReaderVariantAssetPlan {
  page: ReaderPage
  variant: ReaderProcessedAssetVariant = 'enhanced'
  identity: string
  private path: string
  private ownerKey: string
  private originalAvailable: boolean
  private cropStrength: () => string
  private saveUri: string

  constructor(page: ReaderPage, identity: string, path: string, ownerKey: string, originalAvailable: boolean,
    cropStrength: () => string = (): string => '', saveUri: string = '') {
    this.page = page.copy()
    this.identity = identity
    this.path = path
    this.ownerKey = ownerKey
    this.originalAvailable = originalAvailable
    this.cropStrength = cropStrength
    this.saveUri = saveUri
  }

  async load(cancellation: ReaderCancellation, _forceReload: boolean): Promise<ReaderAsset> {
    cancellation.check()
    const facts = new ReaderImageInformation()
    facts.variant = 'enhanced'
    facts.originalAvailable = this.originalAvailable
    const asset = new ReaderAsset(`file://${this.path}`,
      (): void => { readerSuperResolutionReleaseOwner(this.ownerKey) },
      new ReaderFileInformation(this.path, facts))
    asset.saveUri = this.saveUri
    asset.crop = new NextEReaderCropSource(this.path, 'reader-shared-variant', this.cropStrength)
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
  private saveUris: Map<string, string> = new Map<string, string>()
  private sourcePathsBySource: Map<string, string> = new Map<string, string>()
  private eligibilityBySource: Map<string, NextEReaderEligibilityRecord> =
    new Map<string, NextEReaderEligibilityRecord>()
  private informationByPage: Map<string, NextEReaderSuperResolutionInformation> =
    new Map<string, NextEReaderSuperResolutionInformation>()
  private ownerPrefix: string
  private cropStrength: () => string
  private saveUriForPage: (page: ReaderPage) => string
  private onEligibilityChanged: () => void

  constructor(context: common.UIAbilityContext, provider: ReaderAssetProvider,
    configuration: () => NextEReaderSuperResolutionConfiguration,
    cropStrength: () => string = (): string => '',
    saveUriForPage: (page: ReaderPage) => string = (_page: ReaderPage): string => '',
    onEligibilityChanged: () => void = (): void => {}) {
    this.context = context
    this.provider = provider
    this.configuration = configuration
    this.cropStrength = cropStrength
    this.saveUriForPage = saveUriForPage
    this.onEligibilityChanged = onEligibilityChanged
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
    forceReload: boolean, onProgress?: (loaded: number, total: number) => void): Promise<ReaderAsset> {
    const asset = await this.provider.load(page, kind, cancellation, forceReload, onProgress)
    if (kind === 'original') {
      const pageKey = this.pageIdentity(page)
      if (asset.saveUri.length > 0) this.saveUris.set(pageKey, asset.saveUri)
      else this.saveUris.delete(pageKey)
      const path = NextEReaderSuperResolutionProvider.localPath(asset.uri)
      const sourceKey = this.sourceIdentity(page.unit, page.sourceIndex)
      this.sourcePathsBySource.set(sourceKey, path)
      if (path.length > 0) this.sourcePaths.set(pageKey, path)
      else this.sourcePaths.delete(pageKey)
      if (path.length > 0) {
        if (this.configuration().enabled) {
          this.probeEligibility(page, path, this.configuration().maxSourceHeight)
        } else if (this.eligibilityBySource.get(sourceKey)?.path !== path) {
          this.eligibilityBySource.delete(sourceKey)
        }
      } else {
        // Missing local metadata must retain the processor's real source-unavailable report.
        this.eligibilityBySource.set(sourceKey,
          new NextEReaderEligibilityRecord(path, this.configuration().maxSourceHeight, 'applicable'))
        this.onEligibilityChanged()
      }
    }
    return asset
  }

  /** The processor's height limit is an inapplicable variant, not a failed image. */
  mayPrepare(unit: ReaderUnitKey, sourceIndex: number, maxHeight: number): boolean {
    const key = this.sourceIdentity(unit, sourceIndex)
    const record = this.eligibilityBySource.get(key)
    if (record === undefined) {
      const path = this.sourcePathsBySource.get(key)
      if (path !== undefined && path.length > 0) this.probeSource(key, path, maxHeight)
      return false
    }
    if (record.maxHeight !== maxHeight) {
      this.probeSource(key, record.path, maxHeight)
      return false
    }
    return record.status === 'applicable'
  }

  heightLimited(unit: ReaderUnitKey, sourceIndex: number, maxHeight: number): boolean {
    const record = this.eligibilityBySource.get(this.sourceIdentity(unit, sourceIndex))
    return record !== undefined && record.maxHeight === maxHeight && record.status === 'height-limit'
  }

  private probeEligibility(page: ReaderPage, path: string, maxHeight: number): void {
    this.probeSource(this.sourceIdentity(page.unit, page.sourceIndex), path, maxHeight)
  }

  private probeSource(key: string, path: string, maxHeight: number): void {
    const previous = this.eligibilityBySource.get(key)
    if (previous?.path === path && previous.maxHeight === maxHeight) return
    const record = new NextEReaderEligibilityRecord(path, maxHeight, 'pending')
    this.eligibilityBySource.set(key, record)
    void this.readSourceEligibility(key, record)
  }

  private async readSourceEligibility(key: string, record: NextEReaderEligibilityRecord): Promise<void> {
    let source: image.ImageSource | undefined
    let status: NextEReaderSourceEligibility = 'applicable'
    try {
      source = image.createImageSource(record.path)
      const info: image.ImageInfo = await source.getImageInfo()
      if (info.size.height > record.maxHeight) status = 'height-limit'
    } catch (_error) {
      // Unknown dimensions still go through the processor and retain its real failure reporting.
    } finally {
      if (source !== undefined) {
        try { await source.release() } catch (_error) {}
      }
    }
    if (this.eligibilityBySource.get(key) !== record) return
    record.status = status
    this.onEligibilityChanged()
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
        this.context, sourcePath, sourceKey, (state: string): void => {
          this.rememberInformation(page, identity, configuration.model, false, state)
        }, ownerKey)
      cancellation.check()
      this.rememberInformation(page, identity, configuration.model, result.applied, result.reason)
      const current = this.configuration()
      if (!current.enabled || current.identity() !== identity || !result.applied) {
        throw new Error(`reader_variant_not_applied:${result.reason}`)
      }
      const path = result.filePath.length > 0
        ? result.filePath
        : NextEReaderSuperResolutionProvider.localPath(result.displayUri)
      if (path.length === 0) throw new Error('reader_variant_output_unavailable')
      const saveUri = this.saveUris.get(this.pageIdentity(page)) ?? this.saveUriForPage(page)
      if (saveUri.length === 0) throw new Error('reader_variant_save_source_unavailable')
      retained = true
      return new NextEReaderSuperResolutionPlan(page, identity, path, ownerKey,
        this.provider.prepareOriginal !== undefined, this.cropStrength, saveUri)
    } catch (error) {
      const current = this.informationByPage.get(this.pageIdentity(page))
      if (current !== undefined && current.identity === identity && !current.applied &&
        (current.reason === 'queued' || current.reason === 'processing')) {
        this.rememberInformation(page, identity, configuration.model, false, (error as Error).message)
      }
      throw error as Error
    } finally {
      detach()
      if (!retained) readerSuperResolutionReleaseOwner(ownerKey)
    }
  }

  information(page: ReaderPage, identity: string): NextEReaderSuperResolutionInformation | null {
    const value = this.informationByPage.get(this.pageIdentity(page))
    return value !== undefined && value.identity === identity ? value.copy() : null
  }

  private rememberInformation(page: ReaderPage, identity: string, model: string,
    applied: boolean, reason: string): void {
    this.informationByPage.set(this.pageIdentity(page),
      new NextEReaderSuperResolutionInformation(identity, model, applied, reason))
  }

  private pageIdentity(page: ReaderPage): string {
    return JSON.stringify([page.unit.scope, page.unit.work, page.unit.unit, page.key, page.sourceIndex])
  }

  private sourceIdentity(unit: ReaderUnitKey, sourceIndex: number): string {
    return JSON.stringify([unit.scope, unit.work, unit.unit, sourceIndex])
  }

  private static localPath(uri: string): string {
    return uri.startsWith('file://') ? uri.substring('file://'.length) : ''
  }
}

import { common } from '@kit.AbilityKit'
import {
  ReaderAsset, ReaderAssetKind, ReaderAssetNotice, ReaderAssetProvider, ReaderCancellation,
  ReaderOriginalAssetPlan, ReaderPage, ReaderProcessedAssetVariant, ReaderVariantAssetPlan,
} from '@reader-kit/core'
import { AppStrings, DiagnosticLogger, ImageBlockDecision, ImageBlockRuntimeService } from 'shared'

export type NextEReaderImageBlockMarkResult = 'added' | 'waiting' | 'failed' | 'stale'

class NextEReaderImageBlockOriginalPlan implements ReaderOriginalAssetPlan {
  page: ReaderPage
  variant: 'original' = 'original'
  private owner: NextEReaderImageBlockProvider
  private delegate: ReaderOriginalAssetPlan

  constructor(owner: NextEReaderImageBlockProvider, delegate: ReaderOriginalAssetPlan) {
    this.owner = owner
    this.delegate = delegate
    this.page = delegate.page.copy()
  }

  async load(cancellation: ReaderCancellation, forceReload: boolean,
    onProgress?: (loaded: number, total: number) => void): Promise<ReaderAsset> {
    const asset = await this.delegate.load(cancellation, forceReload, onProgress)
    return await this.owner.applyDecision(this.page, asset, cancellation)
  }
}

/** NextE-owned policy bridge. reader-kit only receives a neutral suppressed-content notice. */
export class NextEReaderImageBlockProvider implements ReaderAssetProvider {
  cancellationMode: 'consumer-only' | 'transport'
  informationSupported: boolean
  prepareOriginal?: (page: ReaderPage, cancellation: ReaderCancellation) => Promise<ReaderOriginalAssetPlan>
  prepareVariant?: (page: ReaderPage, variant: ReaderProcessedAssetVariant, identity: string,
    cancellation: ReaderCancellation) => Promise<ReaderVariantAssetPlan>
  private provider: ReaderAssetProvider
  private context: common.UIAbilityContext
  private paths: Map<string, string> = new Map<string, string>()
  private blocked: Set<string> = new Set<string>()
  private feedback: (message: string) => void
  private forcedBlockedSourceIndex: number

  constructor(context: common.UIAbilityContext, provider: ReaderAssetProvider,
    feedback: (message: string) => void = (_message: string): void => {}, forcedBlockedSourceIndex: number = -1) {
    this.context = context
    this.provider = provider
    this.feedback = feedback
    this.cancellationMode = provider.cancellationMode
    this.informationSupported = provider.informationSupported === true
    this.forcedBlockedSourceIndex = forcedBlockedSourceIndex
    if (provider.prepareOriginal !== undefined) {
      this.prepareOriginal = async (page: ReaderPage,
        cancellation: ReaderCancellation): Promise<ReaderOriginalAssetPlan> => {
        cancellation.check()
        if (this.provider.prepareOriginal === undefined) throw new Error('reader_original_unavailable')
        const plan = await this.provider.prepareOriginal(page, cancellation)
        cancellation.check()
        return new NextEReaderImageBlockOriginalPlan(this, plan)
      }
    }
    if (provider.prepareVariant !== undefined) {
      this.prepareVariant = (page: ReaderPage, variant: ReaderProcessedAssetVariant, identity: string,
        cancellation: ReaderCancellation): Promise<ReaderVariantAssetPlan> => {
        if (this.provider.prepareVariant === undefined) throw new Error('reader_variant_unavailable')
        return this.provider.prepareVariant(page, variant, identity, cancellation)
      }
    }
  }

  async load(page: ReaderPage, kind: ReaderAssetKind, cancellation: ReaderCancellation,
    forceReload: boolean, onProgress?: (loaded: number, total: number) => void): Promise<ReaderAsset> {
    const asset = await this.provider.load(page, kind, cancellation, forceReload, onProgress)
    if (kind !== 'original') return asset
    return await this.applyDecision(page, asset, cancellation)
  }

  async applyDecision(page: ReaderPage, asset: ReaderAsset, cancellation: ReaderCancellation): Promise<ReaderAsset> {
    cancellation.check()
    const path = NextEReaderImageBlockProvider.localPath(asset.uri)
    const identity = this.pageIdentity(page)
    if (path.length === 0) {
      this.paths.delete(identity)
      this.blocked.delete(identity)
      return asset
    }
    this.paths.set(identity, path)
    let decision = new ImageBlockDecision()
    if (page.sourceIndex === this.forcedBlockedSourceIndex) {
      // One-shot Debug-lab evidence path supplied by NextEReaderLabContextProbe; never persisted or routed in release.
      decision.blocked = true
      decision.sourceType = 'debug-probe'
      decision.feedId = 'debug-probe'
    } else {
      try {
        decision = await ImageBlockRuntimeService.decisionForFile(this.context, path)
      } catch (error) {
        DiagnosticLogger.warn('image-block', 'reader_shared_decision_failed',
          `page=${page.sourceIndex + 1} ${(error as Error).message}`)
      }
    }
    cancellation.check()
    if (this.paths.get(identity) !== path) return asset
    if (!decision.blocked) {
      this.blocked.delete(identity)
      return asset
    }
    this.blocked.add(identity)
    asset.setNotice(new ReaderAssetNotice(
      `nexte-image-block:${identity}`,
      AppStrings.get('reader_image_blocked'),
      AppStrings.get('reader_image_blocked_hint'),
      AppStrings.get('reader_image_block_allow'),
      asset.uri,
    ), async (): Promise<boolean> => this.allow(identity, path, page.sourceIndex + 1))
    DiagnosticLogger.info('image-block', 'reader_shared_image_blocked',
      `page=${page.sourceIndex + 1} source=${decision.sourceType} feed=${decision.feedId}`)
    return asset
  }

  canMark(page: ReaderPage | null, enabled: boolean): boolean {
    if (!enabled || page === null) return false
    const identity = this.pageIdentity(page)
    return (this.paths.get(identity) ?? '').length > 0 && !this.blocked.has(identity)
  }

  async mark(page: ReaderPage | null, enabled: boolean, gallerySourceUrl: string): Promise<NextEReaderImageBlockMarkResult> {
    if (!enabled || page === null) return 'waiting'
    const identity = this.pageIdentity(page)
    const path = this.paths.get(identity) ?? ''
    if (path.length === 0) return 'waiting'
    try {
      await ImageBlockRuntimeService.addLocalRuleForFile(
        this.context, path, 'scanlator-ad', 8, gallerySourceUrl, page.sourceIndex + 1)
      if (this.paths.get(identity) !== path) return 'stale'
      this.blocked.add(identity)
      return 'added'
    } catch (error) {
      DiagnosticLogger.warn('image-block', 'reader_shared_local_rule_failed', (error as Error).message)
      return 'failed'
    }
  }

  private async allow(identity: string, path: string, page: number): Promise<boolean> {
    if (this.paths.get(identity) !== path || !this.blocked.has(identity)) return false
    try {
      await ImageBlockRuntimeService.addWhitelistForFile(this.context, path)
      if (this.paths.get(identity) !== path) return false
      this.blocked.delete(identity)
      this.feedback(AppStrings.get('reader_image_block_allowed'))
      return true
    } catch (error) {
      DiagnosticLogger.warn('image-block', 'reader_shared_whitelist_failed',
        `page=${page} ${(error as Error).message}`)
      this.feedback(AppStrings.get('reader_image_block_allow_failed'))
      return false
    }
  }

  private pageIdentity(page: ReaderPage): string {
    return JSON.stringify([page.unit.scope, page.unit.work, page.unit.unit, page.key, page.sourceIndex])
  }

  private static localPath(uri: string): string {
    return uri.startsWith('file://') ? uri.substring('file://'.length) : ''
  }
}

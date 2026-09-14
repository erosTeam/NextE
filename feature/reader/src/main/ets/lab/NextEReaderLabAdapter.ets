import { common } from '@kit.AbilityKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { systemShare } from '@kit.ShareKit'
import { ReaderSystemSharePresentation, ReaderFileInformation } from '@reader-kit/ui'
import {
  DiagnosticLogger, EhApiService, EhConstants, EhGalleryImage, ImageResolveService, ImagePipelineService,
  ReaderPageCropService,
  ReaderLocalSourceService, ReaderParams,
} from 'shared'
import {
  ReaderCatalog, ReaderAssetProvider, ReaderPreloadHost, ReaderUnitKey, ReaderUnit, ReaderPage,
  ReaderCancellation, ReaderAsset, ReaderAssetKind, ReaderImageShareHost,
  ReaderImageShareTarget, ReaderImageSharePresentation,
  ReaderImageInformation, ReaderOriginalAssetPlan, ReaderImageCropBounds, ReaderImageCropSource,
} from '@reader-kit/core'
import { ReaderViewModel } from '../viewmodel/ReaderViewModel'

class NextEReaderCropSource implements ReaderImageCropSource {
  private static sequence: number = 0
  private path: string
  private identity: string
  constructor(path: string) {
    this.path = path
    this.identity = `reader-lab-asset:${++NextEReaderCropSource.sequence}`
  }
  async read(): Promise<ReaderImageCropBounds> {
    const bounds = await ReaderPageCropService.detect(this.path, this.identity)
    return new ReaderImageCropBounds(bounds.left, bounds.top, bounds.right, bounds.bottom)
  }
}

class NextEOriginalAssetPlan implements ReaderOriginalAssetPlan {
  page: ReaderPage
  private context: common.UIAbilityContext
  private source: EhGalleryImage
  private url: string
  private cacheKey: string

  constructor(page: ReaderPage, context: common.UIAbilityContext, source: EhGalleryImage, url: string, cacheKey: string) {
    this.page = page.copy()
    this.context = context
    this.source = source.copy()
    this.url = url
    this.cacheKey = cacheKey
  }

  async load(request: ReaderCancellation, forceReload: boolean): Promise<ReaderAsset> {
    request.check()
    const source = this.source.copy()
    const url = forceReload ? await ImageResolveService.getInstance().resolveOriginal(source, true) : this.url
    request.check()
    this.source = source
    this.url = url
    const result = await ImagePipelineService.loadReaderFile(this.context, url, this.cacheKey, 100, undefined, forceReload)
    request.check()
    const facts = new ReaderImageInformation()
    facts.bytes = result.bytes
    facts.variant = 'original'
    facts.originalAvailable = true
    const asset = new ReaderAsset(result.displayUri, () => {}, new ReaderFileInformation(result.filePath, facts))
    asset.originalAvailable = true
    if (result.filePath.length > 0) asset.crop = new NextEReaderCropSource(result.filePath)
    return asset
  }
}

export class NextEReaderLabAdapter implements ReaderCatalog, ReaderAssetProvider, ReaderPreloadHost, ReaderImageShareHost {
  cancellationMode: 'consumer-only' | 'transport' = 'consumer-only'
  informationSupported: boolean = true
  private context: common.UIAbilityContext
  private token: string
  private isEx: boolean
  private pages: Map<string, EhGalleryImage> = new Map()
  private localUnits: Map<string, ReaderParams> = new Map()
  private entryUnits: Map<string, ReaderParams> = new Map()
  private gallerySourceLanguage: string = 'auto'
  private entryParams: ReaderParams | null
  private sourceSelected: ((kind: string, index: number, fileCount: number, seedCount: number,
    exactImagePage: boolean) => void) | null

  constructor(context: common.UIAbilityContext, token: string, isEx: boolean, entryParams: ReaderParams | null = null,
    sourceSelected: ((kind: string, index: number, fileCount: number, seedCount: number,
      exactImagePage: boolean) => void) | null = null) {
    this.context = context
    this.token = token
    this.isEx = isEx
    this.entryParams = entryParams
    this.sourceSelected = sourceSelected
  }

  transitionImage(pageKey: string | null): EhGalleryImage | null {
    if (pageKey === null) return null
    return this.pages.get(pageKey)?.copy() ?? null
  }

  async open(key: ReaderUnitKey, cancellation: ReaderCancellation): Promise<ReaderUnit> {
    cancellation.check()
    if (key.unit !== key.work || this.token.length === 0) throw new Error('invalid_eh_unit')
    try {
      const entry = this.entryParams !== null && this.entryParams.gid === key.work &&
        this.entryParams.token === this.token ? this.entryParams : null
      const localProbe = entry ?? new ReaderParams(key.work, this.token, 0)
      const local = await ReaderLocalSourceService.preferLocal(this.context, localProbe)
      cancellation.check()
      if (local.source.isLocal() && local.seedImages.length > 0 && local.fileCount === local.seedImages.length) {
        this.localUnits.set(key.unit, local)
        const language = local.sourceLanguage.trim()
        this.gallerySourceLanguage = language.length > 0 ? language : 'auto'
        console.info(`[NextEReaderDataSource] source=${local.source.kind} pages=${local.fileCount}`)
        this.sourceSelected?.(local.source.kind, local.index, local.fileCount, local.seedImages.length, false)
        return new ReaderUnit(key, local.title, local.fileCount)
      }
      if (entry !== null && local.fileCount > 0) {
        const vm = new ReaderViewModel()
        await vm.init(key.work, this.token, this.isEx, local.fileCount, local.index,
          local.seedImages, local.seedLoadedPages, local.seedPerPage, local.seedPreviewPages,
          local.seedImagePageUrl, local.source.kind, local.source.sourceKey)
        cancellation.check()
        this.entryUnits.set(key.unit, local)
        const language = local.sourceLanguage.trim()
        this.gallerySourceLanguage = language.length > 0 ? language : 'auto'
        console.info(`[NextEReaderDataSource] source=hostEntry pages=${vm.totalPages()}`)
        this.sourceSelected?.('hostEntry', local.index, local.fileCount, local.seedImages.length,
          local.seedImagePageUrl.length > 0)
        return new ReaderUnit(key, local.title, vm.totalPages())
      }
    } catch (error) {
      cancellation.check()
      console.warn(`[NextEReaderDataSource] local_source_unavailable error=${(error as Error).message}`)
    }
    this.localUnits.delete(key.unit)
    this.entryUnits.delete(key.unit)
    const result = await EhApiService.getInstance().getGalleryDetail(key.work, this.token, this.isEx)
    cancellation.check()
    const sourceLanguage = result.gallery.contentLanguage().trim()
    this.gallerySourceLanguage = sourceLanguage.length > 0 ? sourceLanguage : 'auto'
    // Each prepare owns its VM. A superseded open cannot reset the current catalog.
    const vm = new ReaderViewModel()
    await vm.init(key.work, this.token, this.isEx, result.gallery.fileCountNumber(), 0, result.images, 1)
    cancellation.check()
    this.sourceSelected?.('remoteDetail', 0, result.gallery.fileCountNumber(), result.images.length, false)
    return new ReaderUnit(key, result.gallery.title(), vm.totalPages())
  }

  async page(unit: ReaderUnit, index: number, cancellation: ReaderCancellation): Promise<ReaderPage> {
    cancellation.check()
    const local = this.localUnits.get(unit.key.unit)
    if (local !== undefined) {
      const source = local.seedImages[index]?.copy()
      if (source === undefined || !source.imageUrl.startsWith('file://')) throw new Error('missing_eh_local_page')
      const page = new ReaderPage(unit.key, `${unit.key.work}:${source.page}`, index)
      page.thumbnail.kind = 'image'
      this.pages.set(page.key, source)
      return page
    }
    // A VM's jumpTo ignores overlapping requests. Give each page request its own
    // preparation owner; the VM's bounded metadata cache still avoids repeat fetches.
    const vm = new ReaderViewModel()
    const entry = this.entryUnits.get(unit.key.unit)
    await vm.init(unit.key.work, this.token, this.isEx, unit.pageCount, index,
      entry?.seedImages ?? [], entry?.seedLoadedPages ?? 0, entry?.seedPerPage ?? 0,
      entry?.seedPreviewPages ?? [], entry !== undefined && entry.index === index ? entry.seedImagePageUrl : '')
    cancellation.check()
    const source = vm.imageAt(index).copy()
    if (source.sUrl.length === 0) throw new Error('missing_eh_preview')
    const page = new ReaderPage(unit.key, `${unit.key.work}:${source.page}`, index)
    page.thumbnail.kind = source.spriteWidth > 0 && source.thumbWidth > 0 ? 'sprite' : 'image'
    page.thumbnail.width = source.thumbWidth
    page.thumbnail.height = source.thumbHeight
    page.thumbnail.spriteWidth = source.spriteWidth
    page.thumbnail.spriteHeight = source.spriteHeight
    page.thumbnail.offsetX = source.thumbOffsetX
    this.pages.set(page.key, source)
    return page
  }

  adjacent(_unit: ReaderUnit, _direction: 'next' | 'previous'): ReaderUnitKey | null { return null }

  async preload(page: ReaderPage, cancellation: ReaderCancellation): Promise<void> {
    cancellation.check()
    if (this.localUnits.has(page.unit.unit)) {
      console.info(`[NextEReaderPreload] source=${page.sourceIndex} result=local-skip`)
      return
    }
    const source = this.pages.get(page.key)?.copy()
    if (source === undefined) throw new Error('missing_eh_preload_asset')
    const url = await ImageResolveService.getInstance().resolve(source)
    cancellation.check()
    this.pages.set(page.key, source.copy())
    const key = ImagePipelineService.readerFileCacheKey(page.unit.work, this.token, source.page, false)
    await ImagePipelineService.loadReaderFile(this.context, url, key, 100)
    cancellation.check()
    console.info(`[NextEReaderPreload] source=${page.sourceIndex} result=ready`)
  }

  sourceLanguage(): string { return this.gallerySourceLanguage }

  async prepareOriginal(page: ReaderPage, cancellation: ReaderCancellation): Promise<ReaderOriginalAssetPlan> {
    cancellation.check()
    if (this.localUnits.has(page.unit.unit)) throw new Error('eh_local_original_already_selected')
    const source = this.pages.get(page.key)?.copy()
    if (source === undefined) throw new Error('missing_eh_asset')
    const url = await ImageResolveService.getInstance().resolveOriginal(source)
    cancellation.check()
    const key = ImagePipelineService.readerFileCacheKey(page.unit.work, this.token, source.page, true)
    return new NextEOriginalAssetPlan(page, this.context, source, url, key)
  }

  async prepare(target: ReaderImageShareTarget, cancellation: ReaderCancellation): Promise<ReaderImageSharePresentation> {
    try {
      const page = await this.page(target.unit, target.sourceIndex, cancellation)
      cancellation.check()
      const source = this.pages.get(page.key)?.copy()
      if (source === undefined) throw new Error('missing_eh_share_page')
      const local = this.localUnits.get(target.unit.key.unit)
      let record: systemShare.SharedRecord
      if (local !== undefined) {
        if (!source.imageUrl.startsWith('file://')) throw new Error('missing_eh_local_share_page')
        record = { utd: utd.UniformDataType.IMAGE, title: `${target.unit.title} ${target.sourceIndex + 1}`,
          uri: source.imageUrl }
      } else {
        const url = target.variant === 'original' ? await ImageResolveService.getInstance().resolveOriginal(source) :
          await ImageResolveService.getInstance().resolve(source)
        cancellation.check()
        record = { utd: utd.UniformDataType.HYPERLINK,
          title: `${target.unit.title} ${target.sourceIndex + 1}`, content: url }
      }
      cancellation.check()
      return this.sharePresentation(record)
    } catch (error) {
      cancellation.check()
      DiagnosticLogger.warn('reader', 'shared_share_image_resolve_failed', (error as Error).message)
      return this.sharePresentation({
        utd: utd.UniformDataType.HYPERLINK,
        title: target.unit.title,
        content: `${EhConstants.baseUrl(this.isEx)}/g/${target.unit.key.work}/${this.token}/`,
      })
    }
  }

  private sharePresentation(record: systemShare.SharedRecord): ReaderImageSharePresentation {
    const data = new systemShare.SharedData(record)
    return new ReaderSystemSharePresentation(this.context, data, {
      selectionMode: systemShare.SelectionMode.SINGLE, previewMode: systemShare.SharePreviewMode.DETAIL,
    })
  }

  async load(page: ReaderPage, kind: ReaderAssetKind, cancellation: ReaderCancellation, forceReload: boolean): Promise<ReaderAsset> {
    cancellation.check()
    const source = this.pages.get(page.key)?.copy()
    if (source === undefined) throw new Error('missing_eh_asset')
    const local = this.localUnits.get(page.unit.unit)
    if (local !== undefined) {
      if (!source.imageUrl.startsWith('file://')) throw new Error('missing_eh_local_asset')
      const path = source.imageUrl.substring('file://'.length)
      const facts = new ReaderImageInformation()
      facts.variant = local.source.variant === 'original' ? 'original' : 'resampled'
      const asset = new ReaderAsset(source.imageUrl, () => {}, new ReaderFileInformation(path, facts))
      if (path.length > 0) asset.crop = new NextEReaderCropSource(path)
      return asset
    }
    if (kind === 'thumbnail') return new ReaderAsset(source.thumbUrl)
    // Match the production Reader's “reload image source” contract: a manual
    // force reload must re-resolve /s/?nl= instead of only downloading the
    // already selected CDN URL again. Persist the refreshed reload key only
    // after this request is still current so a cancelled older resolve cannot
    // overwrite the next manual reload's source state.
    const url = await ImageResolveService.getInstance().resolve(source, forceReload)
    cancellation.check()
    this.pages.set(page.key, source.copy())
    const key = ImagePipelineService.readerFileCacheKey(page.unit.work, this.token, source.page, false)
    const result = await ImagePipelineService.loadReaderFile(this.context, url, key, 100, undefined, forceReload)
    const facts = new ReaderImageInformation()
    facts.bytes = result.bytes
    facts.variant = 'resampled'
    facts.originalAvailable = source.originImageUrl.length > 0
    const asset = new ReaderAsset(result.displayUri, () => {}, new ReaderFileInformation(result.filePath, facts))
    asset.originalAvailable = facts.originalAvailable
    if (result.filePath.length > 0) asset.crop = new NextEReaderCropSource(result.filePath)
    return asset
  }
}

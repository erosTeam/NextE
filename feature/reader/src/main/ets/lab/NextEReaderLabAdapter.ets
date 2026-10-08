import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { systemShare } from '@kit.ShareKit'
import { ReaderSystemSharePresentation, ReaderFileInformation } from '@reader-kit/ui'
import {
  CachedImageFileResult, CachedImageProgress, DiagnosticLogger, EhApiService, EhConstants, EhGalleryImage, EhHttpClient,
  ImageResolveService, ImagePipelineService, EH_IMAGE_PRIORITY_HIGH, EH_IMAGE_PRIORITY_MEDIUM, EH_IMAGE_PRIORITY_LOW,
  ReaderLocalSourceService, ReaderParams, ReaderSourceKind, AppStrings,
} from 'shared'
import {
  ReaderCatalog, ReaderAssetProvider, ReaderPreloadHost, ReaderAutoReadSourceHost, ReaderUnitKey, ReaderUnit, ReaderPage,
  ReaderCancellation, ReaderAsset, ReaderAssetFailure, ReaderAssetFailureClassifier, ReaderAssetKind, ReaderImageShareHost,
  ReaderImageShareTarget, ReaderImageSharePresentation,
  ReaderImageInformation, ReaderOriginalAssetPlan,
} from '@reader-kit/core'
import { ReaderViewModel } from '../viewmodel/ReaderViewModel'
import { NextEReaderCropSource } from './NextEReaderCropSource'
import { NextEReaderFailure } from './NextEReaderFailure'

class NextEOriginalAssetPlan implements ReaderOriginalAssetPlan {
  page: ReaderPage
  private context: common.UIAbilityContext
  private source: EhGalleryImage
  private url: string
  private cacheKey: string
  private cropStrength: () => string

  constructor(page: ReaderPage, context: common.UIAbilityContext, source: EhGalleryImage, url: string, cacheKey: string,
    cropStrength: () => string = (): string => '') {
    this.page = page.copy()
    this.context = context
    this.source = source.copy()
    this.url = url
    this.cacheKey = cacheKey
    this.cropStrength = cropStrength
  }

  async load(request: ReaderCancellation, forceReload: boolean,
    onProgress?: (loaded: number, total: number) => void): Promise<ReaderAsset> {
    request.check()
    const source = this.source.copy()
    const cached = forceReload ? null : ImagePipelineService.cachedReaderFile(this.context, this.cacheKey)
    // A prepared local source can be evicted before load; resolve only that miss or an explicit reload.
    const url = forceReload || (cached === null && this.url.startsWith('file://'))
      ? await ImageResolveService.getInstance().resolveOriginal(source, forceReload) : this.url
    request.check()
    this.source = source
    this.url = url
    const result = cached ?? await ImagePipelineService.loadReaderFile(this.context, url, this.cacheKey, EH_IMAGE_PRIORITY_HIGH,
      onProgress !== undefined
        ? (progress: CachedImageProgress): void => { onProgress(progress.loaded, progress.total) }
        : undefined, forceReload)
    request.check()
    const facts = new ReaderImageInformation()
    facts.bytes = result.bytes
    facts.variant = 'original'
    facts.originalAvailable = true
    const asset = new ReaderAsset(result.displayUri, () => {}, new ReaderFileInformation(result.filePath, facts))
    asset.saveUri = this.url
    asset.originalAvailable = true
    if (result.filePath.length > 0) {
      asset.crop = new NextEReaderCropSource(result.filePath, 'reader-lab-original', this.cropStrength)
    }
    return asset
  }
}

export class NextEReaderLabAdapter implements ReaderCatalog, ReaderAssetProvider, ReaderAssetFailureClassifier,
  ReaderPreloadHost, ReaderAutoReadSourceHost, ReaderImageShareHost {
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
  private cropStrength: () => string

  classify(error: Error): ReaderAssetFailure {
    return NextEReaderFailure.from(error)
  }

  constructor(context: common.UIAbilityContext, token: string, isEx: boolean, entryParams: ReaderParams | null = null,
    sourceSelected: ((kind: string, index: number, fileCount: number, seedCount: number,
      exactImagePage: boolean) => void) | null = null,
    cropStrength: () => string = (): string => '') {
    this.context = context
    this.token = token
    this.isEx = isEx
    this.entryParams = entryParams
    this.sourceSelected = sourceSelected
    this.cropStrength = cropStrength
  }

  transitionImage(pageKey: string | null): EhGalleryImage | null {
    if (pageKey === null) return null
    return this.pages.get(pageKey)?.copy() ?? null
  }

  /** Legacy save exports the resolved source choice, never a generated reader variant. */
  saveUri(page: ReaderPage): string {
    const source = this.pages.get(page.key)
    if (source === undefined) return ''
    if (source.imageUrl.length > 0) return source.imageUrl
    const key = ImagePipelineService.readerFileCacheKey(page.unit.work, this.token, source.page, false)
    return ImagePipelineService.cachedReaderFile(this.context, key)?.displayUri ?? ''
  }

  /** Preserve the selected source URI while avoiding a second download of its readable cache. */
  async saveImageFile(work: string, uri: string, path: string): Promise<void> {
    let cached: CachedImageFileResult | null = null
    for (const value of this.pages.values()) {
      const source = value.copy()
      ImageResolveService.getInstance().restoreCachedMetadata(source)
      const original = source.originImageUrl === uri
      if (!original && source.imageUrl !== uri) continue
      const key = ImagePipelineService.readerFileCacheKey(work, this.token, source.page, original)
      cached = ImagePipelineService.cachedReaderFile(this.context, key)
      if (cached !== null) break
    }
    let sourceFile: fileIo.File | null = null
    if (cached !== null) {
      // Open before the first await: cache maintenance may unlink the path while the copy runs.
      try { sourceFile = fileIo.openSync(cached.filePath, fileIo.OpenMode.READ_ONLY) } catch (_) {}
    }
    if (sourceFile === null) {
      await EhHttpClient.getInstance().downloadBinaryToFile(uri, path)
      return
    }
    try {
      await fileIo.copyFile(sourceFile.fd, path)
    } finally {
      try { fileIo.closeSync(sourceFile) } catch (_) {
        DiagnosticLogger.warn('reader', 'save_cache_close_failed', 'source file close failed')
      }
    }
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
      page.bodySourceReady = true
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
    // `sUrl` establishes only preview metadata. Automatic reading follows the
    // legacy body-image condition, which becomes true after resolve() stores
    // a non-empty imageUrl (or a body image has already loaded).
    page.bodySourceReady = source.imageUrl.length > 0
    page.thumbnail.kind = source.spriteWidth > 0 && source.thumbWidth > 0 ? 'sprite' : 'image'
    page.thumbnail.width = source.thumbWidth
    page.thumbnail.height = source.thumbHeight
    page.thumbnail.spriteWidth = source.spriteWidth
    page.thumbnail.spriteHeight = source.spriteHeight
    page.thumbnail.offsetX = source.thumbOffsetX
    // Only the parser can attest that this individual sprite sub-rectangle (or
    // standalone thumbnail) depicts one gallery page. Keep its geometry
    // separate from original dimensions, which arrive after presentation.
    page.previewWidth = source.thumbWidth
    page.previewHeight = source.thumbHeight
    page.previewCoversWholePage = source.previewGeometryWholePage
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
    const key = ImagePipelineService.readerFileCacheKey(page.unit.work, this.token, source.page, false)
    if (ImagePipelineService.cachedReaderFile(this.context, key) !== null) return
    const url = await ImageResolveService.getInstance().resolve(source)
    cancellation.check()
    this.pages.set(page.key, source.copy())
    await ImagePipelineService.loadReaderFile(this.context, url, key, EH_IMAGE_PRIORITY_LOW)
    cancellation.check()
    console.info(`[NextEReaderPreload] source=${page.sourceIndex} result=ready`)
  }

  /** Resolve one automatic-reading target without changing thumbnail availability. */
  async prepareAutoReadSource(page: ReaderPage, cancellation: ReaderCancellation): Promise<ReaderPage> {
    cancellation.check()
    if (this.localUnits.has(page.unit.unit)) {
      const local = this.pages.get(page.key)
      if (local === undefined || !local.imageUrl.startsWith('file://')) throw new Error('missing_eh_local_body_source')
      const resolved = page.copy()
      resolved.bodySourceReady = true
      return resolved
    }
    const source = this.pages.get(page.key)?.copy()
    if (source === undefined) throw new Error('missing_eh_auto_read_source')
    const key = ImagePipelineService.readerFileCacheKey(page.unit.work, this.token, source.page, false)
    if (ImagePipelineService.cachedReaderFile(this.context, key) === null) {
      await ImageResolveService.getInstance().resolve(source)
      cancellation.check()
      if (source.imageUrl.length === 0) throw new Error('missing_eh_resolved_body_source')
    } else {
      ImageResolveService.getInstance().restoreCachedMetadata(source)
    }
    this.pages.set(page.key, source.copy())
    const resolved = page.copy()
    resolved.bodySourceReady = true
    return resolved
  }

  sourceLanguage(): string { return this.gallerySourceLanguage }

  imageInformationSource(page: ReaderPage): string {
    const local = this.localUnits.get(page.unit.unit)
    let source = ''
    if (local?.source.kind === ReaderSourceKind.GALLERY_DOWNLOAD) {
      source = AppStrings.get('reader_image_info_local_download')
    } else if (local?.source.kind === ReaderSourceKind.ARCHIVE) {
      const archive = AppStrings.get('reader_image_info_local_archive')
      source = local.source.resolution.length > 0 ? `${archive} · ${local.source.resolution}` : archive
    } else {
      source = this.imageHost(this.pages.get(page.key)?.imageUrl ?? '')
    }
    return source.length > 0 ? AppStrings.get('reader_image_info_source').replace('%s', source) : ''
  }

  private imageHost(url: string): string {
    const scheme = url.indexOf('://')
    if (scheme < 0) return ''
    const start = scheme + 3
    const slash = url.indexOf('/', start)
    const host = slash >= 0 ? url.substring(start, slash) : url.substring(start)
    const port = host.indexOf(':')
    return port >= 0 ? host.substring(0, port) : host
  }

  async prepareOriginal(page: ReaderPage, cancellation: ReaderCancellation): Promise<ReaderOriginalAssetPlan> {
    cancellation.check()
    if (this.localUnits.has(page.unit.unit)) throw new Error('eh_local_original_already_selected')
    const source = this.pages.get(page.key)?.copy()
    if (source === undefined) throw new Error('missing_eh_asset')
    const key = ImagePipelineService.readerFileCacheKey(page.unit.work, this.token, source.page, true)
    const cached = ImagePipelineService.cachedReaderFile(this.context, key)
    if (cached !== null) {
      ImageResolveService.getInstance().restoreCachedMetadata(source)
      const uri = source.originImageUrl.length > 0 ? source.originImageUrl : cached.displayUri
      return new NextEOriginalAssetPlan(page, this.context, source, uri, key, this.cropStrength)
    }
    const url = await ImageResolveService.getInstance().resolveOriginal(source)
    cancellation.check()
    return new NextEOriginalAssetPlan(page, this.context, source, url, key, this.cropStrength)
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

  async load(page: ReaderPage, kind: ReaderAssetKind, cancellation: ReaderCancellation, forceReload: boolean,
    onProgress?: (loaded: number, total: number) => void): Promise<ReaderAsset> {
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
      asset.saveUri = source.imageUrl
      if (path.length > 0) asset.crop = new NextEReaderCropSource(path, 'reader-lab-local', this.cropStrength)
      return asset
    }
    if (kind === 'thumbnail') return new ReaderAsset(source.thumbUrl)
    // Match the production Reader's “reload image source” contract: a manual
    // force reload must re-resolve /s/?nl= instead of only downloading the
    // already selected CDN URL again. Persist the refreshed reload key only
    // after this request is still current so a cancelled older resolve cannot
    // overwrite the next manual reload's source state.
    const key = ImagePipelineService.readerFileCacheKey(page.unit.work, this.token, source.page, false)
    const cached = forceReload ? null : ImagePipelineService.cachedReaderFile(this.context, key)
    if (cached !== null) {
      // Match Legacy: readable body bytes do not depend on fetching their /s/ metadata again.
      ImageResolveService.getInstance().restoreCachedMetadata(source)
      this.pages.set(page.key, source.copy())
      return this.fileAsset(page, source, cached)
    }
    const url = await ImageResolveService.getInstance().resolve(source, forceReload)
    cancellation.check()
    this.pages.set(page.key, source.copy())
    const result = await ImagePipelineService.loadReaderFile(this.context, url, key, EH_IMAGE_PRIORITY_MEDIUM,
      onProgress !== undefined
        ? (progress: CachedImageProgress): void => { onProgress(progress.loaded, progress.total) }
        : undefined, forceReload)
    return this.fileAsset(page, source, result)
  }

  private fileAsset(page: ReaderPage, source: EhGalleryImage, result: CachedImageFileResult): ReaderAsset {
    const facts = new ReaderImageInformation()
    facts.bytes = result.bytes
    facts.variant = 'resampled'
    const originalKey = ImagePipelineService.readerFileCacheKey(page.unit.work, this.token, source.page, true)
    facts.originalAvailable = source.originImageUrl.length > 0 ||
      ImagePipelineService.cachedReaderFile(this.context, originalKey) !== null
    const asset = new ReaderAsset(result.displayUri, () => {}, new ReaderFileInformation(result.filePath, facts))
    // Metadata may be absent after a cold start; the existing save host owns local-file copies.
    asset.saveUri = source.imageUrl.length > 0 ? source.imageUrl : result.displayUri
    asset.originalAvailable = facts.originalAvailable
    if (result.filePath.length > 0) {
      asset.crop = new NextEReaderCropSource(result.filePath, 'reader-lab-asset', this.cropStrength)
    }
    return asset
  }
}

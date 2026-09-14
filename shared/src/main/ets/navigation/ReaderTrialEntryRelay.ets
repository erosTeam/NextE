import { EhGalleryImage } from '../model/EhGalleryImage'
import { ReaderParams } from '../model/RouteParams'
import { EhThumbnailSnapshotSource } from '../components/EhThumbnailSnapshotSource'
import { connectSiteMode } from '../state/SiteModeState'

export type ReaderTrialEntrySite = 'eh' | 'ex'

/** Only thumbnail identity: no resolved original URLs, pixels, or reader-kit state. */
export class ReaderTrialThumbnailIdentity {
  readonly page: number
  readonly sUrl: string
  readonly imgkey: string
  readonly url: string
  readonly thumbWidth: number
  readonly thumbHeight: number
  readonly offsetX: number
  readonly spriteWidth: number
  readonly spriteHeight: number

  constructor(image: EhGalleryImage) {
    this.page = image.page; this.sUrl = image.sUrl; this.imgkey = image.imgkey; this.url = image.thumbUrl
    this.thumbWidth = image.thumbWidth; this.thumbHeight = image.thumbHeight; this.offsetX = image.thumbOffsetX
    this.spriteWidth = image.spriteWidth; this.spriteHeight = image.spriteHeight
  }

  matches(image: EhGalleryImage): boolean {
    return this.page === image.page && this.sUrl === image.sUrl && this.imgkey === image.imgkey &&
      this.url === image.thumbUrl && this.thumbWidth === image.thumbWidth && this.thumbHeight === image.thumbHeight &&
      this.offsetX === image.thumbOffsetX && this.spriteWidth === image.spriteWidth && this.spriteHeight === image.spriteHeight
  }

  matchesSnapshot(source: EhThumbnailSnapshotSource): boolean {
    return this.url === source.url && this.imgkey === source.imageKey && this.thumbWidth === source.thumbWidth &&
      this.thumbHeight === source.thumbHeight && this.offsetX === source.offsetX &&
      this.spriteWidth === source.spriteWidth && this.spriteHeight === source.spriteHeight
  }

  image(): EhGalleryImage {
    const value = new EhGalleryImage(this.page)
    value.sUrl = this.sUrl; value.imgkey = this.imgkey; value.thumbUrl = this.url
    value.thumbWidth = this.thumbWidth; value.thumbHeight = this.thumbHeight
    value.thumbOffsetX = this.offsetX; value.spriteWidth = this.spriteWidth
    value.spriteHeight = this.spriteHeight
    return value
  }
}

/** One actual mounted leaf. Readiness is deliberately independent of its live identity. */
export class ReaderTrialEntrySourceHandle {
  readonly site: ReaderTrialEntrySite
  readonly sourceComponentId: string
  readonly identity: ReaderTrialThumbnailIdentity
  snapshot: EhThumbnailSnapshotSource | null = null
  private current: () => boolean

  constructor(site: ReaderTrialEntrySite, sourceId: string, image: EhGalleryImage, current: () => boolean) {
    this.site = site; this.sourceComponentId = sourceId
    this.identity = new ReaderTrialThumbnailIdentity(image); this.current = current
  }

  isCurrent(): boolean {
    return this.site === ReaderTrialEntryRelay.currentSite() && this.current()
  }
}

export class ReaderTrialEntrySource {
  readonly site: ReaderTrialEntrySite
  readonly galleryId: string
  readonly pageIndex: number
  readonly sourceComponentId: string
  readonly snapshotComponentId: string
  readonly identity: ReaderTrialThumbnailIdentity
  readonly params: ReaderParams
  readonly snapshot: EhThumbnailSnapshotSource | null
  readonly isCurrent: () => boolean

  constructor(galleryId: string, pageIndex: number, handle: ReaderTrialEntrySourceHandle, params: ReaderParams,
    snapshot: EhThumbnailSnapshotSource | null, current: () => boolean) {
    this.site = handle.site; this.galleryId = galleryId; this.pageIndex = pageIndex
    this.sourceComponentId = handle.sourceComponentId
    this.snapshotComponentId = `${handle.sourceComponentId}-content`
    this.identity = handle.identity; this.params = params; this.snapshot = snapshot; this.isCurrent = current
  }

  sourceScope(): string {
    const suffix = `-page-${this.pageIndex}`
    return this.sourceComponentId.endsWith(suffix)
      ? this.sourceComponentId.substring(0, this.sourceComponentId.length - suffix.length)
      : ''
  }
}

/** Optional Debug host only. Unregistered entries leave the production coordinator untouched. */
export class ReaderTrialEntryRelay {
  private static serial: number = 0
  private static token: number = 0
  private static site: ReaderTrialEntrySite = 'eh'
  private static galleryId: string = ''
  private static handler: ((source: ReaderTrialEntrySource) => boolean) | null = null
  private static pendingToken: number = 0
  private static pendingSite: ReaderTrialEntrySite = 'eh'
  private static pendingGalleryId: string = ''
  private static pendingCancel: (() => boolean) | null = null
  private static sources: Map<string, ReaderTrialEntrySourceHandle> = new Map<string, ReaderTrialEntrySourceHandle>()

  static currentSite(): ReaderTrialEntrySite { return connectSiteMode().isEx ? 'ex' : 'eh' }

  static isSnapshotReady(site: ReaderTrialEntrySite, sourceId: string): boolean {
    const handle = ReaderTrialEntryRelay.sources.get(ReaderTrialEntryRelay.sourceKey(site, sourceId))
    if (site !== ReaderTrialEntryRelay.currentSite() || handle === undefined ||
      !ReaderTrialEntryRelay.sourceCurrent(handle)) return false
    const source = handle.snapshot
    return source !== null && source.isCurrent() && handle.identity.matchesSnapshot(source)
  }

  private static sourceKey(site: ReaderTrialEntrySite, sourceId: string): string { return `${site}:${sourceId}` }

  static bindSource(sourceId: string, image: EhGalleryImage, current: () => boolean): ReaderTrialEntrySourceHandle {
    const handle = new ReaderTrialEntrySourceHandle(ReaderTrialEntryRelay.currentSite(), sourceId, image, current)
    ReaderTrialEntryRelay.sources.set(ReaderTrialEntryRelay.sourceKey(handle.site, sourceId), handle)
    return handle
  }

  static updateSnapshot(handle: ReaderTrialEntrySourceHandle, source: EhThumbnailSnapshotSource | null): void {
    if (!ReaderTrialEntryRelay.sourceCurrent(handle)) return
    if (source === null) {
      // A retiring child can publish null after its replacement has become ready.
      if (handle.snapshot === null || !handle.snapshot.isCurrent()) handle.snapshot = null
    } else if (source.isCurrent() && handle.identity.matchesSnapshot(source)) {
      handle.snapshot = source
    }
  }

  static unbindSource(handle: ReaderTrialEntrySourceHandle): void {
    const key = ReaderTrialEntryRelay.sourceKey(handle.site, handle.sourceComponentId)
    if (ReaderTrialEntryRelay.sources.get(key) === handle) ReaderTrialEntryRelay.sources.delete(key)
  }

  private static sourceCurrent(handle: ReaderTrialEntrySourceHandle): boolean {
    return ReaderTrialEntryRelay.sources.get(ReaderTrialEntryRelay.sourceKey(handle.site, handle.sourceComponentId)) === handle &&
      handle.isCurrent()
  }

  static install(site: ReaderTrialEntrySite, galleryId: string,
    handler: (source: ReaderTrialEntrySource) => boolean): number {
    const token = ++ReaderTrialEntryRelay.serial
    ReaderTrialEntryRelay.token = token; ReaderTrialEntryRelay.site = site
    ReaderTrialEntryRelay.galleryId = galleryId; ReaderTrialEntryRelay.handler = handler
    return token
  }

  static clear(token: number): void {
    if (ReaderTrialEntryRelay.token !== token) return
    ReaderTrialEntryRelay.token = 0; ReaderTrialEntryRelay.galleryId = ''; ReaderTrialEntryRelay.handler = null
  }

  static holdPending(site: ReaderTrialEntrySite, galleryId: string, cancel: () => boolean): number {
    const token = ++ReaderTrialEntryRelay.serial
    ReaderTrialEntryRelay.pendingToken = token; ReaderTrialEntryRelay.pendingSite = site
    ReaderTrialEntryRelay.pendingGalleryId = galleryId; ReaderTrialEntryRelay.pendingCancel = cancel
    return token
  }

  static releasePending(token: number): void {
    if (ReaderTrialEntryRelay.pendingToken !== token) return
    ReaderTrialEntryRelay.pendingToken = 0; ReaderTrialEntryRelay.pendingGalleryId = ''
    ReaderTrialEntryRelay.pendingCancel = null
  }

  static cancelPending(site: ReaderTrialEntrySite, galleryId: string): boolean {
    const cancel = ReaderTrialEntryRelay.pendingCancel
    if (ReaderTrialEntryRelay.pendingToken === 0 || site !== ReaderTrialEntryRelay.currentSite() ||
      site !== ReaderTrialEntryRelay.pendingSite || galleryId !== ReaderTrialEntryRelay.pendingGalleryId || cancel === null) return false
    return cancel()
  }

  static tryOpen(galleryId: string, pageIndex: number, image: EhGalleryImage, sourceId: string,
    params: ReaderParams): boolean {
    const site = ReaderTrialEntryRelay.currentSite()
    if (ReaderTrialEntryRelay.pendingToken !== 0 && ReaderTrialEntryRelay.pendingSite === site &&
      ReaderTrialEntryRelay.pendingGalleryId === galleryId) return true
    const handler = ReaderTrialEntryRelay.handler
    if (handler === null || ReaderTrialEntryRelay.site !== site || ReaderTrialEntryRelay.galleryId !== galleryId ||
      galleryId.length === 0 || sourceId.length === 0 || !Number.isSafeInteger(pageIndex) || pageIndex < 0 ||
      image.page !== pageIndex + 1 || params.gid !== galleryId || params.index !== pageIndex ||
      params.token.length === 0) return false
    const handle = ReaderTrialEntryRelay.sources.get(ReaderTrialEntryRelay.sourceKey(site, sourceId))
    if (handle === undefined || !ReaderTrialEntryRelay.sourceCurrent(handle) || !handle.identity.matches(image)) return false
    const ready = handle.snapshot
    const snapshot = ready !== null && ready.isCurrent() && handle.identity.matchesSnapshot(ready) ? ready : null
    const source = new ReaderTrialEntrySource(galleryId, pageIndex, handle, params, snapshot,
      (): boolean => ReaderTrialEntryRelay.sourceCurrent(handle))
    const token = ReaderTrialEntryRelay.token
    if (!handler(source)) return false
    ReaderTrialEntryRelay.clear(token)
    return true
  }
}

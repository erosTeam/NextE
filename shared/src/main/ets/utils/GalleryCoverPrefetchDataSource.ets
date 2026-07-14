import { BasicPrefetcher, IDataSourcePrefetching } from '@kit.ArkUI'
import { ImageKnifeRequest } from '@ohos/imageknifepro'
import { EhConstants } from '../constants/EhConstants'
import { EhGallery } from '../model/EhGallery'
import { ImageKnifePreloadCallbacks } from '../services/ImageKnifeProRuntime'
import { ImagePipelineService } from '../services/ImagePipelineService'
import { EH_IMAGE_PRIORITY_LOW } from '../services/ImagePipelineTypes'
import { BasicDataSource } from './BasicDataSource'

const GALLERY_COVER_PREFETCH_GUARD_MS: number = 15000

/**
 * One in-flight offscreen cover preload. A request becomes non-cancellable as soon as ImageKnife
 * starts it, so fast direction changes only remove work still waiting in ImageKnife's own queue.
 */
class GalleryCoverPreloadTicket {
  readonly token: number
  readonly completion: Promise<void>
  request: ImageKnifeRequest | null = null
  started: boolean = false
  private finished: boolean = false
  private resolveCompletion: (() => void) | null = null
  private guardTimerId: number = 0

  constructor(token: number) {
    this.token = token
    this.completion = new Promise<void>((resolve: () => void): void => {
      this.resolveCompletion = resolve
    })
  }

  armGuard(onExpired: () => void): void {
    if (this.finished || this.guardTimerId > 0) {
      return
    }
    this.guardTimerId = setTimeout((): void => {
      this.guardTimerId = 0
      onExpired()
    }, GALLERY_COVER_PREFETCH_GUARD_MS)
  }

  finish(): void {
    if (this.finished) {
      return
    }
    this.finished = true
    if (this.guardTimerId > 0) {
      clearTimeout(this.guardTimerId)
      this.guardTimerId = 0
    }
    const resolve: (() => void) | null = this.resolveCompletion
    this.resolveCompletion = null
    if (resolve !== null) {
      resolve()
    }
  }
}

/**
 * Gallery-only LazyForEach source with ArkUI dynamic cover prefetching. Keeping this separate from
 * BasicDataSource avoids making comments, reader rows, and other generic sources acquire image policy.
 */
export class GalleryCoverPrefetchDataSource extends BasicDataSource<EhGallery>
  implements IDataSourcePrefetching {
  private readonly prefetcher: BasicPrefetcher
  private readonly tickets: Map<number, GalleryCoverPreloadTicket> = new Map()
  private nextToken: number = 1

  constructor() {
    super()
    this.prefetcher = new BasicPrefetcher(this)
  }

  protected keyForData(item: EhGallery): string {
    return item.renderKey()
  }

  /** Feed normalized gallery indexes from List/Grid/WaterFlow onScrollIndex. */
  visibleAreaChanged(start: number, end: number): void {
    const total: number = this.totalCount()
    if (total <= 0 || start < 0 || end < 0) {
      return
    }
    const minVisible: number = Math.min(total - 1, Math.max(0, start))
    const maxVisible: number = Math.min(total - 1, Math.max(0, end))
    if (minVisible > maxVisible) {
      return
    }
    this.prefetcher.visibleAreaChanged(minVisible, maxVisible)
  }

  prefetch(index: number): Promise<void> {
    if (index < 0 || index >= this.totalCount()) {
      return Promise.resolve()
    }
    const existing: GalleryCoverPreloadTicket | undefined = this.tickets.get(index)
    if (existing !== undefined) {
      return existing.completion
    }
    const gallery: EhGallery = this.getData(index)
    const url: string = EhConstants.cdnThumb(gallery.thumbUrl)
    if (url.length === 0) {
      return Promise.resolve()
    }
    const ticket: GalleryCoverPreloadTicket = new GalleryCoverPreloadTicket(this.nextToken++)
    this.tickets.set(index, ticket)
    ticket.armGuard((): void => {
      this.finishTicket(index, ticket, true)
    })
    const callbacks: ImageKnifePreloadCallbacks = new ImageKnifePreloadCallbacks()
    callbacks.onStart = () => {
      if (this.isCurrentTicket(index, ticket)) {
        ticket.started = true
      }
    }
    callbacks.onSettled = () => {
      this.finishTicket(index, ticket, false)
    }
    ticket.request = ImagePipelineService.preloadCover(url, EH_IMAGE_PRIORITY_LOW, true, callbacks)
    if (ticket.request === null) {
      this.finishTicket(index, ticket, false)
    }
    return ticket.completion
  }

  cancel(index: number): void {
    this.releaseTicket(index)
  }

  /** Called when the owning page leaves; active ImageKnife requests are intentionally left alone. */
  cancelQueuedCoverPrefetches(): void {
    const indexes: number[] = []
    this.tickets.forEach((_ticket: GalleryCoverPreloadTicket, index: number) => {
      indexes.push(index)
    })
    indexes.forEach((index: number) => {
      this.releaseTicket(index)
    })
  }

  setData(items: EhGallery[]): void {
    this.cancelQueuedCoverPrefetches()
    super.setData(items)
  }

  prependData(items: EhGallery[]): void {
    this.cancelQueuedCoverPrefetches()
    super.prependData(items)
  }

  replaceDataAt(index: number, item: EhGallery): boolean {
    this.releaseTicket(index)
    return super.replaceDataAt(index, item)
  }

  removeDataAt(index: number): boolean {
    this.cancelQueuedCoverPrefetches()
    return super.removeDataAt(index)
  }

  clear(): void {
    this.cancelQueuedCoverPrefetches()
    super.clear()
  }

  private isCurrentTicket(index: number, ticket: GalleryCoverPreloadTicket): boolean {
    const current: GalleryCoverPreloadTicket | undefined = this.tickets.get(index)
    return current !== undefined && current.token === ticket.token
  }

  private releaseTicket(index: number): void {
    const ticket: GalleryCoverPreloadTicket | undefined = this.tickets.get(index)
    if (ticket === undefined) {
      return
    }
    this.finishTicket(index, ticket, true)
  }

  private finishTicket(
    index: number,
    ticket: GalleryCoverPreloadTicket,
    cancelQueued: boolean,
  ): void {
    const current: boolean = this.isCurrentTicket(index, ticket)
    if (current) {
      this.tickets.delete(index)
    }
    // Complete the logical prefetch before invoking vendor cancellation. ImageKnife may call
    // onSettled synchronously from cancel(); finish() is idempotent and an old callback cannot
    // delete a newer ticket for the same index.
    ticket.finish()
    if (current && cancelQueued && !ticket.started && ticket.request !== null) {
      ImagePipelineService.cancelCoverPreload(ticket.request)
    }
  }
}

import { BasicPrefetcher, IDataSourcePrefetching } from '@kit.ArkUI'
import { ImageKnifeRequest } from '@ohos/imageknifepro'
import { EhConstants } from '../constants/EhConstants'
import { EhGallery } from '../model/EhGallery'
import { ImageKnifePreloadCallbacks } from '../services/ImageKnifeProRuntime'
import { ImagePipelineService } from '../services/ImagePipelineService'
import { EH_IMAGE_PRIORITY_LOW } from '../services/ImagePipelineTypes'
import { BasicDataSource } from './BasicDataSource'

/**
 * One in-flight offscreen cover preload. A request becomes non-cancellable as soon as ImageKnife
 * starts it, so fast direction changes only remove work still waiting in ImageKnife's own queue.
 */
class GalleryCoverPreloadTicket {
  readonly token: number
  request: ImageKnifeRequest | null = null
  started: boolean = false

  constructor(token: number) {
    this.token = token
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

  prefetch(index: number): void {
    if (index < 0 || index >= this.totalCount() || this.tickets.has(index)) {
      return
    }
    const gallery: EhGallery = this.getData(index)
    const url: string = EhConstants.cdnThumb(gallery.thumbUrl)
    if (url.length === 0) {
      return
    }
    const ticket: GalleryCoverPreloadTicket = new GalleryCoverPreloadTicket(this.nextToken++)
    this.tickets.set(index, ticket)
    const callbacks: ImageKnifePreloadCallbacks = new ImageKnifePreloadCallbacks()
    callbacks.onStart = () => {
      if (this.isCurrentTicket(index, ticket)) {
        ticket.started = true
      }
    }
    callbacks.onSettled = () => {
      if (this.isCurrentTicket(index, ticket)) {
        this.tickets.delete(index)
      }
    }
    ticket.request = ImagePipelineService.preloadCover(url, EH_IMAGE_PRIORITY_LOW, true, callbacks)
    if (ticket.request === null && this.isCurrentTicket(index, ticket)) {
      this.tickets.delete(index)
    }
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
    this.tickets.delete(index)
    if (!ticket.started && ticket.request !== null) {
      ImagePipelineService.cancelCoverPreload(ticket.request)
    }
  }
}

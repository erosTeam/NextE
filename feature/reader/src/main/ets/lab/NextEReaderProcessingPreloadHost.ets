import { ReaderAsset, ReaderCancellation, ReaderPage, ReaderPreloadHost } from '@reader-kit/core'
import { NextEReaderSuperResolutionProvider } from './NextEReaderSuperResolutionProvider'

export class NextEReaderSourcePreloadHost implements ReaderPreloadHost {
  private source: (page: ReaderPage, cancellation: ReaderCancellation) => Promise<ReaderAsset>

  constructor(source: (page: ReaderPage, cancellation: ReaderCancellation) => Promise<ReaderAsset>) {
    this.source = source
  }

  async preload(page: ReaderPage, cancellation: ReaderCancellation): Promise<void> {
    const asset = await this.source(page, cancellation)
    asset.release()
  }
}

class NextEReaderPreloadDemand {
  page: ReaderPage
  parent: ReaderCancellation
  cancellation: ReaderCancellation = new ReaderCancellation()
  running: boolean = false
  revision: number = 0

  constructor(page: ReaderPage, parent: ReaderCancellation) {
    this.page = page.copy()
    this.parent = parent
  }
}

/** reader-core selects the rolling window; NextE prepares files and optional processing. */
export class NextEReaderProcessingPreloadHost implements ReaderPreloadHost {
  private source: ReaderPreloadHost
  private enhancement: NextEReaderSuperResolutionProvider
  private demands: Map<string, NextEReaderPreloadDemand> = new Map()
  private active: boolean = true

  constructor(source: ReaderPreloadHost, enhancement: NextEReaderSuperResolutionProvider) {
    this.source = source
    this.enhancement = enhancement
  }

  async preload(page: ReaderPage, cancellation: ReaderCancellation): Promise<void> {
    cancellation.check()
    const key = JSON.stringify([page.unit.scope, page.unit.work, page.unit.unit, page.key, page.sourceIndex])
    const previous = this.demands.get(key)
    previous?.cancellation.cancel()
    const demand = new NextEReaderPreloadDemand(page, cancellation)
    this.demands.set(key, demand)
    cancellation.onCancel((): void => {
      demand.cancellation.cancel()
      if (this.demands.get(key) === demand) this.demands.delete(key)
    })
    await this.run(demand)
  }

  setActive(active: boolean): void {
    if (active === this.active) return
    this.active = active
    this.refresh()
  }

  refresh(): void {
    this.demands.forEach((demand): void => {
      demand.revision += 1
      demand.cancellation.cancel()
      if (!demand.running) void this.run(demand)
    })
  }

  close(): void {
    this.active = false
    this.demands.forEach((demand): void => demand.cancellation.cancel())
    this.demands.clear()
  }

  private async run(demand: NextEReaderPreloadDemand): Promise<void> {
    if (!this.active || demand.parent.isCancelled() || demand.running) return
    const revision = demand.revision
    demand.cancellation = new ReaderCancellation()
    demand.running = true
    try {
      await this.source.preload(demand.page.copy(), demand.cancellation)
      demand.cancellation.check()
      await this.enhancement.preload(demand.page.copy(), demand.cancellation)
    } catch (_error) {
      if (!demand.cancellation.isCancelled()) {
        console.warn(`[NextEReaderPreprocess] failed source=${demand.page.sourceIndex}`)
      }
    } finally {
      demand.running = false
      if (revision !== demand.revision) void this.run(demand)
    }
  }
}

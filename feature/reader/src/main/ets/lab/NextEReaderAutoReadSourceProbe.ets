import { ReaderAutoReadSourceHost, ReaderCancellation, ReaderPage } from '@reader-kit/core'

/**
 * Debug-Want-only wrapper around NextE's real target-source resolver.
 * It deliberately returns one resolved page after cancellation so ReaderPagedSession's
 * existing generation/current fence, rather than this probe, decides whether to publish it.
 */
export class NextEReaderAutoReadSourceProbe implements ReaderAutoReadSourceHost {
  private host: ReaderAutoReadSourceHost
  private mode: string
  private injected: boolean = false

  constructor(host: ReaderAutoReadSourceHost, mode: string) {
    this.host = host
    this.mode = mode
  }

  async prepareAutoReadSource(page: ReaderPage, cancellation: ReaderCancellation): Promise<ReaderPage> {
    const inject = !this.injected && this.mode === 'delay-once'
    if (inject) this.injected = true
    console.info(`[NextEReaderAutoReadSourceProbe] prepare_started source=${page.sourceIndex} injected=${inject}`)
    const resolved = await this.host.prepareAutoReadSource(page, cancellation)
    if (!inject) return resolved
    console.info(`[NextEReaderAutoReadSourceProbe] prepare_delay source=${page.sourceIndex}`)
    await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 3000) })
    // Deliberately return after cancellation; the session's current-generation fence owns retirement.
    console.info(`[NextEReaderAutoReadSourceProbe] delayed_result source=${page.sourceIndex} cancelled=${cancellation.isCancelled()}`)
    return resolved
  }
}

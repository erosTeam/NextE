import { ReaderAsset, ReaderCancellation, ReaderPage, ReaderPreloadHost } from '@reader-kit/core'

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

import { ReaderImageCropBounds, ReaderImageCropSource } from '@reader-kit/core'
import { DiagnosticLogger, ReaderPageCropService } from 'shared'

/** NextE owns detector policy; reader-kit consumes only normalized crop bounds. */
export class NextEReaderCropSource implements ReaderImageCropSource {
  private static sequence: number = 0
  private path: string
  private identity: string
  private strength: () => string

  constructor(path: string, identityPrefix: string, strength: () => string) {
    this.path = path
    this.identity = `${identityPrefix}:${++NextEReaderCropSource.sequence}`
    this.strength = strength
  }

  async read(): Promise<ReaderImageCropBounds> {
    const strength = this.strength()
    DiagnosticLogger.info('reader-crop', 'shared_detect', `identity=${this.identity} strength=${strength}`)
    const bounds = await ReaderPageCropService.detect(this.path, this.identity, strength)
    return new ReaderImageCropBounds(bounds.left, bounds.top, bounds.right, bounds.bottom)
  }
}

import { CachedImageFileResult } from 'shared'

/**
 * Keeps the artificial completed-progress hold out of a fully available local reader file.
 * Native image decoding still owns the visible decoding state after this decision.
 */
export class ReaderImageLoadPresentation {
  static shouldSkipCompletionHold(result: CachedImageFileResult): boolean {
    return result.fromCache &&
      result.bytes > 0 &&
      result.filePath.length > 0 &&
      result.displayUri.length > 0
  }
}

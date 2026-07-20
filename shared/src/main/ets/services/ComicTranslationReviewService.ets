import {
  ComicPageDocument,
  ComicQualitySeverity,
  ComicQualitySignal,
  ComicTextBlock,
  ComicTranslationState,
} from '../model/ComicTranslation'

const MAX_COMIC_REVIEW_SIGNALS: number = 512
const MAX_COMIC_REVIEW_BLOCKS: number = 512

/** Maps provider-neutral state to fixed Reader review markers without exposing signal text. */
export class ComicTranslationReviewService {
  static documentNeedsReview(document: ComicPageDocument | null): boolean {
    if (document === null) {
      return false
    }
    if (document.translationState === ComicTranslationState.REVIEW_REQUIRED) {
      return true
    }
    const signalCount: number = Math.min(
      document.qualitySignals.length,
      MAX_COMIC_REVIEW_SIGNALS,
    )
    for (let index: number = 0; index < signalCount; index++) {
      if (ComicTranslationReviewService.isReviewSeverity(
        document.qualitySignals[index].severity,
      )) {
        return true
      }
    }
    return false
  }

  static blockNeedsReview(document: ComicPageDocument | null, blockId: string): boolean {
    if (document === null || blockId.length === 0) {
      return false
    }
    const signalCount: number = Math.min(
      document.qualitySignals.length,
      MAX_COMIC_REVIEW_SIGNALS,
    )
    for (let index: number = 0; index < signalCount; index++) {
      const signal: ComicQualitySignal = document.qualitySignals[index]
      if (signal.blockId === blockId &&
        ComicTranslationReviewService.isReviewSeverity(signal.severity)) {
        return true
      }
    }
    if (document.translationState !== ComicTranslationState.REVIEW_REQUIRED) {
      return false
    }
    const blockCount: number = Math.min(document.blocks.length, MAX_COMIC_REVIEW_BLOCKS)
    for (let index: number = 0; index < blockCount; index++) {
      const block: ComicTextBlock = document.blocks[index]
      if (block.blockId === blockId) {
        return block.translatedText.trim().length === 0
      }
    }
    return false
  }

  private static isReviewSeverity(severity: ComicQualitySeverity): boolean {
    return severity === ComicQualitySeverity.WARNING || severity === ComicQualitySeverity.ERROR
  }
}

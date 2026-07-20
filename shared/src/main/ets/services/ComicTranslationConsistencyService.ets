import {
  ComicPageDocument,
  ComicQualitySeverity,
  ComicQualitySignal,
  ComicTextBlock,
} from '../model/ComicTranslation'
import { ComicTranslationReviewService } from './ComicTranslationReviewService'

export const COMIC_TRANSLATION_CONSISTENCY_SIGNAL_CODE: string =
  'translation_consistency_conflict'

const MAX_CONSISTENCY_PREVIOUS_PAGES: number = 32
const MAX_CONSISTENCY_BLOCKS_PER_PAGE: number = 512
const MAX_DOCUMENT_QUALITY_SIGNALS: number = 512

/** Adds transient review signals without rewriting or persisting provider text. */
export class ComicTranslationConsistencyService {
  static audit(
    document: ComicPageDocument,
    previousPages: ComicPageDocument[],
  ): ComicPageDocument {
    const audited: ComicPageDocument = document.copy()
    if (!audited.hasText || audited.blocks.length === 0 || previousPages.length === 0 ||
      ComicTranslationReviewService.documentHasPageLevelReviewSignal(audited)) {
      return audited
    }
    const previousTranslations: Map<string, Set<string>> =
      ComicTranslationConsistencyService.collectPreviousTranslations(previousPages)
    const blockCount: number = Math.min(
      audited.blocks.length,
      MAX_CONSISTENCY_BLOCKS_PER_PAGE,
    )
    for (let index: number = 0; index < blockCount; index++) {
      const block: ComicTextBlock = audited.blocks[index]
      const source: string = ComicTranslationConsistencyService.sourceKey(block)
      const translated: string = ComicTranslationConsistencyService.normalizedText(
        block.translatedText,
      )
      if (source.length === 0 || translated.length === 0 ||
        ComicTranslationReviewService.blockNeedsReview(audited, block.blockId) ||
        !ComicTranslationConsistencyService.hasDifferentTranslation(
          previousTranslations.get(source),
          translated,
        ) || ComicTranslationConsistencyService.hasConflict(audited, block.blockId)) {
        continue
      }
      const signal: ComicQualitySignal = new ComicQualitySignal()
      signal.code = COMIC_TRANSLATION_CONSISTENCY_SIGNAL_CODE
      signal.severity = ComicQualitySeverity.WARNING
      signal.blockId = block.blockId
      signal.message = 'Translation differs from a previous page for the same source text'
      if (!ComicTranslationConsistencyService.appendActionableSignal(audited, signal)) {
        break
      }
    }
    return audited
  }

  static hasConflict(document: ComicPageDocument | null, blockId: string): boolean {
    if (document === null || blockId.length === 0) {
      return false
    }
    const count: number = Math.min(
      document.qualitySignals.length,
      MAX_DOCUMENT_QUALITY_SIGNALS,
    )
    for (let index: number = 0; index < count; index++) {
      const signal: ComicQualitySignal = document.qualitySignals[index]
      if (signal.code === COMIC_TRANSLATION_CONSISTENCY_SIGNAL_CODE &&
        ComicTranslationConsistencyService.isActionableSeverity(signal.severity) &&
        signal.blockId === blockId) {
        return true
      }
    }
    return false
  }

  private static isActionableSeverity(severity: ComicQualitySeverity): boolean {
    return severity === ComicQualitySeverity.WARNING || severity === ComicQualitySeverity.ERROR
  }

  private static appendActionableSignal(
    document: ComicPageDocument,
    signal: ComicQualitySignal,
  ): boolean {
    if (document.qualitySignals.length < MAX_DOCUMENT_QUALITY_SIGNALS) {
      document.qualitySignals.push(signal)
      return true
    }
    if (document.qualitySignals.length > MAX_DOCUMENT_QUALITY_SIGNALS) {
      return false
    }
    for (let index: number = MAX_DOCUMENT_QUALITY_SIGNALS - 1; index >= 0; index--) {
      if (document.qualitySignals[index].severity === ComicQualitySeverity.INFO) {
        document.qualitySignals.splice(index, 1)
        document.qualitySignals.push(signal)
        return true
      }
    }
    return false
  }

  private static collectPreviousTranslations(
    previousPages: ComicPageDocument[],
  ): Map<string, Set<string>> {
    const translations: Map<string, Set<string>> = new Map<string, Set<string>>()
    const start: number = Math.max(0, previousPages.length - MAX_CONSISTENCY_PREVIOUS_PAGES)
    for (let pageIndex: number = start; pageIndex < previousPages.length; pageIndex++) {
      const page: ComicPageDocument = previousPages[pageIndex]
      if (ComicTranslationReviewService.documentHasPageLevelReviewSignal(page)) {
        continue
      }
      const blockCount: number = Math.min(page.blocks.length, MAX_CONSISTENCY_BLOCKS_PER_PAGE)
      for (let blockIndex: number = 0; blockIndex < blockCount; blockIndex++) {
        const block: ComicTextBlock = page.blocks[blockIndex]
        if (ComicTranslationReviewService.blockNeedsReview(page, block.blockId)) {
          continue
        }
        const source: string = ComicTranslationConsistencyService.sourceKey(block)
        const translated: string = ComicTranslationConsistencyService.normalizedText(
          block.translatedText,
        )
        if (source.length === 0 || translated.length === 0) {
          continue
        }
        let variants: Set<string> | undefined = translations.get(source)
        if (variants === undefined) {
          variants = new Set<string>()
          translations.set(source, variants)
        }
        variants.add(translated)
      }
    }
    return translations
  }

  private static sourceKey(block: ComicTextBlock): string {
    const normalized: string = ComicTranslationConsistencyService.normalizedText(
      block.normalizedSourceText,
    )
    return normalized.length > 0
      ? normalized
      : ComicTranslationConsistencyService.normalizedText(block.sourceText)
  }

  private static normalizedText(value: string | null | undefined): string {
    if (typeof value !== 'string') {
      return ''
    }
    return value.trim().replace(/\s+/g, ' ')
  }

  private static hasDifferentTranslation(
    variants: Set<string> | undefined,
    translated: string,
  ): boolean {
    if (variants === undefined || variants.size === 0) {
      return false
    }
    let different: boolean = false
    variants.forEach((candidate: string): void => {
      if (candidate !== translated) {
        different = true
      }
    })
    return different
  }
}

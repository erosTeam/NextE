import {
  ComicPageDocument,
  ComicRenderState,
  ComicTranslationOrigin,
  ComicTranslationState,
} from '../model/ComicTranslation'
import { ComicTranslationBatch } from '../model/ComicVisualTranslation'
import {
  ComicPageAnalysisContext,
  ComicPreviousPageContext,
} from './ComicPageAnalyzer'
import { ComicPreviousPageContextPolicy } from './ComicPreviousPageContextPolicy'
import { ComicTranslationMemoryService } from './ComicTranslationMemoryService'
import { ComicTranslationReviewService } from './ComicTranslationReviewService'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'

/** Shared context preparation used by both legacy analysis and the visual staged pipeline. */
export class ComicTranslationContextService {
  static prepare(
    source: ComicPageAnalysisContext,
    previousDocuments: ComicPageDocument[],
    currentPageIndex: number,
    previousPageLimit: number,
  ): ComicPageAnalysisContext {
    const context: ComicPageAnalysisContext = source.copy()
    const recent: ComicPageDocument[] = ComicTranslationContextService.recentDocuments(
      previousDocuments,
      previousPageLimit,
    )
    ComicTranslationContextService.mergePreviousContext(context, recent, currentPageIndex)
    ComicTranslationContextService.fillRollingSummary(context, currentPageIndex)
    context.translationMemory = ComicTranslationMemoryService.merge(
      context.translationMemory,
      previousDocuments,
    )
    return context
  }

  static applyTranslationBatch(
    document: ComicPageDocument,
    batch: ComicTranslationBatch,
    pageSummary: string,
    fallbackSummary: string,
  ): ComicPageDocument {
    ComicVisualTranslationContract.validateTranslationBatch(document, batch)
    const translatedById: Map<string, string> = new Map<string, string>()
    for (let index: number = 0; index < batch.blocks.length; index++) {
      translatedById.set(batch.blocks[index].blockId, batch.blocks[index].translatedText)
    }
    const output: ComicPageDocument = document.copy()
    for (let index: number = 0; index < output.blocks.length; index++) {
      const translatedText: string | undefined = translatedById.get(output.blocks[index].blockId)
      if (translatedText === undefined) {
        throw new Error('Comic translated document is missing a block')
      }
      output.blocks[index].translatedText = translatedText
      output.blocks[index].translationOrigin = ComicTranslationOrigin.TEXT
      output.blocks[index].translationRevision = batch.translationRevision
    }
    output.translationRevision = batch.translationRevision
    output.translationState = ComicTranslationState.PROVISIONAL
    output.renderState = ComicRenderState.UNAVAILABLE
    output.pageSummary = pageSummary.trim().length > 0
      ? pageSummary.trim()
      : fallbackSummary.trim()
    return output
  }

  private static recentDocuments(
    documents: ComicPageDocument[],
    limit: number,
  ): ComicPageDocument[] {
    const reversed: ComicPageDocument[] = []
    const boundedLimit: number = Math.max(0, limit)
    for (let index: number = documents.length - 1;
      index >= 0 && reversed.length < boundedLimit; index--) {
      if (ComicTranslationReviewService.documentHasPageLevelReviewSignal(documents[index])) {
        continue
      }
      reversed.push(documents[index])
    }
    const selected: ComicPageDocument[] = []
    for (let index: number = reversed.length - 1; index >= 0; index--) {
      selected.push(reversed[index])
    }
    return selected
  }

  private static mergePreviousContext(
    context: ComicPageAnalysisContext,
    documents: ComicPageDocument[],
    currentPageIndex: number,
  ): void {
    const combined: ComicPreviousPageContext[] = []
    for (let documentIndex: number = 0; documentIndex < documents.length; documentIndex++) {
      combined.push(ComicTranslationContextService.previousContext(documents[documentIndex]))
    }
    for (let contextIndex: number = 0; contextIndex < context.previousPages.length; contextIndex++) {
      combined.push(context.previousPages[contextIndex].copy())
    }
    context.previousPages = ComicPreviousPageContextPolicy.normalize(combined, currentPageIndex)
  }

  private static previousContext(document: ComicPageDocument): ComicPreviousPageContext {
    const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
    previous.pageIndex = document.pageIndex
    const source: string[] = []
    const translated: string[] = []
    for (let index: number = 0; index < document.blocks.length; index++) {
      if (ComicTranslationReviewService.blockNeedsReview(
        document,
        document.blocks[index].blockId,
      )) {
        continue
      }
      const sourceText: string = document.blocks[index].sourceText.trim()
      const translatedText: string = document.blocks[index].translatedText.trim()
      if (sourceText.length > 0) {
        source.push(sourceText)
      }
      if (translatedText.length > 0) {
        translated.push(translatedText)
      }
    }
    previous.sourceText = source.join('\n')
    previous.translatedText = translated.join('\n')
    previous.pageSummary = document.pageSummary
    return previous
  }

  private static fillRollingSummary(
    context: ComicPageAnalysisContext,
    currentPageIndex: number,
  ): void {
    if (context.rollingSummary.trim().length > 0) {
      return
    }
    let latestPageIndex: number = -1
    let latestSummary: string = ''
    for (let index: number = 0; index < context.previousPages.length; index++) {
      const page: ComicPreviousPageContext = context.previousPages[index]
      const summary: string = page.pageSummary.trim()
      if (page.pageIndex >= 0 && page.pageIndex < currentPageIndex &&
        page.pageIndex > latestPageIndex && summary.length > 0) {
        latestPageIndex = page.pageIndex
        latestSummary = summary
      }
    }
    context.rollingSummary = latestSummary
  }
}

import { ComicPageDocument, ComicTextBlock } from '../model/ComicTranslation'
import {
  MAX_COMIC_TRANSLATION_MEMORY_ENTRIES,
  MAX_COMIC_TRANSLATION_MEMORY_SOURCE_CHARS,
  MAX_COMIC_TRANSLATION_MEMORY_TARGET_CHARS,
  ComicTranslationMemoryEntry,
} from './ComicPageAnalyzer'

const MAX_TRANSLATION_MEMORY_PREVIOUS_PAGES: number = 32
const MAX_TRANSLATION_MEMORY_BLOCKS_PER_PAGE: number = 512

class ComicTranslationMemoryCandidate {
  sourceText: string = ''
  translatedText: string = ''
  firstSeenPageIndex: number = Number.MAX_SAFE_INTEGER
  lastSeenPageIndex: number = -1
  pageIndexes: Set<number> = new Set<number>()
  conflicted: boolean = false
}

/** Builds regenerable exact-match memory without claiming that whole blocks are glossary terms. */
export class ComicTranslationMemoryService {
  static merge(
    supplied: ComicTranslationMemoryEntry[],
    previousPages: ComicPageDocument[],
  ): ComicTranslationMemoryEntry[] {
    const merged: ComicTranslationMemoryEntry[] = []
    const sources: Set<string> = new Set<string>()
    const suppliedCount: number = Math.min(
      supplied.length,
      MAX_COMIC_TRANSLATION_MEMORY_ENTRIES,
    )
    for (let index: number = 0; index < suppliedCount; index++) {
      const sourceKey: string = ComicTranslationMemoryService.normalizedText(
        supplied[index].sourceText,
      )
      if (sourceKey.length === 0 || sources.has(sourceKey)) {
        continue
      }
      merged.push(supplied[index].copy())
      sources.add(sourceKey)
    }
    const generated: ComicTranslationMemoryEntry[] =
      ComicTranslationMemoryService.build(previousPages)
    for (let index: number = 0; index < generated.length; index++) {
      if (merged.length >= MAX_COMIC_TRANSLATION_MEMORY_ENTRIES) {
        break
      }
      const sourceKey: string = ComicTranslationMemoryService.normalizedText(
        generated[index].sourceText,
      )
      if (sources.has(sourceKey)) {
        continue
      }
      merged.push(generated[index])
      sources.add(sourceKey)
    }
    return merged
  }

  static build(previousPages: ComicPageDocument[]): ComicTranslationMemoryEntry[] {
    const candidates: Map<string, ComicTranslationMemoryCandidate> =
      new Map<string, ComicTranslationMemoryCandidate>()
    const start: number = Math.max(
      0,
      previousPages.length - MAX_TRANSLATION_MEMORY_PREVIOUS_PAGES,
    )
    for (let pageIndex: number = start; pageIndex < previousPages.length; pageIndex++) {
      const page: ComicPageDocument = previousPages[pageIndex]
      if (!Number.isFinite(page.pageIndex) || page.pageIndex < 0 ||
        page.pageIndex > Number.MAX_SAFE_INTEGER || Math.floor(page.pageIndex) !== page.pageIndex) {
        continue
      }
      const blockCount: number = Math.min(
        page.blocks.length,
        MAX_TRANSLATION_MEMORY_BLOCKS_PER_PAGE,
      )
      for (let blockIndex: number = 0; blockIndex < blockCount; blockIndex++) {
        ComicTranslationMemoryService.collect(candidates, page, page.blocks[blockIndex])
      }
    }
    const stable: ComicTranslationMemoryCandidate[] = []
    candidates.forEach((candidate: ComicTranslationMemoryCandidate): void => {
      if (!candidate.conflicted && candidate.pageIndexes.size >= 2) {
        stable.push(candidate)
      }
    })
    stable.sort(
      (left: ComicTranslationMemoryCandidate, right: ComicTranslationMemoryCandidate): number => {
        if (left.lastSeenPageIndex !== right.lastSeenPageIndex) {
          return right.lastSeenPageIndex - left.lastSeenPageIndex
        }
        if (left.pageIndexes.size !== right.pageIndexes.size) {
          return right.pageIndexes.size - left.pageIndexes.size
        }
        if (left.sourceText < right.sourceText) {
          return -1
        }
        return left.sourceText > right.sourceText ? 1 : 0
      },
    )
    const entries: ComicTranslationMemoryEntry[] = []
    const count: number = Math.min(stable.length, MAX_COMIC_TRANSLATION_MEMORY_ENTRIES)
    for (let index: number = 0; index < count; index++) {
      const entry: ComicTranslationMemoryEntry = new ComicTranslationMemoryEntry()
      entry.sourceText = stable[index].sourceText
      entry.translatedText = stable[index].translatedText
      entry.firstSeenPageIndex = stable[index].firstSeenPageIndex
      entry.occurrenceCount = stable[index].pageIndexes.size
      entries.push(entry)
    }
    return entries
  }

  private static collect(
    candidates: Map<string, ComicTranslationMemoryCandidate>,
    page: ComicPageDocument,
    block: ComicTextBlock,
  ): void {
    const normalizedSource: string = ComicTranslationMemoryService.normalizedText(
      block.normalizedSourceText,
    )
    const source: string = normalizedSource.length > 0
      ? normalizedSource
      : ComicTranslationMemoryService.normalizedText(block.sourceText)
    const translated: string = ComicTranslationMemoryService.normalizedText(block.translatedText)
    if (source.length === 0 || translated.length === 0 ||
      source.length > MAX_COMIC_TRANSLATION_MEMORY_SOURCE_CHARS ||
      translated.length > MAX_COMIC_TRANSLATION_MEMORY_TARGET_CHARS) {
      return
    }
    let candidate: ComicTranslationMemoryCandidate | undefined = candidates.get(source)
    if (candidate === undefined) {
      candidate = new ComicTranslationMemoryCandidate()
      candidate.sourceText = source
      candidate.translatedText = translated
      candidates.set(source, candidate)
    } else if (candidate.translatedText !== translated) {
      candidate.conflicted = true
    }
    candidate.pageIndexes.add(page.pageIndex)
    candidate.firstSeenPageIndex = Math.min(candidate.firstSeenPageIndex, page.pageIndex)
    candidate.lastSeenPageIndex = Math.max(candidate.lastSeenPageIndex, page.pageIndex)
  }

  private static normalizedText(value: string | null | undefined): string {
    if (typeof value !== 'string') {
      return ''
    }
    return value.trim().replace(/\s+/g, ' ')
  }
}

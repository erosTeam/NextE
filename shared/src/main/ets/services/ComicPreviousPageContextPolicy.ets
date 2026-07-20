import { ComicPreviousPageContext } from './ComicPageAnalyzer'

export const MAX_COMIC_PREVIOUS_PAGE_CONTEXT: number = 2

/** Keeps optional cross-page input aligned with its predecessor-only meaning. */
export class ComicPreviousPageContextPolicy {
  static normalize(
    pages: ComicPreviousPageContext[],
    currentPageIndex: number,
  ): ComicPreviousPageContext[] {
    const selected: Map<number, ComicPreviousPageContext> = new Map()
    for (let index: number = 0; index < pages.length; index++) {
      const page: ComicPreviousPageContext = pages[index]
      if (page.pageIndex < 0 || Math.floor(page.pageIndex) !== page.pageIndex ||
        page.pageIndex >= currentPageIndex) {
        continue
      }
      if (selected.has(page.pageIndex)) {
        selected.set(page.pageIndex, page.copy())
        continue
      }
      if (selected.size < MAX_COMIC_PREVIOUS_PAGE_CONTEXT) {
        selected.set(page.pageIndex, page.copy())
        continue
      }
      let oldestPageIndex: number = Number.MAX_SAFE_INTEGER
      selected.forEach((_value: ComicPreviousPageContext, selectedPageIndex: number): void => {
        if (selectedPageIndex < oldestPageIndex) {
          oldestPageIndex = selectedPageIndex
        }
      })
      if (page.pageIndex > oldestPageIndex) {
        selected.delete(oldestPageIndex)
        selected.set(page.pageIndex, page.copy())
      }
    }
    const pageIndexes: number[] = []
    selected.forEach((_value: ComicPreviousPageContext, pageIndex: number): void => {
      pageIndexes.push(pageIndex)
    })
    pageIndexes.sort((left: number, right: number): number => left - right)
    const normalized: ComicPreviousPageContext[] = []
    for (let index: number = 0; index < pageIndexes.length; index++) {
      const page: ComicPreviousPageContext | undefined = selected.get(pageIndexes[index])
      if (page !== undefined) {
        normalized.push(page.copy())
      }
    }
    return normalized
  }
}

import {
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_GALLERY,
  SEARCH_SCOPE_WATCHED,
} from 'shared'

/**
 * Per-Search-page request target. Scope is route/session state rather than a persisted global filter:
 * stacked Search pages must not change each other's endpoint, and a favorites entry must still be
 * able to switch to gallery or watched search from the filter sheet.
 */
@ObservedV2
export class SearchSessionState {
  @Trace scope: string = SEARCH_SCOPE_GALLERY
  @Trace favoriteFavcat: string = 'a'
  @Trace applySeq: number = 0

  setScope(scope: string): void {
    const next: string = SearchSessionState.sanitizeScope(scope)
    if (this.scope === next) {
      return
    }
    this.scope = next
    this.applySeq = this.applySeq + 1
  }

  setFavoriteFavcat(favcat: string): void {
    const next: string = favcat.length > 0 ? favcat : 'a'
    if (this.favoriteFavcat === next) {
      return
    }
    this.favoriteFavcat = next
    this.applySeq = this.applySeq + 1
  }

  reset(): void {
    this.scope = SEARCH_SCOPE_GALLERY
    this.favoriteFavcat = 'a'
    this.applySeq = this.applySeq + 1
  }

  seed(scope: string, favoriteFavcat: string = 'a'): void {
    this.scope = SearchSessionState.sanitizeScope(scope)
    this.favoriteFavcat = favoriteFavcat.length > 0 ? favoriteFavcat : 'a'
  }

  private static sanitizeScope(scope: string): string {
    if (scope === SEARCH_SCOPE_WATCHED || scope === SEARCH_SCOPE_FAVORITE) {
      return scope
    }
    return SEARCH_SCOPE_GALLERY
  }
}

/**
 * Route params for the single shared adaptive Search page. `searchType` '' = normal gallery search;
 * 'favorite' = favorites.php f_search, defaulting to all favorites (`favcat='a'`). Mirrors eros_fe's
 * ONE search page carrying a SearchType: the favorites title-bar magnifier seeds favorite scope while
 * the filter sheet owns any explicit single-folder choice. A plain gallery-search open passes no params
 * (searchType '' → the normal gallery path).
 */
export class SearchPageParams {
  searchType: string = ''
  favcat: string = 'a'
  initialQuery: string = ''
  focusOnAppear: boolean = true
  sessionId: string = ''

  constructor(
    searchType: string = '',
    favcat: string = 'a',
    initialQuery: string = '',
    focusOnAppear: boolean = true,
    sessionId: string = '',
  ) {
    this.searchType = searchType
    this.favcat = favcat
    this.initialQuery = initialQuery
    this.focusOnAppear = focusOnAppear
    this.sessionId = sessionId
  }
}

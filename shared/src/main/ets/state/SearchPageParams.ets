/**
 * Route params for the single shared adaptive Search page. `searchType` '' = normal gallery search;
 * 'favorite' = favorites.php f_search scoped to `favcat` ('a' = all favorites). Mirrors eros_fe's ONE
 * search page carrying a SearchType (search_page_controller.dart:26): the favorites title-bar magnifier
 * pushes 'Search' with searchType 'favorite' + the last-shown favcat (goSearchPage(searchType:favorite),
 * navigator_util.dart:76-106), instead of a bespoke favorites search box. A plain gallery-search open
 * passes no params (searchType '' → the normal gallery path).
 */
export class SearchPageParams {
  searchType: string = ''
  favcat: string = 'a'

  constructor(searchType: string = '', favcat: string = 'a') {
    this.searchType = searchType
    this.favcat = favcat
  }
}

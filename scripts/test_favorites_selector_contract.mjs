#!/usr/bin/env node
/**
 * Contract for the Favorites favcat selector page.
 *
 * Grounding:
 * - eros_fe/lib/pages/tab/view/tabbar/favorite_tabbar_page.dart exposes a bars button from the
 *   favorites favcat bar.
 * - eros_fe/lib/pages/tab/view/favorite_sel_page.dart renders a full favorite-category selector with
 *   colored hearts, counts, and chevrons.
 * - NextE keeps quick switching in the pinned favcat chip bar, while the selector is the overview
 *   surface for long names/counts. It only changes the selected favcat; favorite writes are out of
 *   scope.
 *
 * Run: node scripts/test_favorites_selector_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const index = read('entry/src/main/ets/pages/Index.ets')
const userIndex = read('feature/user/src/main/ets/Index.ets')
const page = read('feature/user/src/main/ets/pages/FavoriteSelectorPage.ets')
const favState = read('shared/src/main/ets/state/FavSelectionState.ets')
const feTabbar = read('../eros_fe/lib/pages/tab/view/tabbar/favorite_tabbar_page.dart')
const feSelector = read('../eros_fe/lib/pages/tab/view/favorite_sel_page.dart')
const locales = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok('FE favorites tabbar exposes a bars selector entry',
  /FontAwesomeIcons\.bars[\s\S]*EHRoutes\.selFavorite[\s\S]*jumpToPage\(index\)/.test(feTabbar))
ok('FE selector renders favcat rows with colored hearts and counts',
  /CupertinoIcons\.heart_fill[\s\S]*ThemeColors\.favColor\[_favcat\.favId\][\s\S]*additionalInfo: Text/.test(feSelector))

ok('Feature barrel exports FavoriteSelectorPage',
  /export \{ FavoriteSelectorPage \} from '\.\/pages\/FavoriteSelectorPage'/.test(userIndex))
ok('Index imports FavoriteSelectorPage',
  /import \{ FavoriteSelectorPage, FavoritesPage, MyTagsPage, ViewedHistoryPage \} from 'user'/.test(index))
ok('Favorites title menu includes selector title action',
  /private favoritesMenu\(\): Record<string, Object> \{[\s\S]*favorites_selector_title[\s\S]*this\.openFavoriteSelector\(\)/.test(index))
ok('Favorites title menu exposes search order and selector actions',
  /const items: Record<string, Object>\[\] = \[[\s\S]*searchInner[\s\S]*orderInner[\s\S]*selectorInner[\s\S]*maxCount': 3/.test(index))
ok('Logged-out Favorites title menu exposes local selector plus local browsing utility only',
  /private localFavoritesMenu\(\): Record<string, Object> \{[\s\S]*favorites_selector_title[\s\S]*this\.openFavoriteSelector\(\)[\s\S]*this\.backToTopMenuItem\(\)[\s\S]*maxCount': 2/.test(index) &&
  !/private localFavoritesMenu\(\): Record<string, Object> \{[\s\S]*this\.openFavoriteSearch\(\)/.test(index) &&
  !/private localFavoritesMenu\(\): Record<string, Object> \{[\s\S]*FavSelectionBridge\.publishOpenOrderMenu\(\)/.test(index) &&
  /if \(this\.auth\.isLogin\) \{[\s\S]*content\['menu'\] = this\.favoritesMenu\(\)[\s\S]*\} else \{[\s\S]*content\['menu'\] = this\.localFavoritesMenu\(\)/.test(index))
ok('Index registers FavoriteSelector route',
  /name === 'FavoriteSelector'[\s\S]*FavoriteSelectorPage\(\)/.test(index))

ok('FavSelectionState still seeds the 10 network slots as placeholders',
  /for \(let i = 0; i < 10; i\+\+\) \{[\s\S]*new Favcat\(`\$\{i\}`, `Favorites \$\{i\}`, 0, true\)/.test(favState))
ok('Selector page uses HDS destination and secondary list scaffold',
  /HdsNavDestination\(\)[\s\S]*SecondaryListScaffold/.test(page))
ok('Selector page renders logged-out local-only rows and logged-in All plus remote plus local rows',
  /const local: Favcat = new Favcat\('l', AppStrings\.get\('favorites_local'\), this\.localFav\.count\(\)\)/.test(page) &&
  /if \(!this\.auth\.isLogin\) \{[\s\S]*return \[local\]/.test(page) &&
  /const items: Favcat\[\] = \[new Favcat\('a', AppStrings\.get\('favorites_all'\), this\.fav\.remoteTotalCount\(\)\)\][\s\S]*this\.fav\.favList\.forEach[\s\S]*items\.push\(local\)/.test(page))
ok('Selector rows use grouped native list rows',
  /GroupedListSection\(\)[\s\S]*ConciseListRow/.test(page))
ok('Selector row uses semantic favcat heart color only for the identity icon',
  /EhConstants\.favCatColor\(favId\)/.test(page) &&
  /private FavcatPrefix\(favId: string\)[\s\S]*sys\.symbol\.heart_fill[\s\S]*this\.colorFor\(favId\)/.test(page) &&
  !/secondaryColor: this\.colorFor\(fc\.favId\)/.test(page))
ok('Current favcat is visibly marked as current, not as a yes boolean',
  /private isSelected\(fc: Favcat\): boolean \{[\s\S]*if \(!this\.auth\.isLogin\) \{[\s\S]*return fc\.favId === 'l'[\s\S]*this\.fav\.selectedFavcat === fc\.favId/.test(page) &&
  /this\.isSelected\(fc\)[\s\S]*sys\.symbol\.checkmark/.test(page) &&
  !/primaryColor: this\.isSelected\(fc\) \? ThemeConstants\.BRAND_PRIMARY : undefined/.test(page))
ok('Selector current marker and counts are secondary metadata, not favcat-colored text',
  /AppStrings\.get\('detail_remote_favorite_current_badge'\)/.test(page) &&
  !/AppStrings\.get\('common_yes'\)/.test(page) &&
  /private FavcatSuffix\(fc: Favcat\)[\s\S]*fontColor\(\$r\('sys\.color\.font_secondary'\)\)/.test(page) &&
  /suffixBuilderParam: \(\) =>/.test(page))
ok('Selecting a favcat writes the persisted subtab preference and pops the route',
  /SubtabSelectionSettings/.test(page) &&
  /private async selectFavcat\(favId: string\): Promise<void> \{[\s\S]*await SubtabSelectionSettings\.setFavoritesFavcat\([\s\S]*this\.ctx\(\),[\s\S]*favId\.length > 0 \? favId : 'a',[\s\S]*this\.auth\.isLogin,[\s\S]*\)[\s\S]*this\.stack\.pop\(\)/.test(page) &&
  !/this\.fav\.selectedFavcat = favId/.test(page))
ok('Selector page does not introduce favorite write calls',
  !/galleryAddFavorite|gallerypopups|setusertag|favdel|addFavorite/.test(page))

for (const file of locales) {
  ok(`${file} defines favorites_selector_title`, /"name": "favorites_selector_title"/.test(read(file)))
}

console.log(`✓ favorites selector contract: ${passed} assertions passed`)

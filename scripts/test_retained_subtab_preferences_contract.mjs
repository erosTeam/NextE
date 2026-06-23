#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8')

function fail(message) {
  console.error(`retained subtab preference contract failed: ${message}`)
  process.exit(1)
}

function ok(message, condition) {
  if (!condition) {
    fail(message)
  }
}

const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
const settings = read('shared/src/main/ets/settings/SubtabSelectionSettings.ets')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const index = read('shared/src/main/ets/Index.ets')
const home = read('feature/home/src/main/ets/pages/HomePage.ets')
const toplist = read('feature/home/src/main/ets/pages/ToplistPage.ets')
const favorites = read('feature/user/src/main/ets/pages/FavoritesPage.ets')
const homeBar = read('entry/src/main/ets/components/HomeSourceBar.ets')
const toplistBar = read('entry/src/main/ets/components/ToplistPeriodBar.ets')
const favcatBar = read('entry/src/main/ets/components/FavcatBar.ets')
const host = read('shared/src/main/ets/components/RetainedSubtabHost.ets')

ok('StorageKeys owns three retained subtab preference keys',
  /HOME_SOURCE: string = 'subtab\.homeSource'/.test(keys) &&
    /FAVORITES_FAVCAT: string = 'subtab\.favoritesFavcat'/.test(keys) &&
    /TOPLIST_TL: string = 'subtab\.toplistTl'/.test(keys))

ok('SubtabSelectionSettings restores Home source, Favorites favcat, and Toplist period into V2 state',
  /class SubtabSelectionSettings/.test(settings) &&
    /static async restore\(context: common\.UIAbilityContext\): Promise<void>/.test(settings) &&
    /StorageKeys\.HOME_SOURCE/.test(settings) &&
    /StorageKeys\.FAVORITES_FAVCAT/.test(settings) &&
    /StorageKeys\.TOPLIST_TL/.test(settings) &&
    /connectHomeSource\(\)[\s\S]*home\.source = homeSource[\s\S]*home\.toplistTl = toplistTl/.test(settings) &&
    /connectFavSelection\(\)\.selectedFavcat = favcat/.test(settings))

ok('Subtab restore is part of startup bootstrap and exported for pages',
  /SubtabSelectionSettings\.restore\(context\)/.test(bootstrap) &&
    /export \{ SubtabSelectionSettings \} from '.\/settings\/SubtabSelectionSettings'/.test(index))

ok('Home source selection saves through the preference writer, including logout fallback',
  /SubtabSelectionSettings\.setHomeSource\(this\.ctx\(\), key, this\.auth\.isLogin\)/.test(home) &&
    /onLoginChange\(\): void[\s\S]*SubtabSelectionSettings\.setHomeSource\(this\.ctx\(\), '', false\)/.test(home))

ok('Toplist period selection saves through the preference writer',
  /SubtabSelectionSettings\.setToplistTl\(this\.ctx\(\), Number\(key\)\)/.test(toplist))

ok('Favorites favcat selection saves through the preference writer',
  /SubtabSelectionSettings\.setFavoritesFavcat\(this\.ctx\(\), key, this\.auth\.isLogin\)/.test(favorites))

ok('Pinned selector bars save through the same preference writer instead of direct V2-only mutation',
  /SubtabSelectionSettings\.setHomeSource\(this\.ctx\(\), items\[index\]\.key, this\.auth\.isLogin\)/.test(homeBar) &&
    !/this\.home\.source = items\[index\]\.key/.test(homeBar) &&
    /SubtabSelectionSettings\.setToplistTl\(this\.ctx\(\), PERIOD_TLS\[index\]\)/.test(toplistBar) &&
    !/this\.home\.toplistTl = PERIOD_TLS\[index\]/.test(toplistBar) &&
    /SubtabSelectionSettings\.setFavoritesFavcat\(this\.ctx\(\), items\[index\]\.key, this\.auth\.isLogin\)/.test(favcatBar) &&
    !/this\.fav\.selectedFavcat = items\[index\]\.key/.test(favcatBar))

ok('Preference writer clamps unavailable sub-tabs instead of restoring invalid selections',
  /normalizeHomeSource\(source: string, isLogin: boolean\)/.test(settings) &&
    /source === 'watched' && isLogin/.test(settings) &&
    /normalizeFavcat\(favcat: string, isLogin: boolean\)/.test(settings) &&
    /if \(!isLogin\) \{[\s\S]*return FAV_LOCAL/.test(settings) &&
    /normalizeToplistTl\(tl: number\)/.test(settings) &&
    /tl === 11 \|\| tl === 12 \|\| tl === 13 \|\| tl === 15/.test(settings))

ok('RetainedSubtabHost ignores a spurious startup onChange that disagrees with the restored tab',
  /private ignoreStartupSelectionChange: boolean = false/.test(host) &&
    /const restoredIndex: number = this\.activeIndex\(\)[\s\S]*this\.ignoreStartupSelectionChange = true/.test(host) &&
    /\.onChange\(\(i: number\) => \{[\s\S]*if \(this\.ignoreStartupSelectionChange\) \{[\s\S]*this\.ignoreStartupSelectionChange = false[\s\S]*const expectedIndex: number = this\.activeIndex\(\)[\s\S]*if \(i !== expectedIndex\) \{[\s\S]*this\.onVisualIndex\(expectedIndex\)[\s\S]*return/.test(host))

console.log('✓ retained subtab preference contract passed')

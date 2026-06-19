#!/usr/bin/env node
/**
 * Contract: list/grid gallery tag chips are secondary search affordances.
 *
 * Detail-page tags already publish a search query; list and grid cards must keep the same user
 * mental model without changing the primary card tap-to-detail action.
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const ok = (name, pass) => {
  if (!pass) {
    console.error(`FAIL ${name}`)
    process.exitCode = 1
  } else {
    console.log(`OK ${name}`)
  }
}

const list = read('shared/src/main/ets/components/GalleryCard.ets')
const grid = read('shared/src/main/ets/components/GalleryGridCard.ets')
const body = read('feature/home/src/main/ets/components/GalleryListBody.ets')
const fav = read('feature/user/src/main/ets/components/FavcatPage.ets')
const search = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')

for (const [name, src] of [['GalleryCard', list], ['GalleryGridCard', grid]]) {
  ok(`${name} imports search action bus`,
    /import \{ connectSearchAction \} from '\.\.\/state\/SearchActionState'/.test(src))
  ok(`${name} formats raw tag text, quoting multi-word tags`,
    /private queryTagValue\(tag: string\): string \{[\s\S]*tag\.indexOf\(' '\) >= 0[\s\S]*return `"\$\{tag\}"`/.test(src))
  ok(`${name} publishes namespace:formattedTag from raw SimpleTag fields`,
    /connectSearchAction\(\)\.publishQuery\(`\$\{namespace\}:\$\{this\.queryTagValue\(tag\)\}`\)/.test(src))
  ok(`${name} chip click triggers tag search`,
    /\.onClick\(\(\) => \{[\s\S]*this\.searchTag\(t\)[\s\S]*\}\)/.test(src))
  ok(`${name} does not search translated display text`,
    !/publishQuery\([^)]*display\(\)/.test(src) && !/searchTag\(t\.display/.test(src))
}

ok('home list parent still owns primary card detail navigation',
  /GalleryCard\(\{ gallery: g, listContentWidth: this\.listContentWidth \}\)/.test(body) &&
  /\.onClick\(\(\) => \{[\s\S]*this\.openDetail\(g\)[\s\S]*\}\)/.test(body))

ok('favorites list parent still owns primary card detail navigation',
  /GalleryCard\(\{ gallery: g, listContentWidth: this\.listContentWidth \}\)/.test(fav) &&
  /\.onClick\(\(\) => \{[\s\S]*this\.openDetail\(g\)[\s\S]*\}\)/.test(fav))

ok('search results parent still owns primary card detail navigation',
  /GalleryCard\(\{ gallery: g, listContentWidth: this\.listContentWidth \}\)/.test(search) &&
  /\.onClick\(\(\) => \{[\s\S]*this\.stack\.pushPathByName\(\s*'GalleryDetail'[\s\S]*new GalleryDetailParams\(/.test(search))

if (process.exitCode) process.exit(process.exitCode)

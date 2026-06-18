#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
let failures = 0

function read(rel) {
  return readFileSync(join(ROOT, rel), 'utf8')
}

function ok(condition, message) {
  if (!condition) {
    failures += 1
    console.error(`✗ ${message}`)
  } else {
    console.log(`✓ ${message}`)
  }
}

const params = read('shared/src/main/ets/model/RouteParams.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const listBody = read('feature/home/src/main/ets/components/GalleryListBody.ets')
const favcat = read('feature/user/src/main/ets/components/FavcatPage.ets')
const search = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')

ok(/imgWidth:\s*number\s*=\s*0/.test(params), 'GalleryDetailParams carries seed imgWidth')
ok(/imgHeight:\s*number\s*=\s*0/.test(params), 'GalleryDetailParams carries seed imgHeight')
ok(/this\.imgWidth\s*=\s*imgWidth/.test(params), 'GalleryDetailParams constructor stores imgWidth')
ok(/this\.imgHeight\s*=\s*imgHeight/.test(params), 'GalleryDetailParams constructor stores imgHeight')

ok(/seed\.imgWidth\s*=\s*p\.imgWidth/.test(detail), 'GalleryDetailPage seeds header imgWidth before load')
ok(/seed\.imgHeight\s*=\s*p\.imgHeight/.test(detail), 'GalleryDetailPage seeds header imgHeight before load')
ok(/seed\.thumbUrl\s*=\s*p\.thumbUrl[\s\S]*seed\.imgWidth\s*=\s*p\.imgWidth[\s\S]*seed\.imgHeight\s*=\s*p\.imgHeight/.test(detail), 'detail seed keeps thumb URL and dimensions together')

const fullSeedCall =
  /new GalleryDetailParams\(\s*g\.gid,\s*g\.token,\s*g\.thumbUrl,\s*g\.title\(\),\s*g\.fileCount,\s*g\.imgWidth,\s*g\.imgHeight,?\s*\)/

ok(fullSeedCall.test(listBody), 'Home/Toplist gallery body passes cover dimensions to detail')
ok(fullSeedCall.test(favcat), 'Favorites gallery body passes cover dimensions to detail')
ok((search.match(/g\.imgWidth,\s*g\.imgHeight/g) || []).length >= 2, 'Search gallery results pass cover dimensions to detail')

if (failures > 0) {
  console.error(`\n✗ gallery detail seed cover contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ gallery detail seed cover contract passed')

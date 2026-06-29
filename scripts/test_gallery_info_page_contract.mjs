#!/usr/bin/env node
/**
 * Contract for the gallery detail -> full metadata page lane.
 *
 * Run: node scripts/test_gallery_info_page_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const files = {
  routeParams: 'shared/src/main/ets/model/RouteParams.ets',
  sharedIndex: 'shared/src/main/ets/Index.ets',
  galleryIndex: 'feature/gallery/src/main/ets/Index.ets',
  detail: 'feature/gallery/src/main/ets/pages/GalleryDetailPage.ets',
  infoBar: 'feature/gallery/src/main/ets/components/GalleryInfoBar.ets',
  infoPage: 'feature/gallery/src/main/ets/pages/GalleryInfoPage.ets',
  entry: 'entry/src/main/ets/pages/Index.ets',
}

const src = {}
for (const key of Object.keys(files)) {
  src[key] = read(files[key])
}

let failures = 0
function ok(cond, label, detail = '') {
  if (!cond) {
    failures++
    console.error(`  ✗ ${label}`)
    if (detail) console.error(`    ${detail}`)
  }
}

console.log('— gallery info page contract —')

ok(/export class GalleryInfoParams/.test(src.routeParams), 'GalleryInfoParams route param exists', files.routeParams)
ok(/gallery:\s*EhGallery/.test(src.routeParams), 'GalleryInfoParams carries an EhGallery snapshot')
ok(/isEx:\s*boolean/.test(src.routeParams), 'GalleryInfoParams carries site mode for URL reconstruction')
ok(/GalleryInfoParams/.test(src.sharedIndex), 'shared barrel exports GalleryInfoParams')

ok(/export \{ GalleryInfoPage \}/.test(src.galleryIndex), 'gallery barrel exports GalleryInfoPage')
ok(/import \{ GalleryDetailPage, GalleryInfoPage,/.test(src.entry), 'entry imports GalleryInfoPage from gallery barrel')
ok(/name === 'GalleryInfo'[\s\S]*?GalleryInfoPage\(\)/.test(src.entry), 'entry router registers GalleryInfo destination')

ok(/private openGalleryInfo\(\): void/.test(src.detail), 'detail page has openGalleryInfo()')
ok(/new GalleryInfoParams\(this\.vm\.gallery\.copy\(\), connectSiteMode\(\)\.isEx, this\.navTitle\(\)\)/.test(src.detail), 'detail passes current copied gallery snapshot, site mode, and title')
ok(/GalleryInfoBar\(\{[\s\S]*?onOpenInfo:[\s\S]*?this\.openGalleryInfo\(\)/.test(src.detail), 'GalleryInfoBar receives an open-info action')

ok(/@Event onOpenInfo\?: \(\) => void/.test(src.infoBar), 'InfoBar exposes optional onOpenInfo event')
ok(/sys\.symbol\.chevron_right/.test(src.infoBar), 'InfoBar shows a visible navigation affordance when clickable')
ok(/\.onClick\(\(\) => \{[\s\S]*?this\.onOpenInfo\(\)/.test(src.infoBar), 'InfoBar click opens the full info page')

const expectedFields = [
  'detail_info_gid',
  'detail_info_token',
  'detail_info_url',
  'detail_info_title',
  'detail_info_jpn_title',
  'detail_info_thumb',
  'detail_info_category',
  'detail_info_uploader',
  'detail_info_posted',
  'detail_info_language',
  'detail_info_pages',
  'detail_info_size',
  'detail_info_visible',
  'detail_info_parent',
  'detail_info_favorite_count',
  'detail_info_favorited',
  'detail_info_favorite',
  'detail_info_rating_count',
  'detail_info_rating',
  'detail_info_rating_fallback',
  'detail_info_torrents',
  'detail_info_archiver',
]
for (const key of expectedFields) {
  ok(src.infoPage.includes(`app.string.${key}`), `GalleryInfoPage renders ${key}`)
}
ok(/EhConstants\.EX_BASE_URL/.test(src.infoPage) && /EhConstants\.EH_BASE_URL/.test(src.infoPage), 'GalleryInfoPage reconstructs /g/ URL from site mode')
ok(/common_yes/.test(src.infoPage) && /common_no/.test(src.infoPage), 'GalleryInfoPage localizes boolean favorited value')
ok(/this\.gallery\(\)\.visible/.test(src.infoPage), 'GalleryInfoPage renders EH visible state')
ok(/this\.gallery\(\)\.parentTitle/.test(src.infoPage), 'GalleryInfoPage renders parent display text')
ok(/this\.gallery\(\)\.ratingFallBack\.toFixed\(2\)/.test(src.infoPage), 'GalleryInfoPage renders EH sprite display rating')
ok(/this\.gallery\(\)\.archiverLink/.test(src.infoPage), 'GalleryInfoPage renders archiver URL/token for diagnostics/future archiver flow')

const locales = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]
const requiredKeys = ['detail_info', 'common_yes', 'common_no', ...expectedFields]
for (const locale of locales) {
  const text = read(locale)
  for (const key of requiredKeys) {
    ok(text.includes(`"name": "${key}"`), `${locale} contains ${key}`)
  }
}

if (failures > 0) {
  console.error(`gallery info page contract failed: ${failures} issue(s)`)
  process.exit(1)
}

console.log(`gallery info page contract passed (${requiredKeys.length} keys × ${locales.length} locales)`)

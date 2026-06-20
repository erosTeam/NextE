#!/usr/bin/env node
/**
 * Contract: detail header keeps compact title ellipsis, but users can inspect the full title in an
 * HDS modal sheet without moving read/favorite actions back into the header.
 *
 * Run: node scripts/test_gallery_detail_full_title_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const header = read('feature/gallery/src/main/ets/components/GalleryHeaderCard.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const modal = read('shared/src/main/ets/components/AppModalScaffold.ets')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const grounding = [
  'eros_fe: lib/pages/gallery/view/header.dart GalleryHeader and lib/pages/gallery/view/gallery_info_page.dart Info row titles',
  'primary information: detail header first shows cover, title, alternate title, uploader, and gallery meta',
  'primary action: tap the truncated title to inspect full text; secondary action: existing copy-title menu remains unchanged',
  'scope: add read-only full-title access only; do not reintroduce read/favorite actions into the header or alter Reader/Favorites/Search',
  'Harmony expression: bindSheet plus AppModalScaffold using HDS modal chrome, close-only title action',
]

ok('grounding has five lines', grounding.length === 5)
ok('grounding names concrete eros_fe files',
  grounding[0].includes('header.dart') && grounding[0].includes('gallery_info_page.dart'))
ok('scope excludes unrelated detail actions',
  grounding[3].includes('read/favorite') && grounding[3].includes('Reader/Favorites/Search'))

ok('GalleryHeaderCard exposes a title tap event',
  /@Event\s+onTitleTap:\s*\(\) => void = \(\) => \{\};/.test(header))
ok('title tap target wraps title group only',
  /Column\(\{ space: ThemeConstants\.SPACE_XS \}\) \{[\s\S]*Text\(this\.primaryTitle\(\)\)[\s\S]*if \(this\.secondaryTitle\(\)\.length > 0\)[\s\S]*Text\(this\.secondaryTitle\(\)\)[\s\S]*\}\s*\n\s*\.width\('100%'\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.onTitleTap\(\)/.test(header))
ok('uploader search tap remains separate from title tap',
  /Text\(this\.gallery\.uploader\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.onUploader\(this\.gallery\.uploader\)/.test(header) &&
  !/Text\(this\.gallery\.uploader\)[\s\S]*this\.onTitleTap\(\)/.test(header))
ok('header still keeps compact ellipsis instead of expanding height',
  /maxLines\(this\.titleMaxLines\(\)\)/.test(header) &&
  /TextOverflow\.Ellipsis/.test(header) &&
  /\.height\(COVER_H\)/.test(header))
ok('header does not own read or favorite actions',
  !/openReader|detail_read|detail_favorite|remoteFavorite|localFavorite/i.test(header))

ok('detail page owns full title sheet state and open guard',
  /@Local\s+fullTitleSheetShown:\s*boolean\s*=\s*false/.test(detail) &&
  /private\s+openFullTitleSheet\(\): void \{[\s\S]*this\.fullTitleSheetShown = true/.test(detail))
ok('detail page passes title tap into header',
  /GalleryHeaderCard\(\{[\s\S]*onTitleTap:\s*\(\) => \{[\s\S]*this\.openFullTitleSheet\(\)/.test(detail))
ok('full title sheet uses AppModalScaffold with close-only modal chrome',
  /private\s+FullTitleSheet\(\) \{[\s\S]*AppModalScaffold\(\{[\s\S]*title:\s*\$r\('app\.string\.detail_full_title'\)[\s\S]*showConfirmAction:\s*false[\s\S]*closeAction:\s*\(\) => \{[\s\S]*this\.fullTitleSheetShown = false/.test(detail) &&
  /HdsNavigationTitleMode\.MODAL/.test(modal))
ok('full title sheet shows display and optional alternate title rows',
  /TitleReadBlock\(\$r\('app\.string\.detail_display_title'\), this\.primaryDetailTitle\(\)\)/.test(detail) &&
  /TitleReadBlock\(\$r\('app\.string\.detail_alternate_title'\), this\.secondaryDetailTitle\(\)\)/.test(detail))
ok('full title sheet is bound by the detail page sheet host',
  /\.bindSheet\(\$\$this\.fullTitleSheetShown,\s*this\.FullTitleSheet\(\),\s*\{[\s\S]*detents:\s*\[SheetSize\.LARGE\][\s\S]*showClose:\s*false/.test(detail))
ok('copy-title action remains available in detail menu',
  /detail_copy_title/.test(detail) &&
  /copyTitleInner[\s\S]*this\.copyGalleryTitle\(\)/.test(detail))

for (const locale of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(`${locale} includes full-title strings`,
    /"name": "detail_full_title"/.test(strings) &&
    /"name": "detail_display_title"/.test(strings) &&
    /"name": "detail_alternate_title"/.test(strings))
}

console.log(`✓ gallery detail full-title contract: ${passed} assertions passed`)

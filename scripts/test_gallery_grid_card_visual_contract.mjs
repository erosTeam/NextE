#!/usr/bin/env node
/**
 * Contract: Grid-mode gallery cards are cover-first browsing tiles.
 *
 * eros_fe/lib/pages/item/gallery_item_grid.dart makes the cover the primary visual, overlays language
 * and count/favorite state on the image, then shows title + tags. NextE grid cards must not regress into
 * a small information card dominated by rating/category rows.
 *
 * Run: node scripts/test_gallery_grid_card_visual_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const src = readFileSync(join(ROOT, 'shared/src/main/ets/components/GalleryGridCard.ets'), 'utf8')
const fe = readFileSync(join(ROOT, '../eros_fe/lib/pages/item/gallery_item_grid.dart'), 'utf8')

let failures = 0
let passed = 0

function ok(label, condition) {
  if (condition) {
    passed++
  } else {
    failures++
    console.error(`✗ ${label}`)
  }
}

ok('grounding: eros_fe grid uses a cover-first card',
  /class GalleryItemGrid[\s\S]*final coverHeight = kCoverRatio \* constraints\.maxWidth/.test(fe) &&
    /_CoverImage\([\s\S]*coverImageHeight: coverHeight[\s\S]*coverImageWidth: constraints\.maxWidth/.test(fe))
ok('grounding: eros_fe overlays translated/category and count/favorite state on cover',
  /RotatedCornerDecoration\.withColor[\s\S]*galleryProvider\.translated/.test(fe) &&
    /Positioned\([\s\S]*bottom: 4[\s\S]*right: 4[\s\S]*_buildFavCatIcon\(\)[\s\S]*_buildCount\(\)/.test(fe))
ok('NextE grid card reads usertag signal and renders tag chips',
  /private tagSig: UserTagSignal = connectUserTagSignal\(\)/.test(src) &&
    /@Builder\s+tagChips\(\)[\s\S]*this\.gallery\.simpleTags\.slice\(0, GRID_TAG_LIMIT\)/.test(src))
ok('NextE grid tags reuse the same usertag color semantics as list cards',
  /UserTagStore\.getInstance\(\)\.lookup\(t\.namespace, t\.text\)/.test(src) &&
    /\(t: SimpleTag\) => `\$\{this\.tagSig\.version\}:\$\{t\.namespace\}:\$\{t\.text\}`/.test(src))
ok('NextE grid card overlays language and page/favorite state on the cover',
  /Stack\(\{ alignContent: Alignment\.TopStart \}\)[\s\S]*EhThumbnail\([\s\S]*if \(this\.gallery\.translated\.length > 0\)[\s\S]*backgroundColor\(EhConstants\.categoryColor\(this\.gallery\.category\)\)[\s\S]*position\(\{ right: ThemeConstants\.SPACE_XS, bottom: ThemeConstants\.SPACE_XS \}\)/.test(src))
ok('NextE grid title stays below the cover and is readable body text',
  /Text\(this\.gallery\.title\(\)\)[\s\S]*fontSize\(ThemeConstants\.FONT_SIZE_BODY\)[\s\S]*maxLines\(2\)/.test(src))
ok('NextE grid does not render the old rating row',
  !/RatingStars\(/.test(src) && !/ratingFallBack/.test(src))
ok('NextE grid does not render the old category/page metadata row below the title',
  !/Text\(this\.gallery\.category\)[\s\S]*Text\(`\$\{this\.gallery\.fileCount\}P`\)/.test(src))

if (failures > 0) {
  console.error(`\n✗ gallery grid card visual contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log(`✓ gallery grid card visual contract: ${passed} assertions passed`)

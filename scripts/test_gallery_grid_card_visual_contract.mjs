#!/usr/bin/env node
/**
 * Contract: Grid-mode gallery cards are cover-first browsing tiles.
 *
 * eros_fe/lib/pages/item/gallery_item_grid.dart makes the cover the primary visual, overlays language
 * and count/favorite state on the image, then shows title + post time. NextE grid cards must not regress
 * into a sparse fixed block whose tag area creates large empty whitespace, nor into Waterfall/masonry.
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
ok('NextE grid card reads usertag signal and renders a bounded tag-chip sample',
  /private tagSig: UserTagSignal = connectUserTagSignal\(\)/.test(src) &&
    /@Builder\s+tagChips\(\)[\s\S]*this\.gallery\.simpleTags\.slice\(0,\s*ThemeConstants\.GALLERY_GRID_TAG_LIMIT\)/.test(src))
ok('NextE grid tags reuse the same usertag color semantics as list cards',
  /UserTagStore\.getInstance\(\)\.lookup\(t\.namespace, t\.text\)/.test(src) &&
    /\(t: SimpleTag\) => `\$\{this\.tagSig\.version\}:\$\{t\.namespace\}:\$\{t\.text\}`/.test(src))
ok('NextE grid card overlays language and page/favorite state on the cover',
  /Stack\(\{ alignContent: Alignment\.TopStart \}\)[\s\S]*EhThumbnail\([\s\S]*if \(this\.gallery\.translated\.length > 0\)[\s\S]*backgroundColor\(EhConstants\.categoryColor\(this\.gallery\.category\)\)[\s\S]*position\(\{ right: ThemeConstants\.SPACE_XS, bottom: ThemeConstants\.SPACE_XS \}\)/.test(src))
ok('NextE grid title stays below the cover and is readable body text',
  /Text\(this\.gallery\.title\(\)\)[\s\S]*fontSize\(ThemeConstants\.FONT_SIZE_BODY\)[\s\S]*maxLines\(2\)/.test(src))
ok('NextE grid card includes compact browsing metadata below the title',
  /private metaText\(\): string[\s\S]*this\.gallery\.postTime[\s\S]*this\.gallery\.uploader[\s\S]*this\.gallery\.category/.test(src) &&
    /height\(ThemeConstants\.GALLERY_GRID_META_HEIGHT\)/.test(src) &&
    /Text\(this\.metaText\(\)\)[\s\S]*fontSize\(ThemeConstants\.FONT_SIZE_CAPTION\)[\s\S]*fontColor\(\$r\('sys\.color\.font_secondary'\)\)/.test(src))
ok('NextE grid rating is a compact meta affordance, not a dominant row',
  /private ratingText\(\): string[\s\S]*this\.gallery\.ratingFallBack[\s\S]*this\.gallery\.rating/.test(src) &&
    /SymbolGlyph\(\$r\('sys\.symbol\.star_fill'\)\)[\s\S]*fontSize\(ThemeConstants\.FONT_SIZE_CAPTION\)[\s\S]*fontColor\(\[EhConstants\.ratingStarColor\(this\.gallery\.colorRating\)\]\)/.test(src))
ok('NextE grid card keeps fixed card rhythm instead of tag-driven masonry height',
  /height\(ThemeConstants\.GALLERY_GRID_TITLE_HEIGHT\)/.test(src) &&
    /height\(ThemeConstants\.GALLERY_GRID_META_HEIGHT\)/.test(src) &&
    /height\(ThemeConstants\.GALLERY_GRID_TAG_AREA_HEIGHT\)/.test(src) &&
    /clip\(true\)/.test(src) &&
    /height\(ThemeConstants\.GALLERY_GRID_INFO_HEIGHT\)/.test(src) &&
    !/const GRID_TAG_LIMIT/.test(src))
ok('NextE grid tag sample is one line and cannot reserve a large empty block',
  /static readonly GALLERY_GRID_INFO_HEIGHT: number = 98/.test(readFileSync(join(ROOT, 'shared/src/main/ets/theme/ThemeConstants.ets'), 'utf8')) &&
    /static readonly GALLERY_GRID_META_HEIGHT: number = 18/.test(readFileSync(join(ROOT, 'shared/src/main/ets/theme/ThemeConstants.ets'), 'utf8')) &&
    /static readonly GALLERY_GRID_TAG_AREA_HEIGHT: number = 28/.test(readFileSync(join(ROOT, 'shared/src/main/ets/theme/ThemeConstants.ets'), 'utf8')) &&
    /static readonly GALLERY_GRID_TAG_LIMIT: number = 1/.test(readFileSync(join(ROOT, 'shared/src/main/ets/theme/ThemeConstants.ets'), 'utf8')))
ok('NextE grid does not render the old category/page metadata row below the title',
  !/Text\(this\.gallery\.category\)[\s\S]*Text\(`\$\{this\.gallery\.fileCount\}P`\)/.test(src))

if (failures > 0) {
  console.error(`\n✗ gallery grid card visual contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log(`✓ gallery grid card visual contract: ${passed} assertions passed`)

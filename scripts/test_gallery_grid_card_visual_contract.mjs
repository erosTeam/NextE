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
const thumbSrc = readFileSync(join(ROOT, 'shared/src/main/ets/components/EhThumbnail.ets'), 'utf8')
const detailHeaderSrc = readFileSync(
  join(ROOT, 'feature/gallery/src/main/ets/components/GalleryHeaderCard.ets'),
  'utf8',
)
const previewTileSrc = readFileSync(
  join(ROOT, 'shared/src/main/ets/components/PreviewThumbTile.ets'),
  'utf8',
)
const fe = readFileSync(join(ROOT, '../eros_fe/lib/pages/item/gallery_item_grid.dart'), 'utf8')
const containFitBranch = thumbSrc.slice(
  thumbSrc.indexOf('} else if (this.containFit && this.hasSourceSize()'),
  thumbSrc.indexOf('} else if (this.stretchHeight)'),
)
const previewFrameBranch = previewTileSrc.slice(
  previewTileSrc.indexOf('Transparent layout slot'),
  previewTileSrc.indexOf('// Page number'),
)

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
ok('NextE grid card deliberately omits tag chips and rating-heavy affordances',
  !/simpleTags/.test(src) &&
    !/tagChips/.test(src) &&
    !/UserTagStore/.test(src) &&
    !/ratingText/.test(src))
ok('NextE grid card uses the shared category corner badge',
  /GalleryCategoryCornerBadge\(\{[\s\S]*category:\s*this\.gallery\.category[\s\S]*translated:\s*this\.gallery\.translated/.test(src))
ok('NextE grid card overlays page/favorite state on the cover',
  /private CoverMeta\(\)[\s\S]*heart_fill[\s\S]*`\$\{this\.gallery\.fileCount\}P`/.test(src) &&
    /position\(\{ right: ThemeConstants\.SPACE_XS, bottom: ThemeConstants\.SPACE_XS \}\)/.test(src))
ok('NextE grid thumbnail passes source dimensions so fixed cover slots do not stretch source images',
  /sourceWidth:\s*this\.gallery\.imgWidth/.test(src) &&
    /sourceHeight:\s*this\.gallery\.imgHeight/.test(src))
ok('NextE grid keeps the list/grid grey-placeholder cover behavior, not the Waterfall crop override',
  !/forceCoverFit:\s*true/.test(src))
ok('NextE grid title stays below the cover and is readable body text',
  /Text\(this\.gallery\.title\(\)\)[\s\S]*fontSize\(ThemeConstants\.FONT_SIZE_BODY\)[\s\S]*maxLines\(2\)/.test(src))
ok('NextE grid card includes compact browsing metadata below the title',
  /private metaText\(\): string[\s\S]*this\.gallery\.postTime[\s\S]*this\.gallery\.fileCount[\s\S]*this\.gallery\.category/.test(src) &&
    /height\(ThemeConstants\.GALLERY_GRID_META_HEIGHT\)/.test(src) &&
    /Text\(this\.metaText\(\)\)[\s\S]*fontSize\(ThemeConstants\.FONT_SIZE_CAPTION\)[\s\S]*fontColor\(\$r\('sys\.color\.font_secondary'\)\)/.test(src))
ok('NextE grid card keeps fixed card rhythm instead of tag-driven masonry height',
  /height\(ThemeConstants\.GALLERY_GRID_TITLE_HEIGHT\)/.test(src) &&
    /height\(ThemeConstants\.GALLERY_GRID_META_HEIGHT\)/.test(src) &&
    /clip\(true\)/.test(src) &&
    /height\(ThemeConstants\.GALLERY_GRID_INFO_HEIGHT\)/.test(src))
ok('NextE grid compact info tokens stay small enough for a phone three-column wall',
  /static readonly GALLERY_GRID_INFO_HEIGHT: number = 66/.test(readFileSync(join(ROOT, 'shared/src/main/ets/theme/ThemeConstants.ets'), 'utf8')) &&
    /static readonly GALLERY_GRID_TITLE_HEIGHT: number = 40/.test(readFileSync(join(ROOT, 'shared/src/main/ets/theme/ThemeConstants.ets'), 'utf8')) &&
    /static readonly GALLERY_GRID_META_HEIGHT: number = 18/.test(readFileSync(join(ROOT, 'shared/src/main/ets/theme/ThemeConstants.ets'), 'utf8')) &&
    !/GALLERY_GRID_TAG_AREA_HEIGHT/.test(readFileSync(join(ROOT, 'shared/src/main/ets/theme/ThemeConstants.ets'), 'utf8')) &&
    !/GALLERY_GRID_TAG_LIMIT/.test(readFileSync(join(ROOT, 'shared/src/main/ets/theme/ThemeConstants.ets'), 'utf8')))
ok('NextE grid does not render the old category/page metadata row below the title',
  !/Text\(this\.gallery\.category\)[\s\S]*Text\(`\$\{this\.gallery\.fileCount\}P`\)/.test(src))
ok('Gallery list/grid cover slots keep the designed grey placeholder backing',
  /else if \(this\.coverRatio > 0\)[\s\S]*backgroundColor\(ThemeConstants\.COVER_PLACEHOLDER\)/.test(thumbSrc))
ok('Detail and preview main visual slots do not get a grey letterbox container',
  /GalleryHeaderCard[\s\S]*EhThumbnail\(\{[\s\S]*containFit:\s*true/.test(detailHeaderSrc) &&
    /Stack\(\{ alignContent: Alignment\.Center \}\)\s*\{[\s\S]*Image\(EhConstants\.cdnThumb\(this\.url\)\)[\s\S]*this\.coverOverlay\(\)[\s\S]*?\}[\s\S]*\.width\(this\.thumbWidth\)[\s\S]*\.height\(this\.thumbHeight\)/.test(containFitBranch) &&
    !/backgroundColor\(ThemeConstants\.COVER_PLACEHOLDER\)/.test(containFitBranch) &&
    /Stack\(\)[\s\S]*\.width\('100%'\)[\s\S]*\.height\(this\.frameHeight\(\)\)[\s\S]*\.alignContent\(Alignment\.Center\)/.test(previewFrameBranch) &&
    /@Local\s+measuredWidth:\s*number\s*=\s*0/.test(previewTileSrc) &&
    /tileWidth\(\)[\s\S]*this\.measuredWidth > 0 \? this\.measuredWidth : ThemeConstants\.PREVIEW_THUMB_MIN_W/.test(previewTileSrc) &&
    !/backgroundColor\(ThemeConstants\.COVER_PLACEHOLDER\)/.test(previewFrameBranch))

if (failures > 0) {
  console.error(`\n✗ gallery grid card visual contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log(`✓ gallery grid card visual contract: ${passed} assertions passed`)

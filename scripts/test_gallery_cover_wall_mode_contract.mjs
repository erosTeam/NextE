#!/usr/bin/env node
/**
 * Contract: Cover Wall is a separate WaterFlow-derived browsing mode that renders covers only.
 *
 * Run: node scripts/test_gallery_cover_wall_mode_contract.mjs
 */
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8')
let failures = 0

function ok(condition, message) {
  if (!condition) {
    console.error(`✗ ${message}`)
    failures += 1
  }
}

function branchBetween(source, start, end) {
  const startIndex = source.indexOf(start)
  if (startIndex < 0) {
    return ''
  }
  const endIndex = source.indexOf(end, startIndex + start.length)
  return source.slice(startIndex, endIndex < 0 ? source.length : endIndex)
}

const grounding = read('docs/plans/active/ui-grounding.md')
ok(grounding.includes('## Active: gallery cover wall mode'), 'UI grounding records the cover wall lane')
ok(grounding.includes('../eros_fe/lib/pages/tab/view/list/waterfall_flow.dart') &&
  grounding.includes('../eros_fe/lib/pages/item/gallery_item_flow.dart'),
'grounding names concrete FE WaterfallFlow and cover-only item references')
ok(grounding.includes('Primary information: the cover image is the entire card') &&
  grounding.includes('Primary action: tapping a cover opens the same gallery detail route'),
'grounding names the primary information and primary action')
ok(grounding.includes('GALLERY_COVER_WALL_MIN_W = 120') &&
  grounding.includes('omitting title, rating, page/favorite overlay, meta, and tag chips'),
'grounding documents the narrow deviation from Waterfall')

const listMode = read('shared/src/main/ets/state/ListModeState.ets')
ok(/COVER_WALL\s*=\s*'coverWall'/.test(listMode), 'ListMode defines a persisted coverWall value')

const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
ok(/GALLERY_COVER_WALL_MIN_W:\s*number\s*=\s*120/.test(theme),
  'cover wall min width is centralized and smaller than Waterfall')

const index = read('shared/src/main/ets/Index.ets')
ok(index.includes("export { GalleryCoverWallCard }"), 'shared barrel exports GalleryCoverWallCard')

const card = read('shared/src/main/ets/components/GalleryCoverWallCard.ets')
ok(card.includes('export struct GalleryCoverWallCard'), 'cover wall uses its own card component')
ok(card.includes('private coverRatio(): number') &&
  card.includes('this.gallery.imgWidth / this.gallery.imgHeight') &&
  card.includes('COVER_WALL_MIN_COVER_RATIO') &&
  card.includes('COVER_WALL_MAX_COVER_RATIO'),
'cover wall card keeps the bounded Waterfall source-ratio policy')
ok(card.includes('EhThumbnail({') &&
  card.includes('coverRatio: this.coverRatio()') &&
  card.includes('radius: ThemeConstants.GALLERY_GRID_CARD_RADIUS') &&
  card.includes('forceCoverFit: !this.isExtremeTallCover()') &&
  card.includes('containFit: this.isExtremeTallCover()') &&
  card.includes('letterboxBackground: true'),
'cover wall card renders proportional covers through EhThumbnail with the Grid card radius')
ok(card.includes('GalleryCategoryCornerBadge') &&
  card.includes('category: this.gallery.category') &&
  card.includes('translated: this.gallery.translated') &&
  card.includes('textCenterXRatio: CATEGORY_BADGE_COMPACT_TEXT_CENTER_X_RATIO') &&
  card.includes('textCenterYRatio: CATEGORY_BADGE_COMPACT_TEXT_CENTER_Y_RATIO'),
'cover wall card exposes only the shared category/translated corner badge with compact label offset')
ok(!card.includes('this.gallery.title()') &&
  !card.includes('RatingStars') &&
  !card.includes('simpleTags') &&
  !card.includes('fileCount') &&
  !card.includes('GalleryWaterfallCard'),
'cover wall card must not render Waterfall title, rating, tag, or page/favorite metadata')

const galleryPages = [
  'feature/home/src/main/ets/components/GalleryListBody.ets',
  'feature/search/src/main/ets/pages/GallerySearchPage.ets',
  'feature/user/src/main/ets/components/FavcatPage.ets',
]

for (const rel of galleryPages) {
  const source = read(rel)
  const coverBranch = branchBetween(source, 'this.listMode.mode === ListMode.COVER_WALL', '} else {')
  ok(source.includes('GalleryCoverWallCard'), `${rel}: imports/uses GalleryCoverWallCard`)
  ok(source.includes('this.listMode.mode === ListMode.COVER_WALL'), `${rel}: branches on ListMode.COVER_WALL`)
  ok(coverBranch.includes('PullRefreshWaterFlowScaffold({') &&
    coverBranch.includes('minColumnWidth: ThemeConstants.GALLERY_COVER_WALL_MIN_W') &&
    coverBranch.includes('itemCount: this.vm.itemCount') &&
    coverBranch.includes('gap: ThemeConstants.GALLERY_GRID_GAP') &&
    coverBranch.includes('horizontalPadding: ThemeConstants.GALLERY_GRID_GAP'),
  `${rel}: cover wall reuses WaterFlow scaffold with its own width token`)
  ok(/FlowItem\(\) \{[\s\S]*GalleryCoverWallCard\(\{ gallery: g \}\)[\s\S]*\.width\('100%'\)/.test(coverBranch),
    `${rel}: cover wall FlowItem fills the native WaterFlow cell`)
  ok(!/GalleryWaterfallCard/.test(coverBranch) &&
    !/GalleryGridCard/.test(coverBranch) &&
    !/GridItem\(\)/.test(coverBranch),
  `${rel}: cover wall must not render Waterfall/Grid card bodies`)
}

const layoutSettings = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')
ok(layoutSettings.includes('ListMode.COVER_WALL') &&
  layoutSettings.includes("app.string.view_cover_wall"),
'Layout settings exposes Cover Wall as a selectable persisted mode')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(strings.includes('"name": "view_cover_wall"'), `${locale}: view_cover_wall string exists`)
}

if (failures > 0) {
  console.error(`\n✗ gallery cover wall mode contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ gallery cover wall mode contract passed')

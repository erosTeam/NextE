#!/usr/bin/env node
/**
 * Contract: user-visible gallery GRID mode is a real responsive Grid, not the WaterFlow renderer.
 *
 * Grounding:
 * - eros_fe separates ListModeEnum.grid -> EhGridView/SliverGrid from ListModeEnum.waterfall ->
 *   EhWaterfallFlow/SliverWaterfallFlow.
 * - NextE's "网格" label must not render through PullRefreshWaterFlowScaffold or FlowItem.
 *
 * Run: node scripts/test_gallery_grid_mode_contract.mjs
 */
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8')
let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
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

const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
ok('gallery grid min width and gap are centralized tokens',
  /GALLERY_GRID_MIN_W:\s*number\s*=\s*106/.test(theme) &&
    /GALLERY_GRID_GAP:\s*number\s*=\s*6/.test(theme) &&
    /GALLERY_GRID_COVER_RATIO:\s*number\s*=\s*0\.7/.test(theme) &&
    /GALLERY_GRID_INFO_HEIGHT:\s*number\s*=\s*\d+/.test(theme) &&
    /GALLERY_GRID_TITLE_HEIGHT:\s*number\s*=\s*\d+/.test(theme) &&
    /GALLERY_GRID_META_HEIGHT:\s*number\s*=\s*\d+/.test(theme) &&
    /GALLERY_GRID_CARD_RADIUS:\s*number\s*=\s*16/.test(theme) &&
    /GALLERY_WATERFALL_MIN_W:\s*number\s*=\s*160/.test(theme))

const galleryPages = [
  'feature/home/src/main/ets/components/GalleryListBody.ets',
  'feature/search/src/main/ets/pages/GallerySearchPage.ets',
  'feature/user/src/main/ets/components/FavcatPage.ets',
]

for (const rel of galleryPages) {
  const source = read(rel)
  const gridBranch = branchBetween(
    source,
    'this.listMode.mode === ListMode.GRID',
    'this.listMode.mode === ListMode.WATERFALL',
  )
  ok(`${rel} imports PullRefreshGridScaffold for GRID mode`,
    /PullRefreshGridScaffold/.test(source))
  ok(`${rel} GRID branch uses PullRefreshGridScaffold`,
    /PullRefreshGridScaffold\(\{/.test(gridBranch))
  ok(`${rel} GRID branch passes responsive min width and gap`,
    /minColumnWidth:\s*ThemeConstants\.GALLERY_GRID_MIN_W/.test(gridBranch) &&
      /gap:\s*ThemeConstants\.GALLERY_GRID_GAP/.test(gridBranch) &&
      /horizontalPadding:\s*ThemeConstants\.GALLERY_GRID_GAP/.test(gridBranch))
  ok(`${rel} GRID branch provides GridItem children`,
    /GridItem\(\) \{[\s\S]*GalleryGridCard/.test(gridBranch))
  ok(`${rel} GRID branch does not use WaterFlow/FlowItem`,
    !/PullRefreshWaterFlowScaffold/.test(gridBranch) &&
      !/FlowItem\(\)/.test(gridBranch))
}

const gridCard = read('shared/src/main/ets/components/GalleryGridCard.ets')
ok('GalleryGridCard uses the shared grid cover ratio token',
  /coverRatio:\s*ThemeConstants\.GALLERY_GRID_COVER_RATIO/.test(gridCard) &&
    !/coverRatio:\s*0\.7/.test(gridCard))
ok('GalleryGridCard has a compact fixed info-area contract and no tag-driven masonry height',
    /Text\(this\.gallery\.title\(\)\)[\s\S]*\.height\(ThemeConstants\.GALLERY_GRID_TITLE_HEIGHT\)/.test(gridCard) &&
    /\.height\(ThemeConstants\.GALLERY_GRID_META_HEIGHT\)/.test(gridCard) &&
    /\.height\(ThemeConstants\.GALLERY_GRID_INFO_HEIGHT\)/.test(gridCard) &&
    /\.borderRadius\(ThemeConstants\.GALLERY_GRID_CARD_RADIUS\)/.test(gridCard) &&
    /GalleryCategoryCornerBadge/.test(gridCard) &&
    /textCenterXRatio:\s*CATEGORY_BADGE_COMPACT_TEXT_CENTER_X_RATIO/.test(gridCard) &&
    /textCenterYRatio:\s*CATEGORY_BADGE_COMPACT_TEXT_CENTER_Y_RATIO/.test(gridCard) &&
    !/simpleTags/.test(gridCard) &&
    !/tagChips/.test(gridCard))

const layoutSettings = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')
ok('Layout settings exposes Waterfall as a separate mode, not as Grid',
  /ListMode\.WATERFALL/.test(layoutSettings) &&
    /view_waterfall/.test(layoutSettings))

if (failures === 0) {
  console.log('✓ gallery grid mode contract passed')
  process.exit(0)
}
console.error(`✗ gallery grid mode contract: ${failures} failure(s)`)
process.exit(1)

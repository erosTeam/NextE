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

const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
ok('gallery grid min width and gap are centralized tokens',
  /GALLERY_GRID_MIN_W:\s*number\s*=\s*150/.test(theme) &&
    /GALLERY_GRID_GAP:\s*number\s*=\s*6/.test(theme) &&
    /GALLERY_GRID_COVER_RATIO:\s*number\s*=\s*0\.7/.test(theme))

const galleryPages = [
  'feature/home/src/main/ets/components/GalleryListBody.ets',
  'feature/search/src/main/ets/pages/GallerySearchPage.ets',
  'feature/user/src/main/ets/components/FavcatPage.ets',
]

for (const rel of galleryPages) {
  const source = read(rel)
  ok(`${rel} imports PullRefreshGridScaffold for GRID mode`,
    /PullRefreshGridScaffold/.test(source))
  ok(`${rel} GRID branch uses PullRefreshGridScaffold`,
    /this\.listMode\.mode === ListMode\.GRID[\s\S]*PullRefreshGridScaffold\(\{/.test(source))
  ok(`${rel} GRID branch passes responsive min width and gap`,
    /minColumnWidth:\s*ThemeConstants\.GALLERY_GRID_MIN_W/.test(source) &&
      /gap:\s*ThemeConstants\.GALLERY_GRID_GAP/.test(source) &&
      /horizontalPadding:\s*ThemeConstants\.GALLERY_GRID_GAP/.test(source))
  ok(`${rel} GRID branch provides GridItem children`,
    /this\.listMode\.mode === ListMode\.GRID[\s\S]*GridItem\(\) \{[\s\S]*GalleryGridCard/.test(source))
  ok(`${rel} GRID branch does not use WaterFlow/FlowItem`,
    !/this\.listMode\.mode === ListMode\.GRID[\s\S]*PullRefreshWaterFlowScaffold/.test(source) &&
      !/this\.listMode\.mode === ListMode\.GRID[\s\S]*FlowItem\(\)/.test(source))
}

const gridCard = read('shared/src/main/ets/components/GalleryGridCard.ets')
ok('GalleryGridCard uses the shared grid cover ratio token',
  /coverRatio:\s*ThemeConstants\.GALLERY_GRID_COVER_RATIO/.test(gridCard) &&
    !/coverRatio:\s*0\.7/.test(gridCard))

if (failures === 0) {
  console.log('✓ gallery grid mode contract passed')
  process.exit(0)
}
console.error(`✗ gallery grid mode contract: ${failures} failure(s)`)
process.exit(1)

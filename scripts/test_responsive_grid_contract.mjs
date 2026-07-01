#!/usr/bin/env node
/**
 * Contract: gallery preview grids must use ArkUI native repeat(auto-fit) sizing. The grid decides the
 * columns; preview tiles consume their actual cell width locally for sprite rendering. No caller should
 * calculate a column count or pass a calculated cell width into the tile.
 *
 * Run: node scripts/test_responsive_grid_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let passed = 0
const ok = (cond, msg) => {
  assert.ok(cond, msg)
  passed += 1
}
const eq = (got, want, msg) => {
  assert.strictEqual(got, want, `${msg}: got ${got} want ${want}`)
  passed += 1
}

const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
const num = (re) => {
  const m = re.exec(theme)
  if (!m) {
    throw new Error(`ThemeConstants missing ${re}`)
  }
  return Number(m[1])
}

eq(num(/PREVIEW_THUMB_MIN_W:\s*number\s*=\s*(\d+)/), 90, 'preview thumbnail min width token')
eq(num(/THUMB_RADIUS:\s*number\s*=\s*(\d+)/), 8, 'thumbnail image radius token')

const scaffold = read('shared/src/main/ets/components/PullRefreshGridScaffold.ets')
ok(
  /return `repeat\(auto-fit, \$\{width\}vp\)`/.test(scaffold),
  'PullRefreshGridScaffold uses ArkUI repeat(auto-fit, effective min width)',
)
ok(/@Param\s+pinchModeKey:\s*string\s*=\s*''/.test(scaffold),
  'PullRefreshGridScaffold exposes a pinch mode key')
ok(/this\.listMode\.overrideWidthFor\(this\.pinchModeKey\)/.test(scaffold),
  'PullRefreshGridScaffold renders the pinch column-width override')
ok(!/ResponsiveGrid/.test(scaffold), 'PullRefreshGridScaffold does not import/use ResponsiveGrid')
ok(!/onCellSize/.test(scaffold), 'PullRefreshGridScaffold does not emit calculated cell widths')
ok(!/estimatedColumns|estimatedColumnWidth|Math\.floor\(\(content \+ this\.gap\)/.test(scaffold),
  'PullRefreshGridScaffold does not hand-calculate columns or cell widths')

const allThumbs = read('feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets')
ok(/minColumnWidth:\s*ThemeConstants\.PREVIEW_THUMB_MIN_W/.test(allThumbs),
  'AllThumbnails passes PREVIEW_THUMB_MIN_W to native Grid scaffold')
ok(/pinchModeKey:\s*ListMode\.THUMBNAIL_GRID/.test(allThumbs),
  'AllThumbnails uses the thumbnail grid pinch key')
ok(/PullRefreshGridScaffold\(\{[\s\S]*itemCount:\s*this\.vm\.itemCount/.test(allThumbs),
  'AllThumbnails passes the real thumbnail itemCount so spacer indexes cannot capture page 1')
ok(/PreviewThumbTile\(/.test(allThumbs), 'AllThumbnails uses PreviewThumbTile')
ok(!/onCellSize|thumbW|tileWidth:|columns:\s*\d/.test(allThumbs),
  'AllThumbnails does not calculate columns or pass tileWidth')

const previewGrid = read('feature/gallery/src/main/ets/components/GalleryPreviewGrid.ets')
ok(
  /return `repeat\(auto-fit, \$\{this\.effectiveMinWidth\(\)\}vp\)`/.test(previewGrid),
  'GalleryPreviewGrid uses ArkUI repeat(auto-fit, effective thumbnail width)',
)
ok(/overrideWidthFor\(ListMode\.THUMBNAIL_GRID\)/.test(previewGrid),
  'GalleryPreviewGrid reads the thumbnail column-width override')
ok(/PinchGesture\(\{\s*fingers:\s*2\s*\}\)/.test(previewGrid),
  'GalleryPreviewGrid supports two-finger thumbnail density pinch')
ok(/ListModeSettings\.setColumnWidth\(this\.ctx\(\),\s*ListMode\.THUMBNAIL_GRID/.test(previewGrid),
  'GalleryPreviewGrid persists the thumbnail column-width override')
ok(/PreviewThumbTile\(/.test(previewGrid), 'GalleryPreviewGrid uses PreviewThumbTile')
ok(!/ResponsiveGrid|gridColumns|gridTileWidth|tileWidth:|gridWidth|columns:\s*\d/.test(previewGrid),
  'GalleryPreviewGrid does not calculate columns or pass tileWidth')
ok(!/'1fr 1fr 1fr'/.test(previewGrid), 'GalleryPreviewGrid has no hardcoded 3-column template')

const listMode = read('shared/src/main/ets/state/ListModeState.ets')
ok(/THUMBNAIL_GRID\s*=\s*'thumbnailGrid'/.test(listMode),
  'ListMode has a dedicated thumbnail-grid density key')
ok(/@Trace\s+thumbnailColW:\s*number\s*=\s*0/.test(listMode),
  'ListModeState stores thumbnail column width separately')

const listModeSettings = read('shared/src/main/ets/settings/ListModeSettings.ets')
ok(/StorageKeys\.THUMBNAIL_COLUMN_WIDTH/.test(listModeSettings),
  'ListModeSettings persists thumbnail column width')

const storageKeys = read('shared/src/main/ets/constants/StorageKeys.ets')
ok(/THUMBNAIL_COLUMN_WIDTH:\s*string\s*=\s*'layout\.thumbnailColumnWidth'/.test(storageKeys),
  'StorageKeys defines thumbnail column width preference')

const layoutSettings = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')
ok(/settings_thumbnail_column_width/.test(layoutSettings),
  'Layout settings exposes thumbnail density row')
ok(/pushPathByName\('ThumbnailColumnDensity'/.test(layoutSettings),
  'Layout settings opens the thumbnail density route')

const index = read('entry/src/main/ets/pages/Index.ets')
ok(/name === 'ThumbnailColumnDensity'[\s\S]*ColumnDensityPage\(\{\s*targetMode:\s*ListMode\.THUMBNAIL_GRID\s*\}\)/.test(index),
  'Index routes thumbnail density to ColumnDensityPage with thumbnail target mode')

const tile = read('shared/src/main/ets/components/PreviewThumbTile.ets')
ok(!/@Param\s+tileWidth/.test(tile), 'PreviewThumbTile does not accept external tileWidth')
ok(/@Local\s+measuredWidth:\s*number\s*=\s*0/.test(tile), 'PreviewThumbTile stores measured cell width')
ok(/tileWidth\(\)[\s\S]*this\.measuredWidth > 0 \? this\.measuredWidth : ThemeConstants\.PREVIEW_THUMB_MIN_W/.test(tile),
  'PreviewThumbTile uses measured width with token fallback')
ok(/frameHeight\(\)[\s\S]*this\.tileWidth\(\) \* FRAME_ASPECT/.test(tile),
  'PreviewThumbTile frame height follows measured cell width')
ok(/\.onAreaChange\([\s\S]*Number\.parseFloat\(`\$\{newValue\.width\}`\)[\s\S]*this\.measuredWidth = parsed/.test(tile),
  'PreviewThumbTile updates measured width from actual cell bounds')
ok(/\.width\('100%'\)[\s\S]*\.aspectRatio\(1 \/ FRAME_ASPECT\)/.test(tile),
  'PreviewThumbTile frame fills the native Grid cell with fixed aspect')
ok(/fitByHeight\(/.test(tile), 'PreviewThumbTile preserves thumb aspect via width-fit vs height-fit')
ok(!/ImageFit\.Cover/.test(tile), 'PreviewThumbTile does not crop preview thumbs with cover fit')
ok(!/radius:\s*0\b/.test(tile), 'PreviewThumbTile never passes radius 0 to the sprite')

const sprite = read('shared/src/main/ets/components/EhSpriteThumbnail.ets')
ok(!/\.backgroundImage\s*\(/.test(sprite), 'sprite thumb is not painted through backgroundImage')
ok(/Stack\([\s\S]*Image\(EhConstants\.cdnThumb[\s\S]*\.offset\(/.test(sprite),
  'sprite thumb uses an offset Image child inside a clipped box')
ok((sprite.match(/\.clip\(true\)/g) || []).length >= 3, 'sprite renderer clips all rendering branches')

console.log(`✓ responsive grid contract: ${passed} assertions passed`)

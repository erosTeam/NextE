#!/usr/bin/env node
/**
 * Contract: the detail inline GRID and the all-thumbnails page must size their columns RESPONSIVELY
 * (derived from pane width + a min comfortable thumb width — never a hardcoded count), and each tile
 * must be a STABLE fixed frame so a flat/wide or misdetected thumb cannot drag the page-number baseline.
 *
 * Locks:
 *   • ResponsiveGrid.columns is a floor((w+gap)/(minW+gap)) derivation, >= 1, monotonic in width;
 *   • with the real ThemeConstants min/gap, a ~1400px-class phone content width resolves to 3 columns,
 *     a wider pane to more, a narrower pane to fewer;
 *   • NO hardcoded column count (`columns: 3|4`, `columns = 3`, `'1fr 1fr 1fr'`) in the grid surfaces;
 *   • PreviewThumbTile = a fixed-height frame (clip + center) with the page number a sibling BELOW it;
 *   • first-page preview is retained (the detail still renders the preview peek).
 *
 * Run: node scripts/test_responsive_grid_contract.mjs   (exit 1 on any failure)
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
  passed++
}
const eq = (got, want, msg) => {
  assert.strictEqual(got, want, `${msg}: got ${got} want ${want}`)
  passed++
}

// Pull the REAL min column width + gap out of ThemeConstants so the formula tests track the source.
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
const num = (re) => {
  const m = re.exec(theme)
  if (!m) throw new Error(`ThemeConstants missing ${re}`)
  return Number(m[1])
}
const MIN = num(/PREVIEW_THUMB_MIN_W:\s*number\s*=\s*(\d+)/)
const GAP = num(/SPACE_SM:\s*number\s*=\s*(\d+)/)

// Mirror of ResponsiveGrid.columns / columnWidth.
const columns = (w, minW, gap) => {
  if (w <= 0 || minW <= 0) return 1
  const n = Math.floor((w + gap) / (minW + gap))
  return n > 0 ? n : 1
}
const columnWidth = (w, cols, gap) => (cols <= 0 ? w : (w - (cols - 1) * gap) / cols)

// 1. Derivation guards + adaptation.
eq(columns(0, MIN, GAP), 1, 'zero width → at least 1 column')
eq(columns(-10, MIN, GAP), 1, 'negative width → at least 1 column')
// 1400px-class phone: the detail card content width lands ~360-420 vp → exactly 3 columns.
eq(columns(360, MIN, GAP), 3, '~1400px-class device width (360vp) → 3 columns')
eq(columns(420, MIN, GAP), 3, '~1400px-class device width (420vp) → 3 columns')
ok(columns(600, MIN, GAP) > 3, 'wider pane (600vp) adapts UP past 3 columns')
ok(columns(240, MIN, GAP) < 3, 'narrower pane (240vp) adapts DOWN below 3 columns')
ok(
  columns(240, MIN, GAP) <= columns(360, MIN, GAP) && columns(360, MIN, GAP) <= columns(600, MIN, GAP),
  'column count is monotonic in width',
)
// columnWidth fills the pane: cols tiles + (cols-1) gaps == width.
{
  const w = 372
  const c = columns(w, MIN, GAP)
  const tile = columnWidth(w, c, GAP)
  ok(Math.abs(c * tile + (c - 1) * GAP - w) < 0.001, 'columnWidth fills the pane exactly')
  ok(tile >= MIN - 0.001, 'derived tile width is at least the min comfortable width')
}

// 2. ResponsiveGrid.ets is the derivation source.
const rg = read('shared/src/main/ets/utils/ResponsiveGrid.ets')
ok(/static columns\(/.test(rg) && /static columnWidth\(/.test(rg), 'ResponsiveGrid exposes columns + columnWidth')
ok(/Math\.floor\(\(availableWidth \+ gap\) \/ \(minColumnWidth \+ gap\)\)/.test(rg), 'columns uses the max-extent floor formula')

// 3. NO hardcoded column count in the grid surfaces; they go through ResponsiveGrid.
const scaffold = read('shared/src/main/ets/components/PullRefreshGridScaffold.ets')
ok(/ResponsiveGrid\.columns\(/.test(scaffold), 'scaffold derives columns via ResponsiveGrid')
ok(/minColumnWidth/.test(scaffold) && /onCellSize/.test(scaffold), 'scaffold supports responsive minColumnWidth + cell-size callback')

const allThumbs = read('feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets')
ok(/minColumnWidth:\s*ThemeConstants\.PREVIEW_THUMB_MIN_W/.test(allThumbs), 'all-thumbnails passes minColumnWidth, not a fixed count')
ok(!/columns:\s*\d/.test(allThumbs), 'all-thumbnails has NO hardcoded columns: <n>')
ok(/PreviewThumbTile\(/.test(allThumbs), 'all-thumbnails uses the shared stable PreviewThumbTile')

const previewGrid = read('feature/gallery/src/main/ets/components/GalleryPreviewGrid.ets')
ok(/ResponsiveGrid\.columns\(/.test(previewGrid), 'inline GRID derives its column count via ResponsiveGrid')
ok(/PreviewThumbTile\(/.test(previewGrid), 'inline GRID uses the shared stable PreviewThumbTile')
ok(!/columns:\s*\d/.test(previewGrid), 'inline GRID has NO hardcoded columns: <n>')

for (const [rel, src] of [
  ['GalleryAllThumbnailsPage', allThumbs],
  ['GalleryPreviewGrid', previewGrid],
]) {
  ok(!/=\s*3\b[^)]*column/i.test(src) && !/column[^=]*=\s*3\b/i.test(src), `${rel}: no hardcoded 3-column literal`)
  ok(!/'1fr 1fr 1fr'/.test(src), `${rel}: no hardcoded 3-column template literal`)
}

// 4. PreviewThumbTile: fixed-height frame, clipped + centered, page number a sibling BELOW the frame.
const tile = read('shared/src/main/ets/components/PreviewThumbTile.ets')
ok(/\.height\(this\.frameHeight\(\)\)/.test(tile), 'tile frame has a FIXED height')
ok(/frameHeight\(\)[\s\S]*?this\.tileWidth \* FRAME_ASPECT/.test(tile), 'frame height = tileWidth * fixed FRAME_ASPECT')
ok(/\.clip\(true\)/.test(tile) && /\.alignContent\(Alignment\.Center\)/.test(tile), 'frame clips + centers its content (flat/wide contained, centered)')
// the page number Text must come AFTER the Stack frame's close → it sits below, at a constant position.
ok(/Stack\(\)[\s\S]*?\.alignContent\(Alignment\.Center\)[\s\S]*?Text\(`\$\{this\.image\.page\}`\)/.test(tile), 'page number renders BELOW the frame (fixed position)')
// contain, not crop: the tile chooses height-fit vs width-fit (no objectFit Cover crop hack).
ok(/fitByHeight\(/.test(tile), 'tile contains the thumb (height-fit vs width-fit), preserving aspect')
ok(!/ImageFit\.Cover/.test(tile), 'tile does NOT crop with a cover hack')

// 5. First-page preview retained — the inline GRID is seeded from the parsed FIRST detail preview
// page, and the SAME first page seeds the all-thumbnails route, so both start at page 1 (the device
// screenshot showing the inline grid at 31-40 was a scrolled-to-bottom view of that same 40-thumb
// first page, not a different source).
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
ok(/this\.vm\.images\.length > 0/.test(detail) && /GalleryPreviewGrid\(/.test(detail), 'detail retains the first-page preview peek')
ok(/this\.images/.test(previewGrid), 'preview component renders the passed first-page images')
const detailVm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
ok(/this\.images = res\.images/.test(detailVm), 'detail VM seeds images from the parsed first preview page (res.images)')
ok(/images:\s*this\.vm\.images/.test(detail), 'inline grid is fed vm.images (the first preview page)')
ok(/new AllThumbnailsParams\([\s\S]*?this\.vm\.images/.test(detail), 'all-thumbnails firstPage is the SAME vm.images — same source, both start at page 1')
const allThumbsVm = read('feature/gallery/src/main/ets/viewmodel/AllThumbnailsViewModel.ets')
ok(/setData\(p\.firstPage\)/.test(allThumbsVm), 'all-thumbnails grid is seeded from firstPage (the detail first page)')

console.log(`✓ responsive grid + stable tile contract: ${passed} assertions passed`)

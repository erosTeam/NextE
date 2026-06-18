#!/usr/bin/env node
/**
 * Contract: the detail inline GRID and the all-thumbnails page must size their columns RESPONSIVELY
 * (derived from pane width + a min comfortable thumb width — never a hardcoded count), and each tile
 * must be a STABLE fixed frame so a flat/wide or misdetected thumb cannot drag the page-number baseline.
 *
 * Locks:
 *   • ResponsiveGrid.columns is a floor((w+gap)/(minW+gap)) derivation, >= 1, monotonic in width;
 *   • the product token is ThemeConstants.PREVIEW_THUMB_MIN_W=90; column count is derived from the
 *     real pane width, so the Mate X7 / Mate 60 Pro class preview panes stay at 3 columns while
 *     wider panes can still scale up without a hardcoded count;
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
eq(MIN, 90, 'preview thumbnail min width respects the current product token')

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
// Device-breakpoint intent: 90 keeps the Mate X7 preview pane at 3 columns; increasing it to 105 would
// collapse that pane to 2. It also keeps Mate 60 Pro-class phone panes from jumping to 4 columns. Wider
// non-phone panes may still scale up by derivation.
eq(columns(300, MIN, GAP), 3, 'Mate X7-class preview pane (300vp) → 3 columns')
eq(columns(330, MIN, GAP), 3, 'Mate X7-class preview pane (330vp) → 3 columns')
eq(columns(360, MIN, GAP), 3, 'Mate 60 Pro-class preview pane (360vp) → 3 columns')
eq(columns(380, MIN, GAP), 3, 'upper phone preview pane (380vp) still → 3 columns')
eq(columns(420, MIN, GAP), 4, 'wider pane (420vp) can adapt to 4 columns with the 90vp product token')
ok(columns(600, MIN, GAP) > columns(420, MIN, GAP), 'wide pane (600vp) adapts UP past 420vp')
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

// 4. PreviewThumbTile: fixed-height transparent layout slot, centered real thumb, page number sibling BELOW.
const tile = read('shared/src/main/ets/components/PreviewThumbTile.ets')
ok(/\.height\(this\.frameHeight\(\)\)/.test(tile), 'tile slot has a FIXED height for aligned page numbers')
ok(/frameHeight\(\)[\s\S]*?this\.tileWidth \* FRAME_ASPECT/.test(tile), 'slot height = tileWidth * fixed FRAME_ASPECT')
ok(/\.clip\(true\)/.test(tile) && /\.alignContent\(Alignment\.Center\)/.test(tile), 'transparent slot clips + centers its visible thumbnail')
ok(!/\.backgroundColor\(ThemeConstants\.BG_SUB\)/.test(tile), 'tile slot does NOT paint a permanent grey letterbox container')
ok(!/\.borderRadius\(ThemeConstants\.RADIUS_SM\)/.test(tile), 'tile slot does NOT own the rounded silhouette; the visible thumbnail does')
// the page number Text must come AFTER the Stack frame's close → it sits below, at a constant position.
ok(/Stack\(\)[\s\S]*?\.alignContent\(Alignment\.Center\)[\s\S]*?Text\(`\$\{this\.image\.page\}`\)/.test(tile), 'page number renders BELOW the slot (fixed position)')
// contain, not crop: the tile chooses height-fit vs width-fit (no objectFit Cover crop hack).
ok(/fitByHeight\(/.test(tile), 'tile contains the thumb (height-fit vs width-fit), preserving aspect')
ok(!/ImageFit\.Cover/.test(tile), 'tile does NOT crop with a cover hack')
// 4b. Rounded corners must live on the SPRITE/IMAGE itself (EhSpriteThumbnail radius), in BOTH the
// height-fit and width-fit branches — NOT a square sprite (radius:0) hidden behind a decorative rounded
// frame. The stable-tile fix had passed radius:0, so a frame-filling thumb read as square.
ok(!/radius:\s*0\b/.test(tile), 'tile never passes radius:0 to the sprite (that made the visible thumb square)')
ok(
  (tile.match(/radius:\s*ThemeConstants\.[A-Z_]+/g) || []).length >= 2,
  'tile passes a real theme radius token into EhSpriteThumbnail in BOTH fit branches (rounded sprite)'
)

// 4c. EFFECTIVE rounded corners (device-verified). The real regression: the sprite thumb was painted as
// a backgroundImage, which HarmonyOS does NOT clip to borderRadius even with clip(true) — so the param
// from 4b was necessary but NOT sufficient and the thumb still rendered square. The sprite MUST be an
// Image CHILD (clippable content) inside a clipped box; every branch (sprite + both image fallbacks) must
// clip(true), not merely set borderRadius (a Cover image without clip stays square); and the horizontal
// row uses the SAME EhSpriteThumbnail so it inherits the rounded path (no separate square thumb).
const sprite = read('shared/src/main/ets/components/EhSpriteThumbnail.ets')
ok(!/\.backgroundImage\s*\(/.test(sprite), 'sprite thumb is NOT painted via backgroundImage (HarmonyOS will not round a backgroundImage)')
ok(
  /Stack\([\s\S]*?Image\(EhConstants\.cdnThumb[\s\S]*?\.offset\(/.test(sprite),
  'sprite is cropped via an offset Image CHILD inside the clipped box (clippable content, not a background)'
)
const spriteClipN = (sprite.match(/\.clip\(true\)/g) || []).length
const spriteRadiusN = (sprite.match(/\.borderRadius\(this\.radius\)/g) || []).length
ok(!/\.backgroundColor\(ThemeConstants\.BG_SUB\)/.test(sprite), 'sprite/thumb renderer does NOT paint a permanent grey backdrop behind loaded real images')
ok(spriteClipN >= 3, 'every render branch clips to its radius (sprite + both image fallbacks)')
ok(
  spriteRadiusN >= 3 && spriteClipN >= spriteRadiusN,
  'no borderRadius(this.radius) is left without a paired clip(true) (an un-clipped Cover image stays square)'
)
ok(
  /horizontalRow\(\)[\s\S]*?EhSpriteThumbnail\(/.test(previewGrid),
  'horizontal preview row uses the same EhSpriteThumbnail (inherits the rounded sprite path)'
)

// 4d. NO axis distortion (device-flagged): the sheet is scaled UNIFORMLY by `factor` from its REAL decoded
// pixel size (Image.onComplete width/height), NOT Fill-fitted to the parsed max-extent — otherwise a canvas
// with padding beyond the last cell compresses one axis of the cropped thumb. Render size derives from the
// real decoded pixels (captured via onComplete, reset per url); the parsed extent is only a pre-load fallback.
ok(
  /@Local\s+sheetRealW:\s*number\s*=\s*0/.test(sprite) && /@Local\s+sheetRealH:\s*number\s*=\s*0/.test(sprite),
  'sprite tracks the real decoded sheet pixels (sheetRealW/sheetRealH)'
)
ok(/@Monitor\('url'\)/.test(sprite), 'sprite resets the decoded size when the url recycles (@Monitor url)')
ok(
  /onComplete\([\s\S]*?this\.sheetRealW = event\.width[\s\S]*?this\.sheetRealH = event\.height/.test(sprite),
  'sprite captures the REAL decoded pixel size from Image.onComplete'
)
ok(
  /this\.sheetRealW > 0 \? this\.sheetRealW : this\.spriteWidth/.test(sprite) &&
    /this\.sheetRealH > 0 \? this\.sheetRealH : this\.spriteHeight/.test(sprite),
  'sprite render size prefers the real decoded pixels (parsed extent is only the pre-load fallback)'
)
ok(
  /\.width\(this\.sheetRenderWidth\(\)\)[\s\S]*?\.height\(this\.sheetRenderHeight\(\)\)/.test(sprite),
  'sprite Image is sized by the real-pixel uniform-scale helpers (one factor on both axes)'
)
ok(
  !/\.width\(this\.spriteWidth \* this\.factor\(\)\)/.test(sprite),
  'sprite Image no longer Fill-fits the bare parsed extent (the axis-distortion path is removed)'
)

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

#!/usr/bin/env node
/**
 * Hard contract for the gallery-detail header / InfoBar visual semantics.
 *
 * This is NOT a pixel test. It encodes user/product hard-fails that must be
 * caught before controller accepts a worker result:
 * - Header must not reintroduce the old inline Read/Favorite action row.
 * - Read/resume CTA is the page-level FAB owned by GalleryDetailPage.
 * - Category badge must not be tiny/visually negligible.
 * - InfoBar in a bordered NextE card must not keep eros_fe's borderless-sliver accent bar.
 * - InfoBar metadata icons must stay quiet/outline, not mix filled heart/star into the grid.
 * - Favorite/share secondary actions live in the title-bar menu, not inside the dense header card.
 *
 * Run: node scripts/test_detail_header_visual_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join, dirname, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const FILES = {
  detail: 'feature/gallery/src/main/ets/pages/GalleryDetailPage.ets',
  header: 'feature/gallery/src/main/ets/components/GalleryHeaderCard.ets',
  info: 'feature/gallery/src/main/ets/components/GalleryInfoBar.ets',
}

const detail = read(FILES.detail)
const header = read(FILES.header)
const info = read(FILES.info)
let failures = 0

function fail(label, detail) {
  failures++
  console.error(`  ✗ ${label}`)
  if (detail) console.error(`    ${detail}`)
}
function ok(cond, label, detail) {
  if (!cond) fail(label, detail)
}
function section(text, startNeedle, endNeedle = null) {
  const s = text.indexOf(startNeedle)
  if (s < 0) return ''
  if (endNeedle === null) return text.slice(s)
  const e = text.indexOf(endNeedle, s + startNeedle.length)
  return e < 0 ? text.slice(s) : text.slice(s, e)
}

console.log('— detail header visual contract —')

// 1) Read/resume CTA: current accepted baseline is a page-level FAB, not the old header-card row.
ok(
  /private readFabLabel\(\): ResourceStr[\s\S]*detail_read_resume[\s\S]*detail_read/.test(detail),
  'GalleryDetailPage owns the read/resume FAB label',
  FILES.detail
)
ok(
  !/detail_read_with_count|gallery\.fileCount|fileCount\.length/.test(section(detail, 'private readFabLabel()', '  private openComments')),
  'read FAB must not include total page count',
  'Use plain detail_read for first-read CTA; page count belongs to InfoBar. Resume state may use resumeIndex only.'
)
ok(/Button\(\{ type: ButtonType\.Capsule \}\)[\s\S]*this\.readFabLabel\(\)/.test(detail), 'detail page renders a capsule read FAB')
ok(/Text\(this\.readFabLabel\(\)\)[\s\S]*\.fontSize\(ThemeConstants\.FONT_SIZE_BODY\)[\s\S]*\.fontColor\(ThemeConstants\.TEXT_ON_BRAND\)/.test(detail), 'detail FAB label has readable primary-action weight')
ok(/\.height\(ThemeConstants\.BUTTON_HEIGHT\)/.test(section(detail, 'Button({ type: ButtonType.Capsule })', '      }\n    }')), 'detail FAB uses BUTTON_HEIGHT token')
ok(!/@Event onRead|readLabel\(\)|detail_read|Button\(this\.readLabel\(\)\)/.test(header), 'GalleryHeaderCard does not own read/resume actions')

// 2) Favorite/share actions: secondary title-menu affordances, not fake colored header-heart state.
const detailMenu = section(detail, 'private detailMenu(): Record<string, Object>', '  // Share the gallery')
const favoriteIconBlock = section(detail, 'private favoriteTitleBarIcon()', '  private galleryUrl()')
ok(detailMenu.length > 0, 'detailMenu() exists', FILES.detail)
ok(
  /'label': \$r\('app\.string\.detail_favorite'\)/.test(detailMenu) &&
    /'icon': this\.favoriteTitleBarIcon\(\)/.test(detailMenu) &&
    /openRemoteFavorite\(\)/.test(detailMenu),
  'favorite action is a stateful title-menu item'
)
ok(
  favoriteIconBlock.length > 0 &&
    /this\.vm\.gallery\.favcat\.length > 0/.test(favoriteIconBlock) &&
    /this\.isLocalFavorite\(\)/.test(favoriteIconBlock) &&
    /sys\.symbol\.heart_fill/.test(favoriteIconBlock) &&
    /sys\.symbol\.heart'/.test(favoriteIconBlock) &&
    /favCatColor/.test(favoriteIconBlock),
  'favorite title-bar icon reflects remote favcat, local favorite, or outline heart'
)
ok(
  /detail_share/.test(detailMenu) && /sys\.symbol\.share/.test(detailMenu),
  'share action remains in the title-menu item set'
)
ok(
  !/favcat\.length|favCatColor|heart_fill|localFavoriteLabel|detail_share/.test(header),
  'GalleryHeaderCard does not render favorite/share actions inside the dense header'
)

// 3) Category badge: this is the gallery category tag (Image Set / Artist CG / …),
// and it must not be rendered as a tiny afterthought.
const categoryBlock = section(info, 'if (this.gallery.category.length > 0)', '        }\n        .width')
ok(categoryBlock.length > 0, 'category badge block exists', FILES.info)
ok(
  !/FONT_SIZE_TINY/.test(categoryBlock),
  'category badge must not use FONT_SIZE_TINY',
  'User-flagged hard fail: gallery category tag is visually too small.'
)
ok(
  !/padding\s*\(\s*\{[^}]*top:\s*1[^}]*bottom:\s*1/.test(categoryBlock.replace(/\n/g, ' ')),
  'category badge must not use 1px vertical padding',
  'Use a real chip/badge scale; 1px vertical padding is too small on device.'
)
// 3b) Category badge geometry must match the comfortable detail-chip family — it was left on the thin
// RADIUS_SM(4) + SPACE_XS(4) box while the tag chips were upgraded, so it read as the "old" square badge.
// Tie it to the shared chip tokens (CHIP_RADIUS + CHIP_LINE_HEIGHT + CHIP_PADDING_V), no flat leftovers.
ok(
  /\.borderRadius\(ThemeConstants\.CHIP_RADIUS\)/.test(categoryBlock),
  'category badge uses the comfortable CHIP_RADIUS (peer of the tag chips)',
  'The detail category/type badge must not stay on the flat RADIUS_SM while the chips are rounded.'
)
ok(
  !/\.borderRadius\(ThemeConstants\.RADIUS_SM\)/.test(categoryBlock),
  'category badge is not left on the flat RADIUS_SM'
)
ok(
  /\.lineHeight\(ThemeConstants\.CHIP_LINE_HEIGHT\)/.test(categoryBlock),
  'category badge sets CHIP_LINE_HEIGHT for a comfortable, even height'
)
ok(
  /top:\s*ThemeConstants\.CHIP_PADDING_V[\s\S]*?bottom:\s*ThemeConstants\.CHIP_PADDING_V/.test(categoryBlock),
  'category badge uses the shared CHIP_PADDING_V vertical padding (no thin SPACE_XS box)',
  'Vertical padding must be the shared comfortable chip token, not the thin SPACE_XS(4).'
)

// 4) InfoBar grouping: NextE card is already bounded, so no copied sliver accent bar.
// Explanatory comments such as "No left accent bar" are allowed; executable constants/layout are not.
ok(!/const\s+ACCENT_BAR_|ACCENT_BAR_|\.width\(ACCENT_BAR_W\)|\.height\(ACCENT_BAR_H\)/.test(info), 'InfoBar must not contain copied left accent bar')

// 5) InfoBar metadata icons: grid must remain quiet/outline; filled heart/star are too loud/mixed.
ok(!/sys\.symbol\.heart_fill/.test(info), 'InfoBar metadata must not use heart_fill')
ok(!/sys\.symbol\.star_fill/.test(info), 'InfoBar metadata must not use star_fill')
ok(/sys\.color\.font_tertiary/.test(info), 'InfoBar metadata icons use tertiary/quiet colour')

// 6) FAB spacing: detail content reserves bottom padding so the final content can scroll clear of the FAB.
ok(
  /bottomPadding:\s*ThemeConstants\.SPACE_XXL \+ ThemeConstants\.BUTTON_HEIGHT/.test(detail),
  'detail list reserves bottom padding for the page-level FAB'
)
ok(
  /\.position\(\{ left: 0, bottom: ThemeConstants\.SPACE_LG \}\)/.test(detail),
  'detail FAB rail sits at the bottom safe content edge (full-width rail)'
)
ok(
  /\.translate\(\{ x: this\.readFabVisualX\(\) \}\)/.test(detail),
  'detail FAB slides to the holding-hand side (smart-grip alignment) instead of a fixed corner'
)
ok(
  /@Local readFabLayoutReady: boolean = false/.test(detail) &&
    /@Local readFabShouldAnimate: boolean = false/.test(detail) &&
    /private onActionEdgeChanged\(\): void \{[\s\S]*this\.readFabShouldAnimate = this\.readFabLayoutReady[\s\S]*this\.visualActionEdge = this\.actionEdge\.edge/.test(detail) &&
    /private readFabAnimationDuration\(\): number \{[\s\S]*return this\.readFabShouldAnimate \? ThemeConstants\.ANIM_DURATION : 0/.test(detail) &&
    /\.opacity\(this\.readFabLayoutReady \? 1 : 0\)/.test(detail) &&
    /\.animation\(\{ duration: this\.readFabAnimationDuration\(\), curve: Curve\.EaseOut \}\)/.test(detail),
  'detail FAB hides first measurement placement, then animates real hand-edge changes'
)

// 7) Shared chip tokens exist in ThemeConstants.
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
const chipPadV = Number((/CHIP_PADDING_V:\s*number\s*=\s*(\d+)/.exec(theme) || [])[1])
ok(Number.isFinite(chipPadV) && chipPadV >= 4, `ThemeConstants defines a comfortable CHIP_PADDING_V (>=4); got ${chipPadV}`)

// 8) Long-title stress structure: the title/metadata block is a FLEXIBLE, CLIPPED group so a long title
// can never push the action row out; the action row is a RESERVED sibling (no Blank spacer that can
// collapse); the title line count is a budgeted METHOD, not a raw maxLines literal. JP + uploader stay
// bounded so they truncate too. This is what catches "maxLines exists but the action row is still pushed".
ok(
  /\.layoutWeight\(1\)[\s\S]{0,120}?\.clip\(true\)/.test(header),
  'title/metadata group is layoutWeight(1) + clip(true) — cannot push the action row out',
  'The flexible text group must clip, reserving the action row at the bottom of the fixed card.'
)
ok(/\.maxLines\(this\.titleMaxLines\(\)\)/.test(header), 'title uses budgeted titleMaxLines(), not a raw maxLines literal')
ok(/private titleMaxLines\(\): number/.test(header), 'titleMaxLines() budget method exists')
ok(
  !/Blank\(\)\s*\n\s*\/\/ Bottom action row/.test(header),
  'no Blank() spacer between the text group and the action row',
  'Action-row reservation must be structural (layoutWeight+clip), not a collapsible Blank spacer.'
)
ok(/japaneseTitle[\s\S]*?\.maxLines\(2\)/.test(header), 'JP title stays bounded to maxLines(2)')
ok(/this\.gallery\.uploader[\s\S]*?\.maxLines\(1\)/.test(header), 'uploader stays bounded to maxLines(1)')

// 9) Synthetic long-title budget: mirror titleMaxLines() + the real line-height tokens and assert that
// the WORST case (a very long title at its budgeted lines + JP(2 lines) + uploader(1 line)) still fits
// the FIXED card height — nothing overflows / clips / overlaps. Deterministic stand-in for a very long
// EN + JP + uploader stress gallery.
const COVER_H = Number((/const COVER_H:\s*number\s*=\s*(\d+)/.exec(header) || [])[1])
const tnum = (re) => Number((re.exec(theme) || [])[1])
const XS = tnum(/SPACE_XS:\s*number\s*=\s*(\d+)/)
const LH_TITLE = tnum(/LINE_HEIGHT_TITLE:\s*number\s*=\s*(\d+)/)
const LH_BODY = tnum(/LINE_HEIGHT_BODY:\s*number\s*=\s*(\d+)/)
ok([COVER_H, XS, LH_TITLE, LH_BODY].every((n) => Number.isFinite(n) && n > 0), 'parsed COVER_H + line-height tokens')
const titleMaxLines = (hasJp, hasUp) => {
  const textArea = COVER_H
  const jpR = hasJp ? 2 * LH_BODY + XS : 0
  const upR = hasUp ? LH_BODY + XS : 0
  const lines = Math.floor((textArea - jpR - upR) / LH_TITLE)
  return Math.min(Math.max(lines, 1), 6)
}
const stackHeight = (hasJp, hasUp) => {
  let h = titleMaxLines(hasJp, hasUp) * LH_TITLE
  if (hasJp) h += XS + 2 * LH_BODY
  if (hasUp) h += XS + LH_BODY
  return h
}
for (const [hasJp, hasUp] of [[true, true], [true, false], [false, true], [false, false]]) {
  ok(titleMaxLines(hasJp, hasUp) >= 1, `titleMaxLines >= 1 (jp=${hasJp}, uploader=${hasUp})`)
  ok(
    stackHeight(hasJp, hasUp) <= COVER_H,
    `worst-case header stack fits COVER_H=${COVER_H} (jp=${hasJp}, uploader=${hasUp}) → ${stackHeight(hasJp, hasUp)}`,
    'A long title + JP + uploader must fit the card; budget the title lines down.'
  )
}

if (failures > 0) {
  console.error(`\n✗ detail-header visual contract: ${failures} failure(s)`)
  console.error(`  files: ${relative(ROOT, join(ROOT, FILES.detail))}, ${relative(ROOT, join(ROOT, FILES.header))}, ${relative(ROOT, join(ROOT, FILES.info))}`)
  process.exit(1)
}

console.log('\n✓ detail-header visual contract passed')

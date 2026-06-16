#!/usr/bin/env node
/**
 * Hard contract for the gallery-detail header / InfoBar visual semantics.
 *
 * This is NOT a pixel test. It encodes user/product hard-fails that must be
 * caught before controller accepts a worker result:
 * - Read CTA must not include total page count (the count already lives in InfoBar).
 * - Category badge must not be tiny/visually negligible.
 * - InfoBar in a bordered NextE card must not keep eros_fe's borderless-sliver accent bar.
 * - InfoBar metadata icons must stay quiet/outline, not mix filled heart/star into the grid.
 * - Favourite state colour must be derived from the real EH favcat slot, not an accent/default token.
 *
 * Run: node scripts/test_detail_header_visual_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join, dirname, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const FILES = {
  header: 'feature/gallery/src/main/ets/components/GalleryHeaderCard.ets',
  info: 'feature/gallery/src/main/ets/components/GalleryInfoBar.ets',
}

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

// 1) Read CTA label: total page count in the button is a hard fail.
const readLabel = section(header, 'private readLabel()', '  build()')
ok(readLabel.length > 0, 'readLabel() exists', FILES.header)
ok(
  !/detail_read_with_count|gallery\.fileCount|fileCount\.length/.test(readLabel),
  'read CTA must not include total page count',
  'Use plain detail_read for first-read CTA; page count belongs to InfoBar. Resume state may use resumeIndex only.'
)
ok(
  /detail_read_resume/.test(readLabel) && /resumeIndex/.test(readLabel),
  'resume label may remain driven by resumeIndex',
  'The gate forbids total count in CTA, not resume affordance.'
)

// 2) Header favourite state colour: must be gated on favcat and use favcat slot colour only.
const favBlock = section(header, 'if (this.gallery.favcat.length > 0)', '            // Content-width capsule')
ok(favBlock.length > 0, 'favourite-state is gated on favcat slot', FILES.header)
ok(
  /EhConstants\.favCatColor\(this\.gallery\.favcat\)/.test(favBlock),
  'favourite heart colour comes from EhConstants.favCatColor(favcat)',
  'No brand/accent/default token may masquerade as a favourited state.'
)
ok(
  !/FAV_HEART_DEFAULT|font_emphasize|brand|accent/i.test(favBlock),
  'favourite-state block has no default/accent colour fallback',
  'Unfavourited detail header should show no fake coloured heart.'
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

// 6) Action-row sizing coordination: the Read pill + the favourite block share ONE tokenized action
// height (no raw height literal), the favourite heart uses a token, and the Read label uses a font token
// — so the two actions read as one coordinated family instead of a 36px capsule next to a floating glyph.
const actionRow = section(header, '// Bottom action row', '        .layoutWeight(1)')
ok(actionRow.length > 0, 'action row block exists', FILES.header)
ok(
  (actionRow.match(/ThemeConstants\.ACTION_HEIGHT/g) || []).length >= 2,
  'Read pill AND favourite block both use the shared ACTION_HEIGHT token',
  'Both detail-header actions must sit at the same tokenized height for a coordinated baseline.'
)
ok(
  !/\.height\(\s*\d/.test(actionRow),
  'no raw numeric height literal in the action row',
  'Action heights must be the ACTION_HEIGHT token, not a hardcoded pixel value (was a raw 36).'
)
ok(
  /heart_fill[\s\S]*?ThemeConstants\.ACTION_FAV_ICON/.test(actionRow),
  'favourite heart uses the ACTION_FAV_ICON token',
  'The favourite heart must be a coordinated token-sized peer to the Read pill.'
)
ok(
  /Button\(this\.readLabel\(\)\)[\s\S]*?\.fontSize\(ThemeConstants\.FONT_SIZE_BODY\)/.test(actionRow),
  'Read label uses the FONT_SIZE_BODY token (CTA weight, not a tiny caption)',
  'A pill at ACTION_HEIGHT needs a real label weight.'
)

// 7) The shared action tokens exist in ThemeConstants.
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
ok(/ACTION_HEIGHT:\s*number\s*=/.test(theme), 'ThemeConstants defines ACTION_HEIGHT')
ok(/ACTION_FAV_ICON:\s*number\s*=/.test(theme), 'ThemeConstants defines ACTION_FAV_ICON')
const chipPadV = Number((/CHIP_PADDING_V:\s*number\s*=\s*(\d+)/.exec(theme) || [])[1])
ok(Number.isFinite(chipPadV) && chipPadV >= 5, `ThemeConstants defines a comfortable CHIP_PADDING_V (>=5); got ${chipPadV}`)

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
// the WORST case (a very long title at its budgeted lines + JP(2 lines) + uploader(1 line) + the action
// row + gaps) still fits the FIXED card height — nothing overflows / clips / overlaps. Deterministic
// stand-in for a "very long EN + JP + uploader + favourited" stress gallery.
const COVER_H = Number((/const COVER_H:\s*number\s*=\s*(\d+)/.exec(header) || [])[1])
const tnum = (re) => Number((re.exec(theme) || [])[1])
const ACTION_H = tnum(/ACTION_HEIGHT:\s*number\s*=\s*(\d+)/)
const XS = tnum(/SPACE_XS:\s*number\s*=\s*(\d+)/)
const LH_TITLE = tnum(/LINE_HEIGHT_TITLE:\s*number\s*=\s*(\d+)/)
const LH_BODY = tnum(/LINE_HEIGHT_BODY:\s*number\s*=\s*(\d+)/)
ok([COVER_H, ACTION_H, XS, LH_TITLE, LH_BODY].every((n) => Number.isFinite(n) && n > 0), 'parsed COVER_H + action/line-height tokens')
const titleMaxLines = (hasJp, hasUp) => {
  const textArea = COVER_H - ACTION_H - XS
  const jpR = hasJp ? 2 * LH_BODY + XS : 0
  const upR = hasUp ? LH_BODY + XS : 0
  const lines = Math.floor((textArea - jpR - upR) / LH_TITLE)
  return Math.min(Math.max(lines, 1), 6)
}
const stackHeight = (hasJp, hasUp) => {
  let h = titleMaxLines(hasJp, hasUp) * LH_TITLE
  if (hasJp) h += XS + 2 * LH_BODY
  if (hasUp) h += XS + LH_BODY
  return h + XS + ACTION_H // + outer gap + the reserved action row
}
for (const [hasJp, hasUp] of [[true, true], [true, false], [false, true], [false, false]]) {
  ok(titleMaxLines(hasJp, hasUp) >= 1, `titleMaxLines >= 1 (jp=${hasJp}, uploader=${hasUp})`)
  ok(
    stackHeight(hasJp, hasUp) <= COVER_H,
    `worst-case header stack fits COVER_H=${COVER_H} (jp=${hasJp}, uploader=${hasUp}) → ${stackHeight(hasJp, hasUp)}`,
    'A long title + JP + uploader + action row must fit the card; budget the title lines down.'
  )
}

if (failures > 0) {
  console.error(`\n✗ detail-header visual contract: ${failures} failure(s)`)
  console.error(`  files: ${relative(ROOT, join(ROOT, FILES.header))}, ${relative(ROOT, join(ROOT, FILES.info))}`)
  process.exit(1)
}

console.log('\n✓ detail-header visual contract passed')

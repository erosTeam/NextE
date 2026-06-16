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

// 4) InfoBar grouping: NextE card is already bounded, so no copied sliver accent bar.
// Explanatory comments such as "No left accent bar" are allowed; executable constants/layout are not.
ok(!/const\s+ACCENT_BAR_|ACCENT_BAR_|\.width\(ACCENT_BAR_W\)|\.height\(ACCENT_BAR_H\)/.test(info), 'InfoBar must not contain copied left accent bar')

// 5) InfoBar metadata icons: grid must remain quiet/outline; filled heart/star are too loud/mixed.
ok(!/sys\.symbol\.heart_fill/.test(info), 'InfoBar metadata must not use heart_fill')
ok(!/sys\.symbol\.star_fill/.test(info), 'InfoBar metadata must not use star_fill')
ok(/sys\.color\.font_tertiary/.test(info), 'InfoBar metadata icons use tertiary/quiet colour')

if (failures > 0) {
  console.error(`\n✗ detail-header visual contract: ${failures} failure(s)`)
  console.error(`  files: ${relative(ROOT, join(ROOT, FILES.header))}, ${relative(ROOT, join(ROOT, FILES.info))}`)
  process.exit(1)
}

console.log('\n✓ detail-header visual contract passed')

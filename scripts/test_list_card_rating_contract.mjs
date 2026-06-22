#!/usr/bin/env node
/**
 * Hard contract for list/simple gallery-card rating stars.
 *
 * eros_fe tints the rating stars in the row-style list renderers by ThemeColors.colorRatingMap[colorRating]
 * (community orange / personal-rating variant) via StaticRatingBar — gallery_item.dart:478-482 and
 * gallery_item_simple.dart:196-201. The cover-first grid card intentionally does not render a rating
 * row; it is protected by test_gallery_grid_card_visual_contract.mjs. NextE list/simple cards must keep
 * using the shared RatingStars component (#36) with the raw colorRating, NOT the system-yellow ArkUI
 * Rating component.
 *
 * Run: node scripts/test_list_card_rating_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join, dirname, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const FILES = [
  'shared/src/main/ets/components/GalleryCard.ets',
  'shared/src/main/ets/components/GallerySimpleCard.ets',
]

let failures = 0
const fail = (label, detail) => {
  failures++
  console.error(`  ✗ ${label}`)
  if (detail) console.error(`    ${detail}`)
}
const ok = (cond, label, detail) => {
  if (!cond) fail(label, detail)
}

console.log('— list-card rating visual contract —')

for (const f of FILES) {
  const src = read(f)
  // 1) No system-yellow ArkUI Rating component for the star display.
  ok(
    !/Rating\(\{/.test(src),
    `${f}: must not use ArkUI Rating({ ... }) for rating stars`,
    'System-yellow Rating loses eros_fe colorRatingMap; use the shared RatingStars.'
  )
  // 2) Renders the shared tinted star component.
  ok(/RatingStars\s*\(\{/.test(src), `${f}: renders RatingStars({ ... })`)
  ok(/import\s*\{\s*RatingStars\s*\}\s*from\s*'\.\/RatingStars'/.test(src), `${f}: imports RatingStars`)
  // 3) The star colour is sourced from colorRating (orange default / personal variant), not a fixed token.
  ok(
    /colorRating:\s*this\.gallery\.colorRating/.test(src),
    `${f}: star colour receives raw gallery.colorRating`,
    'The fill must follow the gallery colorRating inside RatingStars, matching eros_fe StaticRatingBar colorLight.'
  )
}

if (failures > 0) {
  console.error(`\n✗ list-card rating contract: ${failures} failure(s)`)
  console.error(`  files: ${FILES.map((f) => relative(ROOT, join(ROOT, f))).join(', ')}`)
  process.exit(1)
}

console.log('\n✓ list-card rating visual contract passed')

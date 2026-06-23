#!/usr/bin/env node
/**
 * Contract: shared large-card radii stay aligned with V2Next's visual grammar.
 *
 * Grounding:
 * - ../V2Next/shared/src/main/ets/theme/ThemeConstants.ets uses RADIUS_MD = 22.
 * - ../V2Next/shared/src/main/ets/theme/ThemeConstants.ets uses RADIUS_CARD = 24.
 * - NextE gallery list cards use RADIUS_MD, grouped/detail/settings cards use RADIUS_CARD, and compact
 *   grid cards keep their own smaller radius.
 *
 * Run: node scripts/test_v2next_card_radius_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
const galleryCard = read('shared/src/main/ets/components/GalleryCard.ets')
const gridCard = read('shared/src/main/ets/components/GalleryGridCard.ets')
const grouped = read('shared/src/main/ets/components/GroupedListSection.ets')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok('medium card radius matches V2Next token',
  /static readonly RADIUS_MD: number = 22/.test(theme))
ok('large grouped card radius matches V2Next token',
  /static readonly RADIUS_CARD: number = 24/.test(theme))
ok('gallery list card keeps using the shared medium card radius',
  /\.borderRadius\(ThemeConstants\.RADIUS_MD\)/.test(galleryCard))
ok('grouped list sections keep using the shared large card radius',
  /@Param radius: number = ThemeConstants\.RADIUS_CARD/.test(grouped) &&
    /\.borderRadius\(this\.radius\)/.test(grouped))
ok('compact grid cards do not inherit the large grouped card radius',
  /static readonly GALLERY_GRID_CARD_RADIUS: number = 16/.test(theme) &&
    /\.borderRadius\(ThemeConstants\.GALLERY_GRID_CARD_RADIUS\)/.test(gridCard) &&
    !/\.borderRadius\(ThemeConstants\.RADIUS_CARD\)/.test(gridCard))

console.log(`✓ V2Next card radius contract: ${passed} assertions passed`)

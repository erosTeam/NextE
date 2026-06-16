#!/usr/bin/env node
/**
 * Contract for gallery cover PRESENTATION (EhThumbnail + its callers). User-flagged: list/detail covers
 * were crudely side-cropped (ImageFit.Cover over a frame taller than a cover's aspect), and the loading
 * placeholder used the system sub-background ≈ card_background → an unloaded/short cover blended into the
 * card and read as "the card is cut in half".
 *
 * Source of truth (eros_fe CoverImg): the cover sits over a DISTINCT grey backdrop (systemGrey5/6, never
 * the card surface) and is FITTED to its frame (letterbox) where the frame's aspect can differ from the
 * cover's — the whole cover shows, no crude crop. Where the frame IS the cover aspect (the grid cell),
 * Cover is correct because there is nothing to crop.
 *
 * This locks the CONTEXT-SPECIFIC strategy so it can't regress to one-size-fits-all:
 *   - EhThumbnail's backdrop is COVER_PLACEHOLDER (a DISTINCT token), never BG_SUB, in every branch.
 *   - EhThumbnail's objectFit is PARAM-DRIVEN (containFit), never hardcoded ImageFit.Cover.
 *   - list (GalleryCard) + detail (GalleryHeaderCard) pass containFit:true (frame ≠ cover aspect → fit);
 *     grid (GalleryGridCard) does NOT (frame == cover aspect → keep Cover).
 *   - cover_placeholder is defined in BOTH base + dark colour sets and is DISTINCT from card_background.
 *
 * Run: node scripts/test_cover_presentation_contract.mjs   (exit 1 on any failure)
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    failures++
    console.error(`✗ ${msg}`)
  }
}

const thumb = read('shared/src/main/ets/components/EhThumbnail.ets')
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
const listCard = read('shared/src/main/ets/components/GalleryCard.ets')
const gridCard = read('shared/src/main/ets/components/GalleryGridCard.ets')
const headerCard = read('feature/gallery/src/main/ets/components/GalleryHeaderCard.ets')
const baseColors = JSON.parse(read('entry/src/main/resources/base/element/color.json'))
const darkColors = JSON.parse(read('entry/src/main/resources/dark/element/color.json'))

// 1) EhThumbnail exposes the containFit param (default false so other callers are unaffected).
ok(/@Param\s+containFit:\s*boolean\s*=\s*false/.test(thumb), 'EhThumbnail declares @Param containFit (default false)')

// 2) Backdrop is the DISTINCT placeholder token in every Image branch — never BG_SUB.
const placeholderUses = (thumb.match(/\.backgroundColor\(ThemeConstants\.COVER_PLACEHOLDER\)/g) || []).length
ok(placeholderUses >= 3, `every cover branch backs onto COVER_PLACEHOLDER (>=3 branches); got ${placeholderUses}`)
ok(!/\.backgroundColor\(ThemeConstants\.BG_SUB\)/.test(thumb), 'no cover branch is left on BG_SUB (≈ card_background → blends in)')

// 3) objectFit is param-driven, never hardcoded to Cover.
const fitUses = (thumb.match(/\.objectFit\(this\.containFit \? ImageFit\.Contain : ImageFit\.Cover\)/g) || []).length
ok(fitUses >= 3, `every cover branch drives objectFit from containFit (>=3 branches); got ${fitUses}`)
ok(!/\.objectFit\(ImageFit\.Cover\)/.test(thumb), 'no cover branch hardcodes ImageFit.Cover (one-size-fits-all crop)')

// 4) Context-specific wiring: list + detail FIT; grid keeps Cover (no containFit).
ok(/containFit:\s*true/.test(listCard), 'list card (GalleryCard) passes containFit:true (frame taller than cover → fit, no side-crop)')
ok(/containFit:\s*true/.test(headerCard), 'detail header (GalleryHeaderCard) passes containFit:true (fixed box ≠ cover aspect → fit)')
ok(!/containFit/.test(gridCard), 'grid card (GalleryGridCard) does NOT pass containFit — its cell IS the cover aspect, Cover is correct')

// 5) Token + colour resources: COVER_PLACEHOLDER defined, distinct, present in both themes.
ok(/COVER_PLACEHOLDER:\s*ResourceColor\s*=\s*\$r\('app\.color\.cover_placeholder'\)/.test(theme), 'ThemeConstants.COVER_PLACEHOLDER maps to app.color.cover_placeholder')
const colorOf = (set, name) => {
  const e = (set.color || []).find((c) => c.name === name)
  return e ? String(e.value).toUpperCase() : ''
}
const baseCover = colorOf(baseColors, 'cover_placeholder')
const baseCard = colorOf(baseColors, 'card_background')
const darkCover = colorOf(darkColors, 'cover_placeholder')
const darkCard = colorOf(darkColors, 'card_background')
ok(baseCover.length > 0, 'base cover_placeholder colour is defined')
ok(darkCover.length > 0, 'dark cover_placeholder colour is defined')
ok(baseCover !== baseCard, `base cover_placeholder (${baseCover}) is DISTINCT from card_background (${baseCard})`)
ok(darkCover !== darkCard, `dark cover_placeholder (${darkCover}) is DISTINCT from card_background (${darkCard})`)

if (failures === 0) {
  console.log('✓ cover presentation contract: distinct grey backdrop + context-specific fit (list/detail fit, grid cover)')
  process.exit(0)
}
console.error(`✗ cover presentation contract: ${failures} failure(s)`)
process.exit(1)

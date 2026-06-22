#!/usr/bin/env node
/**
 * Contract test for gallery rating inheritance:
 *   - EhGallery.merge only lets non-empty/non-zero values win.
 *   - GalleryDetailViewModel preserves list/gdata seed rating presentation on first open, while
 *     refresh trusts the freshly fetched detail.
 *
 * Locks the SUBTLE-but-correct behavior the re-triage mis-flagged as "list-seed colorRating dropped":
 * the detail parse provides a precise rating/ratingCount and may provide EH's sprite-derived
 * ratingFallBack, but empty personal-vote fields (colorRating / isRated) must not clobber a list seed.
 * merge() only overwrites a field when the detail value is non-empty/non-zero. So personal colour state
 * survives when detail has no stronger value, while precise detail values win.
 *
 * The merge mirror below is copy-equal to EhGallery.merge's rating block. Mirror on change.
 *
 * Run: node scripts/test_gallery_merge_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// Mirror of EhGallery.merge's rating block (non-empty/non-zero detail value wins; else seed survives).
function mergeRating(seed, o) {
  const g = { ...seed }
  if (o.rating > 0) g.rating = o.rating
  if (o.ratingFallBack > 0) g.ratingFallBack = o.ratingFallBack
  if (o.ratingCount.length > 0) g.ratingCount = o.ratingCount
  if (o.colorRating.length > 0) g.colorRating = o.colorRating
  if (o.isRated) g.isRated = o.isRated
  return g
}

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

// A list seed with a personal vote, merged with a detail parse that has rating/ratingCount/ratingFallBack
// but no personal colour class. Detail display rating wins; empty colour/isRated do not clobber the seed.
{
  const seed = { rating: 4.0, ratingFallBack: 4.2, ratingCount: '50', colorRating: 'c', isRated: true }
  const detail = { rating: 4.5, ratingFallBack: 3.5, ratingCount: '1234', colorRating: '', isRated: false }
  const m = mergeRating(seed, detail)
  ok('detail precise rating wins', m.rating === 4.5)
  ok('detail ratingCount wins', m.ratingCount === '1234')
  ok('seed colorRating PRESERVED (detail empty)', m.colorRating === 'c')
  ok('seed isRated PRESERVED (detail false)', m.isRated === true)
  ok('detail ratingFallBack wins when parsed', m.ratingFallBack === 3.5)
}

// When the detail DOES carry a stronger value, it wins (the override path still works).
{
  const seed = { rating: 0, ratingFallBack: 0, ratingCount: '', colorRating: '', isRated: false }
  const detail = { rating: 3.5, ratingFallBack: 0, ratingCount: '7', colorRating: '', isRated: false }
  const m = mergeRating(seed, detail)
  ok('empty seed takes detail rating', m.rating === 3.5)
  ok('empty seed takes detail count', m.ratingCount === '7')
}

// Structural guard: the detail parser may set display rating, but must not invent personal colour state
// unless the #rating_image class contains the real EH personal-rating variant.
{
  const parser = readFileSync(join(ROOT, 'shared/src/main/ets/parser/EhGalleryDetailParser.ets'), 'utf8')
  ok('detail parser reads rating image attrs', /RE_RATING_ATTRS/.test(parser))
  ok('detail parser sets ratingFallBack from EH sprite position', /\.ratingFallBack\s*=/.test(parser) && /80 - x/.test(parser))
  ok('detail parser colorRating comes from ratingVariant only', /g\.colorRating = ratingVariant/.test(parser))
  ok('detail parser isRated is gated by ratingVariant length', /g\.isRated = ratingVariant\.length > 0/.test(parser))
  const model = readFileSync(join(ROOT, 'shared/src/main/ets/model/EhGallery.ets'), 'utf8')
  ok('merge guards colorRating on non-empty', /if \(o\.colorRating\.length > 0\) g\.colorRating = o\.colorRating/.test(model))
  ok('merge guards isRated on true', /if \(o\.isRated\) g\.isRated = o\.isRated/.test(model))
  ok('merge guards ratingFallBack on non-zero', /if \(o\.ratingFallBack > 0\) g\.ratingFallBack = o\.ratingFallBack/.test(model))
}

// VM-level guard: first open preserves list/gdata seed rating colour; refresh does not.
{
  const vm = readFileSync(join(ROOT, 'feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets'), 'utf8')
  ok('load passes non-refresh fetch flag', /await this\.fetchAndApply\(gid, token, false\)/.test(vm))
  ok('refresh passes refresh fetch flag', /await this\.fetchAndApply\(this\.gid, this\.token, true\)/.test(vm))
  ok('fetchAndApply accepts refresh flag', /private async fetchAndApply\(gid: string, token: string, refresh: boolean\)/.test(vm))
  ok('VM snapshots seed colorRating before detail merge', /const seedColorRating: string = this\.gallery\.colorRating/.test(vm))
  ok('non-refresh applies seed rating after merge', /this\.gallery = await this\.translateGallery\(this\.gallery\.merge\(res\.gallery\)\)[\s\S]*if \(!refresh\) \{[\s\S]*this\.applyNonRefreshSeedRating/.test(vm))
  ok('seed colorRating wins on first open', /if \(seedColorRating\.length > 0\) \{[\s\S]*this\.gallery\.colorRating = seedColorRating/.test(vm))
  ok('seed ratingCount only fills a weak detail count', /seedRatingCount\.length > 0 && this\.gallery\.ratingCount\.length === 0/.test(vm))
  ok('seed ratingFallBack only fills a weak detail display rating', /seedRatingFallBack > 0 && this\.gallery\.ratingFallBack <= 0/.test(vm))
}

console.log(`✓ gallery merge rating-inheritance contract: ${passed} assertions passed`)

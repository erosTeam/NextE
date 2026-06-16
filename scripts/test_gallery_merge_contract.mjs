#!/usr/bin/env node
/**
 * Contract test for EhGallery.merge rating-inheritance (shared/src/main/ets/model/EhGallery.ets).
 *
 * Locks the SUBTLE-but-correct behavior the re-triage mis-flagged as "list-seed colorRating dropped":
 * the detail parse provides a precise rating/ratingCount but NEVER sets the personal-vote fields
 * (colorRating / isRated / ratingFallBack — EhGalleryDetailParser only sets rating + ratingCount), and
 * merge() only overwrites a field when the detail value is non-empty/non-zero. So the LIST seed's
 * personal-vote fields survive the detail merge, while the precise rating/count win. This is correct
 * inheritance, not a bug — this test guards against a future regression that would clobber the seed.
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

// A list seed with a personal vote, merged with a detail parse (which sets rating+ratingCount only,
// exactly as EhGalleryDetailParser does — colorRating/isRated/ratingFallBack stay at their defaults).
{
  const seed = { rating: 4.0, ratingFallBack: 4.2, ratingCount: '50', colorRating: 'c', isRated: true }
  const detail = { rating: 4.5, ratingFallBack: 0, ratingCount: '1234', colorRating: '', isRated: false }
  const m = mergeRating(seed, detail)
  ok('detail precise rating wins', m.rating === 4.5)
  ok('detail ratingCount wins', m.ratingCount === '1234')
  ok('seed colorRating PRESERVED (detail empty)', m.colorRating === 'c')
  ok('seed isRated PRESERVED (detail false)', m.isRated === true)
  ok('seed ratingFallBack PRESERVED (detail 0)', m.ratingFallBack === 4.2)
}

// When the detail DOES carry a stronger value, it wins (the override path still works).
{
  const seed = { rating: 0, ratingFallBack: 0, ratingCount: '', colorRating: '', isRated: false }
  const detail = { rating: 3.5, ratingFallBack: 0, ratingCount: '7', colorRating: '', isRated: false }
  const m = mergeRating(seed, detail)
  ok('empty seed takes detail rating', m.rating === 3.5)
  ok('empty seed takes detail count', m.ratingCount === '7')
}

// Structural guard: the detail parser must NOT set the personal-vote fields (the premise of the above).
{
  const parser = readFileSync(join(ROOT, 'shared/src/main/ets/parser/EhGalleryDetailParser.ets'), 'utf8')
  ok('detail parser does not set colorRating', !/\.colorRating\s*=/.test(parser))
  ok('detail parser does not set isRated', !/\.isRated\s*=/.test(parser))
  ok('detail parser does not set ratingFallBack', !/\.ratingFallBack\s*=/.test(parser))
  const model = readFileSync(join(ROOT, 'shared/src/main/ets/model/EhGallery.ets'), 'utf8')
  ok('merge guards colorRating on non-empty', /if \(o\.colorRating\.length > 0\) g\.colorRating = o\.colorRating/.test(model))
  ok('merge guards isRated on true', /if \(o\.isRated\) g\.isRated = o\.isRated/.test(model))
}

console.log(`✓ gallery merge rating-inheritance contract: ${passed} assertions passed`)

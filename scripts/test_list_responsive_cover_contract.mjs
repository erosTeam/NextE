#!/usr/bin/env node
/**
 * Contract for GalleryCard responsive cover sizing.
 *
 * User-flagged foldable regression: GalleryCard used a module-level startup display cache
 * (`display.getDefaultDisplaySync()` → shortestSide / 3). On Mate X7 fold/unfold, the cached
 * value survived in-process display changes, and wide panes incorrectly kept phone sizing.
 *
 * Locks the replacement:
 *   - no startup display cache in GalleryCard;
 *   - PullRefreshListScaffold measures current list content width with onAreaChange;
 *   - every list-card caller passes the measured pane width to GalleryCard;
 *   - GalleryCard mirrors eros_fe sizing: narrow pane = contentWidth / 3, wide pane =
 *     0.7 * kFixedHeight = 142.8vp, with fixed row rhythm at kFixedHeight = 204vp.
 *   - GalleryCard uses an explicit contain-fit cover slot with parsed source dimensions, so high/narrow
 *     source covers cannot force row height during fixed-list rendering.
 *
 * Run: node scripts/test_list_responsive_cover_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

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

const numberFromTheme = (name) => {
  const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
  const re = new RegExp(`${name}:\\s*number\\s*=\\s*([0-9.]+)`)
  const m = re.exec(theme)
  if (!m) {
    throw new Error(`ThemeConstants missing ${name}`)
  }
  return Number(m[1])
}

const FIXED_H = numberFromTheme('LIST_CARD_FIXED_HEIGHT')
const WIDE_W = numberFromTheme('LIST_CARD_WIDE_COVER_WIDTH')
const ASPECT = numberFromTheme('LIST_CARD_COVER_ASPECT')

const coverWidth = (contentWidth) => {
  const resolved = contentWidth > 0 ? contentWidth : WIDE_W * 3
  const narrow = resolved / 3
  return narrow < WIDE_W ? narrow : WIDE_W
}

// 1. Source contract: GalleryCard must not read or cache global display dimensions.
{
  const c = read('shared/src/main/ets/components/GalleryCard.ets')
  for (const forbidden of [
    '@kit.ArkUI',
    'display.getDefaultDisplaySync',
    'display.Display',
    '_coverW',
    'px2vp',
    'shortSide',
    'cardCoverWidth',
    'cardMinHeight',
  ]) {
    ok(!c.includes(forbidden), `GalleryCard does not use startup display cache token: ${forbidden}`)
  }
  ok(/@Param\s+listContentWidth:\s*number\s*=\s*0/.test(c), 'GalleryCard accepts measured listContentWidth')
  ok(/private\s+coverWidth\(\):\s*number/.test(c), 'GalleryCard computes cover width locally')
  ok(/this\.listContentWidth\s*>\s*0/.test(c), 'coverWidth uses measured pane width when available')
  ok(/const\s+narrowWidth:\s*number\s*=\s*contentWidth\s*\/\s*3/.test(c), 'narrow pane width is contentWidth / 3')
  ok(/ThemeConstants\.LIST_CARD_WIDE_COVER_WIDTH/.test(c), 'wide pane width is bounded by the eros_fe wide width token')
  ok(/thumbWidth:\s*this\.coverWidth\(\)/.test(c), 'EhThumbnail width comes from current coverWidth()')
  ok(/private\s+coverHeight\(\):\s*number/.test(c), 'GalleryCard computes cover height locally')
  ok(/@Local\s+coverSlotHeight:\s*number\s*=\s*0/.test(c), 'GalleryCard records the actual stretched cover slot height')
  ok(/private\s+activeCoverHeight\(\):\s*number/.test(c), 'GalleryCard resolves the active cover slot height')
  ok(/thumbHeight:\s*this\.activeCoverHeight\(\)/.test(c), 'EhThumbnail height comes from the active cover slot height')
  ok(/sourceWidth:\s*this\.gallery\.imgWidth/.test(c), 'list cover passes parsed sourceWidth into EhThumbnail')
  ok(/sourceHeight:\s*this\.gallery\.imgHeight/.test(c), 'list cover passes parsed sourceHeight into EhThumbnail')
  ok(!/stretchHeight:\s*true/.test(c), 'list cover does not use intrinsic stretchHeight')
  ok(/minHeight:\s*ThemeConstants\.LIST_CARD_FIXED_HEIGHT/.test(c), 'fixed mode pins minHeight to kFixedHeight token')
  ok(/maxHeight:\s*ThemeConstants\.LIST_CARD_FIXED_HEIGHT/.test(c), 'fixed mode pins maxHeight to kFixedHeight token')
  ok(/minHeight:\s*this\.adaptiveMinHeight\(\)/.test(c), 'adaptive mode floors from responsive cover height')
  // Cover fit is now ratio-aware: close source ratios fill the slot (Cover, light crop); far ratios
  // letterbox (Contain) so EhThumbnail can fill the gaps with the cover-color gradient/blur. The Contain
  // path (the original regression guard against a grey slab) is preserved for the far case.
  ok(/private\s+coverFillsSlot\(\):\s*boolean/.test(c), 'GalleryCard decides close-ratio fill vs far-ratio contain via coverFillsSlot()')
  ok(/const\s+slotRatio:\s*number\s*=\s*this\.coverWidth\(\)\s*\/\s*this\.activeCoverHeight\(\)/.test(c), 'cover fit compares the image against the active container ratio')
  ok(/\.onAreaChange\([\s\S]*area\.height\s+as\s+number[\s\S]*this\.coverSlotHeight\s*=\s*height/.test(c), 'adaptive list cover measures the stretched container height')
  ok(/containFit:\s*!this\.coverFillsSlot\(\)/.test(c), 'list cover letterboxes (Contain) only when the cover does not fill the slot')
  ok(/letterboxBackground:\s*true/.test(c), 'list cover opts into the letterbox gap background (cover-color gradient / blur)')
}

// 2. Theme token values mirror eros_fe gallery_item.dart.
eq(FIXED_H, 204, 'LIST_CARD_FIXED_HEIGHT mirrors eros_fe kFixedHeight')
eq(WIDE_W, 142.8, 'LIST_CARD_WIDE_COVER_WIDTH mirrors 0.7 * 204')
eq(ASPECT, 0.71, 'LIST_CARD_COVER_ASPECT preserves existing cover-height fallback')
eq(coverWidth(360), 120, '360vp narrow pane -> 1/3 cover width')
eq(coverWidth(420), 140, '420vp narrow pane -> 1/3 cover width')
eq(coverWidth(600), 142.8, '600vp wide pane -> capped wide cover width')
eq(coverWidth(900), 142.8, '900vp wide pane does not grow row height')
eq(coverWidth(0), 142.8, 'pre-measure fallback is stable wide cover width, not startup display width')

// 3. Scaffold measures the CURRENT list pane and emits content width after horizontal padding.
{
  const s = read('shared/src/main/ets/components/PullRefreshListScaffold.ets')
  ok(/@Local\s+measuredWidth:\s*number\s*=\s*0/.test(s), 'PullRefreshListScaffold stores measured width reactively')
  ok(/@Event\s+onContentWidth\?:\s*\(contentWidth:\s*number\)\s*=>\s*void/.test(s), 'PullRefreshListScaffold exposes onContentWidth event')
  ok(/\.onAreaChange\(/.test(s), 'PullRefreshListScaffold observes area changes')
  ok(/this\.measuredWidth\s*=\s*newValue\.width\s+as\s+number/.test(s), 'onAreaChange captures current list width')
  ok(/this\.measuredWidth\s*-\s*2\s*\*\s*this\.horizontalPadding/.test(s), 'content width subtracts horizontal padding')
  ok(/this\.onContentWidth\(contentWidth > 0 \? contentWidth : 0\)/.test(s), 'measured content width is published to caller')
}

// 4. Every list-card caller passes the measured pane width.
{
  const callers = [
    'feature/home/src/main/ets/components/GalleryListBody.ets',
    'feature/search/src/main/ets/pages/GallerySearchPage.ets',
    'feature/user/src/main/ets/components/FavcatPage.ets',
  ]
  for (const rel of callers) {
    const src = read(rel)
    ok(new RegExp('@Local\\s+listContentWidth:\\s*number\\s*=\\s*0').test(src), `${rel}: stores listContentWidth`)
    ok(/onContentWidth:\s*\(contentWidth:\s*number\)\s*=>\s*\{[\s\S]*?this\.listContentWidth\s*=\s*contentWidth/.test(src), `${rel}: consumes onContentWidth`)
    ok(/GalleryCard\(\{\s*gallery:\s*g,\s*listContentWidth:\s*this\.listContentWidth\s*\}\)/.test(src), `${rel}: passes measured width into GalleryCard`)
  }
}

// 5. No stray GalleryCard call is allowed to omit listContentWidth.
{
  const roots = ['entry', 'feature', 'shared']
  const files = []
  const walk = (abs) => {
    for (const name of readdirSync(abs)) {
      const p = join(abs, name)
      const st = statSync(p)
      if (st.isDirectory()) {
        if (name !== 'build' && name !== 'oh_modules') {
          walk(p)
        }
      } else if (p.endsWith('.ets')) {
        files.push(p)
      }
    }
  }
  roots.forEach((r) => walk(join(ROOT, r)))
  for (const abs of files) {
    const rel = abs.substring(ROOT.length + 1)
    const src = readFileSync(abs, 'utf8')
    const matches = src.matchAll(/GalleryCard\(\{([\s\S]*?)\}\)/g)
    for (const m of matches) {
      ok(m[1].includes('listContentWidth'), `${rel}: GalleryCard call passes listContentWidth`)
    }
  }
}

// 6. Harness and loop docs include this gate so it is not a one-off local check.
{
  const harness = JSON.parse(read('.harness/config.json'))
  ok(
    harness.gates.some(
      (gate) =>
        gate.name === 'list-responsive-cover' &&
        gate.command === 'node scripts/test_list_responsive_cover_contract.mjs' &&
        gate.blocking === true,
    ),
    'harness registers list-responsive-cover gate',
  )
  ok(read('docs/loop.md').includes('node scripts/test_list_responsive_cover_contract.mjs'), 'docs/loop.md lists list-responsive-cover gate')
}

console.log(`✓ list responsive cover contract: ${passed} assertions passed`)

#!/usr/bin/env node
/**
 * Contract for the detail-page tag chips (GalleryTagsCard). User-flagged: the chips were too thin and
 * not rounded enough (RADIUS_SM=4 + 3px vertical padding read as flat boxes). This locks the comfortable
 * chip GEOMETRY and, just as importantly, the colour/state SEMANTICS that the shape fix must preserve.
 *
 * Geometry: both the namespace label and the member chips use a comfortably-rounded CHIP_RADIUS (>=8,
 * eros_fe TagButton is 8), >=5px vertical padding, and an explicit CHIP_LINE_HEIGHT — no leftover
 * RADIUS_SM or 3px vertical padding.
 * Semantics (must be preserved): namespace colour only on the namespace label; member chip background is
 * the usertag fill or neutral grey (NEVER namespace); member text is vote-coloured → usertag → neutral;
 * the ForEach key carries the usertag signal version (late My-Tags recolour); chips wrap; tapping a
 * member chip publishes an eros_fe-style `namespace:rawTag` search query through the shared search bus.
 *
 * Run: node scripts/test_tag_chip_contract.mjs   (exit 1 on any failure)
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

const card = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')

// 1) Tokens exist with comfortable values.
const chipRadius = Number((/CHIP_RADIUS:\s*number\s*=\s*(\d+)/.exec(theme) || [])[1])
const chipLine = Number((/CHIP_LINE_HEIGHT:\s*number\s*=\s*(\d+)/.exec(theme) || [])[1])
ok(Number.isFinite(chipRadius) && chipRadius >= 8, `CHIP_RADIUS defined and comfortably rounded (>=8); got ${chipRadius}`)
ok(Number.isFinite(chipLine) && chipLine >= 14, `CHIP_LINE_HEIGHT defined (>=14); got ${chipLine}`)

// 2) Geometry: both chips use CHIP_RADIUS + CHIP_LINE_HEIGHT + >=5px vertical padding; nothing left at
// the old flat values.
ok((card.match(/\.borderRadius\(ThemeConstants\.CHIP_RADIUS\)/g) || []).length >= 2, 'both namespace label + member chips use CHIP_RADIUS')
ok(!/\.borderRadius\(ThemeConstants\.RADIUS_SM\)/.test(card), 'no chip is left at the flat RADIUS_SM')
ok((card.match(/\.lineHeight\(ThemeConstants\.CHIP_LINE_HEIGHT\)/g) || []).length >= 2, 'both chips set CHIP_LINE_HEIGHT for an even, comfortable height')
ok((card.match(/top:\s*ThemeConstants\.CHIP_PADDING_V,\s*bottom:\s*ThemeConstants\.CHIP_PADDING_V/g) || []).length >= 2, 'both chips use the shared CHIP_PADDING_V vertical padding (comfortable height, single source)')
ok(!/top:\s*3,\s*bottom:\s*3/.test(card), 'no chip is left at the thin 3px vertical padding')
const chipPadV = Number((/CHIP_PADDING_V:\s*number\s*=\s*(\d+)/.exec(theme) || [])[1])
ok(Number.isFinite(chipPadV) && chipPadV >= 5, `CHIP_PADDING_V defined and comfortable (>=5); got ${chipPadV}`)

// 3) Semantics preserved — namespace colour ONLY on the namespace label.
ok(/\.backgroundColor\(EhConstants\.tagNamespaceColor\(tg\.namespace\)\)/.test(card), 'namespace label keeps its namespace-tint background')
ok(/\.backgroundColor\(this\.chipBg\(t, tg\.namespace\)\)/.test(card), 'member chip background comes from chipBg(), not the namespace tint')

// 4) Member chip colour resolution preserved (chipBg = usertag fill | neutral; chipText = vote | usertag | neutral).
const chipBg = (() => {
  const m = /chipBg\(t: SimpleTag, ns: string\): ResourceColor \{[\s\S]*?\n  \}/.exec(card)
  return m ? m[0] : ''
})()
ok(/u\.fillColor/.test(chipBg), 'chipBg uses the usertag fillColor when the user coloured the tag')
ok(/ohos_id_color_sub_background/.test(chipBg), 'chipBg falls back to neutral grey (never namespace)')
ok(!/tagNamespaceColor/.test(chipBg), 'chipBg never uses the namespace colour for members')

const chipText = (() => {
  const m = /chipText\(t: SimpleTag, ns: string\): ResourceColor \{[\s\S]*?\n  \}/.exec(card)
  return m ? m[0] : ''
})()
ok(/t\.vote > 0[\s\S]*?tag_vote_up/.test(chipText), 'chipText keeps the upvote colour')
ok(/t\.vote < 0[\s\S]*?tag_vote_down/.test(chipText), 'chipText keeps the downvote colour')
ok(/u\.textColor/.test(chipText), 'chipText keeps the usertag text colour')
ok(/font_secondary/.test(chipText), 'chipText keeps the neutral default')

// 5) Reactivity + wrapping preserved.
ok(/this\.tagSig\.version[\s\S]*?:\$\{tg\.namespace\}:\$\{t\.text\}/.test(card) || /\$\{this\.tagSig\.version\}/.test(card), 'ForEach key carries the usertag-signal version (late My-Tags recolour)')
ok(/Flex\(\{\s*wrap:\s*FlexWrap\.Wrap\s*\}\)/.test(card), 'member chips still wrap (FlexWrap.Wrap)')

// 6) Detail tag tap-to-search: eros_fe TagButton.onPressed opens Search with `${tag.type}:${tag.title.trim()}`.
ok(/connectSearchAction/.test(card), 'GalleryTagsCard imports/connects to the shared search action bus')
ok(/private\s+searchTag\(ns:\s*string,\s*t:\s*SimpleTag\):\s*void/.test(card), 'GalleryTagsCard has a scoped tag-search helper')
ok(/const\s+namespace:\s*string\s*=\s*ns\.trim\(\)/.test(card), 'tag search trims the namespace')
ok(/const\s+tag:\s*string\s*=\s*t\.text\.trim\(\)/.test(card), 'tag search uses the raw EH tag text, not translated display text')
ok(/publishQuery\(`\$\{namespace\}:\$\{tag\}`\)/.test(card), 'tag search publishes namespace:rawTag query')
ok(/\.onClick\(\(\)\s*=>\s*\{[\s\S]*?this\.searchTag\(tg\.namespace,\s*t\)[\s\S]*?\}\)/.test(card), 'member chip onClick triggers tag search')
ok(!/publishQuery\(`\$\{namespace\}:\$\{t\.display\(\)\}`\)/.test(card), 'tag search does not use translated display text in the query')

if (failures === 0) {
  console.log('✓ tag chip contract: comfortable chips, namespace/usertag/vote colour, wrap semantics, and tag tap-to-search preserved')
  process.exit(0)
}
console.error(`✗ tag chip contract: ${failures} failure(s)`)
process.exit(1)

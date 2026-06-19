#!/usr/bin/env node
/**
 * Contract: gallery comment UP and score badges share one compact, low-weight visual grammar.
 *
 * Grounding:
 * - eros_fe comment_item.dart renders UP and score as the same compact 18px pill in _CommentHead.
 * - NextE keeps UP branded, but score badges must be neutral/low-weight so they do not compete with
 *   the comment body. The full comments page score badge remains tappable for parsed score details.
 *
 * Run: node scripts/test_gallery_comment_badge_style_contract.mjs
 */
import fs from 'fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

const card = read('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets')
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')

ok('comment badge sizing is centralized in ThemeConstants',
  /COMMENT_BADGE_HEIGHT: number = 18/.test(theme) &&
    /COMMENT_BADGE_MIN_WIDTH: number = 18/.test(theme) &&
    /COMMENT_BADGE_PADDING_H: number = 7/.test(theme) &&
    /COMMENT_BADGE_RADIUS: number = 9/.test(theme))
ok('GalleryCommentsCard has one shared CommentBadge builder',
  /@Builder[\s\S]*CommentBadge\(label: ResourceStr, primary: boolean\)[\s\S]*COMMENT_BADGE_HEIGHT/.test(card) &&
    /@Builder[\s\S]*CommentBadge\(label: ResourceStr, primary: boolean\)[\s\S]*COMMENT_BADGE_RADIUS/.test(card))
ok('UP badge uses the shared builder and remains branded',
  /if \(c\.isUploader\) \{[\s\S]*this\.CommentBadge\(\$r\('app\.string\.comment_uploader'\), true\)/.test(card) &&
    /backgroundColor\(primary \? ThemeConstants\.BRAND_PRIMARY : ThemeConstants\.DIVIDER\)/.test(card))
ok('score badge uses the same builder and remains tappable',
  /this\.CommentBadge\(this\.displayScore\(c\.score\), false\)[\s\S]*this\.showScoreDetails\(c\)/.test(card))
ok('score badge normalizes unsigned scores to +N',
  /private displayScore\(score: string\): string[\s\S]*value\.startsWith\('\+'\)[\s\S]*value\.startsWith\('-'\)[\s\S]*return `\+\$\{value\}`/.test(card))
ok('score badge no longer uses saturated positive or negative backgrounds',
  !/score_positive|score_negative/.test(card))
ok('detail peek still suppresses numeric score badges',
  /c\.score\.length > 0 && this\.max <= 0/.test(card))

for (const locale of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(`${locale} comment_uploader is the short UP badge label`,
    /"name": "comment_uploader",\s*"value": "UP"/.test(strings))
}

if (failures === 0) {
  console.log('✓ gallery comment badge style contract passed')
  process.exit(0)
}
console.error(`✗ gallery comment badge style contract: ${failures} failure(s)`)
process.exit(1)

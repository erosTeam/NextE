#!/usr/bin/env node
/**
 * Contract: full comments page exposes parsed scoreDetails without enabling comment write actions.
 *
 * Run: node scripts/test_comment_score_details_contract.mjs
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
ok(
  'full comments score chip opens native score-details dialog',
  /private showScoreDetails\(c: EhGalleryComment\): void[\s\S]*showAlertDialog\(\{[\s\S]*comment_score_details[\s\S]*c\.scoreDetails\.join\('\\n'\)/.test(card),
)
ok(
  'score details are full-page only and unavailable in detail peek',
  /if \(this\.max > 0 \|\| c\.scoreDetails\.length === 0\)/.test(card) &&
    /c\.score\.length > 0 && this\.max <= 0/.test(card),
)
ok(
  'score badge is an explicit tappable affordance',
  /\.backgroundColor\([\s\S]*score_negative[\s\S]*score_positive[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.showScoreDetails\(c\)/.test(card),
)
ok(
  'comment score-details lane does not add destructive comment write actions',
  !/vote_comment|edit_comment|reply_comment|post_comment|submitComment/.test(card),
)

for (const locale of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(`${locale} has comment_score_details string`, /"name": "comment_score_details"/.test(strings))
  ok(`${locale} has common_ok string`, /"name": "common_ok"/.test(strings))
}

if (failures === 0) {
  console.log('✓ comment score-details contract passed')
  process.exit(0)
}
console.error(`✗ comment score-details contract: ${failures} failure(s)`)
process.exit(1)

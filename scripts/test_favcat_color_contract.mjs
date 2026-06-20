#!/usr/bin/env node
/**
 * Contract: favcat identity colors match eros_fe ThemeColors.favColor.
 *
 * Run: node scripts/test_favcat_color_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const src = readFileSync(join(ROOT, 'shared/src/main/ets/constants/EhConstants.ets'), 'utf8')
const selector = readFileSync(join(ROOT, 'feature/user/src/main/ets/pages/FavoriteSelectorPage.ets'), 'utf8')
let failures = 0
let passed = 0

function ok(cond, msg) {
  if (!cond) {
    failures += 1
    console.error(`✗ ${msg}`)
  } else {
    passed += 1
  }
}

const expected = [
  '#5F5F5F',
  '#DE1C31',
  '#F97D1C',
  '#F8B500',
  '#2BAE85',
  '#5BAE23',
  '#22A2C3',
  '#1661AB',
  '#9F3EF9',
  '#EC2D7A',
]

for (const color of expected) {
  ok(src.includes(`'${color}'`), `FE favcat color present: ${color}`)
}

ok(/slot === 'a'[\s\S]*return '#B5A4A4'/.test(src),
  'All favorites uses FE favcat color #B5A4A4')
ok(/slot === 'l'[\s\S]*return '#A99E68'/.test(src),
  'Local favorite uses FE favcat color #A99E68')
ok(!/#23b26d|#000000|#ee0000|#ffaa00|#dddd00|#008800|#99ff44|#4499ff|#0000ff|#550088|#ee88ee/i.test(src),
  'old NextE/self-picked favcat colors are not retained')
ok(/private FavcatPrefix\(favId: string\)[\s\S]*this\.colorFor\(favId\)/.test(selector),
  'Favorite selector uses favcat color only for the identity icon')
ok(/private FavcatSuffix\(fc: Favcat\)[\s\S]*fontColor\(\$r\('sys\.color\.font_secondary'\)\)/.test(selector) &&
  !/secondaryColor: this\.colorFor\(fc\.favId\)/.test(selector),
  'Favorite selector count/current text stays metadata-colored')
ok(!/AppStrings\.get\('common_yes'\)/.test(selector),
  'Favorite selector does not mark current favcat with Yes')

if (failures > 0) {
  console.error(`favcat color contract failed: ${failures} issue(s)`)
  process.exit(1)
}

console.log(`✓ favcat color contract: ${passed} assertions passed`)

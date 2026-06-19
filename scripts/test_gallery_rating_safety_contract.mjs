#!/usr/bin/env node
/**
 * Contract: gallery rating is discoverable but non-destructive in this lane.
 *
 * eros_fe exposes a Rate action and submits only after the user confirms the rate dialog.
 * NextE does not own the protected EH rating write flow yet, so the detail-page rating
 * entry must open a safety dialog and may only route to the in-app web page.
 *
 * Run: node scripts/test_gallery_rating_safety_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
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

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const api = read('shared/src/main/ets/network/EhApiService.ets')
const locales = ['base', 'en_US', 'zh_CN', 'ja_JP'].map((locale) =>
  read(`entry/src/main/resources/${locale}/element/string.json`))

ok(/private openRatingSafety\(\): void \{[\s\S]*this\.getUIContext\(\)\.showAlertDialog\(\{[\s\S]*detail_rate_readonly_confirm/.test(detail),
  'detail rating action opens a safety dialog')
ok(/primaryButton: \{[\s\S]*value: \$r\('app\.string\.common_cancel'\)/.test(detail),
  'rating safety dialog has cancel as the primary button')
ok(/secondaryButton: \{[\s\S]*value: \$r\('app\.string\.detail_open_internal_web'\)[\s\S]*this\.openInternalWeb\(\)/.test(detail),
  'rating safety dialog routes to internal web instead of submitting')
ok(/app\.string\.detail_rate[\s\S]*this\.openRatingSafety\(\)/.test(detail),
  'detail relations row exposes the rating entry')
ok(!/rategallery|setRating|rateGallery|rating\(|method:\s*'POST'|method:\s*"POST"/.test(detail),
  'detail page does not submit an EH rating write')
ok(!/rategallery|setRating|rateGallery/.test(api),
  'EhApiService has no rating write endpoint in this lane')

for (const key of ['detail_rate', 'detail_rate_readonly_confirm']) {
  ok(locales.every((content) => content.includes(`"name": "${key}"`)),
    `i18n key present in all locales: ${key}`)
}

if (failures > 0) {
  console.error(`gallery rating safety contract failed: ${failures} issue(s)`)
  process.exit(1)
}

console.log(`✓ gallery rating safety contract: ${passed} assertions passed`)

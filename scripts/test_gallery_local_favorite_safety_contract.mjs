#!/usr/bin/env node
/**
 * Contract: removing a local favorite from gallery detail is destructive enough to require confirmation.
 *
 * Adding a local favorite can stay one tap; removing an existing local favorite must route through a
 * native confirmation before the local record is removed. This contract deliberately does not lock
 * visual layout, button colour, or copy.
 *
 * Run: node scripts/test_gallery_local_favorite_safety_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const detail = readFileSync(join(ROOT, 'feature/gallery/src/main/ets/pages/GalleryDetailPage.ets'), 'utf8')
const localFavoriteRowStart = detail.indexOf('  private LocalFavoriteRow()')
const localFavoriteRowEnd = detail.indexOf('  private RemoteFavoriteSheet()', localFavoriteRowStart)
const localFavoriteRow = localFavoriteRowStart >= 0
  ? detail.slice(localFavoriteRowStart, localFavoriteRowEnd > localFavoriteRowStart ? localFavoriteRowEnd : detail.length)
  : ''

let failures = 0
let passed = 0

function ok(label, condition) {
  if (condition) {
    passed++
  } else {
    failures++
    console.error(`✗ ${label}`)
  }
}

ok('local favorite control routes removal through safety wrapper',
  /\.onClick\(\(\) => \{\s*this\.toggleLocalFavoriteWithSafety\(\)\s*\}\)/.test(localFavoriteRow) &&
    !/\.onClick\(\(\) => \{\s*this\.toggleLocalFavorite\(\)\s*\}\)/.test(localFavoriteRow))

ok('safety wrapper confirms only when the gallery is already locally favorited',
  /private toggleLocalFavoriteWithSafety\(\): void \{\s*if \(this\.isLocalFavorite\(\)\) \{\s*this\.confirmRemoveLocalFavorite\(\)\s*return\s*\}\s*this\.toggleLocalFavorite\(\)\s*\}/.test(detail))

ok('remove confirmation uses a native dialog before the local mutation',
  /private confirmRemoveLocalFavorite\(\): void \{[\s\S]*this\.getUIContext\(\)\.showAlertDialog\(\{[\s\S]*action: \(\) => \{\s*this\.toggleLocalFavorite\(\)\s*\}/.test(detail))

if (failures > 0) {
  console.error(`\n✗ gallery local favorite safety contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log(`✓ gallery local favorite safety contract: ${passed} assertions passed`)

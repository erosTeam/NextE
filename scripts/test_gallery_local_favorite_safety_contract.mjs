#!/usr/bin/env node
/**
 * Contract: removing a local favorite from gallery detail is destructive enough to require confirmation.
 *
 * Adding a local favorite can stay one tap; removing an existing local favorite must route through a
 * native alert dialog with Cancel as the primary button and the destructive remove action as the
 * red secondary button.
 *
 * Run: node scripts/test_gallery_local_favorite_safety_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const detail = readFileSync(join(ROOT, 'feature/gallery/src/main/ets/pages/GalleryDetailPage.ets'), 'utf8')
const baseStrings = readFileSync(join(ROOT, 'entry/src/main/resources/base/element/string.json'), 'utf8')
const zhStrings = readFileSync(join(ROOT, 'entry/src/main/resources/zh_CN/element/string.json'), 'utf8')
const enStrings = readFileSync(join(ROOT, 'entry/src/main/resources/en_US/element/string.json'), 'utf8')
const jaStrings = readFileSync(join(ROOT, 'entry/src/main/resources/ja_JP/element/string.json'), 'utf8')

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

ok('detail menu routes local favorite action through safety wrapper',
  /'action': \(\) => \{\s*this\.toggleLocalFavoriteWithSafety\(\)\s*\}/.test(detail) &&
    !/'action': \(\) => \{\s*this\.toggleLocalFavorite\(\)\s*\}/.test(detail))

ok('safety wrapper confirms only when the gallery is already locally favorited',
  /private toggleLocalFavoriteWithSafety\(\): void \{\s*if \(this\.isLocalFavorite\(\)\) \{\s*this\.confirmRemoveLocalFavorite\(\)\s*return\s*\}\s*this\.toggleLocalFavorite\(\)\s*\}/.test(detail))

ok('remove confirmation uses native alert dialog and confirm copy',
  /private confirmRemoveLocalFavorite\(\): void \{[\s\S]*this\.getUIContext\(\)\.showAlertDialog\(\{[\s\S]*message: \$r\('app\.string\.detail_remove_local_favorite_confirm'\)/.test(detail))

ok('remove confirmation keeps cancel as primary button',
  /primaryButton: \{\s*value: \$r\('app\.string\.common_cancel'\),\s*action: \(\) => \{\},\s*\}/.test(detail))

ok('remove confirmation makes the destructive remove action red and explicit',
  /secondaryButton: \{[\s\S]*value: \$r\('app\.string\.detail_remove_local_favorite'\),[\s\S]*fontColor: Color\.Red,[\s\S]*action: \(\) => \{\s*this\.toggleLocalFavorite\(\)\s*\}/.test(detail))

ok('remove confirmation string is present in all locales',
  [baseStrings, zhStrings, enStrings, jaStrings].every((content) => {
    return /"name": "detail_remove_local_favorite_confirm"/.test(content)
  }))

if (failures > 0) {
  console.error(`\n✗ gallery local favorite safety contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log(`✓ gallery local favorite safety contract: ${passed} assertions passed`)

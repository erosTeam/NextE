#!/usr/bin/env node
/**
 * Contract for MyTags management layout semantics.
 *
 * This is not a visual pass claim. It only prevents the specific regression where MyTags was rendered
 * as a namespace-grouped chip wall instead of eros_fe's tagset list + user-tag management rows.
 *
 * Run: node scripts/test_mytags_management_layout_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const page = readFileSync(join(ROOT, 'feature/user/src/main/ets/pages/MyTagsPage.ets'), 'utf8')
const fePage = readFileSync(join(ROOT, '../eros_fe/lib/pages/setting/mytags/eh_usertag_page.dart'), 'utf8')
const feItem = readFileSync(join(ROOT, '../eros_fe/lib/pages/setting/mytags/user_tag_item.dart'), 'utf8')

let failures = 0
function ok(condition, message) {
  if (!condition) {
    failures += 1
    console.error(`✗ ${message}`)
  } else {
    console.log(`✓ ${message}`)
  }
}

ok(/EhUserTagsPage/.test(fePage) && /_buildUserTagItem/.test(fePage) && /CupertinoTextField\.borderless/.test(fePage),
  'eros_fe reference exposes user-tag list rows and title search mode')
ok(/UserTagItem[\s\S]*circleCheck[\s\S]*circleXmark[\s\S]*circleDot[\s\S]*tagWeight/.test(feItem),
  'eros_fe reference row carries status icon and color/weight badge')

ok(/@Local showingTagsetList: boolean = true/.test(page),
  'MyTagsPage keeps an explicit tagset-list versus tag-row mode')
ok(/TagsetRows\(\)[\s\S]*GroupedListSection[\s\S]*ConciseListRow\(\{[\s\S]*title: s\.name[\s\S]*trailingText: `\$\{s\.count\}`[\s\S]*this\.selectTagset\(s\.tagsetId\)/.test(page),
  'MyTags top level renders tagsets as list rows, not horizontal chips')
ok(/TagRow\(t: EhUsertag\)[\s\S]*ConciseListRow\(\{[\s\S]*title: this\.tagTitle\(t\)[\s\S]*subtitle: this\.tagSubtitle\(t\)[\s\S]*this\.TagStatusPrefix\(t\)[\s\S]*this\.TagWeightBadge\(t\)/.test(page),
  'MyTags tagset detail renders full-tag management rows with status prefix and weight badge')
ok(/TagStatusPrefix\(t: EhUsertag\)[\s\S]*checkmark_circle_fill[\s\S]*xmark_circle_fill[\s\S]*dot_circle/.test(page),
  'MyTags tag rows expose watched / hidden / neutral status icons')
ok(/TagWeightBadge\(t: EhUsertag\)[\s\S]*this\.tagWeightLabel\(t\)/.test(page) &&
  /TagWeightBadge\(t: EhUsertag\)[\s\S]*this\.tagFillColor\(t\)/.test(page) &&
  /TagWeightBadge\(t: EhUsertag\)[\s\S]*this\.tagTextColor\(t\)/.test(page),
  'MyTags tag rows expose EH color/weight badge')
ok(!/GroupedListSection\(\{\s*inset:\s*ThemeConstants\.SPACE_MD\s*\}\)/.test(page),
  'MyTags must use the shared settings section inset instead of a page-specific large inset')
ok(!/margin\(\{\s*left:\s*58\s*\}\)/.test(page) &&
  /TagRowDivider\(\)[\s\S]*margin\(\{\s*left:\s*ThemeConstants\.SPACE_MD\s*\}\)/.test(page),
  'MyTags dividers use the shared settings divider inset, not a copied Flutter divider offset')
ok(/if \(this\.loading\) \{[\s\S]*PageLoadingState\(\)[\s\S]*\} else if \(this\.error\.length > 0\)/.test(page) &&
  !/PageLoadingState\(\{\s*expand:\s*false\s*\}\)/.test(page),
  'MyTags loading state stays centered instead of a top-aligned list row')

ok(!/NamespaceGroup\(ns: string\)/.test(page) && !/TagChip\(t: EhUsertag\)/.test(page),
  'MyTags main management surface must not regress to namespace chip groups')
ok(!/Flex\(\{ wrap: FlexWrap\.Wrap \}\)[\s\S]*this\.openEditTag\(t\)/.test(page),
  'existing user tags are not managed through a wrapped chip wall')

if (failures > 0) {
  console.error(`\n✗ mytags management layout contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ mytags management layout contract passed')

#!/usr/bin/env node
/**
 * Contract: My Tags existing-row deletion is a bounded, protected write loop.
 *
 * Scope: delete an existing usertag through /mytags `usertag_action=mass`.
 * Out of scope: new tag creation and tagset create/rename/delete.
 *
 * Run: node scripts/test_mytags_delete_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
let failures = 0

function read(rel) {
  return readFileSync(join(ROOT, rel), 'utf8')
}

function ok(condition, message) {
  if (!condition) {
    failures += 1
    console.error(`✗ ${message}`)
  } else {
    console.log(`✓ ${message}`)
  }
}

const api = read('shared/src/main/ets/network/EhApiService.ets')
const scaffold = read('shared/src/main/ets/components/AppModalScaffold.ets')
const page = read('feature/user/src/main/ets/pages/MyTagsPage.ets')
const editContract = read('scripts/test_mytags_setusertag_contract.mjs')

const grounding = [
  'eros_fe: lib/network/request.dart actionDeleteUserTag posts /mytags usertag_action=mass with modify_usertags[]',
  'eros_fe: lib/pages/setting/mytags/eh_usertag_page.dart exposes delete from an existing usertag row',
  'primary information: current My Tags grouped chips plus selected existing tag identity in the modal sheet',
  'primary action: delete the selected existing usertag after native confirmation; secondary action is cancel or continue editing',
  'Harmony expression: AppModalScaffold HDS modal title actions with trash + checkmark, native confirmation, and non-destructive validation by cancelling',
]

ok(grounding.length === 5, 'MyTags delete lane has five-line grounding')
ok(grounding[0].includes('actionDeleteUserTag') && grounding[1].includes('eh_usertag_page.dart'),
  'grounding names concrete eros_fe delete API and UI files')

ok(/export interface MyTagsDeleteUpdate[\s\S]*tagIds: string\[\][\s\S]*tagset: string/.test(api),
  'EhApiService defines typed MyTags delete input')
ok(/async deleteUserTags\(update: MyTagsDeleteUpdate\): Promise<void>/.test(api),
  'EhApiService exposes deleteUserTags')
ok(/usertag_action[\s\S]*mass/.test(api) &&
  /modify_usertags\[\]/.test(api) &&
  /postFormUrlEncoded\([\s\S]*\/mytags/.test(api),
  'deleteUserTags posts EH-compatible /mytags mass delete form fields')
ok(!/deleteUserTags[\s\S]*api\.php/.test(api),
  'deleteUserTags does not misuse /api.php setusertag')

ok(/@Param showSecondaryAction: boolean = false/.test(scaffold) &&
  /@Event secondaryAction\?: \(\) => void/.test(scaffold) &&
  /IconStyleMode\.SMALL/.test(scaffold) &&
  /HdsNavigationTitleMode\.MODAL/.test(scaffold),
  'AppModalScaffold supports a second HDS modal title action without business hand-rolled chrome')

ok(/secondaryIcon: \$r\('sys\.symbol\.trash'\)/.test(page) &&
  /showSecondaryAction: true/.test(page) &&
  /secondaryAction: \(\) => \{[\s\S]*this\.confirmDeleteTag\(\)/.test(page),
  'MyTags edit sheet exposes delete as a HDS title action')
ok(/confirmDeleteTag\(\): void[\s\S]*showAlertDialog[\s\S]*mytags_delete_confirm[\s\S]*common_cancel[\s\S]*this\.deleteTag\(\)/.test(page),
  'deleting an existing My Tag is gated by a native confirmation dialog')
ok(/deleteTag\(\): Promise<void>[\s\S]*EhApiService\.getInstance\(\)\.deleteUserTags\(\{[\s\S]*tagIds: \[this\.editTagId\][\s\S]*tagset: this\.mytags\.currentTagset/.test(page),
  'MyTagsPage submits the selected existing tag id and current tagset to deleteUserTags')
ok(/deleteTag\(\): Promise<void>[\s\S]*await this\.reloadCurrentTagset\(\)[\s\S]*this\.editSheetShown = false/.test(page),
  'successful delete reloads current tagset and closes the sheet')
ok(/UserTagStore\.getInstance\(\)\.setTags\(this\.mytags\.tags\)/.test(page) &&
  /this\.tagSig\.version = this\.tagSig\.version \+ 1/.test(page),
  'reload after delete republishes shared usertag state')

ok(!/actionNewUserTag|actionCreatTagSet|actionRenameTagSet|actionDeleteTagSet/.test(page),
  'this lane does not mix in new-tag or tagset management')
ok(!/actionDeleteUserTag/.test(editContract),
  'existing setusertag contract no longer forbids the separate delete lane')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'mytags_delete',
    'mytags_delete_confirm',
    'mytags_delete_success',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ mytags delete contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ mytags delete contract passed')

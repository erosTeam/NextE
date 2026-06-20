#!/usr/bin/env node
/**
 * Contract: My Tags existing-row edits are a real, bounded write loop.
 *
 * Scope: edit an existing usertag's watch/hide/weight/color through /api.php `setusertag`.
 * Out of scope: new tag creation, usertag deletion, and tagset create/rename/delete.
 *
 * Run: node scripts/test_mytags_setusertag_contract.mjs
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

const api = read('shared/src/main/ets/network/EhApiPhpService.ets')
const barrel = read('shared/src/main/ets/Index.ets')
const page = read('feature/user/src/main/ets/pages/MyTagsPage.ets')

const grounding = [
  'eros_fe: lib/pages/setting/mytags/eh_usertag_page.dart taps an existing row and lib/pages/setting/mytags/eh_usertag_edit_dialog.dart edits watch/hide/weight/color',
  'eros_fe: lib/network/api.dart Api.setUserTag posts /api.php method=setusertag with apiuid/apikey/tagid/tagwatch/taghide/tagcolor/tagweight',
  'primary information: current My Tags grouped chips plus the selected tag identity in the edit sheet',
  'primary action: save an existing tag edit; secondary actions are cancel and draft toggles; no new/delete/tagset management in this lane',
  'Harmony expression: AppModalScaffold HDS modal with draft rows, switch-like toggles, text inputs, native confirmation, and non-destructive validation by cancelling',
]

ok(grounding.length === 5, 'MyTags setusertag lane has five-line grounding')
ok(grounding[0].includes('eh_usertag_page.dart') && grounding[1].includes('method=setusertag'),
  'grounding names concrete eros_fe UI and API files')

ok(/class SetUserTagRequest[\s\S]*method: string = 'setusertag'/.test(api),
  'EhApiPhpService defines a setusertag request')
ok(/tagwatch: number = 0[\s\S]*taghide: number = 0[\s\S]*tagcolor: string = ''[\s\S]*tagweight: string = ''/.test(api),
  'setusertag request carries watch/hide/color/weight fields')
ok(/static async setUserTag\([\s\S]*apikey: string,[\s\S]*apiuid: string,[\s\S]*tagId: string,[\s\S]*watched: boolean,[\s\S]*hidden: boolean,[\s\S]*color: string,[\s\S]*weight: string/.test(api),
  'EhApiPhpService exposes setUserTag with typed existing-tag fields')
ok(/req\.tagwatch = watched \? 1 : 0[\s\S]*req\.taghide = hidden \? 1 : 0[\s\S]*req\.tagcolor = normalizedColor[\s\S]*req\.tagweight = normalizedWeight/.test(api),
  'setUserTag serializes EH-compatible values')
ok(/postJson\([\s\S]*api\.php[\s\S]*JSON\.stringify\(req\)/.test(api),
  'setUserTag posts JSON to /api.php')
ok(/SetUserTagResult/.test(barrel), 'shared barrel exports SetUserTagResult')

ok(/AppModalScaffold/.test(page) && /EditTagSheet\(\)[\s\S]*AppModalScaffold\(\{[\s\S]*title: \$r\('app\.string\.mytags_edit_title'\)/.test(page),
  'MyTagsPage uses AppModalScaffold for existing-tag edits')
ok(/TagChip\(t: EhUsertag\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.openEditTag\(t\)/.test(page),
  'tapping an existing My Tag chip opens the edit sheet')
ok(/editWatched = value[\s\S]*if \(value\) \{[\s\S]*this\.editHidden = false/.test(page) &&
  /editHidden = value[\s\S]*if \(value\) \{[\s\S]*this\.editWatched = false/.test(page),
  'watch and hide draft switches stay mutually exclusive')
ok(/confirmSubmitEdit\(\): void[\s\S]*showAlertDialog[\s\S]*mytags_save_confirm[\s\S]*common_cancel[\s\S]*this\.submitEdit\(\)/.test(page),
  'saving an edit is gated by a native confirmation dialog')
ok(/EhApiPhpService\.setUserTag\([\s\S]*this\.mytags\.apikey[\s\S]*this\.mytags\.apiuid[\s\S]*this\.editTagId[\s\S]*this\.editWatched[\s\S]*this\.editHidden[\s\S]*this\.normalizedEditColor\(\)[\s\S]*this\.editWeight/.test(page),
  'MyTagsPage submits the current draft through setUserTag')
ok(/await this\.reloadCurrentTagset\(\)/.test(page) &&
  /UserTagStore\.getInstance\(\)\.setTags\(this\.mytags\.tags\)/.test(page) &&
  /this\.tagSig\.version = this\.tagSig\.version \+ 1/.test(page),
  'successful save refreshes MyTags and republishes global tag-color state')
ok(!/actionNewUserTag|actionDeleteUserTag|actionCreatTagSet|actionRenameTagSet|actionDeleteTagSet/.test(page),
  'this lane does not mix in new/delete/tagset management')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'mytags_edit_title',
    'mytags_watch',
    'mytags_hide',
    'mytags_weight',
    'mytags_default_color',
    'mytags_color',
    'mytags_save',
    'mytags_save_confirm',
    'mytags_save_success',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ mytags setusertag contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ mytags setusertag contract passed')

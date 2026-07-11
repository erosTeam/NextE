#!/usr/bin/env node
/**
 * Contract: My Tags tagset management uses EH's /mytags form actions.
 *
 * FE grounding:
 * - eros_fe/lib/network/request.dart actionCreatTagSet/actionRenameTagSet/actionDeleteTagSet
 * - eros_fe/lib/pages/setting/controller/eh_mytags_controller.dart tagset methods
 * - eros_fe/lib/pages/setting/mytags/eh_mytags_page.dart creates tagsets from the top bar
 * - eros_fe/lib/pages/setting/mytags/eh_usertag_page.dart exposes delete / rename as separate top actions
 * - eros_fe/lib/pages/setting/webview/eh_tagset_edit_dialog.dart keeps tagset naming as a focused dialog
 *
 * Run: node scripts/test_mytags_tagset_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const api = readFileSync(join(ROOT, 'shared/src/main/ets/network/EhApiService.ets'), 'utf8')
const page = readFileSync(join(ROOT, 'feature/user/src/main/ets/pages/MyTagsPage.ets'), 'utf8')
const barrel = readFileSync(join(ROOT, 'shared/src/main/ets/Index.ets'), 'utf8')
const feRequest = readFileSync(join(ROOT, '../eros_fe/lib/network/request.dart'), 'utf8')
const feController = readFileSync(
  join(ROOT, '../eros_fe/lib/pages/setting/controller/eh_mytags_controller.dart'),
  'utf8',
)
const feMytagsPage = readFileSync(join(ROOT, '../eros_fe/lib/pages/setting/mytags/eh_mytags_page.dart'), 'utf8')
const feUserTagsPage = readFileSync(join(ROOT, '../eros_fe/lib/pages/setting/mytags/eh_usertag_page.dart'), 'utf8')
const feTagsetDialog = readFileSync(
  join(ROOT, '../eros_fe/lib/pages/setting/webview/eh_tagset_edit_dialog.dart'),
  'utf8',
)
const resources = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
].map((rel) => readFileSync(join(ROOT, rel), 'utf8'))

let failures = 0

function ok(condition, message) {
  if (!condition) {
    failures++
    console.error(`✗ ${message}`)
  }
}

ok(
  /Future<bool> actionRenameTagSet[\s\S]*'tagset_action': 'rename'[\s\S]*'tagset_name': tagsetname[\s\S]*'tagset': tagset \?\? ''/.test(feRequest) &&
    /Future<bool> actionCreatTagSet[\s\S]*'tagset_action': 'create'[\s\S]*'tagset_name': tagsetname/.test(feRequest) &&
    /Future<bool> actionDeleteTagSet[\s\S]*'tagset_action': 'delete'[\s\S]*'tagset': tagset \?\? ''/.test(feRequest),
  'eros_fe grounding must expose create / rename / delete tagset form actions',
)
ok(
  /deleteTagset\(\)[\s\S]*actionDeleteTagSet\(tagset: currSelected\)/.test(feController) &&
    /crtNewTagset[\s\S]*actionCreatTagSet\(tagsetname: name\)/.test(feController) &&
    /renameTagSet[\s\S]*actionRenameTagSet\([\s\S]*tagsetname: newName[\s\S]*tagset: currSelected/.test(feController),
  'eros_fe controller must route tagset writes through the current selected tagset',
)
ok(
  /EhTagSetEditDialog\([\s\S]*title: 'New Tagset'/.test(feMytagsPage) &&
    /controller\.crtNewTagset\(name: newName\)/.test(feMytagsPage) &&
    /CupertinoIcons\.trash[\s\S]*controller\.deleteTagset\(\)/.test(feUserTagsPage) &&
    /CupertinoIcons\.pencil_ellipsis_rectangle[\s\S]*controller\.renameTagSet\(newName: newName\)/.test(feUserTagsPage) &&
    /class EhTagSetEditDialog[\s\S]*CupertinoAlertDialog[\s\S]*CupertinoTextField[\s\S]*Get\.back\(result: tagsetNameTextEditingController\.text\.trim\(\)\)/.test(feTagsetDialog),
  'eros_fe UI model must keep create, rename, and delete as separate actions with a focused name dialog',
)

ok(
  /export interface MyTagsTagsetUpdate[\s\S]*action: string[\s\S]*tagset: string[\s\S]*name: string/.test(api),
  'EhApiService must expose typed tagset update input',
)
ok(
  /updateMyTagsTagset\(update: MyTagsTagsetUpdate\): Promise<void>[\s\S]*action !== 'create'[\s\S]*action !== 'rename'[\s\S]*action !== 'delete'/.test(api),
  'updateMyTagsTagset must guard allowed actions',
)
ok(
  /updateMyTagsTagset\(update: MyTagsTagsetUpdate\): Promise<void>[\s\S]*tagset_action[\s\S]*tagset_name/.test(api),
  'updateMyTagsTagset must serialize EH tagset_action and tagset_name fields',
)
ok(
  /action === 'rename' \|\| action === 'delete'[\s\S]*params\.push\(`tagset=\$\{encodeURIComponent\(update\.tagset\)\}`\)/.test(api),
  'rename/delete must include ?tagset=<current>; create must not require it',
)
ok(
  /postFormUrlEncoded\(url, pairs\.join\('&'\)\)/.test(api) &&
    /EhErrorClassifier\.classifyResponse\(\s*url,\s*update\.isEx,\s*resp,\s*'generic',?\s*\)/.test(api),
  'tagset writes must use the same protected form post and classifier path as other EH writes',
)
ok(/MyTagsTagsetUpdate/.test(barrel), 'shared barrel must export MyTagsTagsetUpdate')

ok(
  /openCreateTagset\(\): void[\s\S]*this\.tagsetAction = 'create'/.test(page) &&
    /openRenameTagset\(\): void[\s\S]*this\.tagsetAction = 'rename'/.test(page),
  'MyTagsPage must expose create and rename tagset sheet entry points',
)
ok(
  /myTagsTitleBar\(\): Record<string, Object>[\s\S]*mytags_add[\s\S]*this\.openAddTag\(\)/.test(page) &&
    /myTagsTitleBar\(\): Record<string, Object>[\s\S]*mytags_tagset_create[\s\S]*this\.openCreateTagset\(\)/.test(page) &&
    /myTagsTitleBar\(\): Record<string, Object>[\s\S]*mytags_tagset_rename[\s\S]*this\.openRenameTagset\(\)/.test(page) &&
    /myTagsTitleBar\(\): Record<string, Object>[\s\S]*mytags_tagset_delete[\s\S]*this\.confirmDeleteTagset\(\)/.test(page) &&
    /if \(this\.showingTagsetList\)[\s\S]*createInner[\s\S]*\} else \{[\s\S]*addInner[\s\S]*renameInner/.test(page) &&
    !/mytags_tagset_manage[\s\S]*gearshape/.test(page),
  'MyTags title menu must expose separate add-tag, create-tagset, rename-current-tagset, and delete-current-tagset actions',
)
ok(
  /TagsetSheet\(\)[\s\S]*AppModalScaffold\(\{[\s\S]*title: this\.tagsetSheetTitle\(\)[\s\S]*confirmText: this\.tagsetConfirmText\(\)[\s\S]*confirmAction: \(\) => \{[\s\S]*this\.confirmSubmitTagset\(\)/.test(page) &&
    !/TagsetSheet\(\)[\s\S]*showSecondaryAction[\s\S]*mytags_tagset_delete/.test(page),
  'tagset naming must use a focused AppModalScaffold and must not hide delete inside the name sheet',
)
ok(
  /confirmSubmitTagset\(\): void[\s\S]*const request: UserTagRequestContext \| null = this\.myTagsManagementRequest[\s\S]*showAlertDialog[\s\S]*common_cancel[\s\S]*this\.submitTagset\(request\)/.test(page) &&
    /confirmDeleteTagset\(\): void[\s\S]*this\.captureManagementRequest\(\)[\s\S]*showAlertDialog[\s\S]*mytags_tagset_delete_confirm[\s\S]*this\.deleteCurrentTagset\(request\)/.test(page),
  'tagset writes must be confirmation-gated before real EH mutation',
)
ok(
  /submitTagset\(request: UserTagRequestContext\): Promise<void>[\s\S]*isEx: request\.isEx[\s\S]*action,[\s\S]*tagset,[\s\S]*name,/.test(page) &&
    /deleteCurrentTagset\(request: UserTagRequestContext\): Promise<void>[\s\S]*isEx: request\.isEx[\s\S]*action: 'delete'[\s\S]*tagset,/.test(page),
  'MyTagsPage must submit create/rename/delete with current tagset state',
)
ok(
  /await this\.reloadCurrentTagset\(tagset\)[\s\S]*this\.isCurrentManagementRequest\(request\)/.test(page) &&
    /await this\.load\(''\)[\s\S]*this\.isCurrentManagementRequest\(request\)/.test(page),
  'successful tagset writes must refresh the visible MyTags state',
)

const keys = [
  'mytags_tagset_create',
  'mytags_tagset_create_title',
  'mytags_tagset_rename',
  'mytags_tagset_rename_title',
  'mytags_tagset_delete',
  'mytags_tagset_name',
  'mytags_tagset_name_placeholder',
  'mytags_tagset_create_confirm',
  'mytags_tagset_rename_confirm',
  'mytags_tagset_delete_confirm',
  'mytags_tagset_create_success',
  'mytags_tagset_rename_success',
  'mytags_tagset_delete_success',
]
for (const src of resources) {
  for (const key of keys) {
    ok(src.includes(`"name": "${key}"`), `missing i18n key ${key}`)
  }
}

if (failures > 0) {
  console.error(`\n✗ mytags tagset contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ mytags tagset contract passed')

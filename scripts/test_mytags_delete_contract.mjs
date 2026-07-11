#!/usr/bin/env node
/**
 * Contract for the protected deletion of an existing EH My Tags usertag.
 *
 * It covers the destructive remote-write form, explicit confirmation, and post-success state refresh.
 * Modal layout, title actions, grounding prose, and localized copy are verified outside this source-shape
 * gate through review and device paths.
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')
const ok = (condition, message) => {
  if (!condition) {
    throw new Error(message)
  }
}

const api = read('shared/src/main/ets/network/EhApiService.ets')
const page = read('feature/user/src/main/ets/pages/MyTagsPage.ets')
const deleteTagStart = page.indexOf('  private async deleteTag(): Promise<void> {')
const deleteTagEnd = page.indexOf('  private async submitTagset()', deleteTagStart)
const deleteTag = deleteTagStart >= 0
  ? page.slice(deleteTagStart, deleteTagEnd > deleteTagStart ? deleteTagEnd : page.length)
  : ''

ok(/export interface MyTagsDeleteUpdate[\s\S]*tagIds: string\[\][\s\S]*tagset: string/.test(api),
  'EhApiService defines typed MyTags delete input')
ok(/async deleteUserTags\(update: MyTagsDeleteUpdate\): Promise<void>/.test(api),
  'EhApiService exposes deleteUserTags')
ok(/usertag_action[\s\S]*mass/.test(api) &&
  /modify_usertags\[\]/.test(api) &&
  /postFormUrlEncoded\([\s\S]*\/mytags/.test(api),
  'deleteUserTags posts EH-compatible /mytags mass-delete fields')
ok(!/deleteUserTags[\s\S]*api\.php/.test(api),
  'deleteUserTags does not misuse the /api.php setusertag endpoint')
ok(/private confirmDeleteTag\(\): void \{[\s\S]*showAlertDialog[\s\S]*action: \(\) => \{\s*this\.deleteTag\(\)/.test(page),
  'deleting an existing My Tag requires native confirmation')
ok(/await EhApiService\.getInstance\(\)\.deleteUserTags\(\{[\s\S]*tagIds: \[this\.editTagId\][\s\S]*tagset: this\.mytags\.currentTagset/.test(deleteTag),
  'selected existing tag id and current tagset are submitted together')
ok(/await this\.reloadCurrentTagset\(\)\s*this\.closeMyTagsSheet\(\)/.test(deleteTag),
  'successful delete refreshes the current tagset before closing its sheet')
ok(/private publishUserTags\(request: UserTagRequestContext\): void\s*\{\s*UserTagContextService\.publishMyTags\(request, this\.mytags\.tags\)/.test(page),
  'tagset reload republishes shared usertag state through the active request fence')

console.log('✓ MyTags delete contract: protected write and post-success state boundaries locked')

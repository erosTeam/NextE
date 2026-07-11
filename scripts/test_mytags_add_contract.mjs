#!/usr/bin/env node
/**
 * Contract: My Tags can add one new usertag through EH's /mytags add form.
 *
 * Scope: search/select or type a tag, configure watch/hide/weight/color, then add it through
 * /mytags `usertag_action=add`.
 * Out of scope: tagset create/rename/delete management.
 *
 * Run: node scripts/test_mytags_add_contract.mjs
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
const barrel = read('shared/src/main/ets/Index.ets')
const page = read('feature/user/src/main/ets/pages/MyTagsPage.ets')
const detailTags = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
const detailManagementCloseCount = (detailTags.match(/closeAction:\s*\(\)\s*=>\s*\{\s*this\.discardMyTagsManagement\(\)\s*\}/g) || []).length

const grounding = [
  'eros_fe: lib/network/request.dart actionNewUserTag posts /mytags usertag_action=add with tagname_new/tagcolor_new/tagweight_new/tagwatch_new/taghide_new',
  'eros_fe: lib/pages/setting/mytags/eh_usertag_page.dart search mode suggests tags, filters existing usertags, and opens the new-tag edit dialog',
  'primary information: current My Tags plus add-sheet draft tag, suggestions, and watch/hide/weight/color state',
  'primary action: add one new usertag after native confirmation; secondary actions are close and selecting a suggestion; tagset management is not in this lane',
  'Harmony expression: HDS title-bar plus action and AppModalScaffold modal title confirm action, not a separate page or bottom primary button',
]

ok(grounding.length === 5, 'MyTags add lane has five-line grounding')
ok(grounding[0].includes('actionNewUserTag') && grounding[1].includes('eh_usertag_page.dart'),
  'grounding names concrete eros_fe add API and UI files')

ok(/export interface MyTagsAddUpdate[\s\S]*tagName: string[\s\S]*tagset: string[\s\S]*color: string[\s\S]*weight: string[\s\S]*watched: boolean[\s\S]*hidden: boolean/.test(api),
  'EhApiService defines typed MyTags add input')
ok(/async addUserTag\(update: MyTagsAddUpdate\): Promise<void>/.test(api),
  'EhApiService exposes addUserTag')
ok(/usertag_action[\s\S]*add/.test(api) &&
  /tagname_new/.test(api) &&
  /tagcolor_new/.test(api) &&
  /tagweight_new/.test(api) &&
  /tagwatch_new[\s\S]*update\.watched \? 'on' : ''/.test(api) &&
  /taghide_new[\s\S]*update\.hidden \? 'on' : ''/.test(api) &&
  /usertag_target[\s\S]*0/.test(api) &&
  /postFormUrlEncoded\([\s\S]*\/mytags/.test(api),
  'addUserTag posts EH-compatible /mytags add form fields')
ok(!/addUserTag[\s\S]*api\.php/.test(api),
  'addUserTag does not misuse /api.php setusertag')
ok(/MyTagsAddUpdate/.test(barrel), 'shared barrel exports MyTagsAddUpdate')

ok(/myTagsTitleBar\(\): Record<string, Object>[\s\S]*mytags_add[\s\S]*sys\.symbol\.plus[\s\S]*this\.openAddTag\(\)/.test(page),
  'MyTagsPage exposes add as a HDS title-bar plus action')
ok(/AddTagSheet\(\)[\s\S]*AppModalScaffold\(\{[\s\S]*title: \$r\('app\.string\.mytags_add_title'\)[\s\S]*confirmText: \$r\('app\.string\.mytags_add'\)[\s\S]*confirmEnabled: this\.canSubmitAdd\(\)/.test(page),
  'new-tag UI is an AppModalScaffold confirm sheet')
ok(/EhApiPhpService\.tagSuggest\([\s\S]*EhConstants\.baseUrl\(connectSiteMode\(\)\.isEx\)[\s\S]*q/.test(page),
  'add sheet uses EH tagSuggest for candidate tags')
ok(/suggestions\.filter\(\(s: EhTagSuggestion\) => !this\.hasExistingTag\(s\.label\(\)\)\)/.test(page),
  'tag suggestions exclude already-owned My Tags')
ok(/addSuppressNextSuggest/.test(page) &&
  /selectAddSuggestion\(s: EhTagSuggestion\)[\s\S]*this\.addSuppressNextSuggest = true/.test(page) &&
  /setAddTagQuery\(value: string\)[\s\S]*if \(this\.addSuppressNextSuggest\)[\s\S]*this\.addSuggestions = \[\]/.test(page),
  'selecting a suggestion clears stale suggestions instead of refilling them from a late request')
ok(/confirmSubmitAdd\(\): void[\s\S]*const request: UserTagRequestContext \| null = this\.myTagsManagementRequest[\s\S]*showAlertDialog[\s\S]*mytags_add_confirm[\s\S]*common_cancel[\s\S]*this\.submitAdd\(request\)/.test(page),
  'adding a new My Tag is gated by a native confirmation dialog')
ok(/submitAdd\(request: UserTagRequestContext\): Promise<void>[\s\S]*isEx: request\.isEx[\s\S]*tagName: this\.addTagLabel\(\)[\s\S]*tagset,[\s\S]*color: this\.normalizedAddColor\(\)[\s\S]*weight: this\.addWeight[\s\S]*watched: this\.addWatched[\s\S]*hidden: this\.addHidden/.test(page),
  'MyTagsPage submits the current add draft through addUserTag')
ok(/submitAdd\(request: UserTagRequestContext\): Promise<void>[\s\S]*await this\.reloadCurrentTagset\(tagset\)[\s\S]*this\.isCurrentManagementRequest\(request\)[\s\S]*this\.closeMyTagsSheet\(\)/.test(page),
  'successful add reloads current tagset and closes the sheet')
ok(/addWatched = value[\s\S]*if \(value\) \{[\s\S]*this\.addHidden = false/.test(page) &&
  /addHidden = value[\s\S]*if \(value\) \{[\s\S]*this\.addWatched = false/.test(page),
  'new-tag watch and hide draft switches stay mutually exclusive')
ok(/private isCurrentMyTagsRequest\(request: UserTagRequestContext\): boolean[\s\S]*this\.myTagsRequest === request[\s\S]*UserTagContextService\.isCurrentAuthenticated\(request\)/.test(detailTags) &&
  /openMyTagsForSelectedTag\(\): void[\s\S]*const request: UserTagRequestContext = this\.currentMyTagsRequest\(\)[\s\S]*UserTagContextService\.isCurrentAuthenticated\(request\)[\s\S]*this\.myTagsRequest = request[\s\S]*MyTagsTargetService\.resolve\(request\.isEx, tagKey\)/.test(detailTags) &&
  /confirmSubmitAdd\(\): void[\s\S]*const request: UserTagRequestContext \| null = this\.myTagsRequest[\s\S]*this\.submitAdd\(request\)/.test(detailTags) &&
  /submitAdd\(request: UserTagRequestContext\): Promise<void>[\s\S]*isEx: request\.isEx[\s\S]*await EhApiService\.getInstance\(\)\.getMyTags\(request\.isEx, tagset\)[\s\S]*!this\.isCurrentMyTagsRequest\(request\) \|\| !UserTagContextService\.publishMyTags\(request, refreshed\.tags\)/.test(detailTags) &&
  detailManagementCloseCount === 3 &&
  !/UserTagStore\.getInstance\(\)\.setTags/.test(detailTags),
  'detail-page add owns one account/site sheet session through reload and shared-cache publish')
ok(/private captureManagementRequest\(\): UserTagRequestContext \| null[\s\S]*this\.myTagsManagementRequest = request/.test(page) &&
  /private isCurrentManagementRequest\(request: UserTagRequestContext\): boolean[\s\S]*this\.myTagsManagementRequest === request[\s\S]*this\.contextMatchesCurrent\(request\)/.test(page),
  'MyTagsPage add sessions are fenced to the account and site that opened the sheet')
ok(!/actionCreatTagSet|actionRenameTagSet|actionDeleteTagSet/.test(page),
  'this lane does not mix in tagset management')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'mytags_add',
    'mytags_add_title',
    'mytags_tag_name',
    'mytags_tag_placeholder',
    'mytags_suggestions',
    'mytags_suggest_loading',
    'mytags_add_existing',
    'mytags_add_confirm',
    'mytags_add_success',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ mytags add contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ mytags add contract passed')

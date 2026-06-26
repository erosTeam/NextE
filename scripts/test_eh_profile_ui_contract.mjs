#!/usr/bin/env node
/**
 * Contract for the EH Profile (uconfig) native editor UI wiring.
 *
 * Guards the fragile bits: the NON-contiguous radio value maps (image size 0/5/4/3/1, front page
 * 3/4/0/2/1, archiver 0..5), the inverted mt toggle, the load/save calls, the top-right Save + WebView
 * actions, route + entry wiring, and i18n parity for the page's keys.
 * Run: node scripts/test_eh_profile_ui_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
const ok = (name, cond) => {
  if (!cond) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

const page = read('feature/settings/src/main/ets/pages/EhProfileSettingsPage.ets')

ok('loads + saves via EhApiService', /getUserConfig\(this\.site\.isEx\)/.test(page) && /saveUserConfig\(this\.site\.isEx, this\.settings\)/.test(page))
ok('top-right Save action', /AppStrings\.get\('common_save'\)/.test(page) && /this\.save\(\)/.test(page))
ok('top-right WebView entry opens uconfig.php', /\/uconfig\.php/.test(page) && /pushPathByName\('GalleryWeb'/.test(page))

// Non-contiguous option value maps (value != index — the easy-to-break part).
ok('image size values 0/5/4/3/1 with 2400x/1600x/1280x/780x', /new UcOption\(5, '2400x'\)/.test(page) && /new UcOption\(4, '1600x'\)/.test(page) && /new UcOption\(3, '1280x'\)/.test(page) && /new UcOption\(1, '780x'\)/.test(page))
ok('front page mode values 3/4/0/2/1', /new UcOption\(3, \$r\('app\.string\.ehp_dm_3'\)\)/.test(page) && /new UcOption\(4, \$r\('app\.string\.ehp_dm_4'\)\)/.test(page) && /new UcOption\(1, \$r\('app\.string\.ehp_dm_1'\)\)/.test(page))
ok('archiver values 0..5', /new UcOption\(0, \$r\('app\.string\.ehp_ar_0'\)\)/.test(page) && /new UcOption\(5, \$r\('app\.string\.ehp_ar_5'\)\)/.test(page))

// Toggles + the inverted mt (pane shown when form value is 0).
ok('oi/qb toggles map 1/0', /this\.settings\.originalImages = value \? 1 : 0/.test(page) && /this\.settings\.alwaysUseMpv = value \? 1 : 0/.test(page))
ok('mt toggle is inverted (checked when ===0, on->0 off->1)', /this\.settings\.mpvThumbnailPane === 0/.test(page) && /this\.settings\.mpvThumbnailPane = value \? 0 : 1/.test(page))

// Standard infra (no hand-rolled selectors).
ok('uses ConciseListRow dropdown + SettingsCheckedMenuItem + bindMenu', /trailingDropdown: true/.test(page) && /SettingsCheckedMenuItem\(/.test(page) && /\.bindMenu\(this\.menuShown/.test(page))

// Excluded languages: grouped per language with the platform multi-select segmented control.
ok('xl grouped per language into a MultiCapsuleSegmentButtonV2', /groupLanguages\(/.test(page) && /MultiCapsuleSegmentButtonV2\(/.test(page) && /\$selectedIndexes:/.test(page))
// Rows are built on ConciseListRow (no hand-rolled titles) so fonts stay uniform.
ok('text + language rows reuse ConciseListRow (uniform titles)', /struct UcTextRow[\s\S]*?ConciseListRow\(/.test(page) && /struct LanguageVariantRow[\s\S]*?ConciseListRow\(/.test(page))

// Permission gating: options filtered to what the page exposes; absent fields hidden; NORMAL icons.
ok('options filtered by presence + oi gated by field presence', /filterOptions\(/.test(page) && /hasField\('oi'\)/.test(page))
ok('title-bar action icons use NORMAL size (not SMALL)', /IconStyleMode\.NORMAL/.test(page) && !/IconStyleMode\.SMALL/.test(page))
ok('profile set-default/delete shown conditionally', /selectedProfile !== this\.settings\.defaultProfile/.test(page))

// Profile management: switch + create/rename/default/delete via postProfileAction.
ok('profile section with the 5 actions', /ProfileSection\(/.test(page) && /runProfileAction\('', /.test(page) && /runProfileAction\('default'/.test(page) && /runProfileAction\('delete'/.test(page) && /'create'/.test(page) && /'rename'/.test(page))
ok('profile create/rename use a name sheet (AppModalScaffold + $$ host)', /openNameSheet\(/.test(page) && /\$\$this\.nameSheetShown/.test(page) && /AppModalScaffold\(/.test(page))
ok('delete confirms first', /confirmDeleteProfile\(/.test(page) && /showAlertDialog/.test(page))
const svc = read('shared/src/main/ets/network/EhApiService.ets')
ok('service postProfileAction posts profile_action/profile_name/profile_set', /postProfileAction\(/.test(svc) && /profile_action/.test(svc) && /profile_name/.test(svc) && /profile_set/.test(svc))

// Front-page categories.
ok('category section toggles ct visibility', /CategorySection\(/.test(page) && /cat\.hidden = !value/.test(page))

// Wiring.
ok('route registered', /name === 'EhProfileSettings'[\s\S]*EhProfileSettingsPage\(\)/.test(read('entry/src/main/ets/pages/Index.ets')))
ok('exported from feature/settings', /export \{ EhProfileSettingsPage \}/.test(read('feature/settings/src/main/ets/Index.ets')))
ok('EhSettings page links to it', /pushPathByName\('EhProfileSettings'/.test(read('feature/settings/src/main/ets/pages/EhSettingsPage.ets')))

// i18n parity for a representative spread of the page's keys.
for (const loc of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const s = read(`entry/src/main/resources/${loc}/element/string.json`)
  for (const key of ['ehp_title', 'ehp_entry_title', 'ehp_open_web', 'ehp_uh', 'ehp_xr', 'ehp_ar', 'ehp_mt', 'ehp_dm_3', 'ehp_uh_0', 'ehp_saved']) {
    ok(`${loc} has ${key}`, new RegExp(`"name": "${key}"`).test(s))
  }
}

if (failures === 0) {
  console.log('✓ eh profile ui contract passed')
  process.exit(0)
}
console.error(`✗ eh profile ui contract: ${failures} failure(s)`)
process.exit(1)

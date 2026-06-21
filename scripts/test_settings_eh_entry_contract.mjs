#!/usr/bin/env node
/**
 * Contract: Settings exposes an EH child page for account/site actions already owned by NextE.
 * This is an information-architecture lane, not an auth-cookie-login or EH website-settings rewrite.
 *
 * Run: node scripts/test_settings_eh_entry_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    console.error(`✗ ${msg}`)
    failures++
  }
}

const grounding = [
  'eros_fe: lib/pages/tab/controller/setting_controller.dart routes EH to EHRoutes.ehSetting; lib/pages/setting/eh_setting_page.dart renders account/site/EH website rows',
  'primary information: EH account and current gallery-site state, not generic app preferences',
  'primary actions: open login/cookie import/My Tags and toggle site through the existing site settings path; back is secondary',
  'scope: Settings root -> EH settings -> existing account/site actions; no WebDAV, MySQL, website settings, image-limit fetch, link handler, or auth-cookie-login rewrite',
  'Harmony expression: HdsNavDestination + SecondaryListScaffold + GroupedListSection + ConciseListRow settings rows',
]

ok(grounding.length === 5, 'EH settings lane has five-line grounding')
ok(grounding[0].includes('setting_controller.dart') && grounding[0].includes('eh_setting_page.dart'),
  'grounding names concrete eros_fe EH settings files')
ok(grounding[3].includes('no WebDAV') && grounding[4].includes('HdsNavDestination'),
  'grounding limits scope and names Harmony expression')

const settingsRoot = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
const entry = read('entry/src/main/ets/pages/Index.ets')
const ehPage = read('feature/settings/src/main/ets/pages/EhSettingsPage.ets')

ok(/export \{ EhSettingsPage \}/.test(settingsIndex), 'settings module exports EhSettingsPage')
ok(/EhSettingsPage/.test(entry) && /name === 'EhSettings'[\s\S]*EhSettingsPage\(\)/.test(entry),
  'entry registers EhSettings route')
ok(/settings_eh/.test(settingsRoot) && /pushPathByName\('EhSettings', null\)/.test(settingsRoot),
  'Settings root exposes an EH row that pushes EhSettings')
ok(!/toggleSite\(\)/.test(settingsRoot) && !/SiteModeSettings/.test(settingsRoot),
  'Settings root no longer owns the raw site-toggle action')
ok(!/settings_mytags/.test(settingsRoot) && !/pushPathByName\('MyTags', null\)/.test(settingsRoot),
  'Settings root does not duplicate the EH-owned My Tags entry')

ok(/export struct EhSettingsPage/.test(ehPage) && /HdsNavDestination/.test(ehPage),
  'EhSettingsPage is a native HDS destination')
ok(/@Local siteMode: SiteModeState = connectSiteMode\(\)/.test(ehPage),
  'page reads V2 site mode state')
ok(/@Local auth: AuthState = connectAuth\(\)/.test(ehPage),
  'page reads V2 auth state')
ok(/SiteModeSettings\.setEx\(ctx, false\)/.test(ehPage) &&
  /SiteModeSettings\.setEx\(ctx, true\)/.test(ehPage) &&
  /site_ex_locked/.test(ehPage),
  'site switching still uses existing SiteModeSettings with ExHentai gate')
ok(/return this\.siteMode\.isEx \? 'ExHentai' : 'E-Hentai'/.test(ehPage),
  'site row uses official service names instead of community nicknames')
ok(!/里站|表站/.test(ehPage),
  'EH settings page must not show community site nicknames in user-visible code')
ok(/pushPathByName\('EhLogin', null\)/.test(ehPage),
  'page routes normal login through existing EhLogin route')
ok(/pushPathByName\('EhCookieImport', null\)/.test(ehPage),
  'page routes cookie import through existing EhCookieImport route')
ok(/pushPathByName\('MyTags', null\)/.test(ehPage),
  'page routes My Tags through existing MyTags route')
ok(/CookieJarSettings\.clear\(this\.ctx\(\)\)/.test(ehPage),
  'page reuses existing CookieJarSettings logout path')
ok(!/ipb_pass_hash|igneous=|webdav|mysql|OpenByDefault|Api\.selEhProfile|getEhHome/.test(ehPage),
  'EH settings page does not introduce cookie secrets, cloud sync, link handlers, profile fetch, or image-limit fetch')
ok(!/eh_settings_website_settings/.test(ehPage) && !/eh_settings_image_limits/.test(ehPage),
  'EH settings page does not expose disabled website-settings or image-limit placeholder rows')
ok(!/isEnabled:\s*false[\s\S]{0,240}eh_settings_/.test(ehPage),
  'EH settings page keeps future EH settings out of the visible settings list')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'settings_eh',
    'eh_settings_site_hint',
    'eh_settings_login_hint',
    'eh_settings_cookie_hint',
    'eh_settings_mytags_hint',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
  ok(!/表站|里站|table site/.test(strings), `${locale}: user-visible strings avoid slang or old table-site wording`)
}

if (failures > 0) {
  console.error(`\n✗ settings EH entry contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ settings EH entry contract: EH settings route and existing account/site actions locked')

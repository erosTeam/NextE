#!/usr/bin/env node
/**
 * Contract: Security settings are exposed only after real native protection is wired.
 *
 * Run: node scripts/test_settings_security_entry_contract.mjs
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
  'eros_fe: lib/common/controller/auto_lock_controller.dart records leave time and locks on resume; lib/pages/tab/view/unlock_page.dart blocks content behind authentication',
  'primary information: recent-task privacy and auto-lock timeout backed by native HarmonyOS protection',
  'primary action: enable recent-task protection, choose auto-lock timeout, unlock through system authentication after background return',
  'scope: expose the Security settings entry because lifecycle lock enforcement and window privacy are wired',
  'Harmony expression: Window.setWindowPrivacyMode plus @ohos.userIAM.userAuth; no custom password page',
]

ok(grounding.length === 5, 'security settings lane has five-line grounding')
ok(grounding[0].includes('auto_lock_controller.dart') && grounding[0].includes('unlock_page.dart'),
  'grounding names concrete eros_fe Security settings files')
ok(grounding[3].includes('expose the Security settings entry') &&
  grounding[4].includes('Window.setWindowPrivacyMode') &&
  grounding[4].includes('@ohos.userIAM.userAuth'), 'grounding limits scope and names Harmony expression')

const state = read('shared/src/main/ets/state/SecuritySettingsState.ets')
ok(/@ObservedV2\s+export class SecuritySettingsState/.test(state), 'security settings holder is V2')
ok(/@Trace autoLockSeconds: number = AutoLockTimeout\.DISABLED/.test(state),
  'auto-lock defaults to disabled')
ok(/@Trace recentTasksProtectionEnabled: boolean = false/.test(state) &&
  /@Trace locked: boolean = false/.test(state),
  'security state tracks recent-task protection and runtime lock')
ok(/AppStorageV2\.connect\(\s*SecuritySettingsState/.test(state),
  'security settings holder connects through AppStorageV2')

const settings = read('shared/src/main/ets/settings/SecuritySettings.ets')
ok(/StorageKeys\.SECURITY_AUTO_LOCK_SEC/.test(settings), 'settings persist auto-lock key')
ok(/StorageKeys\.SECURITY_RECENT_TASKS_PROTECTION/.test(settings),
  'settings persist recent-task protection key')
ok(/AUTO_LOCK_VALUES: number\[\]/.test(settings) &&
  /AutoLockTimeout\.DISABLED/.test(settings) &&
  /AutoLockTimeout\.HOURS_5/.test(settings),
  'settings expose the bounded eros_fe-inspired timeout choices')
ok(/normalizeAutoLockSeconds/.test(settings), 'settings normalize unknown timeout values')
ok(/static async restore/.test(settings) && /connectSecuritySettings\(\)/.test(settings),
  'settings restore preferences into the V2 holder')
ok(/static async setAutoLockSeconds/.test(settings) &&
  /store\.putSync\(StorageKeys\.SECURITY_AUTO_LOCK_SEC/.test(settings),
  'settings write auto-lock timeout to preferences')
ok(/userAuth\.getUserAuthInstance/.test(settings) &&
  /userAuth\.UserAuthType\.FACE/.test(settings) &&
  /userAuth\.UserAuthType\.FINGERPRINT/.test(settings) &&
  /userAuth\.UserAuthType\.PIN/.test(settings),
  'security lock uses native system authentication with biometric plus PIN fallback')
ok(/BIOMETRIC_PERMISSION/.test(settings) &&
  /requestPermissionsFromUser\(context, \[BIOMETRIC_PERMISSION\]\)/.test(settings),
  'security authentication requests biometric permission before starting user auth')
ok(/AUTH_CANDIDATES: AuthCandidate\[\]/.test(settings) &&
  /authTypes: \[userAuth\.UserAuthType\.FACE, userAuth\.UserAuthType\.PIN\]/.test(settings) &&
  /authTrustLevel: userAuth\.AuthTrustLevel\.ATL3/.test(settings) &&
  /authTypes: \[userAuth\.UserAuthType\.FINGERPRINT\]/.test(settings) &&
  /authTrustLevel: userAuth\.AuthTrustLevel\.ATL1/.test(settings),
  'security authentication probes official auth-type/trust-level groups instead of one global level')
ok(/getAvailableStatus\(type, trustLevel\)/.test(settings) &&
  /authTrustLevel: authCandidate\.authTrustLevel/.test(settings),
  'security authentication launches with the same trust level that passed availability')
ok(/setAutoLockSecondsWithBoundaryAuth/.test(settings) &&
  /crossesEnabledBoundary/.test(settings),
  'auto-lock only authenticates when crossing the enabled/disabled boundary')
ok(/export enum SecurityAuthResult/.test(settings) &&
  /Promise<SecurityAuthResult>/.test(settings),
  'auto-lock boundary setter returns the concrete authentication result')
ok(!/setRecentTasksProtectionWithAuth/.test(settings),
  'recent-task privacy switch does not require system authentication')
ok(/enum SecurityAuthResult/.test(settings) &&
  /SecurityAuthResult\.UNAVAILABLE/.test(settings) &&
  /auth_unavailable_unlock/.test(settings) &&
  /AutoLockTimeout\.DISABLED/.test(settings),
  'security lock distinguishes unavailable system auth and does not trap the app locked')
ok(/bindWindowPrivacyApplier/.test(settings) &&
  /state\.recentTasksProtectionEnabled \|\| state\.locked/.test(settings),
  'window privacy stays on for recent-task protection or while locked')

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
ok(/import \{ SecuritySettings \}/.test(bootstrap) && /await SecuritySettings\.restore\(context\)/.test(bootstrap),
  'bootstrap restores security settings')

const barrel = read('shared/src/main/ets/Index.ets')
ok(/SecuritySettingsState/.test(barrel) && /connectSecuritySettings/.test(barrel) &&
  /SecurityAuthResult/.test(barrel) &&
  /SecuritySettings/.test(barrel), 'shared barrel exports security settings API')

const settingsRoot = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
ok(!/title:\s*\$r\('app\.string\.settings_security'\)[\s\S]*pushPathByName\('SecuritySettings', null\)/.test(settingsRoot),
  'Settings root does not expose Security as a top-level row')
const advancedPage = read('feature/settings/src/main/ets/pages/AdvancedSettingsPage.ets')
ok(/settings_security/.test(advancedPage) && /pushPathByName\('SecuritySettings', null\)/.test(advancedPage),
  'Advanced settings exposes Security after lock enforcement is implemented')

const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
ok(/SecuritySettingsPage/.test(settingsIndex), 'parked settings barrel still exports SecuritySettingsPage')

const entryIndex = read('entry/src/main/ets/pages/Index.ets')
ok(/SecuritySettingsPage/.test(entryIndex) && /name === 'SecuritySettings'/.test(entryIndex),
  'parked entry router still registers the SecuritySettings route for future direct-lane validation')
ok(/security_unlock_button[\s\S]*ThemeConstants\.TEXT_ON_BRAND[\s\S]*ThemeConstants\.BRAND_PRIMARY/.test(entryIndex),
  'lock overlay unlock button uses the app theme brand color')

const page = read('feature/settings/src/main/ets/pages/SecuritySettingsPage.ets')
ok(/@ComponentV2\s+export struct SecuritySettingsPage/.test(page),
  'security settings page is V2-only')
ok(/@Local securitySettings: SecuritySettingsState = connectSecuritySettings\(\)/.test(page),
  'page reads the persisted security settings holder')
ok(/security_recent_tasks_blur/.test(page) && /hasSwitch: true/.test(page) &&
  /checked: this\.securitySettings\.recentTasksProtectionEnabled/.test(page) &&
  /SecuritySettings\.setRecentTasksProtection\(this\.ctx\(\), value\)/.test(page),
  'recent-task protection switch writes directly without authentication')
ok(/security_auto_lock/.test(page) && /trailingDropdown: true/.test(page) &&
  /SecuritySettings\.setAutoLockSecondsWithBoundaryAuth/.test(page),
  'page authenticates auto-lock only when enabling or disabling it')
ok(/SecurityAuthResult\.UNAVAILABLE/.test(page) &&
  /security_auth_unavailable/.test(page),
  'settings page shows a specific message when system authentication is not configured')
ok(!/SecuritySettings\.setRecentTasksProtectionWithAuth/.test(page) &&
  !/SecuritySettings\.setAutoLockSeconds\(/.test(page),
  'settings page does not directly write auto-lock preferences without boundary authentication')
ok(!/userAuth|ACCESS_BIOMETRIC|setWindowPrivacy|blurredInRecentTasks\s*=|checkBiometrics/.test(page),
  'settings page does not hand-roll platform authentication or window APIs')

const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets')
ok(/SecuritySettings\.bindWindowPrivacyApplier/.test(entryAbility) &&
  /\.setWindowPrivacyMode\(enabled\)/.test(entryAbility),
  'EntryAbility owns the main-window privacy mode')
ok(/onBackground\(\): void[\s\S]*SecuritySettings\.recordBackground/.test(entryAbility) &&
  /onForeground\(\): void[\s\S]*SecuritySettings\.lockIfNeeded/.test(entryAbility),
  'EntryAbility records background time and checks auto-lock on foreground')

const moduleJson = read('entry/src/main/module.json5')
ok(/ohos\.permission\.ACCESS_BIOMETRIC/.test(moduleJson) &&
  /perm_access_biometric_reason/.test(moduleJson),
  'entry declares biometric access permission with reason')
ok(/ohos\.permission\.PRIVACY_WINDOW/.test(moduleJson) &&
  /perm_privacy_window_reason/.test(moduleJson),
  'entry declares window privacy permission with reason')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'settings_security',
    'perm_access_biometric_reason',
    'perm_privacy_window_reason',
    'security_recent_tasks_blur',
    'security_recent_tasks_blur_hint',
    'security_auto_lock',
    'security_auto_lock_hint',
    'security_locked_title',
    'security_unlock_title',
    'security_unlock_button',
    'security_unlock_failed',
    'security_auth_unavailable',
    'security_auto_lock_disabled',
    'security_auto_lock_instant',
    'security_auto_lock_30s',
    'security_auto_lock_1m',
    'security_auto_lock_5m',
    'security_auto_lock_10m',
    'security_auto_lock_30m',
    'security_auto_lock_1h',
    'security_auto_lock_5h',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ settings security entry contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ settings security entry contract: native privacy and auto-lock are wired')

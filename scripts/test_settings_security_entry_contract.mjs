#!/usr/bin/env node
/**
 * Contract: Settings exposes a Security child page without pretending unsupported privacy/biometric
 * behavior is implemented. Auto-lock is persisted as a preference foundation only.
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
  'eros_fe: lib/pages/tab/controller/setting_controller.dart routes Security to EHRoutes.securitySetting; lib/pages/setting/security_setting_page.dart renders recent-task blur and auto-lock rows',
  'primary information: app privacy and auto-lock settings, not generic diagnostics',
  'primary action: choose auto-lock timeout; recent-task blur stays disabled until HarmonyOS window privacy support is implemented',
  'scope: Settings root + HDS child page + persisted auto-lock preference foundation; no biometric unlock overlay, lifecycle lock enforcement, or recent-task privacy API',
  'Harmony expression: HdsNavDestination + SecondaryListScaffold + GroupedListSection + ConciseListRow, V2 holder plus single-writer settings',
]

ok(grounding.length === 5, 'security settings lane has five-line grounding')
ok(grounding[0].includes('setting_controller.dart') && grounding[0].includes('security_setting_page.dart'),
  'grounding names concrete eros_fe Security settings files')
ok(grounding[3].includes('no biometric unlock') && grounding[4].includes('HdsNavDestination'),
  'grounding limits scope and names Harmony expression')

const state = read('shared/src/main/ets/state/SecuritySettingsState.ets')
ok(/@ObservedV2\s+export class SecuritySettingsState/.test(state), 'security settings holder is V2')
ok(/@Trace autoLockSeconds: number = AutoLockTimeout\.DISABLED/.test(state),
  'auto-lock defaults to disabled')
ok(/AppStorageV2\.connect\(\s*SecuritySettingsState/.test(state),
  'security settings holder connects through AppStorageV2')

const settings = read('shared/src/main/ets/settings/SecuritySettings.ets')
ok(/StorageKeys\.SECURITY_AUTO_LOCK_SEC/.test(settings), 'settings persist auto-lock key')
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

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
ok(/import \{ SecuritySettings \}/.test(bootstrap) && /await SecuritySettings\.restore\(context\)/.test(bootstrap),
  'bootstrap restores security settings')

const barrel = read('shared/src/main/ets/Index.ets')
ok(/SecuritySettingsState/.test(barrel) && /connectSecuritySettings/.test(barrel) &&
  /SecuritySettings/.test(barrel), 'shared barrel exports security settings API')

const settingsRoot = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
ok(/settings_security/.test(settingsRoot) && /pushPathByName\('SecuritySettings', null\)/.test(settingsRoot),
  'Settings root exposes a Security settings entry')

const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
ok(/SecuritySettingsPage/.test(settingsIndex), 'settings barrel exports SecuritySettingsPage')

const entryIndex = read('entry/src/main/ets/pages/Index.ets')
ok(/SecuritySettingsPage/.test(entryIndex) && /name === 'SecuritySettings'/.test(entryIndex),
  'entry router registers the SecuritySettings route')

const page = read('feature/settings/src/main/ets/pages/SecuritySettingsPage.ets')
ok(/@ComponentV2\s+export struct SecuritySettingsPage/.test(page),
  'security settings page is V2-only')
ok(/@Local securitySettings: SecuritySettingsState = connectSecuritySettings\(\)/.test(page),
  'page reads the persisted security settings holder')
ok(/security_recent_tasks_blur/.test(page) && /hasSwitch: true/.test(page) &&
  /checked: false/.test(page) && /isEnabled: false/.test(page),
  'recent-task blur is visible but disabled, not falsely implemented')
ok(/security_auto_lock/.test(page) && /trailingDropdown: true/.test(page) &&
  /SecuritySettings\.setAutoLockSeconds/.test(page),
  'page exposes auto-lock preference as a native dropdown')
ok(!/userAuth|ACCESS_BIOMETRIC|WindowPrivacy|setWindowPrivacy|blurredInRecentTasks\s*=|checkBiometrics|Unlock/.test(page),
  'page does not introduce unvalidated biometric, window privacy, or lock overlay behavior')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'settings_security',
    'security_recent_tasks_blur',
    'security_recent_tasks_blur_hint',
    'security_auto_lock',
    'security_auto_lock_hint',
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

console.log('✓ settings security entry contract: Security route and honest auto-lock preference locked')

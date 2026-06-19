import fs from 'node:fs'

const checks = []

function read(path) {
  return fs.readFileSync(path, 'utf8')
}

function assert(name, condition) {
  checks.push({ name, condition })
}

const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
const aboutPage = read('feature/settings/src/main/ets/pages/AboutPage.ets')
const entryIndex = read('entry/src/main/ets/pages/Index.ets')

assert('settings exports AboutPage', /export \{ AboutPage \} from '\.\/pages\/AboutPage'/.test(settingsIndex))
assert('entry imports AboutPage from settings', /AboutPage/.test(entryIndex) && /from 'settings'/.test(entryIndex))
assert('entry registers About route', /name === 'About'/.test(entryIndex) && /AboutPage\(\)/.test(entryIndex))
assert('settings About row pushes About route', /settings_about/.test(settingsPage) && /pushPathByName\('About', null\)/.test(settingsPage))
assert('settings About row is not static version text only', !/settings_about[\s\S]{0,240}trailingText: 'NextE v1\.0\.0'/.test(settingsPage))
assert('AboutPage uses V2 component', /@ComponentV2/.test(aboutPage) && /export struct AboutPage/.test(aboutPage))
assert('AboutPage uses HDS nav and settings list components', /HdsNavDestination/.test(aboutPage) && /SecondaryListScaffold/.test(aboutPage) && /GroupedListSection/.test(aboutPage))
assert('AboutPage reads bundle version through official API', /bundleManager\.getBundleInfoForSelf/.test(aboutPage) && /versionName/.test(aboutPage))
assert('AboutPage title uses existing settings_about resource', /immersiveTitleBar\(AppStrings\.get\('settings_about'\)\)/.test(aboutPage))
assert('AboutPage exposes license and unofficial notice', /about_source_license/.test(aboutPage) && /about_unofficial_notice/.test(aboutPage))

const resourceFiles = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]
const keys = [
  'about_tagline',
  'about_app_info',
  'about_app_name',
  'about_version',
  'about_platform',
  'about_license',
  'about_source_license',
  'about_unofficial_notice',
  'about_eh_notice',
]

for (const file of resourceFiles) {
  const text = read(file)
  for (const key of keys) {
    assert(`${file} contains ${key}`, text.includes(`"name": "${key}"`))
  }
}

const failed = checks.filter((check) => !check.condition)
if (failed.length > 0) {
  for (const check of failed) {
    console.error(`FAIL ${check.name}`)
  }
  process.exit(1)
}

console.log(`settings_about_entry_contract: ${checks.length} checks passed`)

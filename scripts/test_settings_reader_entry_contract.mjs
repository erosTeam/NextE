#!/usr/bin/env node
/**
 * Contract: Reader settings must be reachable from the Settings root, not only from Reader chrome.
 *
 * eros_fe exposes Read as a first-level Settings row (`setting_controller.dart`) and also opens the
 * same readSetting route from the reader top menu (`view_widget.dart`). NextE already has the route
 * and page; this contract locks the Settings root entry point.
 *
 * Run: node scripts/test_settings_reader_entry_contract.mjs
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

const settings = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
const readerSettings = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')
const index = read('entry/src/main/ets/pages/Index.ets')
const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')

ok(/ReaderSettingsPage\(\)/.test(index), 'ReaderSettings route remains registered in Index')
ok(/export struct ReaderSettingsPage/.test(readerSettings), 'ReaderSettingsPage exists')
ok(/title:\s*\$r\('app\.string\.settings_reader'\)/.test(settings), 'Settings root renders a Reader settings row')
ok(/this\.stack\.pushPathByName\('ReaderSettings',\s*null\)/.test(settings),
  'Settings root Reader row pushes the ReaderSettings route')
ok(/settings_reader[\s\S]*pushPathByName\('DownloadSettings'/.test(settings),
  'Reader settings row appears before Download settings in the main settings group')
ok(/private openReaderSettings\(\): void[\s\S]*pushPathByName\('ReaderSettings',\s*null\)/.test(reader),
  'Reader chrome still opens the same ReaderSettings route')

if (failures > 0) {
  console.error(`\n✗ settings reader entry contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ settings reader entry contract passed')

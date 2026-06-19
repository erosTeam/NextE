#!/usr/bin/env node
/**
 * Contract: settings dropdown menus are anchored to the tapped row, not to a broad section/page
 * container. Binding Menu to an outer Column/ListItem makes HarmonyOS position it from the bottom or
 * from unexpected page geometry.
 *
 * Run: node scripts/test_settings_dropdown_anchor_contract.mjs
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

const row = read('shared/src/main/ets/components/ConciseListRow.ets')
ok(!/menuBuilderParam|menuShown|menuOnDisappear|\.bindMenu\(/.test(row),
  'ConciseListRow stays a stable row primitive; pages own their row-local menu anchors')

const dropdownPages = [
  {
    file: 'feature/settings/src/main/ets/pages/LayoutSettingsPage.ets',
    states: ['viewMenuShown'],
    builders: ['ViewModeMenu'],
  },
  {
    file: 'feature/settings/src/main/ets/pages/ReaderSettingsPage.ets',
    states: ['dirMenuShown', 'columnMenuShown', 'autoPageMenuShown'],
    builders: ['DirMenu', 'ColumnMenu', 'AutoPageMenu'],
  },
  {
    file: 'feature/settings/src/main/ets/pages/DownloadSettingsPage.ets',
    states: ['originalMenuShown'],
    builders: ['OriginalModeMenu'],
  },
  {
    file: 'feature/settings/src/main/ets/pages/SecuritySettingsPage.ets',
    states: ['autoLockMenuShown'],
    builders: ['AutoLockMenu'],
  },
]

for (const page of dropdownPages) {
  const source = read(page.file)
  const lines = source.split('\n')
  const bindLines = lines
    .map((line, index) => ({ line, index }))
    .filter((entry) => entry.line.includes('.bindMenu('))
  ok(bindLines.length === page.states.length, `${page.file}: binds exactly one menu per dropdown row`)
  for (const state of page.states) {
    ok(source.includes(`.bindMenu(this.${state},`), `${page.file}: ${state} is bound to a menu anchor`)
  }
  for (const builder of page.builders) {
    ok(source.includes(`, this.${builder},`), `${page.file}: ${builder} supplies row-local menu content`)
  }
  for (const entry of bindLines) {
    const start = Math.max(0, entry.index - 18)
    const context = lines.slice(start, entry.index + 3).join('\n')
    ok(/Column\(\) \{[\s\S]*ConciseListRow\(\{/.test(context),
      `${page.file}:${entry.index + 1}: menu anchor is a single-row wrapper`)
    ok(/placement: Placement\.BottomRight/.test(context),
      `${page.file}:${entry.index + 1}: menu opens from the row's trailing side`)
    ok(/onDisappear: \(\) => \{/.test(context),
      `${page.file}:${entry.index + 1}: menu closes through onDisappear`)
  }
}

if (failures > 0) {
  console.error(`\n✗ settings dropdown anchor contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ settings dropdown anchor contract: row-local settings menu anchors locked')

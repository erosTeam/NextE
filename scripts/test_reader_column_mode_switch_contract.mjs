#!/usr/bin/env node
/**
 * Contract: double-page is a global on/off switch; odd/even spread pairing is
 * adjusted only by the reader's per-gallery "turn one page" action.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')
const readModeSettings = read('shared/src/main/ets/settings/ReadModeSettings.ets')
const progressState = read('shared/src/main/ets/state/GalleryReadProgressState.ets')
const progressSettings = read('shared/src/main/ets/settings/GalleryReadProgressSettings.ets')

ok('settings page exposes double-page as a switch, not an A/B menu',
  /settings_reader_double_page/.test(settingsPage) &&
    /hasSwitch:\s*true/.test(settingsPage) &&
    /checked:\s*this\.readMode\.doublePageEnabled/.test(settingsPage) &&
    /ReadModeSettings\.setDoublePageEnabled/.test(settingsPage) &&
    !/ColumnMenu|columnModeLabel|ReadColumnMode/.test(settingsPage))
ok('ReadModeSettings persists only the double-page boolean and migrates old A/B values',
  /restoreDoublePageEnabled/.test(readModeSettings) &&
    /value === ReadColumnMode\.ODD_LEFT/.test(readModeSettings) &&
    /static async setDoublePageEnabled/.test(readModeSettings) &&
    /store\.putSync\(StorageKeys\.READING_DOUBLE_PAGE, enabled\)/.test(readModeSettings) &&
    !/static async setColumnMode/.test(readModeSettings))
ok('Reader gates double-page by global enabled flag, not columnMode != single',
  /static isDoublePage\(mode: string, enabled: boolean\): boolean \{[\s\S]*mode !== ReadMode\.VERTICAL && enabled/.test(reader) &&
    /private doublePageEnabled\(\): boolean \{[\s\S]*this\.readMode\.doublePageEnabled/.test(reader))
ok('Reader double-page toggle does not rewrite currentIndex',
  /private toggleDoublePage\(\): void \{[\s\S]*ReadModeSettings\.setDoublePageEnabled\(ctx, !this\.readMode\.doublePageEnabled\)[\s\S]*syncReaderPagerToIndex\(this\.vm\.currentIndex/.test(reader) &&
    !/toggleDoublePage[\s\S]*this\.vm\.currentIndex =/.test(reader))
ok('Reader has a per-gallery one-page action that shifts the double-page window by one image and stores pairing',
  /private refreshSpreadStartSource\(\): void \{[\s\S]*this\.spreadDataSource\.setData\(this\.spreadStarts\(\)\)/.test(reader) &&
    /private currentDoublePageStart\(\): number \{[\s\S]*this\.spreadStartIndex\(this\.spreadIndexForImage\(this\.vm\.currentIndex\)\)/.test(reader) &&
    /private columnModeForSpreadStart\(index: number\): string \{[\s\S]*index <= 0 \|\| index % 2 === 0[\s\S]*ReadColumnMode\.ODD_LEFT[\s\S]*ReadColumnMode\.EVEN_LEFT/.test(reader) &&
    /private setCurrentGalleryColumnMode\(columnMode: string\): void \{[\s\S]*this\.readMode\.columnMode = columnMode[\s\S]*this\.refreshSpreadStartSource\(\)/.test(reader) &&
    /private turnOnePageInDoublePage\(\): void \{[\s\S]*const targetStart: number = this\.currentDoublePageStart\(\) \+ 1[\s\S]*this\.setCurrentGalleryColumnMode\(this\.columnModeForSpreadStart\(targetStart\)\)[\s\S]*this\.turnTo\(targetStart\)/.test(reader) &&
    /GalleryReadProgressSettings\.setColumnMode\(this\.hostContext\(\), this\.params\.gid, columnMode\)/.test(reader))
ok('read-progress state stores column mode per gid',
  /private columnModeMap: Map<string, string>/.test(progressState) &&
    /getColumnMode\(gid: string\): string/.test(progressState) &&
    /setColumnMode\(gid: string, columnMode: string, time: number\): void/.test(progressState) &&
    /new ReadProgressEntry\(gid, idx,[\s\S]*c/.test(progressState))
ok('read-progress settings persists per-gallery column mode through the same debounce path',
  /static setColumnMode\(context: common\.UIAbilityContext, gid: string, columnMode: string\): void/.test(progressSettings) &&
    /connectGalleryReadProgress\(\)\.setColumnMode\(gid, columnMode, Date\.now\(\)\)/.test(progressSettings))
ok('double-page reader path still uses spread starts',
  /@Builder\s+DoublePageReader\(\)[\s\S]*this\.spreadStartSource\(\)/.test(reader))

console.log(`✓ reader column-mode switch contract: ${passed} assertions passed`)

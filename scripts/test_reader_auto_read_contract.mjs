#!/usr/bin/env node
/**
 * Contract for Reader auto-read:
 *   - auto-read is a secondary reader chrome control, not a new primary surface;
 *   - page advance is timer-driven but gated by the target being real-image ready;
 *   - a missing/unresolved target pauses the timer and warms preview/url data instead of showing blank;
 *   - interval is persisted through ReadModeSettings / ReadModeState.
 *
 * Run: node scripts/test_reader_auto_read_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const vm = read('feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets')
const settings = read('shared/src/main/ets/settings/ReadModeSettings.ets')
const state = read('shared/src/main/ets/state/ReadModeState.ets')
const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')
const zh = read('entry/src/main/resources/zh_CN/element/string.json')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

function autoStep(current, total, ready, hasPreview) {
  const target = current + 1
  if (target >= total) return { active: false, target }
  if (!hasPreview.includes(target) || !ready.includes(target)) {
    return { wait: true, target }
  }
  return { turn: true, target }
}

{
  assert.deepStrictEqual(autoStep(0, 3, [0, 1], [0, 1]), { turn: true, target: 1 })
  passed++
  assert.deepStrictEqual(autoStep(0, 3, [0], [0, 1]), { wait: true, target: 1 })
  passed++
  assert.deepStrictEqual(autoStep(2, 3, [0, 1, 2], [0, 1, 2]), { active: false, target: 3 })
  passed++
}

ok('ReadModeState carries persisted auto-page interval',
  /@Trace autoPageSeconds: number = 3/.test(state))
ok('StorageKeys has reading.autoPageSeconds',
  /READING_AUTO_PAGE_SEC: string = 'reading\.autoPageSeconds'/.test(keys))
ok('ReadModeSettings restores autoPageSeconds',
  /StorageKeys\.READING_AUTO_PAGE_SEC[\s\S]*connectReadMode\(\)\.autoPageSeconds/.test(settings))
ok('ReadModeSettings persists autoPageSeconds',
  /static async setAutoPageSeconds[\s\S]*store\.putSync\(StorageKeys\.READING_AUTO_PAGE_SEC, normalized\)/.test(settings))
ok('ReaderPage has transient autoReadActive state',
  /@Local autoReadActive: boolean = false/.test(reader))
ok('ReaderPage starts a setInterval timer with the persisted interval',
  /setInterval\(\(\) => \{[\s\S]*this\.advanceAutoRead\(\)[\s\S]*this\.autoReadIntervalMs\(\)/.test(reader))
ok('ReaderPage clears interval on stop/disappear',
  /private stopAutoRead\(\): void \{[\s\S]*this\.clearAutoReadTimer\(\)[\s\S]*this\.autoReadActive = false/.test(reader) &&
  /aboutToDisappear\(\): void \{[\s\S]*this\.stopAutoRead\(\)/.test(reader))
ok('ReaderPage tracks loaded pages from Image.onComplete',
  /private loadedPages: number\[\] = \[\]/.test(reader) &&
  /onImageLoaded\(this\.image\.page\)/.test(reader) &&
  /markPageImageLoaded\(page\)/.test(reader))
ok('Reader auto-read treats onComplete or resolved imageUrl as ready',
  /private isPageReadyForAutoRead\(index: number\): boolean \{[\s\S]*this\.isPageImageLoaded\(index\)[\s\S]*this\.vm\.images\[index\]\.imageUrl\.length > 0/.test(reader))
ok('Reader auto-read waits when preview or real image URL is not ready',
  /if \(!this\.vm\.hasPreviewAt\(target\) \|\| !this\.isPageReadyForAutoRead\(target\)\) \{[\s\S]*this\.waitForAutoReadPage\(target\)/.test(reader))
ok('Waiting auto-read warms target without changing current page',
  /private waitForAutoReadPage\(index: number\): void \{[\s\S]*this\.vm\.warmForAutoRead\(index\)/.test(reader) &&
  /warmForAutoRead\(index: number\): void \{[\s\S]*this\.ensureLoaded\(index\)[\s\S]*this\.precacheAhead\(\)/.test(vm))
ok('loaded callback resumes paused auto-read',
  /private maybeResumeAutoRead\(index: number\): void \{[\s\S]*this\.startAutoReadTimer\(\)/.test(reader))
ok('bottom chrome exposes auto-read as a secondary clock control',
  /SymbolGlyph\(\$r\('sys\.symbol\.clock'\)\)/.test(reader) &&
  /this\.toggleAutoRead\(\)/.test(reader))
ok('ReaderSettings exposes interval row and menu',
  /settings_reader_auto_page_interval/.test(settingsPage) &&
  /AutoPageMenu\(\)/.test(settingsPage) &&
  /ReadModeSettings\.setAutoPageSeconds/.test(settingsPage))
ok('zh_CN has interval label',
  /"settings_reader_auto_page_interval"[\s\S]*"自动翻页间隔"/.test(zh))

console.log(`✓ reader auto-read contract: ${passed} assertions passed`)

#!/usr/bin/env node
/**
 * Contract: Home bottom tabs use the same HDS tab auto-hide model as V2Next.
 *
 * This does not replace device validation. It only prevents regressions back to
 * unbound tabs, ad-hoc thresholds, or non-persisted settings.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let passed = 0
const ok = (condition, message) => {
  assert.ok(condition, message)
  passed += 1
}

const index = read('entry/src/main/ets/pages/Index.ets')
ok(/HdsAnimationMode/.test(index), 'Index imports HdsAnimationMode')
ok(/private readonly HOME_TAB_SCROLL_DELTA_PX:\s*number\s*=\s*6/.test(index),
  'Index keeps the Next2V home tab scroll delta')
ok(/private readonly HOME_TAB_ANIMATION_GUARD_MS:\s*number\s*=\s*180/.test(index),
  'Index keeps the Next2V home tab animation guard')
ok(/@Local\s+homeTab:\s*HomeTabAutoHideState\s*=\s*connectHomeTabAutoHide\(\)/.test(index),
  'Index connects V2 HomeTabAutoHideState')
ok(/@Monitor\('homeTab\.autoHide'\)[\s\S]*onHomeTabAutoHideChanged/.test(index),
  'Index reacts to persisted auto-hide setting changes')
ok(/tabsController\.bindScroller\(index, this\.homeTabScrollers\[index\]\)/.test(index) &&
  /tabsController\.unbindScroller\(this\.homeTabScrollers\[index\]\)/.test(index),
  'Index binds and unbinds HDS tab scrollers')
ok(/tabsController\.applyHideAnimation\(HdsAnimationMode\.SCROLL_ANIMATION\)/.test(index) &&
  /tabsController\.applyShowAnimation\(HdsAnimationMode\.SCROLL_ANIMATION\)/.test(index),
  'Index uses HDS tab hide/show scroll animations')
ok(/HomePage\(\{[\s\S]*onScrollerReady:[\s\S]*this\.setHomeActiveScroller\(0, scroller\)[\s\S]*onDidScroll:[\s\S]*this\.onHomeTabDidScroll\(0, offset, state\)/.test(index),
  'Home tab reports its active retained scroller and scroll events')
ok(/FavoritesPage\(\{[\s\S]*this\.setHomeActiveScroller\(1, scroller\)[\s\S]*this\.onHomeTabDidScroll\(1, offset, state\)/.test(index),
  'Favorites tab reports its active retained scroller and scroll events')
ok(/ToplistPage\(\{[\s\S]*this\.setHomeActiveScroller\(2, scroller\)[\s\S]*this\.onHomeTabDidScroll\(2, offset, state\)/.test(index),
  'Toplist tab reports its active retained scroller and scroll events')
ok(/DownloadQueuePage\(\{[\s\S]*scroller:\s*this\.homeTabScrollers\[3\][\s\S]*this\.onHomeTabDidScroll\(3, offset, state\)/.test(index),
  'Download tab reports scroll events')
ok(/SettingsPage\(\{[\s\S]*scroller:\s*this\.homeTabScrollers\[4\][\s\S]*this\.onHomeTabDidScroll\(4, offset, state\)/.test(index),
  'Settings tab reports scroll events')

const state = read('shared/src/main/ets/state/HomeTabAutoHideState.ets')
ok(/@ObservedV2/.test(state) && /@Trace\s+autoHide:\s*boolean\s*=\s*true/.test(state),
  'HomeTabAutoHideState is V2 and defaults enabled')
ok(!/@State|@Prop|@Link|@Component\b/.test(state), 'HomeTabAutoHideState contains no V1 decorators')

const settings = read('shared/src/main/ets/settings/HomeTabSettings.ets')
ok(/DEFAULT_AUTO_HIDE:\s*boolean\s*=\s*true/.test(settings),
  'HomeTabSettings default is enabled')
ok(/StorageKeys\.HOME_TAB_AUTO_HIDE/.test(settings) &&
  /preferences\.getPreferences/.test(settings) &&
  /store\.putSync\(StorageKeys\.HOME_TAB_AUTO_HIDE, autoHide\)/.test(settings),
  'HomeTabSettings persists the setting')

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
ok(/HomeTabSettings\.restore\(context\)/.test(bootstrap), 'SettingsBootstrap restores home tab setting')

const settingsPage = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
ok(/connectHomeTabAutoHide\(\)/.test(settingsPage) &&
  /settings_home_tab_auto_hide/.test(settingsPage) &&
  /HomeTabSettings\.save\(ctx, enabled\)/.test(settingsPage),
  'SettingsPage exposes a persisted switch for home tab auto-hide')

const retained = read('shared/src/main/ets/components/RetainedSubtabHost.ets')
ok(/@Event onDidScroll/.test(retained) &&
  /onDidScroll\(offset, state\)/.test(retained),
  'RetainedSubtabHost forwards active child scroll events')

for (const file of [
  'shared/src/main/ets/components/PullRefreshGridScaffold.ets',
  'shared/src/main/ets/components/PullRefreshWaterFlowScaffold.ets',
  'feature/home/src/main/ets/components/GalleryListBody.ets',
  'feature/user/src/main/ets/components/FavcatPage.ets',
  'feature/download/src/main/ets/pages/DownloadQueuePage.ets',
  'feature/settings/src/main/ets/pages/SettingsPage.ets',
]) {
  const source = read(file)
  ok(/onDidScroll/.test(source), `${file} forwards scroll events for home tab auto-hide`)
}

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(strings.includes('"name": "settings_home_tab_auto_hide"'),
    `${locale} has settings_home_tab_auto_hide`)
}

console.log(`✓ home tab auto-hide contract: ${passed} assertions passed`)

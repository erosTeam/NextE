#!/usr/bin/env node
/**
 * Contract: edge-drag ownership is explicit.
 *
 * Custom PullRefresh containers move their content with PullRefresh.pullOffset,
 * so their inner List/Grid/WaterFlow must not also run native spring overscroll
 * or alwaysEnabled. Non-refresh short-content scroll surfaces opt into
 * alwaysEnabled locally when they need sparse-content gestures; settings pages
 * are the explicit SecondaryListScaffold opt-in.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const pullRefreshFiles = [
  'shared/src/main/ets/components/PullRefreshListScaffold.ets',
  'shared/src/main/ets/components/PullRefreshGridScaffold.ets',
  'shared/src/main/ets/components/PullRefreshWaterFlowScaffold.ets',
]
const plainListFiles = [
  'shared/src/main/ets/components/SecondaryListScaffold.ets',
]
const searchPage = 'feature/search/src/main/ets/pages/GallerySearchPage.ets'
const pullRefresh = 'shared/src/main/ets/components/PullRefresh.ets'
const settingPages = [
  'feature/settings/src/main/ets/pages/AboutPage.ets',
  'feature/settings/src/main/ets/pages/AccountLoginPage.ets',
  'feature/settings/src/main/ets/pages/AccountPage.ets',
  'feature/settings/src/main/ets/pages/AdvancedSettingsPage.ets',
  'feature/settings/src/main/ets/pages/DownloadSettingsPage.ets',
  'feature/settings/src/main/ets/pages/EhSettingsPage.ets',
  'feature/settings/src/main/ets/pages/LayoutSettingsPage.ets',
  'feature/settings/src/main/ets/pages/ReaderSettingsPage.ets',
  'feature/settings/src/main/ets/pages/SearchSettingsPage.ets',
  'feature/settings/src/main/ets/pages/SecuritySettingsPage.ets',
  'feature/settings/src/main/ets/pages/SettingsPage.ets',
  'feature/settings/src/main/ets/pages/TagTranslationSettingsPage.ets',
]

let passed = 0
for (const file of pullRefreshFiles) {
  const src = readFileSync(join(ROOT, file), 'utf8')
  assert.match(
    src,
    /\.edgeEffect\(EdgeEffect\.None\)/,
    `${file} must let PullRefresh own edge-drag movement`,
  )
  assert.doesNotMatch(
    src,
    /alwaysEnabled:\s*true/,
    `${file} must not re-enable native sparse-content edge spring`,
  )
  passed++
}

for (const file of plainListFiles) {
  const src = readFileSync(join(ROOT, file), 'utf8')
  assert.match(
    src,
    /@Param\s+alwaysEnableEdgeSpring:\s*boolean\s*=\s*false/,
    `${file} must default always-on edge spring off`,
  )
  assert.match(
    src,
    /\.edgeEffect\(this\.alwaysEnableEdgeSpring \? EdgeEffect\.Spring : EdgeEffect\.None,\s*\{[\s\S]*alwaysEnabled:\s*this\.alwaysEnableEdgeSpring/,
    `${file} must make alwaysEnabled a local opt-in`,
  )
  passed++
}

for (const file of settingPages) {
  const src = readFileSync(join(ROOT, file), 'utf8')
  assert.match(
    src,
    /SecondaryListScaffold\(\{[\s\S]*alwaysEnableEdgeSpring:\s*true/,
    `${file} must keep sparse settings pages drag-responsive`,
  )
  passed++
}

const searchSrc = readFileSync(join(ROOT, searchPage), 'utf8')
assert.match(
  searchSrc,
  /private suggestionScroller: Scroller = new Scroller\(\)[\s\S]*\.edgeEffect\(EdgeEffect\.Spring,\s*\{\s*alwaysEnabled:\s*true\s*\}\)/,
  'search suggestion list is the local non-refresh sparse-content opt-in',
)
passed++

const pullSrc = readFileSync(join(ROOT, pullRefresh), 'utf8')
assert.match(
  pullSrc,
  /private async doBottomRefresh\(\): Promise<void> \{[\s\S]*try \{[\s\S]*await this\.onBottomRefresh\(\)[\s\S]*\} catch \(_error\) \{[\s\S]*RefreshFeedback\.notifyRefreshFailed\(\)[\s\S]*\}[\s\S]*this\.bottomRefreshState = 3[\s\S]*this\.bounceBottomBack\(0\)/,
  'bottom refresh failures must still feedback and bounce back so scroll interaction is restored',
)
passed++

console.log(`✓ scroll edge-effect ownership contract: ${passed} surface(s) checked`)

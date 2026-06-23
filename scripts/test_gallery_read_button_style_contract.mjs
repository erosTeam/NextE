#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const hdsButton = read('shared/src/main/ets/components/HdsCapsuleBarButton.ets')
ok('HDS capsule button uses real HdsTabs floating material',
  /HdsTabs\(\{ controller: this\.controller \}\)/.test(hdsButton) &&
  /\.barFloatingStyle\(\{[\s\S]*systemMaterialEffect:[\s\S]*materialType: this\.currentMaterialType\(\)[\s\S]*materialLevel: this\.currentMaterialLevel\(\)/.test(hdsButton))
ok('HDS capsule button preserves V2Next activity box parameters',
  /@Param barWidth: number/.test(hdsButton) &&
  /@Param barHeight: number/.test(hdsButton) &&
  /@Param activityPadding: number/.test(hdsButton) &&
  /@Param barBottomMargin: number/.test(hdsButton) &&
  /return this\.barWidth \+ this\.activityPadding \* 2/.test(hdsButton) &&
  /return this\.barHeight \+ this\.activityPadding \* 2/.test(hdsButton))
ok('HDS capsule button reuses app immersive material settings',
  /ImmersiveMaterialSettings\.effect\(this\.immersiveMaterial\.level\)/.test(hdsButton))

const state = read('shared/src/main/ets/state/ReadButtonStyleState.ets')
const settings = read('shared/src/main/ets/settings/ReadButtonStyleSettings.ets')
const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const barrel = read('shared/src/main/ets/Index.ets')
ok('read button style state defaults to filled',
  /READ_BUTTON_STYLE_FILLED: string = 'filled'/.test(state) &&
  /READ_BUTTON_STYLE_HDS: string = 'hds'/.test(state) &&
  /@Trace style: string = READ_BUTTON_STYLE_FILLED/.test(state))
ok('read button style persists through settings store',
  /READ_BUTTON_STYLE: string = 'layout\.readButtonStyle'/.test(keys) &&
  /StorageKeys\.READ_BUTTON_STYLE/.test(settings) &&
  /setStyle\(context: common\.UIAbilityContext, style: string\)/.test(settings))
ok('settings bootstrap restores read button style',
  /ReadButtonStyleSettings/.test(bootstrap) &&
  /await ReadButtonStyleSettings\.restore\(context\)/.test(bootstrap))
ok('shared barrel exports HDS capsule and read button style APIs',
  /HdsCapsuleBarButton/.test(barrel) &&
  /ReadButtonStyleSettings/.test(barrel) &&
  /connectReadButtonStyle/.test(barrel))

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
ok('detail keeps existing filled capsule style as the default branch',
  /private ReadFabFilledButton\(\)[\s\S]*Button\(\{ type: ButtonType\.Capsule \}\)[\s\S]*ThemeConstants\.TEXT_ON_BRAND/.test(detail))
ok('detail adds optional HDS material capsule style',
  /private ReadFabHdsButton\(\)[\s\S]*HdsCapsuleBarButton\(\{[\s\S]*barHeight: ThemeConstants\.BUTTON_HEIGHT[\s\S]*activityPadding: ThemeConstants\.SPACE_LG[\s\S]*barBottomMargin: ThemeConstants\.SPACE_LG/.test(detail))
ok('HDS read button first-read bar matches filled capsule visual width',
  /private readFabMaterialBarWidth\(\): number \{[\s\S]*if \(index <= 0\) \{[\s\S]*return 86[\s\S]*return Math\.min\(172, 104 \+ \(index \+ 1\)\.toString\(\)\.length \* 8\)/.test(detail))
ok('HDS read button icon and text use the app primary color',
  /ReadFabHdsButton\(\)[\s\S]*sys\.symbol\.doc_plaintext_fill[\s\S]*fontColor\(\[ThemeConstants\.BRAND_PRIMARY\]\)[\s\S]*fontColor\(ThemeConstants\.BRAND_PRIMARY\)/.test(detail))
ok('filled read button keeps the original outline document icon',
  /ReadFabFilledButton\(\)[\s\S]*sys\.symbol\.doc_plaintext'/.test(detail))
ok('HDS read button content corrects HdsTabs tab item vertical offset',
  /ReadFabHdsButton\(\)[\s\S]*\.alignItems\(VerticalAlign\.Center\)[\s\S]*\.translate\(\{ y: -ThemeConstants\.SPACE_XS \}\)/.test(detail))
ok('detail preserves current translate-based hand-edge animation',
  /readFabVisualX\(\)/.test(detail) &&
  /\.translate\(\{ x: this\.readFabVisualX\(\) \}\)/.test(detail) &&
  /readFabAnimationDuration\(\)/.test(detail))
ok('HDS style uses internal activity padding instead of double rail padding',
  /private readFabRailSideInset\(\): number \{[\s\S]*this\.readFabUsesHdsMaterial\(\) \? 0 : ThemeConstants\.SPACE_LG/.test(detail) &&
  /private readFabRailBottomInset\(\): number \{[\s\S]*this\.readFabUsesHdsMaterial\(\) \? 0 : ThemeConstants\.SPACE_LG/.test(detail))
ok('style changes reset measurement before re-positioning',
  /@Monitor\('readButtonStyle\.style'\)[\s\S]*this\.readFabWidth = 0[\s\S]*this\.readFabLayoutReady = false/.test(detail))

const layout = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')
ok('layout settings exposes read button style beside action alignment',
  /settings_action_alignment[\s\S]*settings_read_button_style/.test(layout) &&
  /ReadButtonStyleMenu/.test(layout) &&
  /ReadButtonStyleSettings\.setStyle/.test(layout))

for (const loc of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${loc}/element/string.json`)
  for (const key of [
    'settings_read_button_style',
    'settings_read_button_style_hint',
    'read_button_style_filled',
    'read_button_style_hds',
  ]) {
    ok(`${loc} has ${key}`, strings.includes(`"name": "${key}"`))
  }
}

console.log(`✓ gallery read button style contract: ${passed} assertions passed`)

#!/usr/bin/env node
/**
 * Contract for the gallery LIST-row height mode (eros_fe `fixedHeightOfListItems`) across
 *   shared/state/ListModeState.ets · shared/settings/ListModeSettings.ets · shared/constants/StorageKeys.ets
 *   shared/components/GalleryCard.ets · feature/settings/.../SettingsPage.ets · 4 locale string.json
 *
 * Locks the P1 acceptance gate (gallery-visual-navigation-regression-contract.md → "List card height
 * modes"): NextE must expose BOTH eros_fe layouts as an OPTIONAL user setting (not one forced layout):
 *   • DEFAULT = fixed (true) — eros_fe `_fixedHeightOfListItems` defaults to true (fixed rows out of box);
 *   • the axis persists (single-writer setFixedHeight → Preferences; restore re-reads it, default true);
 *   • FIXED → every list row is pinned to eros_fe kFixedHeight=204 (min==max) with the tag block CLIPPED
 *     (layoutWeight + clip) so the meta stays foot-anchored — uniform rhythm, no runaway height;
 *   • ADAPTIVE → the row only floors at a responsive cover height (minHeight, no maxHeight) and grows with content;
 *   • NO cover stretch/crop regression: the list card keeps containFit:true (Contain over grey) in BOTH
 *     modes (preserves the cover-presentation fix — never ImageFit.Cover side-crop or a stretched cover);
 *   • the setting is wired into the Settings page (toggle → setFixedHeight) and i18n'd in all 4 locales.
 * Mirror any change here.
 *
 * Run: node scripts/test_list_height_mode_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

// 1. State holder: the orthogonal fixedHeight axis, @Trace + DEFAULT TRUE (eros_fe parity).
{
  const s = src('shared/src/main/ets/state/ListModeState.ets')
  ok('ListModeState declares @Trace fixedHeight defaulting TRUE', /@Trace\s+fixedHeight:\s*boolean\s*=\s*true/.test(s))
  ok('ListModeState keeps the mode axis (list/simple/grid) intact', /@Trace\s+mode:\s*string/.test(s))
}

// 2. Storage key + persistence (single-writer, restore default true).
{
  const k = src('shared/src/main/ets/constants/StorageKeys.ets')
  ok('StorageKeys defines LIST_ITEM_FIXED_HEIGHT', /LIST_ITEM_FIXED_HEIGHT[\s\S]*?=\s*'layout\.fixedHeightOfListItems'/.test(k))

  const set = src('shared/src/main/ets/settings/ListModeSettings.ets')
  ok(
    'restore reads LIST_ITEM_FIXED_HEIGHT with default TRUE',
    /getSync\(\s*StorageKeys\.LIST_ITEM_FIXED_HEIGHT,\s*true\s*,?\s*\)/.test(set),
  )
  ok('setFixedHeight is the single writer', /static\s+async\s+setFixedHeight\(/.test(set))
  ok('setFixedHeight updates the reactive state', /connectListMode\(\)\.fixedHeight\s*=\s*fixedHeight/.test(set))
  ok('setFixedHeight persists to Preferences', /putSync\(StorageKeys\.LIST_ITEM_FIXED_HEIGHT,\s*fixedHeight\)/.test(set))
}

// 3. GalleryCard: reactive read + the two structural layouts + the no-crop invariant.
{
  const c = src('shared/src/main/ets/components/GalleryCard.ets')
  ok('GalleryCard reads the list-mode holder reactively', /connectListMode\(\)/.test(c) && /this\.listMode\.fixedHeight/.test(c))

  // FIXED → pin the row to eros_fe kFixedHeight (min==max) AND clip the tag middle so meta is foot-anchored.
  ok(
    'FIXED pins the card to exactly LIST_CARD_FIXED_HEIGHT (min==max)',
    /fixedHeight\s*\?\s*\{\s*minHeight:\s*ThemeConstants\.LIST_CARD_FIXED_HEIGHT,\s*maxHeight:\s*ThemeConstants\.LIST_CARD_FIXED_HEIGHT/.test(c),
  )
  ok(
    'FIXED clips the tag block in a flexible (layoutWeight) container',
    /this\.listMode\.fixedHeight\)\s*\{[\s\S]*?layoutWeight\(1\)[\s\S]*?\.clip\(true\)/.test(c),
  )
  // ADAPTIVE → responsive floor only (minHeight, NO maxHeight) so the row grows; tags float between two springs.
  ok(
    'ADAPTIVE floors at adaptiveMinHeight with NO maxHeight (row grows)',
    /:\s*\{\s*minHeight:\s*this\.adaptiveMinHeight\(\)\s*\}/.test(c),
  )
  ok(
    'ADAPTIVE centers tags between two Blank springs',
    /\}\s*else\s*\{\s*Blank\(\)\s*this\.tagChips\(\)\s*Blank\(\)/.test(c),
  )
  // The single tag renderer is shared by both modes (no duplicated/diverging chip logic).
  ok('one shared tagChips() builder feeds both modes', /@Builder\s+tagChips\(\)/.test(c))
  // NO cover stretch/crop regression: list card stays Contain-over-grey (cover-presentation fix preserved).
  ok('list cover keeps containFit:true (no Cover side-crop / stretch) in both modes', /containFit:\s*true/.test(c))
  ok('list cover is height-stretched to the resolved row height', /stretchHeight:\s*true/.test(c))
}

// 4. Settings page exposes the toggle, wired to the single writer (an OPTIONAL setting, not forced).
{
  const p = src('feature/settings/src/main/ets/pages/SettingsPage.ets')
  ok('Settings row uses the settings_list_fixed_height label', /settings_list_fixed_height/.test(p))
  ok('Settings toggle reflects the current fixedHeight', /checked:\s*this\.listMode\.fixedHeight/.test(p))
  ok('Settings toggle routes through ListModeSettings.setFixedHeight', /ListModeSettings\.setFixedHeight\(/.test(p))
}

// 5. i18n: the toggle label exists and is non-empty in every locale (parity is enforced separately).
{
  for (const loc of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
    const json = JSON.parse(src(`entry/src/main/resources/${loc}/element/string.json`))
    const entry = json.string.find((e) => e.name === 'settings_list_fixed_height')
    ok(`${loc}: settings_list_fixed_height present and non-empty`, entry && entry.value.trim().length > 0)
  }
}

console.log(`✓ list height mode contract: ${passed} assertions passed`)

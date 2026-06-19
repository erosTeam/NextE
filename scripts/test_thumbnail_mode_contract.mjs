#!/usr/bin/env node
/**
 * Contract: detail-page preview semantics (eros_fe ThumbTile) must not collapse again. b5791a9 had
 * flattened the detail preview to horizontal-only; this locks the restored three-mode behavior +
 * the persisted toggles + the always-reachable all-thumbnails entry.
 *
 * Invariants:
 *   • ThumbnailModeState: V2 holder, BOTH toggles default FALSE (out-of-box = GRID, not horizontal/hidden);
 *   • ThumbnailModeSettings: restore + the two setters (Preferences single writer), registered in
 *     SettingsBootstrap + exported from the shared barrel + keyed in StorageKeys;
 *   • GalleryPreviewGrid dispatches three modes (hidden / horizontal / grid-default) and the
 *     all-thumbnails entry (onMore) is reachable in EVERY mode;
 *   • GalleryDetailPage passes both toggles into the preview component;
 *   • LayoutSettingsPage exposes both as switch rows wired to the setters;
 *   • the AllThumbnails route stays registered + pushed (functional).
 *
 * Run: node scripts/test_thumbnail_mode_contract.mjs   (exit 1 on any failure)
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    failures++
    console.error(`✗ ${msg}`)
  }
}

// Extract a method/@Builder body by brace matching from a header match.
function block(src, headerRe) {
  const m = headerRe.exec(src)
  if (!m) return ''
  let i = m.index + m[0].length
  let depth = 1
  while (i < src.length && depth > 0) {
    const ch = src[i]
    if (ch === '{') depth++
    else if (ch === '}') depth--
    i++
  }
  return src.slice(m.index, i)
}

// 1. State holder: V2, both defaults FALSE (grid default), 'v2:thumbnailMode' connect.
const state = read('shared/src/main/ets/state/ThumbnailModeState.ets')
ok(/@ObservedV2/.test(state), 'ThumbnailModeState is @ObservedV2')
ok(/@Trace\s+hideGalleryThumbnails:\s*boolean\s*=\s*false/.test(state), 'hideGalleryThumbnails defaults false')
ok(/@Trace\s+horizontalThumbnails:\s*boolean\s*=\s*false/.test(state), 'horizontalThumbnails defaults false (default = GRID)')
ok(/connectThumbnailMode/.test(state) && /'v2:thumbnailMode'/.test(state), 'connectThumbnailMode wires the v2:thumbnailMode holder')
ok(!/@(State|Prop|Link|Observed|Provide|Consume|StorageLink)\b/.test(state), 'ThumbnailModeState uses no V1 decorators')

// 2. Settings persistence: restore + both setters.
const settings = read('shared/src/main/ets/settings/ThumbnailModeSettings.ets')
ok(/static async restore\(/.test(settings), 'ThumbnailModeSettings.restore present')
ok(/setHideGalleryThumbnails\(/.test(settings), 'setHideGalleryThumbnails present')
ok(/setHorizontalThumbnails\(/.test(settings), 'setHorizontalThumbnails present')
ok(/flushSync\(\)/.test(settings), 'ThumbnailModeSettings flushes to the preferences store')

// 3. Keys + bootstrap + barrel.
const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
ok(/HIDE_GALLERY_THUMBNAILS/.test(keys) && /HORIZONTAL_THUMBNAILS/.test(keys), 'StorageKeys define both thumbnail keys')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
ok(/ThumbnailModeSettings\.restore\(context\)/.test(bootstrap), 'SettingsBootstrap restores ThumbnailModeSettings at startup')
const barrel = read('shared/src/main/ets/Index.ets')
ok(/connectThumbnailMode/.test(barrel) && /ThumbnailModeSettings/.test(barrel), 'shared barrel exports the thumbnail state + settings')

// 4. Preview component: three modes + all-thumbnails entry in every mode.
const preview = read('feature/gallery/src/main/ets/components/GalleryPreviewGrid.ets')
ok(/@Param\s+horizontal:\s*boolean/.test(preview), 'GalleryPreviewGrid has a horizontal param')
ok(/@Param\s+hidden:\s*boolean/.test(preview), 'GalleryPreviewGrid has a hidden param')
const buildBody = block(preview, /build\(\)\s*\{/)
ok(/if \(this\.hidden\)/.test(buildBody), 'build dispatches the hidden mode')
ok(/else if \(this\.horizontal\)/.test(buildBody), 'build dispatches the horizontal mode')
ok(/this\.gridPeek\(\)/.test(buildBody), 'build renders the grid peek (default mode)')
// All-thumbnails entry (onMore) reachable in all three modes:
const moreBtn = block(preview, /moreButton\(\)\s*\{/)
ok(/this\.onMore\(\)/.test(moreBtn), 'moreButton navigates to all-thumbnails (grid + hidden entry)')
const header = block(preview, /sectionHeader\(entry: boolean\)\s*\{/)
ok(/entry/.test(header) && /this\.onMore\(\)/.test(header), 'horizontal-mode sectionHeader(entry) navigates to all-thumbnails')
// hidden branch and grid branch both render moreButton; horizontal branch renders sectionHeader(true).
ok(/this\.hidden\)[\s\S]*?this\.moreButton\(\)/.test(buildBody), 'hidden mode offers the more-previews entry')
ok(/this\.horizontal\)[\s\S]*?this\.sectionHeader\(true\)/.test(buildBody), 'horizontal mode offers the tappable header entry')
ok(/else \{[\s\S]*?this\.moreButton\(\)/.test(buildBody), 'grid mode offers the more-previews entry (button below)')

// 4b. The preview card HEADER is a valid, AFFORDANCED all-thumbnails entry in EVERY mode (not just
// horizontal): a user can tap the header to open all-thumbnails without scrolling to the bottom button.
// (User: "为什么不能点击缩略图卡片头部进入缩略图页？" — GRID/HIDDEN used to pass sectionHeader(false).)
ok(!/this\.sectionHeader\(false\)/.test(buildBody), 'no mode leaves the header a non-entry (sectionHeader(false))')
ok((buildBody.match(/this\.sectionHeader\(true\)/g) || []).length >= 3, 'all three modes pass sectionHeader(true) — header is a tappable entry everywhere')
ok(/this\.hidden\)[\s\S]*?this\.sectionHeader\(true\)/.test(buildBody), 'hidden mode header is a tappable all-thumbnails entry')
ok(/else \{[\s\S]*?this\.sectionHeader\(true\)/.test(buildBody), 'grid mode header is a tappable all-thumbnails entry')
// The entry header must show a VISIBLE 查看全部 affordance (no invisible/hidden tap target) and navigate.
ok(/if \(entry\)[\s\S]*?detail_view_all/.test(header), 'entry header shows the visible 查看全部 affordance (no invisible tap target)')
ok(/if \(entry\)[\s\S]*?this\.onMore\(\)/.test(header), 'tapping the entry header navigates to all-thumbnails (onMore)')

// 5. Detail page passes both toggles into the preview component.
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
ok(/connectThumbnailMode\(\)/.test(detail), 'GalleryDetailPage connects the thumbnail mode')
ok(/horizontal:\s*this\.thumbMode\.horizontalThumbnails/.test(detail), 'detail passes horizontal toggle')
ok(/hidden:\s*this\.thumbMode\.hideGalleryThumbnails/.test(detail), 'detail passes hidden toggle')

// 6. Layout settings page: two switch rows wired to the setters.
const layoutSettingsPage = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')
ok(/settings_hide_gallery_thumbnails/.test(layoutSettingsPage) && /setHideGalleryThumbnails\(/.test(layoutSettingsPage), 'layout settings page has the hide-thumbnails switch')
ok(/settings_horizontal_thumbnails/.test(layoutSettingsPage) && /setHorizontalThumbnails\(/.test(layoutSettingsPage), 'layout settings page has the horizontal-thumbnails switch')
ok((layoutSettingsPage.match(/hasSwitch:\s*true/g) || []).length >= 2, 'both thumbnail rows are real switches')

// 7. AllThumbnails route stays functional.
const navShell = read('entry/src/main/ets/pages/Index.ets')
ok(/'AllThumbnails'/.test(navShell) && /GalleryAllThumbnailsPage\(\)/.test(navShell), 'AllThumbnails route registered in the nav shell')
ok(/pushPathByName\(\s*'AllThumbnails'/.test(detail), 'detail page pushes the AllThumbnails route')

// 8. i18n keys present in every locale.
for (const loc of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const s = read(`entry/src/main/resources/${loc}/element/string.json`)
  for (const k of ['settings_hide_gallery_thumbnails', 'settings_horizontal_thumbnails', 'detail_more_previews', 'detail_no_more_previews']) {
    ok(s.includes(`"${k}"`), `${loc} string.json has ${k}`)
  }
}

if (failures === 0) {
  console.log('✓ thumbnail mode contract: default grid + optional horizontal/hidden, all-thumbnails entry reachable in every mode, toggles persisted')
  process.exit(0)
}
console.error(`✗ thumbnail mode contract: ${failures} failure(s)`)
process.exit(1)

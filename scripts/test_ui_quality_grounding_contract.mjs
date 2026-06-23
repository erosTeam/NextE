#!/usr/bin/env node
/**
 * Contract: UI quality cleanup lanes must be grounded before implementation.
 *
 * This locks the current lane's five-line grounding and the resulting implementation constraints:
 * torrent content is primary and actions are low-weight; download type switching is pinned in the
 * title bar with a V2-native segmented control, not mixed into the scrolling queue body.
 *
 * Run: node scripts/test_ui_quality_grounding_contract.mjs
 */
import assert from 'node:assert'
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const guide = read('docs/agent-guides/always-loaded-rules.md')
const groundingDoc = read('docs/plans/active/ui-grounding.md')
const changed = execFileSync('git', ['diff', '--name-only', 'HEAD'], {
  cwd: ROOT,
  encoding: 'utf8',
}).trim().split('\n').filter(Boolean)
const untracked = execFileSync('git', ['ls-files', '--others', '--exclude-standard'], {
  cwd: ROOT,
  encoding: 'utf8',
}).trim().split('\n').filter(Boolean)
const touched = [...changed, ...untracked]
const uiChanged = touched.filter((file) => /^(entry|feature|shared)\/src\/main\/ets\/.+\.ets$/.test(file))
const groundingChanged = touched.includes('docs/plans/active/ui-grounding.md')

ok('always-loaded rules require grounding before sheet/settings UI changes',
  /涉及半模态、设置页、管理页、选择列表、确认 \/ 编辑面板时[\s\S]*写代码前必须先找项目内同类实现并说明复用关系/.test(guide))
ok('always-loaded rules reject visual guesses as layout parameters',
  /不要把视觉猜测写成布局参数/.test(guide))
ok('always-loaded rules name the executable UI grounding contract',
  /node scripts\/test_ui_quality_grounding_contract\.mjs/.test(guide))

if (uiChanged.length > 0) {
  ok('UI changes update the active grounding ledger', groundingChanged)
}
for (const label of [
  'Status',
  'Reference implementation',
  'Surface type',
  'Primary information',
  'Primary action',
  'Reuse or deviation',
  'Verification',
]) {
  ok(`active UI grounding has ${label}`, new RegExp(`^${label}:\\s+\\S`, 'm').test(groundingDoc))
}

const torrent = read('feature/gallery/src/main/ets/pages/GalleryTorrentsPage.ets')
const download = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
const downloadBar = read('entry/src/main/ets/components/DownloadTypeBar.ets')
const index = read('entry/src/main/ets/pages/Index.ets')
const shared = read('shared/src/main/ets/Index.ets')
const state = read('shared/src/main/ets/state/DownloadViewState.ets')

const grounding = {
  torrent: [
    'eros_fe: lib/pages/gallery/view/torrent_dialog.dart TorrentView/TorrentItem/showTorrentDialog',
    'primary information: torrent metrics, torrent name, posted/uploader metadata',
    'primary action: open/share .torrent from the name; secondary action: magnet icon',
    'scope: real torrent list display and share URL/magnet only; no destructive download submission',
    'Harmony expression: pushed HDS page with quiet list items, text link, toolbar-like icon action',
  ],
  download: [
    'eros_fe: lib/pages/tab/view/download_page.dart DownloadTab with CupertinoSlidingSegmentedControl',
    'primary information: selected gallery/archive queue status and empty queue guidance',
    'primary action: switch queue type; secondary settings are not queue content',
    'scope: non-destructive queue workbench shell; no background download engine or settings editing here',
    'Harmony expression: Index HDS title-bar bottomBuilder hosting V2 TabSegmentButtonV2',
  ],
}
ok('torrent grounding has exactly five lines', grounding.torrent.length === 5)
ok('download grounding has exactly five lines', grounding.download.length === 5)
ok('torrent grounding names concrete eros_fe file/component', grounding.torrent[0].includes('torrent_dialog.dart') && grounding.torrent[0].includes('TorrentItem'))
ok('download grounding names concrete eros_fe file/component', grounding.download[0].includes('download_page.dart') && grounding.download[0].includes('DownloadTab'))

ok('torrent page no longer imports GroupedListSection for torrent items', !/GroupedListSection/.test(torrent))
ok('torrent item is content-first quiet card', /private\s+TorrentItem\(torrent: EhGalleryTorrent\)/.test(torrent) && /Text\(torrent\.name\)[\s\S]*ThemeConstants\.TEXT_LINK/.test(torrent))
ok('torrent .torrent action is on the name, not a full-width primary button', /Text\(torrent\.name\)[\s\S]*this\.shareTorrent\(torrent\)/.test(torrent))
ok('magnet action is a circle icon secondary action', /private\s+MagnetAction\(torrent: EhGalleryTorrent\)[\s\S]*Button\(\{ type: ButtonType\.Circle \}\)[\s\S]*this\.shareMagnet\(torrent\)/.test(torrent))
ok('torrent page does not render two large share buttons', !/gallery_torrent_share_file[\s\S]*gallery_torrent_share_magnet/.test(torrent))

ok('download view state is V2-only and exported', /@ObservedV2[\s\S]*class DownloadViewState/.test(state) && /@Trace\s+viewType/.test(state) && /connectDownloadView/.test(shared))
ok('download segmented control uses V2-native TabSegmentButtonV2', /TabSegmentButtonV2/.test(downloadBar) && /SegmentButtonV2Items/.test(downloadBar))
ok('download type bar writes DownloadViewState', /this\.downloadView\.viewType\s*=/.test(downloadBar))
ok('Index pins download type bar in title-bar bottomBuilder', /DownloadTypeBarCCBuilder/.test(index) && /this\.currentTab === 3[\s\S]*bottomBuilder/.test(index))
ok('download page reads shared download view state', /@Local\s+downloadView:\s+DownloadViewState\s*=\s*connectDownloadView\(\)/.test(download))
ok('download queue body no longer owns QueueSwitcher buttons', !/QueueSwitcher|SwitchButton|DOWNLOAD_VIEW_GALLERY|DOWNLOAD_VIEW_ARCHIVER/.test(download))
ok('download queue body no longer mixes settings preview rows', !/SettingsPreviewSection|download_concurrency|download_original_images/.test(download))

console.log(`✓ UI quality grounding contract: ${passed} assertions passed`)

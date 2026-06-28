#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const src = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const ok = (cond, msg) => {
  if (!cond) {
    throw new Error(msg)
  }
}
const eq = (actual, expected, msg) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${msg}\nexpected=${JSON.stringify(expected)}\nactual=${JSON.stringify(actual)}`)
  }
}

const state = src('shared/src/main/ets/state/LocalBlockState.ets')
const settings = src('shared/src/main/ets/settings/LocalBlockSettings.ets')
const service = src('shared/src/main/ets/services/LocalBlockService.ets')
const api = src('shared/src/main/ets/network/EhApiService.ets')
const detail = src('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const comments = src('feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets')
const settingsPage = src('feature/settings/src/main/ets/pages/SettingsPage.ets')
const ehSettings = src('feature/settings/src/main/ets/pages/EhSettingsPage.ets')
const searchSettings = src('feature/settings/src/main/ets/pages/SearchSettingsPage.ets')
const localPage = src('feature/settings/src/main/ets/pages/LocalBlockSettingsPage.ets')
const favVm = src('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
const bootstrap = src('shared/src/main/ets/settings/SettingsBootstrap.ets')
const keys = src('shared/src/main/ets/constants/StorageKeys.ets')
const entry = src('entry/src/main/ets/pages/Index.ets')
const uiGrounding = src('docs/plans/active/ui-grounding.md')

ok(state.includes('LOCAL_BLOCK_TYPE_TITLE') &&
  state.includes('LOCAL_BLOCK_TYPE_UPLOADER') &&
  state.includes('LOCAL_BLOCK_TYPE_COMMENTATOR') &&
  state.includes('LOCAL_BLOCK_TYPE_COMMENT'),
'state exposes the four eros_fe local block buckets')
ok(state.includes('@ObservedV2') && state.includes('@Trace rules: LocalBlockRule[] = []'),
  'local block state is State Management V2 only')
ok(keys.includes("LOCAL_BLOCK_RULES: string = 'localBlock.rules'"), 'storage key exists')
ok(bootstrap.includes('await LocalBlockSettings.restore(context)'), 'settings bootstrap restores local block rules')
ok(settings.includes('filterCommentsByScore') && settings.includes('scoreFilteringThreshold'),
  'score filter settings persist with rules')
ok(settings.includes('LocalBlockRepository.load(context)') &&
  settings.includes('LocalBlockRepository.replaceAll(context, LocalBlockSettings.current())') &&
  !settings.includes('store.putSync(StorageKeys.LOCAL_BLOCK_RULES'),
  'local block rules persist through RDB, not Preferences JSON')
ok(settings.includes('migrateLegacyPreferences') &&
  settings.includes("store.getSync(StorageKeys.LOCAL_BLOCK_RULES, '')") &&
  settings.includes('store.deleteSync(StorageKeys.LOCAL_BLOCK_RULES)'),
  'legacy local block Preferences rows are migrated once')
ok(settings.includes('snapshotEquals(LocalBlockSettings.current(), next)') &&
  settings.includes('local_block_apply_unchanged') &&
  settings.includes('local_block_version'),
  'unchanged local block restore/sync does not bump version and reload retained lists')
{
  const store = src('shared/src/main/ets/storage/LocalDataStore.ets')
  const repo = src('shared/src/main/ets/storage/LocalBlockRepository.ets')
  ok(store.includes('CREATE TABLE IF NOT EXISTS local_block_settings') &&
    store.includes('CREATE TABLE IF NOT EXISTS local_block_rules') &&
    store.includes('position_index INTEGER'),
  'local block RDB tables exist')
  ok(repo.includes('ORDER BY position_index ASC, rule_id ASC') &&
    repo.includes('UPDATE local_block_settings SET deleted_at = ?, updated_at = ?') &&
    repo.includes('ON CONFLICT(scope_key, rule_id) DO UPDATE'),
  'local block repository preserves order and tombstones scoped rows')
  const backupTypes = src('shared/src/main/ets/backup/BackupTypes.ets')
  const backupAdapter = src('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
  ok(backupTypes.includes('localBlock: BackupLocalBlockSection') &&
    backupAdapter.includes('LocalBlockSettings.exportForBackup(context)') &&
    backupAdapter.includes('LocalBlockSettings.restoreBackup(context, localBlock)'),
  'backup localData includes local block rules')
}
ok(settings.includes('commentDisplayMode') &&
  settings.includes('setCommentDisplayMode') &&
  service.includes('shouldCollapseBlockedComments'),
  'blocked comment display mode persists and is exposed to comment cards')
ok(service.includes('replace(/\\(\\?i\\)/g, \'\')') &&
  service.includes("new RegExp(ruleText, caseInsensitive ? 'i' : '').test(normalizedText)") &&
  service.includes('normalizedText.toLowerCase().indexOf(ruleText.toLowerCase()) >= 0'),
'matching supports FE-style (?i) stripping, regex, and contains')
ok(api.includes('filterLocalBlocked') &&
  api.includes('return this.filterLocalBlocked(this.filterHidden') &&
  api.includes('return this.filterLocalBlocked(list)'),
'gallery, toplist, watched, and favorites list results pass through local block filtering')
ok(favVm.includes('LocalBlockService.filterGalleryList(cached.copy())') &&
  favVm.includes('!LocalBlockService.isGalleryBlocked(g)'),
'favorites cached/local rows also pass through local block filtering')
ok(detail.includes('visiblePreviewComments(): EhGalleryComment[]') &&
  detail.includes('comments: this.visiblePreviewComments()') &&
  detail.includes('referenceComments: this.vm.comments'),
'detail preview filters display comments while retaining raw reference comments')
ok(comments.includes('LocalBlockService.filterComments(source)') &&
  comments.includes('referenceComments: this.comments'),
'full comments page filters display comments while retaining raw reference comments')
ok(localPage.includes('local_block_comment_display') &&
  localPage.includes('LOCAL_BLOCK_COMMENT_DISPLAY_HIDE') &&
  localPage.includes('LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE') &&
  localPage.includes('if (this.ruleCount(type) > 0)'),
  'settings page exposes hide/collapse display choices and hides empty rule-type sections')
ok(src('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets').includes('CollapsedBlockedComment') &&
  /animateTo\(\s*\{ duration: ThemeConstants\.ANIM_DURATION/.test(src('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets')) &&
  src('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets').includes('LocalBlockService.isCommentBlocked(c)') &&
  src('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets').includes('Row({ space: 0 })') &&
  src('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets').includes('.width(24)'),
  'comment cards render blocked comments as animated single-line collapsible cards when configured')
ok(!settingsPage.includes('local_block_title') &&
  ehSettings.includes("this.stack.pushPathByName('LocalBlockSettings', null)") &&
  ehSettings.includes('localBlock.rules.length') &&
  !searchSettings.includes("this.stack.pushPathByName('LocalBlockSettings', null)") &&
  localPage.includes('bindSheet($$this.ruleSheetShown'),
'EH settings entry and rule sheet are wired; loose options stay off settings root')
ok(entry.includes("name === 'LocalBlockSettings'") && uiGrounding.includes('## Active: local block rules'),
'route and UI grounding are recorded')

const normalizeType = (type) => ['title', 'uploader', 'commentator', 'comment'].includes(type) ? type : 'title'
const matchText = (rules, text, type) => {
  if (!text) return false
  for (const rule of rules) {
    if (normalizeType(rule.blockType) !== type || rule.enabled === false) continue
    const ruleText = String(rule.ruleText || '').trim().replace(/\(\?i\)/g, '')
    if (!ruleText) continue
    if (rule.enableRegex) {
      try {
        if (new RegExp(ruleText).test(text)) return true
      } catch {
        continue
      }
    } else if (text.includes(ruleText)) {
      return true
    }
  }
  return false
}
const galleryBlocked = (rules, g) =>
  matchText(rules, g.englishTitle, 'title') ||
  matchText(rules, g.japaneseTitle, 'title') ||
  matchText(rules, g.uploader, 'uploader')
const commentBlocked = (rules, scoreEnabled, threshold, c) => {
  if (scoreEnabled && c.score.trim()) {
    const score = Number.parseInt(c.score.trim(), 10)
    if (!Number.isNaN(score) && score <= threshold) return true
  }
  return matchText(rules, c.contentText, 'comment') || matchText(rules, c.author, 'commentator')
}

const rules = [
  { blockType: 'title', ruleText: 'Shapeshifter', enabled: true, enableRegex: false },
  { blockType: 'title', ruleText: 'disabled-title', enabled: false, enableRegex: false },
  { blockType: 'uploader', ruleText: '^BadUploader$', enabled: true, enableRegex: true },
  { blockType: 'commentator', ruleText: 'NoisyUser', enabled: true, enableRegex: false },
  { blockType: 'comment', ruleText: 'spoiler keyword', enabled: true, enableRegex: false },
  { blockType: 'comment', ruleText: '(?i)BadRegexWord', enabled: true, enableRegex: true },
  { blockType: 'comment', ruleText: '[', enabled: true, enableRegex: true },
]

const galleries = [
  { gid: '1', englishTitle: '[LemonFont] Shapeshifter Parts 1, 2, & 3', japaneseTitle: '', uploader: 'NHOrous' },
  { gid: '2', englishTitle: 'Plain gallery', japaneseTitle: 'disabled-title survives because rule is off', uploader: 'GoodUploader' },
  { gid: '3', englishTitle: 'Uploader hit', japaneseTitle: '', uploader: 'BadUploader' },
  { gid: '4', englishTitle: 'Clean gallery', japaneseTitle: '', uploader: 'SomeoneElse' },
]
const visibleGids = galleries.filter((g) => !galleryBlocked(rules, g)).map((g) => g.gid)
eq(visibleGids, ['2', '4'], 'gallery title/uploader block filters only matched rows')

const beforeComments = [
  { commentId: '10', author: 'ReaderA', contentText: 'normal useful comment', score: '+2' },
  { commentId: '11', author: 'NoisyUser', contentText: 'author should hide', score: '+4' },
  { commentId: '12', author: 'ReaderB', contentText: 'contains spoiler keyword here', score: '+3' },
  { commentId: '13', author: 'ReaderC', contentText: 'BadRegexWord should hide after (?i) strip', score: '+5' },
  { commentId: '14', author: 'ReaderD', contentText: 'low score only', score: '-22' },
  { commentId: '15', author: 'ReaderE', contentText: 'invalid regex rule must not hide me', score: '+1' },
]
const afterComments = beforeComments
  .filter((c) => !commentBlocked(rules, true, -20, c))
  .map((c) => c.commentId)
eq(afterComments, ['10', '15'], 'comment keyword/author/score/regex filters produce expected before-after result')

const scoreOff = beforeComments
  .filter((c) => !commentBlocked(rules, false, -20, c))
  .map((c) => c.commentId)
eq(scoreOff, ['10', '14', '15'], 'low-score comment remains visible when score filter is off')

const displayComments = (mode, comments) =>
  mode === 'collapse' ? comments : comments.filter((c) => !commentBlocked(rules, true, -20, c))
eq(displayComments('hide', beforeComments).map((c) => c.commentId), ['10', '15'],
  'hide mode removes locally-blocked comments')
eq(displayComments('collapse', beforeComments).map((c) => c.commentId), ['10', '11', '12', '13', '14', '15'],
  'collapse mode keeps locally-blocked comments available for collapsed rendering')

console.log('✓ local block contract: FE-style rule types, settings UI wiring, and sample before/after filtering locked')

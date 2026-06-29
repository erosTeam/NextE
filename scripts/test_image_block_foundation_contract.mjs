#!/usr/bin/env node
import { readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { dirname } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

function read(path) {
  return readFileSync(join(ROOT, path), 'utf8')
}

function exists(path) {
  statSync(join(ROOT, path))
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message)
  }
}

function hexValue(char) {
  const code = char.charCodeAt(0)
  if (code >= 48 && code <= 57) return code - 48
  if (code >= 97 && code <= 102) return code - 87
  return -1
}

function popcountNibble(value) {
  let out = 0
  let v = value
  while (v > 0) {
    out += v & 1
    v >>= 1
  }
  return out
}

function hamming(left, right) {
  assert(/^[0-9a-f]{16}$/.test(left), 'left hash must be lowercase hex64')
  assert(/^[0-9a-f]{16}$/.test(right), 'right hash must be lowercase hex64')
  let out = 0
  for (let i = 0; i < 16; i++) {
    out += popcountNibble(hexValue(left[i]) ^ hexValue(right[i]))
  }
  return out
}

function parseSampleFeed() {
  const text = JSON.stringify({
    schema: 1,
    kind: 'nexte-image-block-feed',
    id: 'zh-scanlator-ads',
    title: 'Chinese scanlator ads',
    algorithm: 'dct64-v1',
    defaultThreshold: 8,
    updatedAt: 123,
    items: [
      {
        hash: '0123456789abcdef',
        threshold: 8,
        label: 'scanlator-ad',
        scope: 'whole',
      },
    ],
  })
  const feed = JSON.parse(text)
  assert(feed.schema === 1, 'feed schema must be 1')
  assert(feed.kind === 'nexte-image-block-feed', 'feed kind must match subscription contract')
  assert(feed.algorithm === 'dct64-v1', 'feed algorithm must be dct64-v1')
  assert(feed.items.length === 1, 'sample feed must include one item')
  assert(/^[0-9a-f]{16}$/.test(feed.items[0].hash), 'feed hash must be 16 lowercase hex chars')
  assert(feed.items[0].threshold >= 0 && feed.items[0].threshold <= 12, 'threshold must stay in 0..12')
  assert(feed.items[0].scope === 'whole', 'first slice supports only whole-image rules')
}

const files = [
  'shared/src/main/ets/model/ImageBlockRule.ets',
  'shared/src/main/ets/services/PHashService.ets',
  'shared/src/main/ets/services/ImageBlockFeedParser.ets',
  'shared/src/main/ets/services/ImageBlockService.ets',
  'shared/src/main/ets/services/ImageBlockContributionService.ets',
  'shared/src/main/ets/services/ImageBlockRuntimeService.ets',
  'shared/src/main/ets/services/ImageBlockSubscriptionService.ets',
  'shared/src/main/ets/storage/ImageBlockRepository.ets',
  'feature/settings/src/main/ets/pages/ImageBlockSettingsPage.ets',
  'docs/fixtures/image-block-public-samples.json',
  'docs/plans/active/image-block-community-rules.md',
  'shared/src/main/ets/model/RouteParams.ets',
  'shared/src/main/ets/constants/InternalQaRoutes.ets',
  'entry/src/main/ets/entryability/EntryAbility.ets',
  'entry/src/main/module.json5',
  'scripts/qa_image_block_seeded_reader.mjs',
  'scripts/test_image_block_sample_contract.mjs',
]
for (const file of files) {
  exists(file)
}

const index = read('shared/src/main/ets/Index.ets')
for (const token of [
  'IMAGE_BLOCK_DEFAULT_MANIFEST_URL',
  'ImageBlockFeedParser',
  'ImageBlockService',
  'ImageBlockContributionBatch',
  'ImageBlockContributionService',
  'ImageBlockContributionIssuePackage',
  'ImageBlockRuntimeService',
  'ImageBlockSubscriptionService',
  'PHashService',
  'ImageBlockRepository',
]) {
  assert(index.includes(token), `shared barrel must export ${token}`)
}

const model = read('shared/src/main/ets/model/ImageBlockRule.ets')
assert(
  model.includes('https://raw.githubusercontent.com/erosTeam/nexte-image-block-rules/main/dist/manifest.json'),
  'default manifest URL must point at the erosTeam rules repository',
)
assert(model.includes('IMAGE_BLOCK_MAX_THRESHOLD: number = 12'), 'max threshold must remain 12')

const phash = read('shared/src/main/ets/services/PHashService.ets')
assert(phash.includes('hashImageFileDct64'), 'PHashService must expose image-file dct64 hashing')
assert(phash.includes('@Concurrent'), 'image-file pHash must run off the UI thread')
assert(phash.includes('image.createImageSource(filePath)'), 'image-file pHash must decode from local file path')
assert(phash.includes('desiredSize: { width: sampleSize, height: sampleSize }'), 'pHash decode must downsample')
assert(phash.includes('readPixelsToBuffer'), 'pHash must read PixelMap pixels')
assert(phash.includes('coeffs.slice(1)'), 'dct64-v1 median must exclude the DC coefficient')

const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
assert(store.includes('LOCAL_DATA_SCHEMA_VERSION: number = 13'), 'LocalDataStore schema must be 13')
for (const table of [
  'image_block_subscriptions',
  'image_block_rules',
  'image_block_whitelist',
  'image_block_hash_cache',
]) {
  assert(store.includes(table), `LocalDataStore must create ${table}`)
}

const repository = read('shared/src/main/ets/storage/ImageBlockRepository.ets')
assert(repository.includes('replaceSubscription'), 'repository must replace subscription feeds')
assert(repository.includes('loadEnabledRules'), 'repository must load enabled rules')
assert(repository.includes('replaceWhitelist'), 'repository must support whitelist replacement')
assert(repository.includes('upsertWhitelistHash'), 'repository must support adding one whitelist hash')
assert(repository.includes('removeWhitelistHash'), 'repository must support removing one whitelist hash')
assert(repository.includes('SQL_TOMBSTONE_ONE_WHITELIST'), 'single whitelist removal must tombstone only one hash')
assert(repository.includes('loadCachedFileHash'), 'repository must load cached file hashes')
assert(repository.includes('upsertFileHash'), 'repository must cache file hashes')
assert(repository.includes('IMAGE_BLOCK_SOURCE_SUBSCRIPTION'), 'subscription rules must be source-tagged')
assert(repository.includes('setSubscriptionEnabled'), 'repository must expose subscription provider enable toggles')
assert(repository.includes('loadSubscriptions'), 'repository must expose subscription provider list loading')
assert(repository.includes('loadLocalRuleCount'), 'repository must expose local image-block rule count')
assert(repository.includes('loadLocalRules'), 'repository must expose local image-block rule list loading')
assert(repository.includes('removeLocalRule'), 'repository must expose local image-block rule deletion')
assert(repository.includes('source_url'), 'repository must persist review source URLs for local rules')
assert(repository.includes('source_page'), 'repository must persist review source pages for local rules')
assert(repository.includes('COALESCE(s.enabled, 0) > 0'), 'disabled subscription providers must not match rules')
assert(repository.includes('feed.enabled ? 1 : 0'), 'new subscription persistence must seed provider enabled state')
assert(repository.includes('enabled = image_block_subscriptions.enabled'), 'feed refresh must preserve user-disabled providers')

const runtime = read('shared/src/main/ets/services/ImageBlockRuntimeService.ets')
assert(runtime.includes('decisionForFile'), 'runtime service must expose file decisions')
assert(runtime.includes('addLocalRuleForFile'), 'runtime service must support local rule creation from a file')
assert(runtime.includes('addWhitelistForFile'), 'runtime service must support false-positive whitelist creation from a file')
assert(runtime.includes('fileIo.statSync(filePath).size'), 'runtime service must fingerprint file bytes')
assert(runtime.includes('if (rules.length === 0)'), 'runtime service must skip hashing when no rules are enabled')
assert(
  runtime.indexOf('loadEnabledRules(context)') < runtime.indexOf('hashForFile(context, path, bytes)'),
  'runtime service must load enabled rules before hashing reader files',
)
assert(runtime.includes('loadCachedFileHash'), 'runtime service must reuse cached pHash values')
assert(runtime.includes('hashImageFileDct64'), 'runtime service must hash uncached local files')
assert(runtime.includes('ImageBlockService.decisionForHash'), 'runtime service must return rule decisions')
assert(runtime.includes('upsertLocalRule'), 'runtime service must persist user-marked local rules')
assert(runtime.includes('upsertWhitelistHash'), 'runtime service must persist user-whitelisted file hashes')
assert(runtime.includes('sourceUrl: string ='), 'runtime service must accept manual rule source URLs')
assert(runtime.includes('sourcePage: number ='), 'runtime service must accept manual rule source pages')

const subscription = read('shared/src/main/ets/services/ImageBlockSubscriptionService.ets')
assert(subscription.includes('BackupChecksum.hashText'), 'subscription updater must verify feed sha256')
assert(subscription.includes('replaceSubscription'), 'subscription updater must store validated feeds')
assert(!subscription.includes('EhCookieStore'), 'rules subscription fetch must not send EH cookies')
assert(subscription.includes('https://'), 'rules subscription fetch must require HTTPS')

const imageBlockSettings = read('feature/settings/src/main/ets/pages/ImageBlockSettingsPage.ets')
assert(imageBlockSettings.includes('ImageBlockSubscriptionService.updateDefault'), 'settings page must refresh default community rules')
assert(imageBlockSettings.includes('ImageBlockRepository.loadSubscriptions'), 'settings page must load installed providers')
assert(imageBlockSettings.includes('ImageBlockRepository.setSubscriptionEnabled'), 'settings page must toggle provider enablement')
assert(imageBlockSettings.includes('localRuleCount'), 'settings page must show local rule count')
assert(imageBlockSettings.includes('ImageBlockRepository.loadLocalRules'), 'settings page must list local rules')
assert(imageBlockSettings.includes('ImageBlockRepository.removeLocalRule'), 'settings page must delete local rules')
assert(imageBlockSettings.includes('ImageBlockRepository.loadWhitelist'), 'settings page must list false-positive whitelist hashes')
assert(imageBlockSettings.includes('ImageBlockRepository.removeWhitelistHash'), 'settings page must delete false-positive whitelist hashes')
assert(imageBlockSettings.includes("import { pasteboard } from '@kit.BasicServicesKit'"), 'settings page must use the existing pasteboard text-copy pattern')
assert(imageBlockSettings.includes('ImageBlockContributionService'), 'settings page must expose assisted local-rule contribution drafts')
assert(imageBlockSettings.includes('buildSubmissionBatchFromRules'), 'settings contribution draft must reuse the sanitized batch helper')
assert(imageBlockSettings.includes('pasteboard.MIMETYPE_TEXT_PLAIN'), 'settings contribution draft must copy JSONL as plain text')
assert(imageBlockSettings.includes('contributionTotalCount'), 'settings page must show contribution ready count against total local rules')
assert(imageBlockSettings.includes('contributionReadyCount'), 'settings page must show submit-ready local-rule count')
assert(imageBlockSettings.includes('contributionSkippedCount'), 'settings page must expose skipped local-rule contribution count')
assert(imageBlockSettings.includes('contributionDraftTrailing'), 'settings contribution row must show ready/total instead of an unexplained count')
assert(imageBlockSettings.includes('contributionSkipReasonText'), 'settings contribution row must summarize skipped-rule reasons')
assert(imageBlockSettings.includes('image_block_contribution_draft'), 'settings page must include a contribution draft action row')
assert(imageBlockSettings.includes('image_block_contribution_empty'), 'settings page must report when no local rules are submit-ready')
assert(imageBlockSettings.includes('showAlertDialog'), 'local rule deletion must require confirmation')
assert(imageBlockSettings.includes('deletingLocalRuleId'), 'local rule deletion must guard duplicate taps')
assert(imageBlockSettings.includes('deletingWhitelistHash'), 'whitelist deletion must guard duplicate taps')
assert(imageBlockSettings.includes('this.reloadLocalRules()'), 'local rule deletion must refresh the visible local-rule list')
assert(imageBlockSettings.includes('this.reloadWhitelist()'), 'whitelist deletion must refresh the visible whitelist list')
assert(imageBlockSettings.includes('image_block_local_rule_deleted'), 'local rule deletion must show success feedback')
assert(imageBlockSettings.includes('image_block_whitelist_deleted'), 'whitelist deletion must show success feedback')
assert(imageBlockSettings.includes('localRuleTitle'), 'settings page must show readable local rule titles')
assert(imageBlockSettings.includes('image_block_whitelist_hash_title'), 'settings page must show readable whitelist row titles')
assert(imageBlockSettings.includes('sourceUrl'), 'settings page must surface local rule review source URLs')
assert(
  imageBlockSettings.includes('${feed.id}:${feed.count}:${feed.enabled'),
  'provider row identity must include count/enabled so refreshed feed subtitles repaint',
)
assert(imageBlockSettings.includes('SecondaryListScaffold'), 'settings page must reuse shared settings scaffold')
assert(!imageBlockSettings.match(/GitHub|pull request|OAuth|fork|create.*PR/i), 'settings page must not bundle PR submission')
assert(!imageBlockSettings.match(/Qr|QR|QRCode|qrCode|scanQr/i), 'settings page must not bundle QR blocking')

const ehSettings = read('feature/settings/src/main/ets/pages/EhSettingsPage.ets')
assert(ehSettings.includes("pushPathByName('ImageBlockSettings'"), 'EH settings must route to image block settings')
const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
assert(settingsIndex.includes('ImageBlockSettingsPage'), 'settings barrel must export image block settings page')
const entryIndex = read('entry/src/main/ets/pages/Index.ets')
assert(entryIndex.includes('ImageBlockSettingsPage'), 'entry shell must import image block settings page')
assert(entryIndex.includes("name === 'ImageBlockSettings'"), 'entry shell must register image block settings route')

const internalQaRoutes = read('shared/src/main/ets/constants/InternalQaRoutes.ets')
assert(
  internalQaRoutes.includes("IMAGE_BLOCK_SEED_URI: string = 'nexte://qa/image-block-seed'"),
  'internal QA routes must define a seeded image-block URI',
)
assert(
  internalQaRoutes.includes("IMAGE_BLOCK_SEED_READER_URI: string = 'nexte://qa/image-block-seed-reader'"),
  'internal QA routes must define a seeded image-block direct Reader URI',
)
assert(
  internalQaRoutes.includes("IMAGE_BLOCK_SUBSCRIPTION_READER_URI: string = 'nexte://qa/image-block-subscription-reader'"),
  'internal QA routes must define a seeded subscription image-block Reader URI',
)
assert(
  internalQaRoutes.includes("IMAGE_BLOCK_READER_OPEN_URI: string = 'nexte://qa/image-block-reader-open'"),
  'internal QA routes must define a non-mutating image-block Reader URI',
)
assert(
  internalQaRoutes.includes("IMAGE_BLOCK_MANUAL_READER_URI: string = 'nexte://qa/image-block-manual-reader'"),
  'internal QA routes must define a manual image-block direct Reader URI',
)
assert(
  internalQaRoutes.includes("IMAGE_BLOCK_SETTINGS_URI: string = 'nexte://qa/image-block-settings'"),
  'internal QA routes must define a seeded image-block settings URI',
)
assert(
  internalQaRoutes.includes("IMAGE_BLOCK_SETTINGS_OPEN_URI: string = 'nexte://qa/image-block-settings-open'"),
  'internal QA routes must define a non-seeding image-block settings URI',
)
assert(
  internalQaRoutes.includes("IMAGE_BLOCK_SETTINGS_EDGE_URI: string = 'nexte://qa/image-block-settings-edge'"),
  'internal QA routes must define a seeded image-block settings edge-case URI',
)
assert(
  internalQaRoutes.includes("IMAGE_BLOCK_SETTINGS_REFRESH_URI: string = 'nexte://qa/image-block-settings-refresh'"),
  'internal QA routes must define a reset image-block settings refresh URI',
)
const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets')
assert(entryAbility.includes('InternalQaRoutes.IMAGE_BLOCK_SEED_URI'), 'EntryAbility must accept the hidden image-block QA URI')
assert(entryAbility.includes('InternalQaRoutes.IMAGE_BLOCK_SEED_READER_URI'), 'EntryAbility must accept the hidden image-block direct Reader QA URI')
assert(entryAbility.includes('InternalQaRoutes.IMAGE_BLOCK_SUBSCRIPTION_READER_URI'), 'EntryAbility must accept the hidden image-block subscription Reader QA URI')
assert(entryAbility.includes('InternalQaRoutes.IMAGE_BLOCK_READER_OPEN_URI'), 'EntryAbility must accept the hidden non-mutating image-block Reader QA URI')
assert(entryAbility.includes('InternalQaRoutes.IMAGE_BLOCK_MANUAL_READER_URI'), 'EntryAbility must accept the hidden image-block manual Reader QA URI')
assert(entryAbility.includes('InternalQaRoutes.IMAGE_BLOCK_SETTINGS_URI'), 'EntryAbility must accept the hidden image-block settings QA URI')
assert(entryAbility.includes('InternalQaRoutes.IMAGE_BLOCK_SETTINGS_OPEN_URI'), 'EntryAbility must accept the hidden image-block settings-open QA URI')
assert(entryAbility.includes('InternalQaRoutes.IMAGE_BLOCK_SETTINGS_EDGE_URI'), 'EntryAbility must accept the hidden image-block settings edge-case QA URI')
assert(entryAbility.includes('InternalQaRoutes.IMAGE_BLOCK_SETTINGS_REFRESH_URI'), 'EntryAbility must accept the hidden image-block settings refresh QA URI')
const moduleJson = read('entry/src/main/module.json5')
assert(!moduleJson.includes('nexte://qa/image-block-seed'), 'hidden image-block QA URI must not be published in module.json5')
assert(!moduleJson.includes('nexte://qa/image-block-seed-reader'), 'hidden image-block direct Reader QA URI must not be published in module.json5')
assert(!moduleJson.includes('nexte://qa/image-block-subscription-reader'), 'hidden image-block subscription Reader QA URI must not be published in module.json5')
assert(!moduleJson.includes('nexte://qa/image-block-reader-open'), 'hidden non-mutating image-block Reader QA URI must not be published in module.json5')
assert(!moduleJson.includes('nexte://qa/image-block-manual-reader'), 'hidden image-block manual Reader QA URI must not be published in module.json5')
assert(!moduleJson.includes('nexte://qa/image-block-settings'), 'hidden image-block settings QA URI must not be published in module.json5')
assert(!moduleJson.includes('nexte://qa/image-block-settings-open'), 'hidden image-block settings-open QA URI must not be published in module.json5')
assert(!moduleJson.includes('nexte://qa/image-block-settings-edge'), 'hidden image-block settings edge-case QA URI must not be published in module.json5')
assert(!moduleJson.includes('nexte://qa/image-block-settings-refresh'), 'hidden image-block settings refresh QA URI must not be published in module.json5')
assert(entryIndex.includes('InternalQaRoutes.IMAGE_BLOCK_SEED_URI'), 'entry shell must route the hidden image-block QA URI')
assert(entryIndex.includes('InternalQaRoutes.IMAGE_BLOCK_SEED_READER_URI'), 'entry shell must route the hidden image-block direct Reader QA URI')
assert(entryIndex.includes('InternalQaRoutes.IMAGE_BLOCK_SUBSCRIPTION_READER_URI'), 'entry shell must route the hidden image-block subscription Reader QA URI')
assert(entryIndex.includes('InternalQaRoutes.IMAGE_BLOCK_READER_OPEN_URI'), 'entry shell must route the hidden non-mutating image-block Reader QA URI')
assert(entryIndex.includes('InternalQaRoutes.IMAGE_BLOCK_MANUAL_READER_URI'), 'entry shell must route the hidden image-block manual Reader QA URI')
assert(entryIndex.includes('InternalQaRoutes.IMAGE_BLOCK_SETTINGS_URI'), 'entry shell must route the hidden image-block settings QA URI')
assert(entryIndex.includes('InternalQaRoutes.IMAGE_BLOCK_SETTINGS_OPEN_URI'), 'entry shell must route the hidden image-block settings-open QA URI')
assert(entryIndex.includes('InternalQaRoutes.IMAGE_BLOCK_SETTINGS_EDGE_URI'), 'entry shell must route the hidden image-block settings edge-case QA URI')
assert(entryIndex.includes('InternalQaRoutes.IMAGE_BLOCK_SETTINGS_REFRESH_URI'), 'entry shell must route the hidden image-block settings refresh QA URI')
assert(entryIndex.includes('openImageBlockSeedQa'), 'entry shell must keep the seeded image-block QA handler')
assert(entryIndex.includes('openImageBlockSeedReaderQa'), 'entry shell must keep the seeded image-block direct Reader QA handler')
assert(entryIndex.includes('openImageBlockSubscriptionReaderQa'), 'entry shell must keep the seeded subscription image-block Reader QA handler')
assert(entryIndex.includes('openImageBlockReaderOpenQa'), 'entry shell must keep the non-mutating image-block Reader QA handler')
assert(entryIndex.includes('openImageBlockManualReaderQa'), 'entry shell must keep the manual image-block direct Reader QA handler')
assert(entryIndex.includes('openImageBlockSettingsQa'), 'entry shell must keep the seeded image-block settings QA handler')
assert(entryIndex.includes('openImageBlockSettingsEdgeQa'), 'entry shell must keep the seeded image-block settings edge-case QA handler')
assert(entryIndex.includes('openImageBlockSettingsRefreshQa'), 'entry shell must keep the image-block settings refresh QA handler')
assert(entryIndex.includes('seedImageBlockRule'), 'entry shell must share one seeded local-rule insert path')
assert(entryIndex.includes('seedImageBlockRuleEdgeCases'), 'entry shell must seed manual-rule edge cases for settings QA')
assert(entryIndex.includes('prepareImageBlockManualMarkQa'), 'entry shell must prepare manual mark QA without a preexisting local rule')
assert(entryIndex.includes("IMAGE_BLOCK_QA_GID: string = '3049882'"), 'seeded QA gallery gid must match the review fixture')
assert(entryIndex.includes("IMAGE_BLOCK_QA_TOKEN: string = 'd7e740a39e'"), 'seeded QA gallery token must match the review fixture')
assert(entryIndex.includes("IMAGE_BLOCK_QA_HASH: string = 'ce9e181d354a3cd5'"), 'seeded QA hash must match the reviewed rule')
assert(entryIndex.includes("IMAGE_BLOCK_QA_MISSING_SOURCE_HASH: string = '0123456789abcdef'"), 'seeded edge QA must preserve the missing-source hash fixture')
assert(entryIndex.includes('IMAGE_BLOCK_QA_FILE_COUNT: number = 6'), 'seeded direct Reader QA must preserve the reviewed file count')
assert(
  entryIndex.includes("IMAGE_BLOCK_QA_SOURCE_URL: string = 'https://e-hentai.org/g/3049882/d7e740a39e/'"),
  'seeded QA source URL must be the stable gallery review URL',
)
assert(entryIndex.includes('ImageBlockRepository.upsertLocalRule'), 'seeded QA route must create a real local image-block rule')
assert(entryIndex.includes('rule.sourcePage = 1'), 'seeded QA route must preserve the reviewed source page')
assert(entryIndex.includes("IMAGE_BLOCK_QA_FEED_ID: string = 'zh-scanlator-ads'"), 'subscription QA must use the default community provider id')
assert(entryIndex.includes('seedImageBlockSubscription'), 'entry shell must seed a subscription feed for subscription Reader QA')
assert(entryIndex.includes('seedEmptyImageBlockSubscription'), 'entry shell must seed an empty subscription feed for network refresh QA')
assert(entryIndex.includes('createImageBlockSubscriptionFeed'), 'entry shell must share subscription feed construction between QA routes')
assert(entryIndex.includes('replaceQaSubscription'), 'entry shell must clear local/allowlist state before replacing QA subscription feeds')
assert(entryIndex.includes('const feed: ImageBlockFeed = new ImageBlockFeed()'), 'subscription QA must persist a real feed model')
assert(entryIndex.includes('const item: ImageBlockFeedItem = new ImageBlockFeedItem()'), 'subscription QA must persist a real feed item model')
assert(entryIndex.includes('ImageBlockRepository.replaceSubscription(context, feed)'), 'subscription QA must write rules through subscription storage')
assert(entryIndex.includes('ImageBlockRepository.setSubscriptionEnabled(context, this.IMAGE_BLOCK_QA_FEED_ID, true)'), 'subscription QA must enable the seeded provider')
assert(entryIndex.includes("missingSource.sourceUrl = ''"), 'seeded edge QA must create a local rule missing review source')
assert(entryIndex.includes("duplicate.id = 'local:qa-duplicate'"), 'seeded edge QA must create a duplicate-hash local rule')
assert(entryIndex.includes("ImageBlockRepository.removeLocalRule(context, 'local:' + this.IMAGE_BLOCK_QA_HASH)"), 'manual mark QA route must remove the preexisting sample local rule')
assert(entryIndex.includes('ImageBlockRepository.removeWhitelistHash(context, this.IMAGE_BLOCK_QA_HASH)'), 'manual mark QA route must remove the sample false-positive allowlist')
assert(entryIndex.includes('ImageBlockRepository.setSubscriptionEnabled(context, this.IMAGE_BLOCK_QA_FEED_ID, false)'), 'manual mark QA route must disable the sample subscription provider before opening Reader')
assert(
  /openImageBlockManualReaderQa[\s\S]*this\.IMAGE_BLOCK_QA_TITLE,[\s\S]*true,[\s\S]*qa_manual_reader_prepare_failed[\s\S]*this\.IMAGE_BLOCK_QA_TITLE,[\s\S]*true,/.test(entryIndex),
  'manual mark QA route must open Reader with chrome initially visible so automation can click the real toolbar action',
)
assert(
  entryIndex.includes("new GalleryDetailParams(this.IMAGE_BLOCK_QA_GID, this.IMAGE_BLOCK_QA_TOKEN)"),
  'seeded QA route must open the seed gallery detail after inserting the local rule',
)
assert(
  entryIndex.includes("new ReaderParams(") &&
    entryIndex.includes('this.IMAGE_BLOCK_QA_FILE_COUNT') &&
    entryIndex.includes('this.IMAGE_BLOCK_QA_TITLE'),
  'seeded direct Reader QA route must open Reader with the reviewed gallery params',
)
const readerOpenStart = entryIndex.indexOf('private openImageBlockReaderOpenQa')
const readerOpenEnd = entryIndex.indexOf('private openImageBlockSettingsQa')
const readerOpenFn = entryIndex.slice(readerOpenStart, readerOpenEnd)
assert(
  readerOpenStart >= 0 && readerOpenEnd > readerOpenStart,
  'entry shell must expose the non-mutating Reader open QA route',
)
assert(
  !readerOpenFn.includes('seedImageBlockRule') && !readerOpenFn.includes('prepareImageBlockManualMarkQa'),
  'non-mutating Reader open QA route must not seed or clean image-block rules',
)

const seededQaScript = read('scripts/qa_image_block_seeded_reader.mjs')
for (const token of [
  'entry-default-signed.hap',
  'nexte://qa/image-block-seed',
  'nexte://qa/image-block-seed-reader',
  'nexte://qa/image-block-subscription-reader',
  'nexte://qa/image-block-reader-open',
  'nexte://qa/image-block-manual-reader',
  'nexte://qa/image-block-settings',
  'nexte://qa/image-block-settings-open',
  'nexte://qa/image-block-settings-edge',
  'nexte://qa/image-block-settings-refresh',
  '--via-detail',
  '--settings',
  '--settings-edge',
  '--settings-refresh',
  '--verify-block-after-settings-refresh',
  '--allow-and-verify',
  '--verify-settings-after-allow',
  '--delete-whitelist',
  '--verify-block-after-whitelist-delete',
  '--copy-draft',
  '--subscription',
  '--verify-settings-after-subscription',
  '--manual-mark',
  '--verify-settings-after-mark',
  '--delete-local-rule',
  '--verify-image-after-local-rule-delete',
  '--wake-unlock',
  'scripts',
  'device-lease',
  'ScreenLockRootComponent',
  'reader_block_placeholder_visible',
  'reader_allowlist_image_visible',
  'reader_allowlist_settings_visible',
  'reader_allowlist_deleted',
  'reader_block_after_whitelist_delete_visible',
  'reader_subscription_placeholder_visible',
  'reader_subscription_settings_visible',
  'reader_manual_mark_placeholder_visible',
  'reader_manual_mark_settings_visible',
  'reader_manual_mark_rule_deleted',
  'reader_image_after_local_rule_delete_visible',
  'settings_manual_rule_draft_visible',
  'settings_contribution_draft_clicked',
  'settings_subscription_update_visible',
  'reader_block_after_settings_refresh_visible',
  'settingsEdgeMode',
  'settingsRefreshMode',
  'verifyBlockAfterSettingsRefresh',
  'verifySettingsAfterAllow',
  'deleteWhitelist',
  'verifyBlockAfterWhitelistDelete',
  'subscriptionMode',
  'verifyImageAfterLocalRuleDelete',
  'blocked_device_leased',
  'lease-error.txt',
  'blocked_install_failed',
  'blocked_screen_locked_after_wake_unlock',
  'blocked_settings_manual_rule_not_seen',
  'blocked_settings_contribution_draft_not_seen',
  'blocked_settings_subscription_reset_not_seen',
  'blocked_settings_subscription_update_button_not_seen',
  'blocked_settings_subscription_update_not_seen',
  'blocked_settings_refresh_reader_not_blocked',
  'blocked_allow_button_not_found',
  'blocked_allowlist_image_not_seen',
  'blocked_allow_settings_whitelist_not_seen',
  'blocked_manual_mark_preexisting_placeholder',
  'blocked_manual_mark_button_not_found',
  'blocked_manual_settings_rule_not_seen',
  'blocked_local_rule_delete_button_not_found',
  'blocked_local_rule_delete_confirm_not_seen',
  'blocked_local_rule_still_visible',
  'blocked_local_rule_delete_reader_still_blocked',
  'blocked_whitelist_delete_button_not_found',
  'blocked_whitelist_delete_confirm_not_seen',
  'blocked_whitelist_still_visible',
  'blocked_whitelist_delete_reader_not_blocked',
  'blocked_subscription_settings_not_seen',
  'manual-mark-click.json',
  'settings-refresh-click.json',
  'block-after-settings-refresh-aa-start.txt',
  'local-rule-delete-click.json',
  'local-rule-delete-confirm-click.json',
  'image-after-local-rule-aa-start.txt',
  'subscription-settings-aa-start.txt',
  'allow-settings-aa-start.txt',
  'whitelist-delete-click.json',
  'whitelist-delete-confirm-click.json',
  'block-after-whitelist-aa-start.txt',
  'MANUAL_MARK_LABELS',
  'DELETE_LABELS',
  'SUBSCRIPTION_PROVIDER_LABELS',
  'UPDATE_RULES_LABELS',
  'WHITELIST_SECTION_LABELS',
  'WHITELIST_ROW_TITLE_LABELS',
  '!IMAGE_BLOCK_TITLE_LABELS.some',
  '!LOCAL_RULE_SECTION_LABELS.some',
  '!WHITELIST_SECTION_LABELS.some',
  'findManualMarkButton',
  'findLocalRuleDeleteButton',
  'findWhitelistDeleteButton',
  'settingsManualRuleRemovedVisible',
  'settingsSubscriptionProviderVisible',
  'settingsSubscriptionResetVisible',
  'settingsWhitelistVisible',
  'settingsWhitelistRemovedVisible',
  'verifyReaderImageAfterLocalRuleDelete',
  'verifySettingsAfterSubscriptionBlock',
  'verifySettingsRefreshPage',
  'verifyReaderBlockedAfterWhitelistDelete',
  'whitelistHashVisibleInSection',
  'whitelistCountText',
  'findExactTextCenter',
  'bottomToolbarButtonCenter',
  'reader bottom toolbar button',
  'keepAwake()',
  "'power-shell', 'timeout', '-o', '600000'",
  "'power-shell', 'wakeup'",
  "'630',",
  "'40000'",
  'wake-keep-awake.json',
  'wake-unlock.json',
  'wake-unlock-result.json',
  "'uitest', 'screenCap'",
  'snapshot_display',
  '--no-install',
  '--no-click-read',
  'ce9e181d354a3cd5',
  '0123456789abcdef',
  'https://e-hentai.org/g/3049882/d7e740a39e/',
]) {
  assert(seededQaScript.includes(token), `seeded Reader QA script must include ${token}`)
}
const readerPage = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
assert(
  readerPage.includes("accessibilityText($r('app.string.reader_image_block_mark'))"),
  'Reader manual image-block toolbar action must be accessible for automation and screen readers',
)
assert(
  readerPage.includes('this.showChrome = p.initialChromeVisible'),
  'Reader must honor the QA-only initial chrome flag without changing the default Reader route behavior',
)
const routeParams = read('shared/src/main/ets/model/RouteParams.ets')
assert(routeParams.includes('initialChromeVisible: boolean = false'), 'ReaderParams initial chrome flag must default to false')
assert(routeParams.includes('this.initialChromeVisible = initialChromeVisible'), 'ReaderParams must persist the initial chrome flag')
assert(
  seededQaScript.indexOf('let chrome = reader') < seededQaScript.indexOf('openReaderChrome(chrome.layoutPath)'),
  'manual-mark QA must first use the already-visible chrome before trying tap-to-open fallback',
)
assert(
  seededQaScript.includes('bottomToolbarButtonCenter(path, 1)'),
  'manual-mark QA must fall back to the second bottom-toolbar action when layout dumps omit icon accessibility text',
)
assert(
  seededQaScript.includes('findLocalRuleDeleteButton(settings.layoutPath)') &&
    seededQaScript.includes('findExactTextCenter(readLayout(alert.layoutPath), DELETE_LABELS)') &&
    seededQaScript.includes('settingsManualRuleRemovedVisible(deleted.layoutPath)'),
  'manual-mark QA must support deleting the created local rule through the real settings confirmation flow',
)
assert(
  seededQaScript.includes("localRuleCountText(path) === '0'") &&
    seededQaScript.includes("!draftVisible") &&
    seededQaScript.includes("!text.includes('scanlator-ad / P1')"),
  'local-rule deletion QA must verify the visible rule count, contribution row, and local rule row disappear',
)
assert(
  seededQaScript.includes('Math.floor((bounds.top + bounds.bottom) / 2)'),
  'manual-mark bottom-toolbar fallback must click the real button center, not the detail-page bottom-safe-area point',
)
assert(
  seededQaScript.includes('settingsManualRuleEdgeVisible') &&
    seededQaScript.includes("text.includes('1/3')") &&
    seededQaScript.includes("text.includes('missing source')") &&
    seededQaScript.includes("text.includes('duplicate')"),
  'seeded Reader QA script must verify edge-case ready/total and skipped reasons',
)
const whitelistRemovedStart = seededQaScript.indexOf('function settingsWhitelistRemovedVisible')
const whitelistRemovedEnd = seededQaScript.indexOf('function findLocalRuleDeleteButton')
const whitelistRemovedFn = seededQaScript.slice(whitelistRemovedStart, whitelistRemovedEnd)
assert(
  whitelistRemovedStart >= 0 && whitelistRemovedEnd > whitelistRemovedStart,
  'seeded Reader QA script must keep a scoped whitelist removal verifier',
)
assert(
  whitelistRemovedFn.includes('!whitelistHashVisibleInSection(path)'),
  'seeded Reader QA script must verify allowlist deletion inside the allowlist section',
)
assert(
  !whitelistRemovedFn.includes("!text.includes('ce9e...3cd5')"),
  'seeded Reader QA script must not globally reject the sample hash because the local-rule section may still contain it',
)
assert(
  seededQaScript.includes("return text.includes('ScreenLockRootComponent')"),
  'seeded Reader QA script must use the real lockscreen component as the lock guard',
)
assert(
  seededQaScript.indexOf('keepAwake()') < seededQaScript.indexOf("let preflight = capture('preflight')"),
  'seeded Reader QA script must keep the display awake before the lockscreen preflight capture',
)
assert(
  !seededQaScript.includes('"bundleName":"com.ohos.sceneboard"'),
  'seeded Reader QA script must not treat the normal system status bar as a lockscreen',
)

const plan = read('docs/plans/active/image-block-community-rules.md')
for (const token of [
  '--allow-and-verify',
  'reader_allowlist_image_visible',
  'ReaderTapOverlay',
  'image-block-allowlist-emulator-fixed',
  'image-block-allowlist-197-after-reader-tap-fix',
  'image-block-seeded-reader-197-wake-unlock-direct',
  'image-block-allowlist-197-wake-unlock',
  '--verify-settings-after-allow',
  '--delete-whitelist',
  '--verify-block-after-whitelist-delete',
  'image-block-allowlist-delete-197-wake-unlock',
  'reader_allowlist_deleted',
  'image-block-allowlist-delete-reblock-197-wake-unlock',
  'reader_block_after_whitelist_delete_visible',
  '--verify-image-after-local-rule-delete',
  'image-block-manual-delete-unblock-197-wake-unlock-final',
  'reader_image_after_local_rule_delete_visible',
  'image_after_local_rule_wait_0.png',
  '--subscription',
  '--verify-settings-after-subscription',
  'image-block-subscription-reader-settings-197-wake-unlock',
  'reader_subscription_settings_visible',
  'subscription_settings_wait_0.png',
  '--settings-refresh',
  'image-block-settings-refresh-197-wake-unlock',
  'settings_subscription_update_visible',
  'settings-refresh-click.json',
  'settings_refresh_wait_0.png',
  '--verify-block-after-settings-refresh',
  'image-block-settings-refresh-reader-197-wake-unlock',
  'reader_block_after_settings_refresh_visible',
  'block-after-settings-refresh-aa-start.txt',
  'block_after_settings_refresh_wait_0.png',
  'image-block-blur80-visible-native-button-197',
  'visible blurred Reader image surface',
  'not a full-screen cover background or black canvas',
  'native default text button',
  'reader_block_placeholder_visible',
  'reader_allowlist_image_visible',
]) {
  assert(plan.includes(token), `image-block plan must preserve allowlist QA evidence: ${token}`)
}

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  assert(strings.includes('"name": "reader_image_block_mark"'), `${locale} must define reader_image_block_mark`)
  for (const key of [
    'image_block_title',
    'image_block_hint',
    'image_block_update_default',
    'image_block_update_default_hint',
    'image_block_update_started',
    'image_block_update_finished',
    'image_block_update_failed',
    'image_block_rules',
    'image_block_local_rules',
    'image_block_local_rules_hint',
    'image_block_local_rule_title',
    'image_block_local_rule_delete_confirm',
    'image_block_local_rule_deleted',
    'image_block_local_rule_delete_failed',
    'image_block_contribution_draft',
    'image_block_contribution_draft_hint',
    'image_block_contribution_copied',
    'image_block_contribution_empty',
    'image_block_contribution_failed',
    'image_block_contribution_skipped',
    'image_block_contribution_missing_source',
    'image_block_contribution_duplicate',
    'image_block_contribution_invalid',
    'image_block_whitelist',
    'image_block_whitelist_hint',
    'image_block_whitelist_hash_title',
    'image_block_whitelist_delete_confirm',
    'image_block_whitelist_deleted',
    'image_block_whitelist_delete_failed',
  ]) {
    assert(strings.includes(`"name": "${key}"`), `${locale} must define ${key}`)
  }
}

const contribution = read('shared/src/main/ets/services/ImageBlockContributionService.ets')
assert(contribution.includes('buildJsonlLine'), 'contribution helper must generate a JSONL rule line')
assert(contribution.includes('buildJsonlLineFromRule'), 'contribution helper must generate JSONL from local rules')
assert(contribution.includes('buildJsonlLinesFromRules'), 'contribution helper must generate JSONL from multiple local rules')
assert(contribution.includes("return lines.join('\\n')"), 'multi-rule contribution helper must emit JSONL lines')
assert(contribution.includes('ImageBlockContributionBatch'), 'contribution helper must expose a batch summary model')
assert(contribution.includes('buildSubmissionBatchFromRules'), 'contribution helper must build submit-ready batches from local rules')
assert(contribution.includes('ImageBlockContributionIssuePackage'), 'contribution helper must expose a pre-submission issue package model')
assert(contribution.includes('buildIssuePackageFromRules'), 'contribution helper must build issue packages from local rules without UI coupling')
assert(contribution.includes('buildIssuePackageFromBatch'), 'contribution helper must build issue packages from prepared batches')
assert(contribution.includes('https://github.com/erosTeam/nexte-image-block-rules/issues/new'), 'contribution issue package must target the rules repository issue page')
assert(contribution.includes("RULE_SUBMISSION_TEMPLATE: string = 'rule_submission.yml'"), 'contribution issue URL must select the rules issue form')
assert(contribution.includes('labels='), 'contribution issue URL must carry the rule-submission label')
assert(contribution.includes('if (batch.drafts.length === 1)'), 'contribution issue URL must use the issue form only for single-rule packages')
for (const field of [
  '&hash=',
  '&source_url=',
  '&source_page=',
  '&note=',
  '&feed=',
]) {
  assert(contribution.includes(field), `single-rule issue URL must prefill form field ${field}`)
}
assert(contribution.includes('body='), 'contribution issue URL must carry the generated review body when short enough')
assert(contribution.includes('MAX_ISSUE_URL_LENGTH'), 'contribution issue URL must have a bounded query length fallback')
assert(contribution.includes('pack.jsonl = batch.jsonl'), 'contribution issue package must retain JSONL even when URL body fallback is used')
assert(contribution.includes('pack.urlTooLong = true'), 'contribution issue package must flag URL-length fallback')
assert(contribution.includes('totalCount'), 'submission batch must track total local-rule count')
assert(contribution.includes('skippedCount()'), 'submission batch must expose total skipped-rule count')
assert(contribution.includes('skippedMissingSourceCount'), 'submission batch must track rules missing review sources')
assert(contribution.includes('skippedDuplicateHashCount'), 'submission batch must track duplicate pHash rules')
assert(contribution.includes('skippedInvalidCount'), 'submission batch must track invalid local rules')
assert(contribution.includes('hasSeenHash'), 'submission batch must de-duplicate local rules by normalized pHash')
assert(contribution.includes('sanitizeReviewSourceUrl'), 'contribution helper must sanitize review source URLs')
assert(
  contribution.includes('ImageBlockContributionService.cleanSourcePage(rule.sourcePage) <= 0'),
  'submission batch must exclude local rules without a positive structured source page',
)
for (const unsafe of [
  'ipb_pass_hash',
  'igneous',
  'showkey',
  'fullimg.php',
  'nl=',
  'token=',
  'session=',
]) {
  assert(contribution.includes(`'${unsafe}'`), `contribution helper must reject ${unsafe}`)
}
assert(contribution.includes('JSON.stringify(line)'), 'contribution helper must use structured JSON output')
assert(contribution.includes('sourceUrl'), 'contribution JSONL must retain reviewer-only sourceUrl')
assert(contribution.includes('sourcePage'), 'contribution JSONL must retain reviewer-only sourcePage')
assert(contribution.includes('draft.sourcePage = ImageBlockContributionService.cleanSourcePage(sourcePage)'), 'local-rule contribution drafts must preserve structured source pages')
assert(contribution.includes('line.sourcePage = sourcePage'), 'JSONL contribution output must emit sourcePage only after normalization')
assert(contribution.includes('node tools/rules.mjs import-jsonl --feed'), 'issue body must include the maintainer dry-run command')
assert(contribution.includes('MAX_NOTE_LENGTH: number = 200'), 'contribution notes must be bounded')

assert(hamming('0000000000000000', '0000000000000000') === 0, 'identical hash distance must be 0')
assert(hamming('0000000000000000', 'ffffffffffffffff') === 64, 'opposite hash distance must be 64')
assert(hamming('0123456789abcdef', '0123456789abcdee') === 1, 'one-bit hash distance must be 1')
parseSampleFeed()

console.log('✓ image block foundation contract passed')

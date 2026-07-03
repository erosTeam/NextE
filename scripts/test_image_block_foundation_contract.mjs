#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const exists = (p) => statSync(join(ROOT, p))

for (const file of [
  'shared/src/main/ets/model/ImageBlockRule.ets',
  'shared/src/main/ets/services/PHashService.ets',
  'shared/src/main/ets/services/ImageBlockService.ets',
  'shared/src/main/ets/services/ImageBlockRuntimeService.ets',
  'shared/src/main/ets/services/ImageBlockSubscriptionService.ets',
  'shared/src/main/ets/storage/ImageBlockRepository.ets',
  'shared/src/main/ets/storage/LocalDataStore.ets',
]) {
  exists(file)
}

const model = read('shared/src/main/ets/model/ImageBlockRule.ets')
assert.match(model, /IMAGE_BLOCK_MAX_THRESHOLD:\s*number\s*=\s*12/, 'threshold upper bound stays 12')
assert.match(model, /nexte-image-block-rules\/main\/dist\/manifest\.json/, 'default manifest uses rules repo dist manifest')

const phash = read('shared/src/main/ets/services/PHashService.ets')
assert.match(phash, /hashImageFileDct64/, 'file pHash API exists')
assert.match(phash, /hashImageFileRegionDct64/, 'region pHash API exists')
assert.match(phash, /hammingDistanceHex/, 'hex hamming distance exists')
assert.match(phash, /clampThreshold/, 'threshold clamp exists')

const service = read('shared/src/main/ets/services/ImageBlockService.ets')
assert.match(service, /decisionForHash/, 'hash decision API exists')
assert.match(service, /isAllowedByRule/, 'allow rules are checked before blocking')
assert.match(service, /!rule\.enabled/, 'disabled rules are skipped')
assert.match(service, /distance <= threshold/, 'threshold controls matching')

const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
for (const table of [
  'image_block_subscriptions',
  'image_block_rules',
  'image_block_hash_cache',
]) {
  assert.match(store, new RegExp(table), `${table} table exists`)
}
assert.doesNotMatch(store, /CREATE TABLE IF NOT EXISTS image_block_whitelist/, 'allow rules live in image_block_rules')
assert.doesNotMatch(store, /CREATE TABLE IF NOT EXISTS image_block_rule_overrides/, 'rule overrides live in image_block_rules')

const repo = read('shared/src/main/ets/storage/ImageBlockRepository.ets')
assert.match(repo, /replaceSubscription/, 'subscription replacement exists')
assert.match(repo, /loadEnabledRules/, 'enabled rule loading exists')
assert.match(repo, /upsertLocalRule/, 'local rule writer exists')
assert.match(repo, /upsertAllowRule/, 'allow writer uses image_block_rules')

const runtime = read('shared/src/main/ets/services/ImageBlockRuntimeService.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/ImageBlockSettingsPage.ets')
const backupTypes = read('shared/src/main/ets/backup/BackupTypes.ets')
const backupAdapter = read('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
const cloudSchema = read('entry/src/main/resources/rawfile/arkdata/cloud/cloud_schema.json')
assert.match(runtime, /previewPathForRuleSource/, 'settings can fetch rule previews from EH source metadata')
assert.match(runtime, /EhApiService\.getInstance\(\)\.getGalleryDetail/, 'rule preview fetch starts from gallery detail')
assert.match(runtime, /getPreviewImages/, 'rule preview fetch can scan preview pages')
assert.match(runtime, /rule\.previewPath = ''/, 'new local image rules do not store image preview content')
assert.doesNotMatch(runtime, /previewDataReferenceForFile/, 'full-image local rules no longer store portable preview data')
assert.match(settingsPage, /ImageBlockRuntimeService\.previewPathForRuleSource/, 'settings repairs missing previews from source metadata')
assert.match(settingsPage, /rule\.previewPath\.startsWith\('data:image\/'\)[\s\S]*return ''/, 'settings ignores synced data URI preview payloads')
assert.match(settingsPage, /fileIo\.statSync\(localPath\)\.size > 0/, 'settings can still use local preview files when present')
assert.match(backupTypes, /imageBlock: BackupImageBlockSection/, 'backup carries image block rule metadata')
assert.doesNotMatch(backupTypes, /previewPath/, 'backup image block entries do not carry preview image content')
assert.match(backupAdapter, /rule\.previewPath = ''/, 'backup restore clears image block preview paths')
assert.match(syncAdapter, /r\.previewPath = ''/, 'provider sync exports image block rules without preview content')
assert.match(syncAdapter, /r\.sourceType, r\.sourceUrl, r\.sourcePage, '', r\.enabled/, 'provider sync applies image block rules without preview content')
assert.doesNotMatch(cloudSchema, /preview_data/, 'cloud schema has no separate preview payload field')

const subscription = read('shared/src/main/ets/services/ImageBlockSubscriptionService.ets')
assert.match(subscription, /BackupChecksum\.hashText/, 'feed sha256 is checked')
assert.doesNotMatch(subscription, /EhCookieStore/, 'rule feed fetch does not depend on EH cookies')

console.log('✓ image block foundation contract passed')

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
assert.match(service, /isWhitelisted/, 'whitelist check exists before blocking')
assert.match(service, /!rule\.enabled/, 'disabled rules are skipped')
assert.match(service, /distance <= threshold/, 'threshold controls matching')

const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
for (const table of [
  'image_block_subscriptions',
  'image_block_rules',
  'image_block_whitelist',
  'image_block_hash_cache',
]) {
  assert.match(store, new RegExp(table), `${table} table exists`)
}

const repo = read('shared/src/main/ets/storage/ImageBlockRepository.ets')
assert.match(repo, /replaceSubscription/, 'subscription replacement exists')
assert.match(repo, /loadEnabledRules/, 'enabled rule loading exists')
assert.match(repo, /upsertLocalRule/, 'local rule writer exists')
assert.match(repo, /upsertWhitelistHash/, 'whitelist writer exists')

const subscription = read('shared/src/main/ets/services/ImageBlockSubscriptionService.ets')
assert.match(subscription, /BackupChecksum\.hashText/, 'feed sha256 is checked')
assert.doesNotMatch(subscription, /EhCookieStore/, 'rule feed fetch does not depend on EH cookies')

console.log('✓ image block foundation contract passed')

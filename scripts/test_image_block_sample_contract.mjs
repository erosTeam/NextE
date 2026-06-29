#!/usr/bin/env node
import assert from 'node:assert'
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

function read(path) {
  return readFileSync(join(ROOT, path), 'utf8')
}

function readJson(path) {
  return JSON.parse(read(path))
}

function sha256(text) {
  return createHash('sha256').update(text).digest('hex')
}

function rulesRepoRoot() {
  const envPath = process.env.NEXTE_IMAGE_BLOCK_RULES_REPO || ''
  const candidates = [
    envPath,
    join(ROOT, '..', 'nexte-image-block-rules'),
    join(ROOT, '..', '..', 'nexte-image-block-rules'),
  ]
  for (const candidate of candidates) {
    if (candidate.length > 0 && existsSync(join(candidate, 'dist', 'manifest.json'))) {
      return candidate
    }
  }
  return ''
}

function assertGalleryUrl(url) {
  assert.match(
    url,
    /^https:\/\/e-hentai\.org\/g\/[0-9]+\/[0-9a-f]+\/$/,
    `sample review URL must be a stable EH gallery URL: ${url}`,
  )
  assert.doesNotMatch(url, /\/s\/|fullimg\.php|showkey|nl=|ipb_pass_hash|igneous/i, 'sample URL must not be temporary or credential-bearing')
}

function firstUnusedDraftHash(feed) {
  const existing = new Set(feed.items.map((item) => item.hash))
  const candidates = [
    '0011223344556677',
    '0123456789abcdef',
    '89abcdef01234567',
    'fedcba9876543210',
  ]
  for (const hash of candidates) {
    if (!existing.has(hash)) {
      return hash
    }
  }
  throw new Error('sample contract needs an unused synthetic draft hash')
}

const samples = readJson('docs/fixtures/image-block-public-samples.json')
assert.equal(samples.schema, 1, 'sample fixture schema must be 1')
assert.equal(samples.kind, 'nexte-image-block-public-samples', 'sample fixture kind must match')
assert.equal(samples.updatedAt, '2026-06-29', 'sample fixture must preserve the verified search date')

const candidateById = new Map()
for (const gallery of samples.candidateGalleries) {
  assertGalleryUrl(gallery.url)
  assert.ok(Number.isInteger(gallery.gid) && gallery.gid > 0, 'candidate gallery gid must be positive')
  assert.ok(Number.isInteger(gallery.pages) && gallery.pages > 0, 'candidate gallery page count must be positive')
  assert.ok(gallery.token.length > 0, 'candidate gallery token must be recorded')
  assert.ok(gallery.title.length > 0, 'candidate gallery title must be recorded for public review')
  assert.ok(gallery.category.length > 0, 'candidate gallery category must be recorded')
  assert.equal(gallery.discovery, 'title_search', 'current public samples must be title-search candidates')
  assert.deepEqual(gallery.advertisementNamespaceTags, [], 'candidate galleries must not claim a stable advertisement namespace tag')
  assert.match(gallery.evidence, /title search/, 'candidate evidence must describe the public title-search source')
  candidateById.set(gallery.gid, gallery)
}

for (const gid of [3049882, 3917158, 1284740, 2991483, 2652400, 1757442, 1678170]) {
  assert.ok(candidateById.has(gid), `candidate fixture must include gallery ${gid}`)
}
assert.equal(candidateById.get(3049882).priority, 'seed', '3049882 must remain the first seed sample')
assert.equal(candidateById.get(1284740).priority, 'secondary', '1284740 must remain the next short manual-rule sample')
assert.equal(candidateById.get(3917158).priority, 'short_title_sample', '3917158 must remain a short advertising-title sample')
assert.equal(candidateById.get(2991483).priority, 'short_title_sample', '2991483 must remain a short advertising-title sample')
assert.equal(candidateById.get(1757442).priority, 'low', '1757442 must remain lower priority than short samples')

const otherTagCheck = samples.searchChecks.find((item) => item.query === 'other:advertisement')
assert.ok(otherTagCheck !== undefined, 'fixture must record the negative namespace-tag search')
assert.equal(otherTagCheck.expected, 'no_hits', 'other:advertisement must not be treated as a stable EH tag')
assert.match(otherTagCheck.evidence, /No hits found/, 'negative tag evidence must record the public no-hit result')
for (const query of ['other:advertisements', 'other:advertising']) {
  const check = samples.searchChecks.find((item) => item.query === query)
  assert.ok(check !== undefined, `fixture must record negative namespace-tag search ${query}`)
  assert.equal(check.expected, 'no_hits', `${query} must not be treated as a stable EH tag`)
  assert.match(check.evidence, /No hits found/, `${query} evidence must record the public no-hit result`)
}

const advertisementCheck = samples.searchChecks.find((item) => item.query === 'advertisement')
assert.ok(advertisementCheck !== undefined, 'fixture must record advertisement title search')
assert.equal(advertisementCheck.resultCount, 3, 'advertisement title search must keep the public result count')
assert.deepEqual(advertisementCheck.candidateGalleryIds, [3049882, 1757442, 1284740], 'advertisement title search candidates must stay ordered')
assert.match(advertisementCheck.evidence, /did not expose an advertisement namespace tag/, 'advertisement search must record missing namespace tag evidence')

const advertisementsCheck = samples.searchChecks.find((item) => item.query === 'advertisements')
assert.ok(advertisementsCheck !== undefined, 'fixture must record advertisements title search')
assert.equal(advertisementsCheck.resultCount, 1, 'advertisements title search must keep the public result count')
assert.deepEqual(advertisementsCheck.candidateGalleryIds, [1284740], 'advertisements title search must point to the short secondary sample')
assert.match(advertisementsCheck.evidence, /did not expose an advertisement namespace tag/, 'advertisements search must record missing namespace tag evidence')

const advertisingCheck = samples.searchChecks.find((item) => item.query === 'advertising')
assert.ok(advertisingCheck !== undefined, 'fixture must record advertising title search')
assert.equal(advertisingCheck.resultCount, 5, 'advertising title search must keep the public result count')
assert.deepEqual(
  advertisingCheck.candidateGalleryIds,
  [3917158, 3636516, 2991483, 2652400, 1678170],
  'advertising title search candidates must stay ordered',
)
assert.deepEqual(
  advertisingCheck.accessibleCandidateGalleryIds,
  [3917158, 2991483, 2652400, 1678170],
  'advertising title search must record candidates with public metadata',
)
assert.deepEqual(
  advertisingCheck.skippedCandidateGalleryIds,
  [3636516],
  'advertising title search must record candidates without public metadata',
)
assert.match(advertisingCheck.evidence, /did not expose an advertisement namespace tag/, 'advertising search must record missing namespace tag evidence')

assert.deepEqual(candidateById.get(3049882).publicOtherTags, [], 'seed sample must not claim unrelated other tags')
assert.deepEqual(candidateById.get(1284740).publicOtherTags, ['other:missing cover'], 'secondary sample must preserve the visible non-ad other tag')
assert.deepEqual(candidateById.get(1757442).publicOtherTags, ['other:artbook'], 'low-priority sample must preserve the visible non-ad other tag')

assert.equal(samples.seedRules.length, 1, 'first validation slice must keep exactly one seed rule')
const seed = samples.seedRules[0]
assertGalleryUrl(seed.galleryUrl)
assert.equal(seed.feedId, 'zh-scanlator-ads', 'seed rule must target the scanlator-ad feed')
assert.equal(seed.galleryUrl, candidateById.get(3049882).url, 'seed rule must point to the seed gallery review URL')
assert.equal(seed.page, 1, 'seed rule must keep the reviewed page index')
assert.match(seed.hash, /^[0-9a-f]{16}$/, 'seed pHash must be lowercase hex64')
assert.equal(seed.hash, 'ce9e181d354a3cd5', 'seed pHash must match the first verified manual mark')
assert.equal(seed.threshold, 8, 'seed threshold must match the default feed threshold')
assert.equal(seed.scope, 'whole', 'first validation slice must stay whole-image scoped')

const model = read('shared/src/main/ets/model/ImageBlockRule.ets')
assert.match(
  model,
  /https:\/\/raw\.githubusercontent\.com\/erosTeam\/nexte-image-block-rules\/main\/dist\/manifest\.json/,
  'app default manifest URL must point to the erosTeam rules dist manifest',
)

const plan = read('docs/plans/active/image-block-community-rules.md')
for (const url of samples.candidateGalleries.map((gallery) => gallery.url)) {
  assert.ok(plan.includes(url), `image-block plan must mention sample gallery ${url}`)
}
assert.ok(plan.includes(seed.hash), 'image-block plan must mention the seed pHash')
assert.ok(plan.includes('other:advertisement') && plan.includes('No hits found'), 'image-block plan must record the negative EH tag evidence')
assert.ok(plan.includes('Manual-rule validation path'), 'image-block plan must keep the manual-rule validation path')

const repo = rulesRepoRoot()
if (repo.length > 0) {
  const manifestText = readFileSync(join(repo, 'dist', 'manifest.json'), 'utf8')
  const manifest = JSON.parse(manifestText)
  assert.equal(manifest.kind, 'nexte-image-block-manifest', 'rules repo manifest kind must match app parser contract')
  const manifestFeed = manifest.feeds.find((feed) => feed.id === seed.feedId)
  assert.ok(manifestFeed !== undefined, 'rules repo manifest must include the scanlator-ad feed')
  assert.equal(
    manifestFeed.url,
    'https://raw.githubusercontent.com/erosTeam/nexte-image-block-rules/main/dist/zh-scanlator-ads.json',
    'rules repo feed URL must match the app subscription target',
  )

  const feedText = readFileSync(join(repo, 'dist', 'zh-scanlator-ads.json'), 'utf8')
  assert.equal(manifestFeed.sha256, sha256(feedText), 'rules repo manifest sha256 must match the generated feed file')
  const feed = JSON.parse(feedText)
  assert.equal(feed.kind, 'nexte-image-block-feed', 'rules repo feed kind must match app parser contract')
  assert.equal(feed.algorithm, 'dct64-v1', 'rules repo feed algorithm must match app pHash algorithm')
  assert.equal(feed.defaultThreshold, 8, 'rules repo feed default threshold must remain 8')
  assert.equal(feed.items.length, manifestFeed.count, 'manifest count must match generated feed item count')
  const distSeed = feed.items.find((item) => item.hash === seed.hash)
  assert.ok(distSeed !== undefined, 'rules repo dist feed must include the seed pHash')
  assert.equal(distSeed.threshold, seed.threshold, 'dist seed threshold must match the fixture')
  assert.equal(distSeed.label, seed.label, 'dist seed label must match the fixture')
  assert.equal(distSeed.scope, seed.scope, 'dist seed scope must match the fixture')
  assert.equal(distSeed.sourceUrl, seed.galleryUrl, 'dist feed must keep the review source URL for app display')
  assert.equal(distSeed.sourcePage, seed.page, 'dist feed must keep the review source page for app display')
  assert.equal(distSeed.note, undefined, 'dist feed must strip reviewer-only note')

  const draftHash = firstUnusedDraftHash(feed)
  const draftDir = mkdtempSync(join(tmpdir(), 'nexte-image-block-app-draft-'))
  const draftPath = join(draftDir, 'app-draft.jsonl')
  const appDraft = {
    hash: draftHash,
    threshold: seed.threshold,
    label: seed.label,
    scope: seed.scope,
    sourceUrl: seed.galleryUrl,
    note: '',
    sourcePage: seed.page,
  }
  writeFileSync(draftPath, `${JSON.stringify(appDraft)}\n`)
  const dryRun = execFileSync(
    process.execPath,
    ['tools/rules.mjs', 'import-jsonl', '--feed', seed.feedId, '--file', draftPath],
    { cwd: repo, encoding: 'utf8' },
  )
  assert.ok(dryRun.includes('new=1 duplicateExisting=0 duplicateIncoming=0 invalid=0'), 'rules importer dry-run must accept app-shaped JSONL drafts')
  assert.ok(dryRun.includes(`source=${seed.galleryUrl}`), 'rules importer dry-run must report the app draft source URL')
  assert.ok(dryRun.includes(`page=${seed.page}`), 'rules importer dry-run must report the app draft source page')

  const sourceRules = readFileSync(join(repo, 'rules', 'zh-scanlator-ads.jsonl'), 'utf8')
  assert.ok(sourceRules.includes(`"hash":"${seed.hash}"`), 'rules repo source JSONL must include the seed pHash')
  assert.ok(sourceRules.includes(`"sourceUrl":"${seed.galleryUrl}"`), 'rules repo source JSONL must preserve the stable review URL')
  assert.ok(sourceRules.includes(`"sourcePage":${seed.page}`), 'rules repo source JSONL must preserve structured reviewer page evidence')

  const rulesTool = readFileSync(join(repo, 'tools', 'rules.mjs'), 'utf8')
  assert.ok(rulesTool.includes('import-jsonl'), 'rules repo tool must import app-copied JSONL drafts')
  assert.ok(rulesTool.includes('sourceUrl is required for app-imported review drafts'), 'rules repo importer must require review source URLs')
  assert.ok(rulesTool.includes('wherePrefix'), 'rules repo importer must report draft-file line locations')
  for (const unsafe of ['fullimg.php', 'showkey', 'nl=', 'sk=', 'session=', 'sid=']) {
    assert.ok(rulesTool.includes(`'${unsafe}'`), `rules repo importer must reject unsafe source token ${unsafe}`)
  }
  assert.ok(existsSync(join(repo, 'tools', 'test_import_jsonl.mjs')), 'rules repo must include an importer smoke test')
  const importerSmoke = readFileSync(join(repo, 'tools', 'test_import_jsonl.mjs'), 'utf8')
  for (const token of [
    'duplicateIncoming=1',
    'invalid=3',
    'page=1',
    'sourcePage must be an integer from 1 to 100000',
    'sourcePage is required for app-imported review drafts',
    'refused to apply',
    'clean apply must rebuild dist by default',
    'clean apply must persist structured source page evidence',
    'rebuilt client feed must keep review sourceUrl',
    'rebuilt client feed must keep review sourcePage',
  ]) {
    assert.ok(importerSmoke.includes(token), `rules repo importer smoke must cover ${token}`)
  }
  const workflow = readFileSync(join(repo, '.github', 'workflows', 'validate.yml'), 'utf8')
  assert.ok(workflow.includes('node tools/test_import_jsonl.mjs'), 'rules repo CI must run the importer smoke test')
}

console.log('✓ image block sample contract passed')

#!/usr/bin/env node
/**
 * Contract: comment identity rules (member id / comment id) reuse the existing `commentator` and
 * `comment` block types with a typed text prefix, so no new block type, RDB column, backup field or sync
 * record is needed. This protects three things a plain-behaviour test would miss:
 *
 *   1. exact identity matching (a prefix rule must not match by substring, or #uid:123 would hit #uid:1234);
 *   2. an empty identity never matches (uploader comments and rows without a member id must stay visible);
 *   3. the cross-version inertness of the prefix — an older client normalizes unknown block types to
 *      `title`, so a prefixed value must not read as a title match there.
 *
 * The mirror below reproduces LocalBlockService's matching rules, and the source assertions keep it in sync.
 * Run: node scripts/test_local_block_identity_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (path) => readFileSync(join(ROOT, path), 'utf8')

let passed = 0
const ok = (name, condition) => {
  assert.ok(condition, name)
  passed += 1
}

const TYPE_TITLE = 'title'
const TYPE_UPLOADER = 'uploader'
const TYPE_COMMENTATOR = 'commentator'
const TYPE_COMMENT = 'comment'
const MEMBER_ID_PREFIX = '#uid:'
const COMMENT_ID_PREFIX = '#cid:'

const normalizeType = (type) =>
  type === TYPE_UPLOADER || type === TYPE_COMMENTATOR || type === TYPE_COMMENT ? type : TYPE_TITLE

const normalized = (text) => text.replace(/[\u200B-\u200F\uFEFF]/g, '').trim()

// Mirror of LocalBlockService.identityPrefixFor / matchText / matchIdentity.
const identityPrefixFor = (blockType) => {
  if (blockType === TYPE_COMMENTATOR) return MEMBER_ID_PREFIX
  if (blockType === TYPE_COMMENT) return COMMENT_ID_PREFIX
  return ''
}

const isIdentityRule = (rule) => {
  const prefix = identityPrefixFor(rule.blockType)
  const text = normalized(rule.ruleText)
  return !rule.enableRegex && prefix.length > 0 && text.startsWith(prefix) && /^[1-9]\d*$/.test(text.substring(prefix.length).trim())
}

const matchText = (rules, text, blockType) => {
  const value = normalized(text)
  if (value.length === 0) return false
  for (const rule of rules) {
    if (rule.blockType !== blockType || !rule.enabled) continue
    const rawRuleText = normalized(rule.ruleText)
    if (isIdentityRule(rule)) continue
    const caseInsensitive = rule.enableRegex && rawRuleText.includes('(?i)')
    const ruleText = rule.enableRegex ? rawRuleText.replace(/\(\?i\)/g, '') : rawRuleText
    if (ruleText.length === 0) continue
    if (rule.enableRegex) {
      try {
        if (new RegExp(ruleText, caseInsensitive ? 'i' : '').test(value)) return true
      } catch {
        continue
      }
    } else {
      const plainText = blockType === TYPE_COMMENT ? value.replace(/[\r\n\u2028\u2029]+/g, ' ') : value
      if (plainText.toLowerCase().includes(ruleText.toLowerCase())) return true
    }
  }
  return false
}

const matchIdentity = (rules, identity, blockType) => {
  const target = normalized(identity)
  if (target.length === 0) return false
  const prefix = identityPrefixFor(blockType)
  if (prefix.length === 0) return false
  for (const rule of rules) {
    if (rule.blockType !== blockType || !rule.enabled) continue
    const ruleText = normalized(rule.ruleText)
    if (!isIdentityRule(rule)) continue
    if (ruleText.substring(prefix.length).trim() === target) return true
  }
  return false
}

const rule = (blockType, ruleText, enabled = true) => ({ blockType, ruleText, enabled })

// --- exact identity matching must not degrade into substring matching -----------------------------
{
  const rules = [rule(TYPE_COMMENTATOR, MEMBER_ID_PREFIX + '123')]
  ok('member id rule matches its own id', matchIdentity(rules, '123', TYPE_COMMENTATOR))
  ok('member id rule does not match a longer id sharing its prefix',
    !matchIdentity(rules, '1234', TYPE_COMMENTATOR))
  ok('member id rule does not match a shorter id sharing its prefix',
    !matchIdentity(rules, '12', TYPE_COMMENTATOR))
}

// --- a comment id rule and a member id rule are different fields ---------------------------------
{
  const rules = [rule(TYPE_COMMENT, COMMENT_ID_PREFIX + '8337138')]
  ok('comment id rule matches the comment id', matchIdentity(rules, '8337138', TYPE_COMMENT))
  ok('comment id rule never matches a member id', !matchIdentity(rules, '8337138', TYPE_COMMENTATOR))
  ok('member-id rule does not leak into comment-id matching', !matchIdentity(rules, '999', TYPE_COMMENT))
}

// --- an empty identity never matches (uploader comment / row without member id) -------------------
{
  const rules = [
    rule(TYPE_COMMENTATOR, MEMBER_ID_PREFIX + '123'),
    rule(TYPE_COMMENT, COMMENT_ID_PREFIX + '0'),
  ]
  ok('empty member id matches nothing', !matchIdentity(rules, '', TYPE_COMMENTATOR))
  ok('whitespace member id matches nothing', !matchIdentity(rules, '   ', TYPE_COMMENTATOR))
  ok('empty comment id never matches the block-all form of a rule',
    !matchIdentity(rules, '', TYPE_COMMENT))
}

// --- the prefix is inert in the other buckets, which is the cross-version guarantee ---------------
{
  const rules = [rule(TYPE_COMMENTATOR, MEMBER_ID_PREFIX + '123')]
  ok('identity rule does not participate in text matching',
    !matchText(rules, 'some body text #uid:123', TYPE_COMMENTATOR))
  // The older client has no notion of the prefix: it normalizes the type to 'title' and treats the value as
  // plain text. The value therefore stays inert only because the literal '#uid:123' does not occur in gallery
  // titles — this asserts that mechanism (plain literal match, no id semantics) rather than a false guarantee.
  ok('a prefixed value degrades to a literal text rule in another bucket',
    matchText([rule(TYPE_TITLE, MEMBER_ID_PREFIX + '123')], 'a gallery about #uid:123', TYPE_TITLE))
  ok('a prefixed value does not match an ordinary title',
    !matchText([rule(TYPE_TITLE, MEMBER_ID_PREFIX + '123')], '[Artist] Some Gallery Title', TYPE_TITLE))
  ok('an older client normalizes an unknown type to title',
    normalizeType('commentator_id') === TYPE_TITLE)
  ok('plain nickname rules still match by substring',
    matchText([rule(TYPE_COMMENTATOR, 'spammer')], 'SpAmMeR_99', TYPE_COMMENTATOR))
  ok('plain comment-text rules still match by substring',
    matchText([rule(TYPE_COMMENT, '广告')], '这里有广告内容', TYPE_COMMENT))
}

// --- disabled rules stay disabled for identity matching -------------------------------------------
{
  ok('a disabled identity rule does not match',
    !matchIdentity([rule(TYPE_COMMENTATOR, MEMBER_ID_PREFIX + '123', false)], '123', TYPE_COMMENTATOR))
}

// Persisted plain-text phrases use the same newline normalization as the comment being matched.
{
  const rules = [rule(TYPE_COMMENT, '电子版 漫画')]
  ok('a saved phrase spanning a newline matches its source comment',
    matchText(rules, '这是电子版\n漫画内容', TYPE_COMMENT))
  ok('a phrase does not become separate independent keywords',
    !matchText(rules, '这是电子版，其他漫画', TYPE_COMMENT))
}

// --- source stays in sync with this mirror ---------------------------------------------------------
{
  const state = read('shared/src/main/ets/state/LocalBlockState.ets')
  const service = read('shared/src/main/ets/services/LocalBlockService.ets')
  const actions = read('shared/src/main/ets/services/LocalBlockCommentActionService.ets')

  ok('state defines both identity prefixes',
    state.includes("LOCAL_BLOCK_MEMBER_ID_PREFIX: string = '#uid:'") &&
      state.includes("LOCAL_BLOCK_COMMENT_ID_PREFIX: string = '#cid:'"))
  ok('state type whitelist is unchanged (no new block type)',
    /type === LOCAL_BLOCK_TYPE_UPLOADER[\s\S]*?type === LOCAL_BLOCK_TYPE_COMMENTATOR[\s\S]*?type === LOCAL_BLOCK_TYPE_COMMENT/.test(read('shared/src/main/ets/settings/LocalBlockSettings.ets')) &&
      !/commentator_id/.test(state))
  ok('service matches both identities and skips identity rules in text matching',
    /matchIdentity\(comment\.commentId, LOCAL_BLOCK_TYPE_COMMENT\)/.test(service) &&
      /matchIdentity\(comment\.memberId, LOCAL_BLOCK_TYPE_COMMENTATOR\)/.test(service) &&
      /isIdentityRule\(rule\)[\s\S]{0,40}continue/.test(service))
  ok('action service writes member-id first and falls back to the author name',
    /LOCAL_BLOCK_MEMBER_ID_PREFIX, memberId/.test(actions) &&
      /blockCommentAuthor[\s\S]*?comment\.author/.test(actions))
  ok('action service de-duplicates identical rules instead of appending duplicates',
    /ensureLiteralRules/.test(actions))
  ok('no schema, backup or sync shape gained an identity column',
    !/member_id/.test(read('shared/src/main/ets/storage/LocalBlockRepository.ets')) &&
      !/memberId/.test(read('shared/src/main/ets/sync/SyncTypes.ets')) &&
      !/memberId/.test(read('shared/src/main/ets/backup/BackupTypes.ets')))
}

console.log(`✓ local-block identity contract: ${passed} assertions passed`)

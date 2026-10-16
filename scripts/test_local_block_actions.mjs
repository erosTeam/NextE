#!/usr/bin/env node
// Execute the production ArkTS logic with an in-memory store and injected write failures.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const ts = require(process.env.TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js')
const load = (path, dependencies) => {
  const source = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
    .replace(/^import\s[\s\S]*?from\s+['"][^'"]+['"]\s*;?\s*$/gm, '')
  const js = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
    fileName: fileURLToPath(new URL(`../${path}`, import.meta.url)),
  }).outputText
  const exports = {}
  new Function('exports', ...Object.keys(dependencies), js)(exports, ...Object.values(dependencies))
  return exports
}

class LocalBlockRule {
  id = ''; blockType = 'title'; ruleText = ''; enabled = true; enableRegex = false
}
const state = { rules: [], version: 0, filterCommentsByScore: false,
  scoreFilteringThreshold: -20, commentDisplayMode: 'hide' }
const constants = {
  LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE: 'collapse', LOCAL_BLOCK_COMMENT_DISPLAY_HIDE: 'hide',
  LOCAL_BLOCK_TYPE_TITLE: 'title', LOCAL_BLOCK_TYPE_UPLOADER: 'uploader',
  LOCAL_BLOCK_TYPE_COMMENTATOR: 'commentator', LOCAL_BLOCK_TYPE_COMMENT: 'comment',
  LOCAL_BLOCK_MEMBER_ID_PREFIX: '#uid:', LOCAL_BLOCK_COMMENT_ID_PREFIX: '#cid:',
  LocalBlockRule, connectLocalBlock: () => state,
}
const logger = { info() {}, warn() {} }
const db = new Map()
let transaction, failText = '', beforeWrite = null
const store = {
  beginTransaction() { transaction = new Map(db) },
  commit() { db.clear(); for (const [id, value] of transaction) db.set(id, value) },
  rollBack() { transaction = null },
}
const repo = load('shared/src/main/ets/storage/LocalBlockRepository.ets', {
  ...constants, LocalDataStore: { open: async () => store },
})
repo.LocalBlockRepository.nextMutationTime = async () => Date.now()
repo.LocalBlockRepository.positionForUpsert = async () => transaction.size
repo.LocalBlockRepository.writeRule = async (_store, rule, id) => {
  if (beforeWrite) { const callback = beforeWrite; beforeWrite = null; await callback() }
  if (rule.ruleText === failText) throw new Error('injected write failure')
  transaction.set(id, { ...rule })
}
repo.LocalBlockRepository.load = async () => ({ ...state, rules: [...db.values()] })
const { LocalBlockSettings } = load('shared/src/main/ets/settings/LocalBlockSettings.ets', {
  ...constants, ...repo, DiagnosticLogger: logger, SyncScheduler: { requestAfterLocalWrite() {} },
})
const { LocalBlockCommentActionService: actions } = load(
  'shared/src/main/ets/services/LocalBlockCommentActionService.ets', { ...constants, LocalBlockSettings })
const { LocalBlockService: matcher } = load('shared/src/main/ets/services/LocalBlockService.ets', {
  ...constants, LocalBlockSettings,
})
const context = {}
const rule = (text, enabled = true, regex = false, type = 'comment') =>
  Object.assign(new LocalBlockRule(), { id: `existing-${state.rules.length}`, ruleText: text,
    blockType: type, enabled, enableRegex: regex })
let passed = 0
const test = async (name, fn) => { await fn(); passed++; console.log(`✓ ${name}`) }
const reset = () => { state.rules = []; db.clear(); failText = ''; beforeWrite = null }

await test('preview/storage normalization removes all hard line separators and preserves English spaces', async () => {
  assert.equal(LocalBlockSettings.cleanText('电子版\r\n漫画\u2028Thanks\u2029again'), '电子版 漫画 Thanks again')
})
await test('disabled literal is re-enabled using its existing ID', async () => {
  reset(); state.rules = [rule('电子版', false)]
  const id = state.rules[0].id
  assert.equal(await actions.blockCommentWords(context, ['电子版']), 1)
  assert.equal(state.rules.length, 1); assert.equal(state.rules[0].enabled, true)
  assert.equal(db.get(id).enabled, true)
})
await test('case variants and duplicate phrases share one durable rule', async () => {
  reset(); assert.equal(await actions.blockCommentWords(context, ['Art', 'art', 'ART', '']), 1)
  await actions.blockCommentWords(context, ['aRt'])
  assert.equal(state.rules.length, 1); assert.equal(db.size, 1)
})
await test('a regex with the same text cannot suppress a new literal rule', async () => {
  reset(); state.rules = [rule('a(?i)b', true, true)]
  await actions.blockCommentWords(context, ['a(?i)b'])
  assert.equal(state.rules.length, 2)
  assert.equal(matcher.matchText('a(?i)b', 'comment'), true)
  state.rules = state.rules.filter(item => !item.enableRegex)
  assert.equal(matcher.matchText('ab', 'comment'), false)
})
await test('concurrent repeated actions do not create duplicate rules', async () => {
  reset(); await Promise.all([actions.blockCommentWords(context, ['同一词']),
    actions.blockCommentWords(context, ['同一词'])])
  assert.equal(state.rules.length, 1); assert.equal(db.size, 1)
})
await test('failure on the second phrase rolls back the whole transaction and visible state', async () => {
  reset(); await actions.blockCommentWords(context, ['existing'])
  failText = 'bad'; const version = state.version
  await assert.rejects(actions.blockCommentWords(context, ['first', 'bad']), /injected/)
  assert.equal(db.size, 1); assert.equal(state.rules.length, 1); assert.equal(state.version, version)
  assert.equal(state.rules[0].ruleText, 'existing')
  await LocalBlockSettings.flushForSync(context)
})
await test('a failed batch can be retried successfully', async () => {
  failText = ''; assert.equal(await actions.blockCommentWords(context, ['first', 'bad']), 2)
  assert.equal(db.size, 3); assert.equal(state.rules.length, 3)
})
await test('a newer edit during persistence is retained after the queue drains', async () => {
  reset(); beforeWrite = async () => {
    const other = rule('other'); other.id = 'other'
    void LocalBlockSettings.upsertRule(context, other)
  }
  await actions.blockCommentWords(context, ['first'])
  assert.equal(state.rules.length, 2)
})
await test('saved multiline phrases match LF and CRLF source comments', async () => {
  reset(); await actions.blockCommentWords(context, ['电子版\r\n漫画'])
  assert.equal(matcher.matchText('这是电子版\n漫画', 'comment'), true)
  assert.equal(matcher.matchText('这是电子版\r\n漫画', 'comment'), true)
  assert.equal(matcher.matchText('这是电子版，其他漫画', 'comment'), false)
})
await test('regex identity-like text remains a regex; malformed IDs remain literal text', async () => {
  reset(); state.rules = [rule('#cid:[0-9]+', true, true)]
  assert.equal(matcher.isIdentityRule(state.rules[0]), false)
  assert.equal(matcher.matchIdentity('123', 'comment'), false)
  assert.equal(matcher.matchText('see #cid:123', 'comment'), true)
  state.rules = [rule('#cid:0')]
  assert.equal(matcher.matchIdentity('0', 'comment'), false)
})
await test('user ID rules survive renames and do not match a longer ID', async () => {
  reset(); await actions.blockCommentAuthor(context, { memberId: '123', author: 'old-name' })
  assert.equal(matcher.matchIdentity('123', 'commentator'), true)
  assert.equal(matcher.matchIdentity('1234', 'commentator'), false)
})
await test('zero user IDs fall back to the name; uploader comment cannot create ID zero rule', async () => {
  reset(); assert.equal(await actions.blockCommentAuthor(context, { memberId: '0', author: 'author' }), 'name')
  assert.equal(await actions.blockComment(context, { commentId: '0' }), false)
  assert.equal(state.rules[0].ruleText, 'author')
})
console.log(`local block actions: ${passed} tests passed (production logic, injected storage failures)`)

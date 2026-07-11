#!/usr/bin/env node
/**
 * Contract: multi-request My Tags target resolution stays within its initiating account/site context.
 *
 * Scope: the resolver must stop before it continues from the root /mytags read into another tagset
 * after the request context becomes stale. A single transport GET may still retry internally; that
 * lower-level cancellation boundary is intentionally outside this focused contract.
 *
 * Run: node scripts/test_mytags_target_resolution_context_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
let failures = 0

function read(rel) {
  return readFileSync(join(ROOT, rel), 'utf8')
}

function ok(condition, message) {
  if (!condition) {
    failures += 1
    console.error(`✗ ${message}`)
  } else {
    console.log(`✓ ${message}`)
  }
}

const resolver = read('shared/src/main/ets/services/MyTagsTargetService.ets')
const gallery = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
const page = read('feature/user/src/main/ets/pages/MyTagsPage.ets')
const resolveBody = resolver.match(/static async resolve\(request: UserTagRequestContext, fullTag: string\): Promise<MyTagsTargetResolveResult \| null>\s*\{[\s\S]*?(?=\n  private static defaultTagset)/)?.[0] ?? ''
const rootReadIndex = resolveBody.indexOf("getMyTags(request.isEx, '')")
const scopedReadIndex = resolveBody.indexOf('getMyTags(request.isEx, tagset.tagsetId)')
const rootBefore = rootReadIndex >= 0 ? resolveBody.slice(0, rootReadIndex) : ''
const rootAfter = rootReadIndex >= 0 ? resolveBody.slice(rootReadIndex) : ''
const scopedBefore = scopedReadIndex >= 0 ? resolveBody.slice(0, scopedReadIndex) : ''
const scopedAfter = scopedReadIndex >= 0 ? resolveBody.slice(scopedReadIndex) : ''
const fence = /if \(!UserTagContextService\.isCurrentAuthenticated\(request\)\) \{\s*return null\s*\}/

ok(/import \{ UserTagContextService, UserTagRequestContext \} from '\.\/UserTagContextService'/.test(resolver),
  'target resolver imports the authenticated request-context fence')
ok(resolveBody.length > 0,
  'target resolver accepts the full request context and can return a stale-result sentinel')
ok(rootReadIndex >= 0 && fence.test(rootBefore) && fence.test(rootAfter),
  'root My Tags read is fenced before dispatch and after completion')
ok(scopedReadIndex >= 0 && fence.test(scopedBefore) && fence.test(scopedAfter),
  'each scoped tagset read is fenced before dispatch and after completion')
ok(!resolveBody.includes('getMyTags(isEx,'),
  'target resolver never switches to a dynamic site argument between requests')
ok(/return UserTagContextService\.isCurrentAuthenticated\(request\) \? result : null/.test(resolveBody),
  'a stale context cannot receive a completed unresolved target result')
ok(/MyTagsTargetService\.resolve\(request, tagKey\)\.then\(\(result: MyTagsTargetResolveResult \| null\)[\s\S]*if \(result === null\)[\s\S]*this\.discardMyTagsManagementIfCurrent\(request\)[\s\S]*if \(result\.found/.test(gallery),
  'gallery tag management drops a stale resolver result before reading it')
ok(/const resolved: MyTagsTargetResolveResult \| null = await MyTagsTargetService\.resolve\(request, targetTag\)[\s\S]*if \(resolved === null\)[\s\S]*this\.mytags = resolved\.mytags/.test(page),
  'My Tags page drops a stale resolver result before updating page state')
ok(!/MyTagsTargetService\.resolve\(request\.isEx/.test(gallery) &&
  !/MyTagsTargetService\.resolve\(request\.isEx/.test(page),
  'resolver call sites pass the immutable request context instead of only its site flag')

if (failures > 0) {
  console.error(`\n✗ mytags target resolution context contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ mytags target resolution context contract passed')

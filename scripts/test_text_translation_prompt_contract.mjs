#!/usr/bin/env node
/**
 * Static contract for the comment/gallery-title translation prompt profiles (Phase A scope).
 *
 * The runtime truth lives in the shared source; this script pins the invariants unit tests
 * cannot see: the four stable built-in IDs, the standard default, the request-identity scope,
 * the composer section order, and the custom-store rejection boundary.
 * Run: node scripts/test_text_translation_prompt_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'

const read = (p) => readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')

const model = read('shared/src/main/ets/model/TextTranslationPromptProfile.ets')
const catalog = read('shared/src/main/ets/services/TextTranslationPromptCatalog.ets')
const contract = read('shared/src/main/ets/services/TextTranslationPromptContract.ets')
const codec = read('shared/src/main/ets/services/TextTranslationPromptCodec.ets')
const composer = read('shared/src/main/ets/services/TextTranslationPromptComposer.ets')
const barrel = read('shared/src/main/ets/Index.ets')

assert.match(model, /TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION: number = 1/)
assert.match(model, /TEXT_TRANSLATION_CONTENT_COMMENT: string = 'comment'/)
assert.match(model, /TEXT_TRANSLATION_CONTENT_GALLERY_TITLE: string = 'gallery_title'/)

const builtInIds = [...catalog.matchAll(/TEXT_TRANSLATION_PROMPT_BUILTIN_\w+: string = '(builtin\.[a-z_]+)'/g)].map((m) => m[1])
assert.equal(builtInIds.length, 4, 'four built-in id constants')
assert.equal(new Set(builtInIds).size, 4, 'unique built-in IDs')
assert.ok(builtInIds.includes('builtin.standard'), 'standard built-in id present')

assert.match(catalog, /defaultProfileId\(\): string \{\s*return TEXT_TRANSLATION_PROMPT_BUILTIN_STANDARD/, 'standard is the default')
assert.match(catalog, /profile\.builtIn = true/, 'built-ins are created read-only')
assert.ok(!/preferences|StorageKeys|getPreferences/.test(catalog), 'built-in catalog never persists')

assert.match(
  model,
  /requestIdentity\(\): string \{[^}]*JSON\.stringify\(\s*\[this\.promptProfileId,\s*this\.promptRevision\]\s*\)/s,
  'request identity is id + revision only',
)
assert.doesNotMatch(model, /requestIdentity\(\)\s*\{[\s\S]{0,160}\bdisplayName\b/, 'request identity excludes display name')

assert.match(contract, /MAX_TEXT_TRANSLATION_CUSTOM_PROFILES: number = 32/)
assert.match(contract, /MAX_TEXT_TRANSLATION_PROMPT_ID_CHARS: number = 160/)
assert.match(contract, /MAX_TEXT_TRANSLATION_PROMPT_NAME_CHARS: number = 120/)
assert.match(contract, /MAX_TEXT_TRANSLATION_STYLE_CHARS: number = 8192/)
assert.match(contract, /MAX_TEXT_TRANSLATION_CUSTOM_STORE_CHARS: number = 256 \* 1024/)
assert.match(contract, /startsWith\('builtin\.'/, 'contract reserves the builtin. prefix')

assert.match(codec, /value\.builtIn = false/, 'codec clears the built-in flag on decode')

assert.match(
  composer,
  /invariantProtocol\(targetLang\)[\s\S]{0,80}\+ task[\s\S]{0,40}\+ style/,
  'composer order: protocol, task, style',
)
assert.doesNotMatch(composer, /sourceText|userMessage/, 'composer never accepts the source text')

const expectedExports = [
  'TextTranslationPromptProfile',
  'TextTranslationPromptCatalog',
  'TextTranslationPromptContract',
  'TextTranslationPromptCodec',
  'TextTranslationPromptComposer',
  'TEXT_TRANSLATION_PROMPT_BUILTIN_STANDARD',
]
for (const name of expectedExports) {
  assert.ok(barrel.includes(name), `barrel exports ${name}`)
}

console.log('✓ text translation prompt profile contract passed')

#!/usr/bin/env node
/**
 * Contract for the comment-translation language pre-check.
 *
 * A local (network-free) language detector gates AUTO-translation: comments already in the current UI
 * language are not auto-translated (the user can already read them). The MANUAL translate button is NOT
 * gated — the user can still force a translation of a same-language comment.
 *
 * Run: node scripts/test_comment_language_gate_contract.mjs
 */
import fs from 'fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

const svc = read('shared/src/main/ets/services/CommentTranslationService.ets')

ok('service exposes a static needsTranslation pre-check', /static needsTranslation\(text: string\): boolean/.test(svc))
ok('needsTranslation compares the detected script to the target family, translating when unknown',
  /static needsTranslation\(text: string\): boolean \{[\s\S]*detectScript\(t\)[\s\S]*if \(script === 'unknown'\)\s*\{[\s\S]*return true[\s\S]*return script !== CommentTranslationService\.targetScriptFamily\(\)/.test(svc))
ok('target family folds zh-CN/zh-TW into one Chinese family (variant never auto-translates)',
  /private static targetScriptFamily\(\): string \{[\s\S]*target\.startsWith\('zh'\)[\s\S]*return 'zh'/.test(svc))
ok('script detector classifies kana, hangul, han and latin over the BMP',
  /private static detectScript\(text: string\): string/.test(svc) &&
    /0x3040[\s\S]*0x309f[\s\S]*0x30a0[\s\S]*0x30ff/.test(svc) && // kana
    /0xac00[\s\S]*0xd7a3/.test(svc) && // hangul
    /0x4e00[\s\S]*0x9fff/.test(svc) && // han
    /0x41[\s\S]*0x5a[\s\S]*0x61[\s\S]*0x7a/.test(svc)) // latin
ok('detector resolves kana before han so kanji-bearing Japanese is not mistaken for Chinese',
  /if \(kana > 0\)\s*\{\s*return 'ja'[\s\S]*if \(hangul > 0\)\s*\{\s*return 'ko'[\s\S]*if \(han > 0\)\s*\{\s*return 'zh'[\s\S]*if \(latin > 0\)\s*\{\s*return 'latin'/.test(svc))

const card = read('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets')

ok('auto-translate skips comments already in the current language',
  /autoTranslateVisibleComments\(\): void \{[\s\S]*!CommentTranslationService\.needsTranslation\([^)]+\)[\s\S]*continue[\s\S]*publishAutoTranslate/.test(card))
ok('the manual translate button is NOT gated by needsTranslation (still shown for any non-empty comment)',
  /this\.translationEnabled\(\) && c\.contentText\.trim\(\)\.length > 0\)\s*\{\s*this\.TranslationAction\(c\)/.test(card) &&
    !/needsTranslation[\s\S]{0,40}TranslationAction/.test(card))

if (failures === 0) {
  console.log('✓ comment language gate contract passed')
  process.exit(0)
}
console.error(`✗ comment language gate contract: ${failures} failure(s)`)
process.exit(1)

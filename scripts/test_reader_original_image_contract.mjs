#!/usr/bin/env node
/**
 * Contract: Reader "view original" is an explicit current-page action.
 *
 * FE grounding:
 * - eros_fe reader long-press image sheet exposes the parsed `originImageUrl` as "Original".
 * - Original image links come from the /s/ image page or showpage response, not URL guessing.
 *
 * NextE boundary:
 * - Default reader display/share/save stays resampled.
 * - Tapping the original-image toolbar action enables original only for the current page.
 * - The single, double, and vertical reader image components all load through resolveOriginal().
 *
 * Run: node scripts/test_reader_original_image_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    console.error(`✗ ${msg}`)
    failures++
  }
}

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const resolver = read('shared/src/main/ets/services/ImageResolveService.ets')
const parser = read('shared/src/main/ets/parser/EhImagePageParser.ets')
const strings = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
].map(read)

ok(parser.includes('RE_ORIGIN') && parser.includes('/fullimg') && parser.includes('originImageUrl = og[1]'),
  'image-page parser extracts /fullimg origin links')
ok(parser.includes('RE_SP_ORIGIN') && parser.includes('og[1].replace(/&amp;/g, \'&\')'),
  'showpage parser extracts /fullimg origin links from i6')
ok(/async resolveOriginal\(image: EhGalleryImage\): Promise<string>/.test(resolver),
  'ImageResolveService exposes resolveOriginal')
ok(/this\.resolved\.get\(image\.sUrl\)/.test(resolver) &&
  /await this\.doResolve\(image, false\)/.test(resolver) &&
  /original image unavailable/.test(resolver),
  'resolveOriginal reuses cached metadata, then falls back to the normal /s/showpage resolve path')
ok(/resolve_original/.test(resolver) && /\/fullimg/.test(resolver),
  'resolveOriginal logs fullimg evidence')

ok(/@Local originalImagePages: string = ''/.test(reader),
  'Reader tracks original display per page, not as a global all-page mode')
ok(/private toggleOriginalImage\(\): void/.test(reader) &&
  /ImageResolveService\.getInstance\(\)\s*\.\s*resolveOriginal\(image\)/.test(reader),
  'toolbar action resolves original before enabling display')
ok(/setOriginalModeForPage\(image\.page, true\)/.test(reader) &&
  /setOriginalModeForPage\(image\.page, false\)/.test(reader),
  'toolbar action toggles only the current image page')
ok(/arrow_outward_and_rectangle[\s\S]*this\.toggleOriginalImage\(\)/.test(reader),
  'Reader bottom toolbar exposes the original-image action as a real toolbar icon')
ok(/currentDisplayUrl\(image\)/.test(reader) &&
  /resolveCurrentDisplayUrl\(image\)/.test(reader),
  'share/save use the current display source instead of always preferring original')

ok((reader.match(/@Param preferOriginal: boolean = false/g) || []).length >= 3,
  'single, double-spread layer, and vertical image components accept preferOriginal')
ok((reader.match(/@Monitor\('preferOriginal'\)/g) || []).length >= 3,
  'reader image components reload when original mode changes')
ok((reader.match(/resolveOriginal\(this\.image\)/g) || []).length >= 3,
  'all reader image render paths load original through ImageResolveService')
ok(/firstPreferOriginal/.test(reader) && /secondPreferOriginal/.test(reader),
  'double-page reader passes original state separately for both pages')
ok(/display_original/.test(reader),
  'image components log original display evidence')

strings.forEach((s, i) => {
  ok(s.includes('"name": "reader_original_unavailable"'), `locale ${i}: original unavailable string exists`)
})

if (failures > 0) {
  console.error(`\n✗ reader original-image contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ reader original-image contract passed')

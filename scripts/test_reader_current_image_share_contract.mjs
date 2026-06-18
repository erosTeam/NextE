#!/usr/bin/env node
/**
 * Contract: the reader top-bar share action shares the current image, not only the gallery URL.
 *
 * eros_fe ViewTopBar calls tapShare(), which shares the current GalleryImage's image/original URL.
 * NextE must reuse the existing /s/ -> full-image resolver and only fall back to gallery sharing when
 * the current page cannot be resolved.
 *
 * Run: node scripts/test_reader_current_image_share_contract.mjs
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
const share = read('shared/src/main/ets/utils/ShareUtil.ets')

ok(/private currentImage\(\): EhGalleryImage \| null/.test(reader), 'Reader exposes a bounded currentImage helper')
ok(/this\.vm\.currentIndex < 0 \|\| this\.vm\.currentIndex >= this\.vm\.images\.length/.test(reader),
  'currentImage clamps against the loaded image array')
ok(/private shareCurrentImage\(\): void/.test(reader), 'Reader has a current-image share action')
ok(/image\.originImageUrl\.length > 0 \? image\.originImageUrl : image\.imageUrl/.test(reader),
  'current-image share prefers originImageUrl before imageUrl')
ok(/ImageResolveService\.getInstance\(\)\s*\.\s*resolve\(image\)/.test(reader),
  'current-image share resolves an unresolved /s/ page before sharing')
ok(/image\.originImageUrl\.length > 0 \? image\.originImageUrl : imageUrl/.test(reader),
  'after resolve, share still prefers the newly parsed originImageUrl')
ok(/share_image_resolve_failed/.test(reader) && /this\.shareGallery\(\)/.test(reader),
  'resolve failure logs and falls back to gallery sharing')
ok(/this\.shareCurrentImage\(\)/.test(reader) && !/onClick\(\(\) => \{\s*this\.shareGallery\(\)\s*\}\)/.test(reader),
  'top-bar share button is wired to current-image sharing')

ok(/static shareUrl\(/.test(share), 'ShareUtil exposes reusable URL sharing')
ok(/utd\.UniformDataType\.HYPERLINK/.test(share), 'URL sharing uses hyperlink UTD')
ok(/ShareUtil\.shareUrl\(context, url, title\)/.test(share), 'shareGallery delegates to shareUrl')

if (failures > 0) {
  console.error(`\n✗ reader current-image share contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ reader current-image share contract: 11 assertions passed')

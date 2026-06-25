#!/usr/bin/env node
/**
 * Contract: the reader top-bar share action shares the current image, not only the gallery URL.
 *
 * eros_fe ViewTopBar calls tapShare(), which shares from the current GalleryImage. NextE must share the
 * currently displayed source: resampled by default, original only after the user explicitly enables it.
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
ok(/if \(!this\.vm\.hasPreviewAt\(this\.vm\.currentIndex\)\) \{[\s\S]*return null[\s\S]*return this\.vm\.imageAt\(this\.vm\.currentIndex\)/.test(reader),
  'currentImage clamps through the ReaderViewModel preview guard')
ok(/private shareCurrentImage\(\): void/.test(reader), 'Reader has a current-image share action')
ok(/const alreadyResolvedUrl: string = this\.currentDisplayUrl\(image\)/.test(reader),
  'current-image share uses the current display source')
ok(/this\.resolveCurrentDisplayUrl\(image\)/.test(reader),
  'current-image share resolves the current display source before sharing')
ok(/ShareUtil\.shareUrl\(this\.hostContext\(\), imageUrl, title\)/.test(reader),
  'after resolve, share uses the resolved display source directly')
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

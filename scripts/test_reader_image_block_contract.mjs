#!/usr/bin/env node
import assert from 'node:assert'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

function readFirst(paths) {
  for (const p of paths) {
    const full = join(ROOT, p)
    if (existsSync(full)) {
      return readFileSync(full, 'utf8')
    }
  }
  throw new Error(`missing reference file: ${paths.join(' or ')}`)
}

function section(source, name) {
  const start = source.indexOf(`struct ${name}`)
  assert.notEqual(start, -1, `${name} section must exist`)
  const next = source.indexOf('\n@ComponentV2', start + 1)
  return source.slice(start, next === -1 ? source.length : next)
}

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const routeParams = read('shared/src/main/ets/model/RouteParams.ets')
const grounding = read('docs/plans/active/ui-grounding.md')
const erosWidget = readFirst([
  '../eros_fe/lib/pages/image_view/view/view_widget.dart',
  '../../eros_fe/lib/pages/image_view/view/view_widget.dart',
])
const erosImage = readFirst([
  '../eros_fe/lib/pages/image_view/view/view_image.dart',
  '../../eros_fe/lib/pages/image_view/view/view_image.dart',
])

assert.match(erosWidget, /class ViewAD/, 'FE reference must still expose ViewAD hidden-image placeholder')
assert.match(erosWidget, /_ImageWithHideState/, 'FE reference must still hide image widgets after block checks')
assert.match(erosImage, /imageFromState\?\.hide/, 'FE reader must still branch on hidden image state')

assert.match(grounding, /Active: reader image block placeholder/, 'UI grounding must record reader image block placeholder lane')
assert.match(grounding, /ImageBlockRuntimeService/, 'grounding must name the reused runtime service')
assert.match(grounding, /whitelist escape action/, 'grounding must record the false-positive whitelist escape action')
assert.match(grounding, /visible but unreadable blurred preview/, 'grounding must record the blurred hidden-image presentation')
assert.match(grounding, /HDS floating controls[\s\S]*stay separate lanes/, 'grounding must keep HDS floating controls out of this presentation slice')

assert.match(reader, /ImageBlockDecision/, 'Reader must import image block decisions')
assert.match(reader, /ImageBlockRuntimeService/, 'Reader must import image block runtime service')
assert.match(reader, /readerImageBlockDecisionForFile/, 'Reader must isolate runtime decision failure handling')
assert.match(reader, /markCurrentImageAsBlocked/, 'Reader must expose a current-page local image-block action')
assert.match(reader, /addLocalRuleForFile/, 'Reader local mark action must reuse the runtime local rule helper')
assert.match(reader, /this\.showChrome = p\.initialChromeVisible/, 'Reader must support the QA-only initial chrome flag')
assert.match(routeParams, /initialChromeVisible:\s+boolean\s*=\s*false/, 'ReaderParams initial chrome flag must default to false')
assert.match(reader, /allowImageBlockForPage/, 'Reader must expose a blocked-page false-positive allow action')
assert.match(reader, /addWhitelistForFile/, 'Reader allow action must reuse the runtime whitelist helper')
assert.match(reader, /@Local\s+currentImageBlocked:\s+boolean\s*=\s*false/, 'Reader must track whether the current page is showing a blocked placeholder')
assert.match(reader, /rememberImageBlockState/, 'Reader must remember blocked-placeholder state by page')
assert.match(reader, /if\s*\(!this\.currentImageBlocked\)\s*{[\s\S]*this\.ReaderTapOverlay\(\)/, 'Reader tap overlay must stay out of the way while the blocked placeholder is visible')
assert.match(reader, /currentGallerySourceUrl/, 'Reader local mark action must attach a public gallery source URL')
assert.match(reader, /image\.page/, 'Reader local mark action must attach the source page number')
assert.match(reader, /sys\.symbol\.eye_slash/, 'Reader local mark action must use the existing hide-image symbol')
assert.match(reader, /imageBlockRuleVersion\+\+/, 'Reader must re-run cached image decisions after adding a local rule')
assert.doesNotMatch(reader, /Qr|QR|QRCode|qrCode|scanQr/i, 'Reader image block integration must not add QR scanning in this lane')

for (const name of ['ReaderSpreadImageLayer', 'ReaderImagePage', 'ReaderVerticalImage']) {
  const body = section(reader, name)
  assert.match(body, /@Local\s+imageBlocked:\s+boolean\s*=\s*false/, `${name} must track a blocked-image state`)
  assert.match(body, /@Local\s+imageBlockPreviewUri:\s+string\s*=\s*''/, `${name} must keep a local display URI for blurred blocked previews`)
  assert.match(body, /onImageFileReady/, `${name} must report loaded local files for manual local rules`)
  assert.match(body, /onImageBlockState/, `${name} must report blocked-placeholder state to the Reader parent`)
  assert.match(body, /cached\.filePath,[\s\S]*cached\.bytes,[\s\S]*cached\.displayUri,[\s\S]*seq/, `${name} must check cached files before rendering and keep a blocked-preview display URI`)
  assert.match(body, /result\.filePath,[\s\S]*result\.bytes,[\s\S]*result\.displayUri,[\s\S]*seq/, `${name} must check freshly loaded files before rendering and keep a blocked-preview display URI`)
  assert.match(body, /onImageBlockState\(this\.image\.page,\s*false\)/, `${name} must clear parent blocked state when the image is allowed`)
  assert.match(body, /onImageBlockState\(this\.image\.page,\s*true\)/, `${name} must set parent blocked state when the placeholder is shown`)
  assert.match(body, /this\.imageBlockPreviewUri\s*=\s*displayUri/, `${name} must pass the local image preview to the blocked overlay`)
  assert.match(body, /this\.onImageLoaded\(this\.image\.page\)/, `${name} must mark blocked pages as loaded`)
  assert.match(body, /ReaderImageBlockedOverlay/, `${name} must render the blocked placeholder`)
  assert.match(body, /onAllowImageBlock/, `${name} must forward blocked-page false-positive allow actions`)
}

const overlay = section(reader, 'ReaderImageBlockedOverlay')
const allowButtonBlocks = overlay.match(/Button\(\$r\('app\.string\.reader_image_block_allow'\)\)[\s\S]*?(?:\.enabled\(false\)|\.onClick\()/g) || []
assert.match(overlay, /@Param\s+previewUri:\s+string\s*=\s*''/, 'blocked overlay must accept a local preview URI')
assert.match(overlay, /Image\(this\.previewUri\)[\s\S]*\.objectFit\(ImageFit\.Contain\)[\s\S]*\.scale\(\{\s*x:\s*1\.02,\s*y:\s*1\.02\s*\}\)[\s\S]*\.blur\([\s\S]*\.opacity\(/, 'blocked overlay must show a blurred contained image rather than falling back to a plain canvas')
assert.doesNotMatch(overlay, /objectFit\(ImageFit\.Cover\)/, 'blocked overlay must not use a full-screen cover background preview')
assert.doesNotMatch(overlay, /backgroundColor\('#EE000000'\)/, 'blocked overlay must not use the near-black scrim that hides the blurred preview entirely')
assert.match(overlay, /backgroundColor\(Color\.Black\)/, 'blocked overlay must retain a black fallback when no preview URI exists')
assert.match(overlay, /reader_image_blocked/, 'blocked overlay must have a localized title')
assert.match(overlay, /reader_image_blocked_hint/, 'blocked overlay must have a localized hint')
assert.match(overlay, /reader_image_block_allow/, 'blocked overlay must expose a localized allow action')
assert.match(overlay, /Button\(\$r\('app\.string\.reader_image_block_allow'\)\)/, 'blocked overlay allow action must use a native localized text Button')
assert.equal(allowButtonBlocks.length, 2, 'blocked overlay must keep one disabled and one active native allow button path')
for (const block of allowButtonBlocks) {
  assert.doesNotMatch(
    block,
    /\.(?:height|constraintSize|padding|fontSize|fontWeight|fontColor|backgroundColor|border)\(/,
    'blocked overlay allow button must keep native Button styling instead of custom visual layers',
  )
}
assert.match(overlay, /onAllow\(this\.page\)/, 'blocked overlay allow action must report its page')
assert.match(overlay, /Text\(`P\$\{this\.page\}`\)/, 'blocked overlay must keep the page-number affordance')
assert.doesNotMatch(overlay, /ImageBlockContributionService|buildJsonl|GitHub|pull request|PR/, 'blocked overlay must not bundle contribution or PR management')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  assert.match(strings, /"name": "reader_image_blocked"/, `${locale} must define reader_image_blocked`)
  assert.match(strings, /"name": "reader_image_blocked_hint"/, `${locale} must define reader_image_blocked_hint`)
  assert.match(strings, /"name": "reader_image_block_mark_added"/, `${locale} must define reader_image_block_mark_added`)
  assert.match(strings, /"name": "reader_image_block_allow"/, `${locale} must define reader_image_block_allow`)
  assert.match(strings, /"name": "reader_image_block_allowed"/, `${locale} must define reader_image_block_allowed`)
  assert.match(strings, /"name": "reader_image_block_allow_failed"/, `${locale} must define reader_image_block_allow_failed`)
}

console.log('✓ reader image block contract passed')

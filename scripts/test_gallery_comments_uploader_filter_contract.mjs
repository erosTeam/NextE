#!/usr/bin/env node
/**
 * Contract: full comments page has a read-only "uploader only" filter.
 *
 * Grounding:
 * - eros_fe CommentPage._filterComments uses showOnlyUploaderComment and narrows comments by
 *   the uploader comment's memberId when available.
 * - NextE keeps this as a page-local read filter in the comments title menu; it must not add
 *   comment write actions.
 *
 * Run: node scripts/test_gallery_comments_uploader_filter_contract.mjs
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

const page = read('feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets')

ok('comments page owns a page-local uploaderOnly filter state',
  /@Local uploaderOnly: boolean = false/.test(page))
ok('uploader filter derives the uploader memberId from parsed uploader comment metadata',
  /private uploaderMemberId\(\): string[\s\S]*this\.comments\.find\(\(c: EhGalleryComment\) => c\.isUploader\)[\s\S]*uploader\.memberId/.test(page))
ok('visible comments use uploader memberId first and isUploader fallback',
  /private visibleComments\(\): EhGalleryComment\[\][\s\S]*!this\.uploaderOnly[\s\S]*return this\.comments[\s\S]*c\.memberId === memberId[\s\S]*c\.isUploader/.test(page))
ok('comments page title menu exposes all/uploader labels',
  /private commentsTitleBar\(\): Record<string, Object>[\s\S]*comment_filter_uploader_only/.test(page) &&
    /private commentsTitleBar\(\): Record<string, Object>[\s\S]*comment_filter_all/.test(page))
ok('comments page title menu uses native menu symbols and checkmark active state',
  /sys\.symbol\.person/.test(page) &&
    /sys\.symbol\.list_bullet_square_fill/.test(page) &&
    /sys\.symbol\.checkmark/.test(page) &&
    /immersiveTitleBarOpts/.test(page))
ok('GalleryCommentsCard receives visibleComments rather than mutating the parsed comments list',
  /GalleryCommentsCard\(\{[\s\S]*comments: this\.visibleComments\(\)/.test(page))
ok('uploader-only filter remains read-only',
  !/vote_comment|edit_comment|reply_comment|post_comment|submitComment|rategallery|addfav/.test(page))

for (const locale of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(`${locale} has uploader-only filter string`, /"name": "comment_filter_uploader_only"/.test(strings))
  ok(`${locale} has all-comments filter string`, /"name": "comment_filter_all"/.test(strings))
}

if (failures === 0) {
  console.log('✓ gallery comments uploader filter contract passed')
  process.exit(0)
}
console.error(`✗ gallery comments uploader filter contract: ${failures} failure(s)`)
process.exit(1)

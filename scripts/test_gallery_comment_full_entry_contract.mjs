#!/usr/bin/env node
/**
 * Contract: detail-page comment peeks can always open the full comments page.
 *
 * One- and two-comment galleries still render clamped peek rows (`max: 2`), so "has more than peek"
 * must not be the same condition as "can open full comments".
 *
 * Run: node scripts/test_gallery_comment_full_entry_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const card = readFileSync(join(ROOT, 'feature/gallery/src/main/ets/components/GalleryCommentsCard.ets'), 'utf8')
const detail = readFileSync(join(ROOT, 'feature/gallery/src/main/ets/pages/GalleryDetailPage.ets'), 'utf8')

let failures = 0
let passed = 0

function ok(label, condition) {
  if (condition) {
    passed++
  } else {
    failures++
    console.error(`✗ ${label}`)
  }
}

ok('detail page still uses a two-comment peek with a full-comments callback',
  /GalleryCommentsCard\(\{[\s\S]*comments:\s*this\.visiblePreviewComments\(\)[\s\S]*referenceComments:\s*this\.vm\.comments[\s\S]*max:\s*2[\s\S]*onMore:\s*\(\) => \{[\s\S]*this\.openComments\(\)/.test(detail))
ok('comments card separates has-more from can-open-full-comments',
  /private hasMore\(\): boolean \{\s*return this\.max > 0 && this\.sourceComments\(\)\.length > this\.max\s*\}/.test(card) &&
    /private canOpenFullComments\(\): boolean \{\s*return this\.max > 0 && this\.sourceComments\(\)\.length > 0\s*\}/.test(card))
ok('peek header shows full-comments affordance whenever any peek comment exists',
  /if \(this\.canOpenFullComments\(\)\) \{[\s\S]*Text\(\$r\('app\.string\.detail_view_all'\)\)[\s\S]*SymbolGlyph\(\$r\('sys\.symbol\.chevron_right'\)\)/.test(card))
ok('peek header click opens full comments for one/two-comment galleries',
  /\.onClick\(\(\) => \{\s*if \(this\.canOpenFullComments\(\)\) \{\s*this\.onMore\(\)/.test(card))
ok('comment bubble provides a broad full-comments tap target in peek mode',
  /CommentRow\(c: EhGalleryComment[\s\S]*\.backgroundColor\(\$r\('app\.color\.card_background'\)\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*if \(this\.canOpenFullComments\(\)\) \{[\s\S]*this\.onMore\(\)/.test(card))
ok('peek comment text does not consume the card tap target',
  /CommentText\(c: EhGalleryComment, text: string, clamp: boolean, color: ResourceColor\)[\s\S]*if \(clamp\) \{[\s\S]*\.maxLines\(4\)[\s\S]*\.textOverflow\(\{ overflow: TextOverflow\.Ellipsis \}\)[\s\S]*\} else \{[\s\S]*Span\(seg\.text\)[\s\S]*this\.openCommentUrl\(seg\.url\)/.test(card) &&
    !/firstCommentUrl\(text: string\)/.test(card))
ok('html anchor comment links keep label text while clicking the stored href',
  /EhGalleryCommentLink/.test(card) &&
    /c\.contentLinks\.length > 0/.test(card) &&
    /new CommentTextSegment\(`h\$\{nextSeq\+\+\}`, text\.substring\(start, end\), link\.url\)/.test(card) &&
    /this\.openCommentUrl\(seg\.url\)/.test(card))
ok('full comments page remains full mode and does not pass max/onMore',
  /LazyForEach\(\s*this\.commentSource[\s\S]*GalleryCommentsCard\(\{[\s\S]*referenceComments:\s*this\.comments[\s\S]*useSingleComment:\s*true[\s\S]*singleComment:\s*comment[\s\S]*onAuthor:/.test(readFileSync(join(ROOT, 'feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets'), 'utf8')) &&
    !/GalleryCommentsCard\(\{[\s\S]*max:\s*2/.test(readFileSync(join(ROOT, 'feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets'), 'utf8')))

if (failures > 0) {
  console.error(`\n✗ gallery comment full entry contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log(`✓ gallery comment full entry contract: ${passed} assertions passed`)

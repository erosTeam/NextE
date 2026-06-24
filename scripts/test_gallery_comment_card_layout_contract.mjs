#!/usr/bin/env node
/**
 * Contract: gallery comments render as one white card per comment, not as nested cards inside a
 * larger section card. Detail peeks and the full comments page both reuse V2Next's tight reply-list gap.
 *
 * Grounding:
 * - V2Next shared ReplyCard renders top-level replies on app.color.card_background.
 * - V2Next HotRepliesPanel keeps the section header outside the reply cards and uses a tighter in-panel
 *   list gap.
 * - NextE detail comments expose only two comment cards, and the full comments page is the same reply
 *   family, so both surfaces keep the same close card-to-card interval.
 *
 * Run: node scripts/test_gallery_comment_card_layout_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const card = read('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets')
const grounding = read('docs/plans/active/ui-grounding.md')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok('active UI grounding records the comment card refactor',
  /Active: gallery detail comment cards/.test(grounding) &&
  /ReplyCard\.ets/.test(grounding) &&
  /HotRepliesPanel\.ets/.test(grounding) &&
  /white card/.test(grounding) &&
  /quoted replies sit on a secondary gray block/.test(grounding))

ok('GalleryCommentsCard no longer imports or renders the outer GroupedListSection chrome',
  !/GroupedListSection/.test(card))

ok('comment gap matches V2Next hot-reply spacing on both detail and full comments surfaces',
  /private commentGap\(\): number \{[\s\S]*return ThemeConstants\.SPACE_SM - 2/.test(card) &&
  /Column\(\{ space: this\.commentGap\(\) \}\)/.test(card))

ok('section header is outside comment cards and keeps full-comments affordance',
  /following Next2V's HotRepliesPanel[\s\S]*Row\(\{ space: ThemeConstants\.SPACE_XS \}\)[\s\S]*Text\(\$r\('app\.string\.gallery_comments'\)\)[\s\S]*if \(this\.canOpenFullComments\(\)\)/.test(card))

ok('each comment row is its own top-level white card',
  /CommentRow\(c: EhGalleryComment[\s\S]*\.borderRadius\(ThemeConstants\.RADIUS_CARD\)[\s\S]*\.backgroundColor\(\$r\('app\.color\.card_background'\)\)/.test(card))

ok('detail peek comment cards have extra bottom padding for the larger corner radius',
  /private commentBottomPadding\(\): number \{[\s\S]*this\.max > 0 \? ThemeConstants\.SPACE_MD : ThemeConstants\.SPACE_SM/.test(card) &&
  /bottom: this\.commentBottomPadding\(\)/.test(card))

ok('reply quote inverts the old color relation and sits on the secondary surface inside the white card',
  /COMMENT_QUOTE_RADIUS: number = 8/.test(read('shared/src/main/ets/theme/ThemeConstants.ets')) &&
  /ReplyQuote\(c: EhGalleryComment\)[\s\S]*\.borderRadius\(ThemeConstants\.COMMENT_QUOTE_RADIUS\)[\s\S]*\.backgroundColor\(ThemeConstants\.BG_SUB\)/.test(card) &&
  !/ReplyQuote\(c: EhGalleryComment\)[\s\S]*\.backgroundColor\(ThemeConstants\.BG_PRIMARY\)/.test(card))

ok('peek cards remain broad tap targets for opening full comments',
  /CommentRow\(c: EhGalleryComment[\s\S]*\.onClick\(\(\) => \{[\s\S]*if \(this\.canOpenFullComments\(\)\) \{[\s\S]*this\.onMore\(\)/.test(card))

console.log(`✓ gallery comment card layout contract: ${passed} assertions passed`)

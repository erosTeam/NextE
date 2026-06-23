#!/usr/bin/env node
/**
 * Contract: full GalleryComments page supports bounded new/reply/edit comment composition.
 *
 * Grounding:
 * - eros_fe request.dart::postComment posts /g/{gid}/{token} with commenttext_new for new/reply and
 *   commenttext_edit + edit_comment for edit.
 * - eros_fe CommentController.reptyComment only pre-fills @user + encoded comment id; it still submits
 *   as a new comment.
 * - eros_fe CommentController.editComment pre-fills the original text and submits with edit_comment.
 *
 * NextE scope for this lane: new comment, reply prefill, and own-comment edit.
 */
import fs from 'fs'
import path from 'path'

const ROOT = path.resolve(new URL('..', import.meta.url).pathname)
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8')

let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

const api = read('shared/src/main/ets/network/EhApiService.ets')
ok('EhApiService exposes gallery comment write request semantics',
  /export interface GalleryCommentWrite[\s\S]*gid: string[\s\S]*token: string[\s\S]*comment: string[\s\S]*commentId: string[\s\S]*isEdit: boolean/.test(api))
ok('comment write posts to the gallery detail URL as a form',
  /async postGalleryComment\(update: GalleryCommentWrite\): Promise<void>/.test(api) &&
    /`\$\{base\}\/g\/\$\{encodeURIComponent\(update\.gid\)\}\/\$\{encodeURIComponent\(update\.token\)\}`/.test(api) &&
    /postFormUrlEncoded\(url, pairs\.join\('&'\)\)/.test(api))
ok('new and reply comments use commenttext_new while edit stays separate',
  /pairs\.push\(this\.formPair\('commenttext_new', comment\)\)/.test(api) &&
    /pairs\.push\(this\.formPair\('commenttext_edit', comment\)\)/.test(api) &&
    /pairs\.push\(this\.formPair\('edit_comment', update\.commentId\)\)/.test(api))
ok('comment write validates minimum text and gallery identity before posting',
  /comment\.length < 10/.test(api) &&
    /update\.gid\.length === 0 \|\| update\.token\.length === 0/.test(api))

const barrel = read('shared/src/main/ets/Index.ets')
ok('GalleryCommentWrite is exported from shared barrel',
  /GalleryCommentWrite/.test(barrel))

const page = read('feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets')
ok('comments page owns bottom composer state for new, reply, and edit',
  /@Local commentText: string = ''/.test(page) &&
    /@Local commentReplyToId: string = ''/.test(page) &&
    /@Local commentEditId: string = ''/.test(page) &&
    /@Local commentEditOriginal: string = ''/.test(page) &&
    /@Local commentSubmitting: boolean = false/.test(page) &&
    !/@Local commentSheetShown: boolean = false/.test(page))
ok('comments page gates comment compose on route identity and login cookies',
  /private canOpenCommentSheet\(\): boolean[\s\S]*this\.params\.gid\.length > 0[\s\S]*this\.params\.token\.length > 0[\s\S]*EhCookieStore\.getInstance\(\)\.isLogin\(\)/.test(page))
ok('new and reply composition use the bottom floating composer, not the title action sheet',
  /Stack\(\{ alignContent: Alignment\.Bottom \}\)[\s\S]*this\.CommentComposer\(\)/.test(page) &&
    /@Builder[\s\S]*CommentComposer\(\)[\s\S]*TextArea\(\{[\s\S]*placeholder: this\.commentPlaceholder\(\)[\s\S]*sys\.symbol\.arrow_up_circle_fill/.test(page) &&
    !/const newComment: Record<string, Object> = \{[\s\S]*comment_new_title[\s\S]*this\.openNewComment\(\)/.test(page))
ok('reply action pre-fills @author plus encoded comment id and still submits as new comment',
  /private openReplyComment\(comment: EhGalleryComment\): void[\s\S]*this\.commentReplyToId = comment\.commentId[\s\S]*this\.commentText = `@\$\{comment\.author\}\\n\$\{this\.encodeCommentId\(comment\.commentId\)\}\\n`/.test(page) &&
    /this\.commentReplyPreview = comment\.contentText/.test(page) &&
    /this\.commentEditId = ''/.test(page))
ok('own-comment edit pre-fills original text and submits commenttext_edit',
  /private openEditComment\(comment: EhGalleryComment\): void[\s\S]*!comment\.canEdit[\s\S]*this\.commentEditId = comment\.commentId[\s\S]*this\.commentEditOriginal = comment\.contentText[\s\S]*this\.commentText = comment\.contentText[\s\S]*this\.requestCommentFocus\(\)/.test(page) &&
    /postGalleryComment\(\{[\s\S]*commentId: this\.commentEditId[\s\S]*isEdit: this\.commentEditId\.length > 0/.test(page))
ok('edit reuses the same bottom composer context preview as replies',
  /private composerContextTitle\(\): ResourceStr[\s\S]*commentEditId\.length > 0[\s\S]*comment_edit_original[\s\S]*comment_reply_to/.test(page) &&
    /private composerContextPreview\(\): string[\s\S]*this\.commentEditOriginal : this\.commentReplyPreview/.test(page) &&
    /@Builder[\s\S]*CommentComposer\(\)[\s\S]*if \(this\.hasComposerContext\(\)\)[\s\S]*Text\(this\.composerContextTitle\(\)\)[\s\S]*Text\(this\.composerContextPreview\(\)\)/.test(page) &&
    /private commentPlaceholder\(\): ResourceStr[\s\S]*commentEditId\.length > 0[\s\S]*comment_edit_placeholder/.test(page))
ok('comment compose no longer uses the legacy edit half-modal sheet',
  !/AppModalScaffold/.test(page) &&
    !/CommentComposeSheet/.test(page) &&
    !/bindSheet\(\$\$this\.commentSheetShown/.test(page) &&
    !/commentSheetTitle/.test(page))
ok('successful comment submit refreshes the comments instead of fabricating a local row',
  /private async submitComment\(\): Promise<void>[\s\S]*await this\.refreshComments\(\)/.test(page) &&
    !/private async submitComment\(\): Promise<void>[\s\S]*new EhGalleryComment\(\)/.test(page))

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
ok('detail title menu opens full comments even when detail peek has zero comments',
  /private detailMenu\(\): Record<string, Object>[\s\S]*const commentsInner: Record<string, Object> = \{[\s\S]*gallery_comments[\s\S]*this\.openComments\(\)/.test(detail) &&
    /const commentsInner: Record<string, Object> = \{[\s\S]*sys\.symbol\.doc_plaintext/.test(detail) &&
    /const items: Record<string, Object>\[\] = \[[\s\S]*\{ 'content': commentsInner \}/.test(detail))

const card = read('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets')
ok('full comments card exposes reply event and keeps peek mode quiet',
  /@Event onReply: \(comment: EhGalleryComment\) => void/.test(card) &&
    /if \(this\.max <= 0 && c\.commentId\.length > 0 && c\.commentId !== '0'\) \{[\s\S]*this\.ReplyAction\(c\)/.test(card) &&
    /ReplyAction\(c: EhGalleryComment\)[\s\S]*sys\.symbol\.ellipsis_message/.test(card))
ok('full comments card exposes edit only for editable own comments',
  /@Event onEdit: \(comment: EhGalleryComment\) => void/.test(card) &&
    /if \(this\.max <= 0 && c\.canEdit && c\.commentId\.length > 0 && c\.commentId !== '0'\) \{[\s\S]*this\.EditAction\(c\)/.test(card) &&
    /EditAction\(c: EhGalleryComment\)[\s\S]*sys\.symbol\.square_and_pencil[\s\S]*this\.onEdit\(c\)/.test(card))
ok('comment footer actions use compact local hit sizing instead of global primary button height',
  /const COMMENT_FOOTER_ACTION_SIZE: number = \d+/.test(card) &&
    /const COMMENT_FOOTER_ICON_SIZE: number = \d+/.test(card) &&
    /const COMMENT_FOOTER_ACTION_SIZE: number = (2[8-9]|3[0-4])/.test(card) &&
    /const COMMENT_FOOTER_ICON_SIZE: number = (1[5-8])/.test(card) &&
    /FooterAction\(icon: Resource, color: ResourceColor, disabled: boolean, action: \(\) => void\)/.test(card) &&
    !/EditAction\(c: EhGalleryComment\)[\s\S]*ThemeConstants\.BUTTON_HEIGHT/.test(card) &&
    !/ReplyAction\(c: EhGalleryComment\)[\s\S]*ThemeConstants\.BUTTON_HEIGHT/.test(card) &&
    !/VoteAction\(c: EhGalleryComment[\s\S]*ThemeConstants\.BUTTON_HEIGHT/.test(card))

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'comment_new_title',
    'comment_reply_title',
    'comment_edit_title',
    'comment_send',
    'comment_new_placeholder',
    'comment_reply_placeholder',
    'comment_edit_placeholder',
    'comment_reply_to',
    'comment_edit_original',
    'comment_min_length_hint',
    'comment_post_success',
    'comment_post_failed',
    'comment_login_required',
  ]) {
    ok(`${locale} has ${key}`, strings.includes(`"name": "${key}"`))
  }
}

if (failures === 0) {
  console.log('✓ gallery comment compose contract passed')
  process.exit(0)
}
console.error(`✗ gallery comment compose contract: ${failures} failure(s)`)
process.exit(1)

#!/usr/bin/env node
/**
 * Contract: full GalleryComments page supports bounded new/reply comment composition.
 *
 * Grounding:
 * - eros_fe request.dart::postComment posts /g/{gid}/{token} with commenttext_new for new/reply and
 *   commenttext_edit + edit_comment for edit.
 * - eros_fe CommentController.reptyComment only pre-fills @user + encoded comment id; it still submits
 *   as a new comment.
 *
 * NextE scope for this lane: new comment + reply prefill. Own-comment edit remains out of scope.
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
ok('comments page owns compose sheet state',
  /@Local commentSheetShown: boolean = false/.test(page) &&
    /@Local commentText: string = ''/.test(page) &&
    /@Local commentReplyToId: string = ''/.test(page) &&
    /@Local commentSubmitting: boolean = false/.test(page))
ok('comments page gates comment compose on route identity and login cookies',
  /private canOpenCommentSheet\(\): boolean[\s\S]*this\.params\.gid\.length > 0[\s\S]*this\.params\.token\.length > 0[\s\S]*EhCookieStore\.getInstance\(\)\.isLogin\(\)/.test(page))
ok('new comment title action opens the compose sheet',
  /const newComment: Record<string, Object> = \{[\s\S]*comment_new_title[\s\S]*sys\.symbol\.doc_plaintext[\s\S]*this\.openNewComment\(\)/.test(page))
ok('reply action pre-fills @author plus encoded comment id and still submits as new comment',
  /private openReplyComment\(comment: EhGalleryComment\): void[\s\S]*this\.commentReplyToId = comment\.commentId[\s\S]*this\.commentText = `@\$\{comment\.author\}\\n\$\{this\.encodeCommentId\(comment\.commentId\)\}\\n`/.test(page) &&
    /postGalleryComment\(\{[\s\S]*commentId: ''[\s\S]*isEdit: false/.test(page))
ok('comment compose uses AppModalScaffold with title actions, not a bottom primary button',
  /@Builder[\s\S]*CommentComposeSheet\(\)[\s\S]*AppModalScaffold\(\{[\s\S]*confirmText: \$r\('app\.string\.comment_send'\)[\s\S]*confirmEnabled: this\.canSubmitComment\(\)[\s\S]*confirmLoading: this\.commentSubmitting/.test(page) &&
    !/CommentComposeSheet\(\)[\s\S]*Button\(\$r\('app\.string\.comment_send'\)/.test(page))
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
    /ReplyAction\(c: EhGalleryComment\)[\s\S]*sys\.symbol\.doc_plaintext/.test(card))

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'comment_new_title',
    'comment_reply_title',
    'comment_send',
    'comment_new_placeholder',
    'comment_reply_placeholder',
    'comment_reply_to',
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

#!/usr/bin/env node
/**
 * Contract: full GalleryComments page exposes protected EH comment voting.
 *
 * Mirrors eros_fe:
 * - Api.commitVote sends /api.php method=votecomment with apikey/apiuid/gid/token/comment_id/comment_vote.
 * - CommentController applies returned comment_vote and comment_score to the matching comment.
 *
 * NextE applies an optimistic row state immediately, rolls back on failure, and lets EH return
 * comment_vote=0 when a repeated up/down tap cancels the vote.
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

const api = read('shared/src/main/ets/network/EhApiPhpService.ets')
ok('api has votecomment request shape',
  /class VoteCommentRequest[\s\S]*method: string = 'votecomment'[\s\S]*apikey: string[\s\S]*apiuid: number[\s\S]*gid: number[\s\S]*token: string[\s\S]*comment_id: number[\s\S]*comment_vote: number/.test(api))
ok('api validates votecomment auth and ids before posting',
  /static async voteComment\([\s\S]*apikey: string[\s\S]*apiuid: string[\s\S]*commentId: string[\s\S]*vote: number/.test(api) &&
    /apikey\.length === 0[\s\S]*token\.length === 0[\s\S]*Number\.isNaN\(apiuidNum\)[\s\S]*Number\.isNaN\(commentIdNum\)[\s\S]*vote !== 1 && vote !== -1/.test(api))
ok('api posts to api.php and parses returned comment score and vote',
  /postJson\([\s\S]*`\$\{base\}\/api\.php`[\s\S]*JSON\.stringify\(req\)/.test(api) &&
    /obj\.comment_id === undefined[\s\S]*obj\.comment_score === undefined[\s\S]*obj\.comment_vote === undefined/.test(api) &&
    /result\.commentId = EhApiPhpService\.intFrom\(obj\.comment_id\)\.toString\(\)/.test(api) &&
    /result\.commentScore = EhApiPhpService\.intFrom\(obj\.comment_score\)/.test(api) &&
    /result\.commentVote = EhApiPhpService\.intFrom\(obj\.comment_vote\)/.test(api))
ok('api sends only up/down votes but accepts EH cancellation result comment_vote=0',
  /\(vote !== 1 && vote !== -1\)/.test(api) &&
    /result\.commentVote !== 1 && result\.commentVote !== -1 && result\.commentVote !== 0/.test(api))

const barrel = read('shared/src/main/ets/Index.ets')
ok('CommentVoteResult is exported from shared barrel',
  /EhApiPhpService[\s\S]*GalleryRatingResult[\s\S]*CommentVoteResult/.test(barrel))
ok('comment vote mutation state is exported from shared barrel',
  /CommentVoteMutationState[\s\S]*connectCommentVoteMutation/.test(barrel))

const params = read('shared/src/main/ets/model/RouteParams.ets')
ok('GalleryCommentsParams carries api metadata for votecomment',
  /export class GalleryCommentsParams[\s\S]*apikey: string = ''[\s\S]*apiuid: string = ''[\s\S]*constructor\([\s\S]*apikey: string = ''[\s\S]*apiuid: string = ''[\s\S]*this\.apikey = apikey[\s\S]*this\.apiuid = apiuid/.test(params))

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
ok('detail passes parsed apikey and apiuid to full comments route',
  /new GalleryCommentsParams\([\s\S]*this\.params\.gid[\s\S]*this\.params\.token[\s\S]*this\.vm\.comments[\s\S]*this\.navTitle\(\)[\s\S]*this\.vm\.gallery\.apikey[\s\S]*this\.vm\.gallery\.apiuid/.test(detail))

const card = read('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets')
const page = read('feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets')
ok('full comments card exposes vote event but peek mode stays quiet',
  /@Event onVote: \(comment: EhGalleryComment, vote: number\) => void/.test(card) &&
    /if \(this\.max <= 0 && c\.canVote\) \{[\s\S]*this\.VoteAction\(c, 1[\s\S]*this\.VoteAction\(c, -1/.test(card))
ok('vote actions use current vote state and page avoids double submit',
  /private voteColor\(c: EhGalleryComment, vote: number\)/.test(card) &&
    /private canVote\(c: EhGalleryComment\): boolean \{[\s\S]*this\.max <= 0 && c\.canVote/.test(card) &&
    /private async submitCommentVote\([\s\S]*commentId: string,[\s\S]*requestVote: number,[\s\S]*localVote: number,[\s\S]*tappedVote: number,[\s\S]*\): Promise<void> \{[\s\S]*if \(this\.votingCommentId\.length > 0\)/.test(page))
ok('vote pending state stays out of the comment card so optimistic voting has no loading spinner',
  !/@Param votingCommentId/.test(card) &&
    !/this\.votingCommentId/.test(card) &&
    !/votingCommentId: this\.votingCommentId/.test(page))
ok('vote row keys stay stable while observed comment fields repaint',
  /private commentRowKey\(c: EhGalleryComment\): string \{[\s\S]*return c\.commentId/.test(card) &&
    !/return `\$\{c\.commentId\}:\$\{c\.vote\}:\$\{c\.score\}`/.test(card) &&
    /\(c: EhGalleryComment\) => this\.commentRowKey\(c\)/.test(card))
ok('single comment card can delegate vote state to its parent without local mutation',
  /@Param parentManagedActions: boolean = false/.test(card) &&
    !/@Param singleScore/.test(card) &&
    !/@Param singleVote/.test(card) &&
    /private publishVote\(c: EhGalleryComment, vote: number\): void \{[\s\S]*if \(this\.parentManagedActions\) \{[\s\S]*this\.onVote\(c, vote\)[\s\S]*return[\s\S]*const targetVote: number = c\.vote === vote \? 0 : vote[\s\S]*c\.score = \(score \+ targetVote - c\.vote\)\.toString\(\)[\s\S]*c\.vote = targetVote/.test(card) &&
    !/commentAction/.test(card) &&
    !/actionScope/.test(card) &&
    /private voteColor\(c: EhGalleryComment, vote: number\): ResourceColor \{[\s\S]*this\.effectiveVote\(c\) === vote/.test(card) &&
    /private effectiveScore\(c: EhGalleryComment\): string \{[\s\S]*this\.useSingleComment \? this\.singleComment\.score : c\.score/.test(card) &&
    /private effectiveVote\(c: EhGalleryComment\): number \{[\s\S]*this\.useSingleComment \? this\.singleComment\.vote : c\.vote/.test(card))
ok('vote actions use native thumbs icons with filled selected state',
  /hand_thumbsup_fill/.test(card) &&
    /hand_thumbsup/.test(card) &&
    /hand_thumbsdown_fill/.test(card) &&
    /hand_thumbsdown/.test(card) &&
    !/VoteAction\(c, 1, \$r\('sys\.symbol\.arrow_up'\)\)/.test(card) &&
    !/VoteAction\(c, -1, \$r\('sys\.symbol\.arrow_down'\)\)/.test(card))

ok('comments page votes immediately without confirmation and computes local cancellation state',
  /private handleCommentVote\(comment: EhGalleryComment, vote: number\): void[\s\S]*const targetVote: number = this\.renderVote\(comment\) === vote \? 0 : vote[\s\S]*this\.submitCommentVote\(comment\.commentId, vote, targetVote, vote\)/.test(page) &&
    !/showAlertDialog\([\s\S]*submitCommentVote\(comment\.commentId/.test(page))
ok('comments page submits votecomment with route api metadata',
  /EhApiPhpService\.voteComment\([\s\S]*EhConstants\.baseUrl\(connectSiteMode\(\)\.isEx\)[\s\S]*this\.params\.apikey[\s\S]*this\.params\.apiuid[\s\S]*this\.params\.gid[\s\S]*this\.params\.token[\s\S]*commentId[\s\S]*requestVote/.test(page))
ok('comments page sends tapped vote to EH while applying target vote locally',
  /private async submitCommentVote\([\s\S]*requestVote: number,[\s\S]*localVote: number,[\s\S]*tappedVote: number,[\s\S]*this\.applyLocalVote\(commentId, localVote\)[\s\S]*commentId,[\s\S]*requestVote/.test(page))
ok('comments page uses vote-specific cancel success copy',
  /private voteSuccessText\(requestVote: number, resultVote: number\): ResourceStr[\s\S]*comment_vote_cancel_up_success[\s\S]*comment_vote_cancel_down_success/.test(page) &&
    /this\.showCommentToast\(this\.voteSuccessText\(tappedVote, result\.commentVote\)\)/.test(page))
ok('comments page applies returned vote and score to the matching local comment',
  /private applyVoteResult\(result: CommentVoteResult\): void[\s\S]*this\.replaceComment\(result\.commentId, \(current: EhGalleryComment\) => \{[\s\S]*current\.vote = result\.commentVote[\s\S]*current\.score = result\.commentScore\.toString\(\)/.test(page) &&
    /private replaceComment\(commentId: string, updater: \(comment: EhGalleryComment\) => void\): EhGalleryComment \| undefined \{[\s\S]*updater\(current\)[\s\S]*return current/.test(page) &&
    !/comments\[i\] = next/.test(page) &&
    !/@Local commentRenderVersion/.test(page))
ok('comments page publishes confirmed vote mutation for the detail page',
  /connectCommentVoteMutation\(\)\.publish\([\s\S]*this\.params\.gid[\s\S]*result\.commentId[\s\S]*result\.commentScore\.toString\(\)[\s\S]*result\.commentVote/.test(page))
ok('comments page applies optimistic row vote and rolls back on failure',
  /private applyLocalVote\(commentId: string, vote: number\): EhGalleryComment \| undefined[\s\S]*previous = this\.cloneComment\(current\)/.test(page) &&
    /private applyLocalVote\(commentId: string, vote: number\): EhGalleryComment \| undefined[\s\S]*const current: EhGalleryComment \| undefined = this\.commentById\(commentId\)[\s\S]*score \+ vote - next\.vote/.test(page) &&
    /next\.vote = vote/.test(page) &&
    !/private applyLocalVote\(commentId: string, vote: number\): EhGalleryComment \| undefined[\s\S]*animateTo\(\{ duration: ThemeConstants\.ANIM_DURATION, curve: Curve\.EaseOut \}[\s\S]*this\.replaceComment\(commentId/.test(page) &&
    /private restoreComment\(comment: EhGalleryComment\): void[\s\S]*this\.replaceComment\(comment\.commentId, \(current: EhGalleryComment\) => \{[\s\S]*current\.score = comment\.score[\s\S]*current\.vote = comment\.vote/.test(page) &&
    /const previous: EhGalleryComment \| undefined = this\.applyLocalVote\(commentId, localVote\)[\s\S]*catch \(err\) \{[\s\S]*this\.restoreComment\(previous\)/.test(page))
ok('comments page wires card onVote',
  /parentManagedActions: true/.test(page) &&
    !/singleScore: comment\.score/.test(page) &&
    !/singleVote: comment\.vote/.test(page) &&
    /onVote: \(selectedComment: EhGalleryComment, vote: number\) => \{[\s\S]*this\.handleCommentVote\(selectedComment, vote\)/.test(page) &&
    !/@Monitor\('commentAction\.version'\)/.test(page))

const detailPage = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const detailVm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
ok('detail page listens for confirmed comment vote mutation',
  /@Local commentVoteMutation: CommentVoteMutationState = connectCommentVoteMutation\(\)/.test(detailPage) &&
    /@Monitor\('commentVoteMutation\.version'\)[\s\S]*this\.vm\.applyCommentVote\([\s\S]*this\.commentVoteMutation\.commentId[\s\S]*this\.commentVoteMutation\.score[\s\S]*this\.commentVoteMutation\.vote/.test(detailPage) &&
    /applyCommentVote\(commentId: string, score: string, vote: number\): void[\s\S]*c\.score = score[\s\S]*c\.vote = vote/.test(detailVm) &&
    !/applyCommentVote\(commentId: string, score: string, vote: number\): void[\s\S]*comments\[i\] = next/.test(detailVm))

ok('detail view model patches comments and cache after a confirmed vote',
  /applyCommentVote\(commentId: string, score: string, vote: number\): void[\s\S]*c\.score = score[\s\S]*c\.vote = vote[\s\S]*this\.saveCurrentDetailCache\(\)/.test(detailVm))

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'comment_vote_up',
    'comment_vote_down',
    'comment_vote_cancel_success',
    'comment_vote_cancel_up_success',
    'comment_vote_cancel_down_success',
    'comment_vote_up_success',
    'comment_vote_down_success',
    'comment_vote_failed',
  ]) {
    ok(`${locale} has ${key}`, strings.includes(`"name": "${key}"`))
  }
}

if (failures === 0) {
  console.log('✓ gallery comment vote contract passed')
  process.exit(0)
}
console.error(`✗ gallery comment vote contract: ${failures} failure(s)`)
process.exit(1)

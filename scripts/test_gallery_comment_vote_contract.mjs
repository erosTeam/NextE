#!/usr/bin/env node
/**
 * Contract: full GalleryComments page exposes protected EH comment voting.
 *
 * Mirrors eros_fe:
 * - Api.commitVote sends /api.php method=votecomment with apikey/apiuid/gid/token/comment_id/comment_vote.
 * - CommentController applies returned comment_vote and comment_score to the matching comment.
 *
 * NextE confirms all four visible actions, then applies the accepted result optimistically:
 * up, down, cancel-up, cancel-down.
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
    /apikey\.length === 0[\s\S]*token\.length === 0[\s\S]*Number\.isNaN\(apiuidNum\)[\s\S]*Number\.isNaN\(commentIdNum\)[\s\S]*vote !== 1 && vote !== -1 && vote !== 0/.test(api))
ok('api posts to api.php and parses returned comment score and vote',
  /postJson\([\s\S]*`\$\{base\}\/api\.php`[\s\S]*JSON\.stringify\(req\)/.test(api) &&
    /obj\.comment_id === undefined[\s\S]*obj\.comment_score === undefined[\s\S]*obj\.comment_vote === undefined/.test(api) &&
    /result\.commentId = EhApiPhpService\.intFrom\(obj\.comment_id\)\.toString\(\)/.test(api) &&
    /result\.commentScore = EhApiPhpService\.intFrom\(obj\.comment_score\)/.test(api) &&
    /result\.commentVote = EhApiPhpService\.intFrom\(obj\.comment_vote\)/.test(api))
ok('api accepts EH cancellation result comment_vote=0',
  /result\.commentVote !== 1 && result\.commentVote !== -1 && result\.commentVote !== 0/.test(api))

const barrel = read('shared/src/main/ets/Index.ets')
ok('CommentVoteResult is exported from shared barrel',
  /EhApiPhpService[\s\S]*GalleryRatingResult[\s\S]*CommentVoteResult/.test(barrel))

const params = read('shared/src/main/ets/model/RouteParams.ets')
ok('GalleryCommentsParams carries api metadata for votecomment',
  /export class GalleryCommentsParams[\s\S]*apikey: string = ''[\s\S]*apiuid: string = ''[\s\S]*constructor\([\s\S]*apikey: string = ''[\s\S]*apiuid: string = ''[\s\S]*this\.apikey = apikey[\s\S]*this\.apiuid = apiuid/.test(params))

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
ok('detail passes parsed apikey and apiuid to full comments route',
  /new GalleryCommentsParams\([\s\S]*this\.params\.gid[\s\S]*this\.params\.token[\s\S]*this\.vm\.comments[\s\S]*this\.navTitle\(\)[\s\S]*this\.vm\.gallery\.apikey[\s\S]*this\.vm\.gallery\.apiuid/.test(detail))

const card = read('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets')
ok('full comments card exposes vote event but peek mode stays quiet',
  /@Event onVote: \(comment: EhGalleryComment, vote: number\) => void/.test(card) &&
    /if \(this\.max <= 0 && c\.canVote\) \{[\s\S]*this\.VoteAction\(c, 1[\s\S]*this\.VoteAction\(c, -1/.test(card))
ok('vote actions use current vote state and avoid double submit',
  /private voteColor\(c: EhGalleryComment, vote: number\)/.test(card) &&
    /private canVote\(c: EhGalleryComment\): boolean \{[\s\S]*this\.votingCommentId\.length === 0/.test(card))
ok('vote actions use native thumbs icons with filled selected state',
  /hand_thumbsup_fill/.test(card) &&
    /hand_thumbsup/.test(card) &&
    /hand_thumbsdown_fill/.test(card) &&
    /hand_thumbsdown/.test(card) &&
    !/VoteAction\(c, 1, \$r\('sys\.symbol\.arrow_up'\)\)/.test(card) &&
    !/VoteAction\(c, -1, \$r\('sys\.symbol\.arrow_down'\)\)/.test(card))

const page = read('feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets')
ok('comments page confirms up/down votes and selected-vote cancellation with distinct copy',
  /private handleCommentVote\(comment: EhGalleryComment, vote: number\): void[\s\S]*const targetVote: number = comment\.vote === vote \? 0 : vote[\s\S]*showAlertDialog\([\s\S]*message: targetVote === 0 \? this\.voteCancelConfirmText\(vote\) : this\.voteConfirmText\(vote\)[\s\S]*submitCommentVote\(comment\.commentId, targetVote\)/.test(page))
ok('comments page submits votecomment with route api metadata',
  /EhApiPhpService\.voteComment\([\s\S]*EhConstants\.baseUrl\(connectSiteMode\(\)\.isEx\)[\s\S]*this\.params\.apikey[\s\S]*this\.params\.apiuid[\s\S]*this\.params\.gid[\s\S]*this\.params\.token[\s\S]*commentId[\s\S]*vote/.test(page))
ok('comments page applies returned vote and score to the matching local comment',
  /private applyVoteResult\(result: CommentVoteResult\): void[\s\S]*next\.vote = result\.commentVote[\s\S]*next\.score = result\.commentScore\.toString\(\)[\s\S]*this\.comments = nextComments/.test(page))
ok('comments page applies optimistic row vote and rolls back on failure',
  /private applyLocalVote\(commentId: string, vote: number\): EhGalleryComment \| undefined[\s\S]*previous = this\.cloneComment\(c\)[\s\S]*next\.vote = vote[\s\S]*this\.comments = nextComments/.test(page) &&
    /score \+ vote - c\.vote/.test(page) &&
    /private restoreComment\(comment: EhGalleryComment\): void[\s\S]*c\.commentId === comment\.commentId/.test(page) &&
    /const previous: EhGalleryComment \| undefined = this\.applyLocalVote\(commentId, vote\)[\s\S]*catch \(err\) \{[\s\S]*this\.restoreComment\(previous\)/.test(page))
ok('comments page wires card onVote and pending state',
  /GalleryCommentsCard\(\{[\s\S]*votingCommentId: this\.votingCommentId[\s\S]*onVote: \(comment: EhGalleryComment, vote: number\) => \{[\s\S]*this\.handleCommentVote\(comment, vote\)/.test(page))

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'comment_vote_up',
    'comment_vote_down',
    'comment_vote_confirm_up',
    'comment_vote_confirm_down',
    'comment_vote_cancel_up',
    'comment_vote_cancel_down',
    'comment_vote_cancel_success',
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

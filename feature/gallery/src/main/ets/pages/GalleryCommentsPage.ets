import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  EhConstants,
  EhApiService,
  EhApiPhpService,
  EhGalleryComment,
  CommentVoteResult,
  GalleryCommentsParams,
  PullRefreshListScaffold,
  PullRefreshController,
  CardEmptyState,
  AppStrings,
  connectSearchAction,
  connectSiteMode,
  DiagnosticLogger,
  EhErrorText,
  immersiveTitleBarOpts,
} from 'shared'
import { GalleryCommentsCard } from '../components/GalleryCommentsCard'
import { SymbolGlyphModifier } from '@kit.ArkUI'

/**
 * The separate full comments page (eros_fe galleryComment). The detail page shows a 2-comment peek
 * and links here; this page renders the whole list (already parsed from the detail fetch, passed by
 * reference). Comment voting is the first bounded write action here; composer / reply / edit remain
 * deferred write-operation lanes.
 */
@ComponentV2
export struct GalleryCommentsPage {
  @Local params: GalleryCommentsParams = new GalleryCommentsParams();
  @Local comments: EhGalleryComment[] = [];
  @Local errorMessage: string = '';
  @Local uploaderOnly: boolean = false;
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();
  @Local votingCommentId: string = '';

  private uploaderMemberId(): string {
    const uploader: EhGalleryComment | undefined = this.comments.find((c: EhGalleryComment) => c.isUploader)
    return uploader !== undefined ? uploader.memberId : ''
  }

  private visibleComments(): EhGalleryComment[] {
    if (!this.uploaderOnly) {
      return this.comments
    }
    const memberId: string = this.uploaderMemberId()
    if (memberId.length > 0) {
      return this.comments.filter((c: EhGalleryComment) => c.memberId === memberId)
    }
    return this.comments.filter((c: EhGalleryComment) => c.isUploader)
  }

  // Tap a comment author → search their uploads (same bus + behavior as the detail page). eros_fe
  // quotes namespaced searches so a multi-word username matches exactly.
  private searchUploader(name: string): void {
    const n: string = name.trim()
    if (n.length === 0) {
      return
    }
    connectSearchAction().publishQuery(`uploader:"${n}"`)
  }

  private async refreshComments(): Promise<void> {
    if (this.params.gid.length === 0 || this.params.token.length === 0) {
      return
    }
    this.errorMessage = ''
    try {
      const result = await EhApiService.getInstance().getGalleryDetail(
        this.params.gid,
        this.params.token,
        connectSiteMode().isEx,
      )
      this.comments = result.comments
      if (this.visibleComments().length === 0) {
        this.uploaderOnly = false
      }
      DiagnosticLogger.info(
        'gallery',
        'comments_refresh_ok',
        `gid=${this.params.gid} comments=${this.comments.length}`,
      )
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'comments_refresh_failed', (err as Error).message)
      throw new Error(this.errorMessage)
    }
  }

  private voteText(vote: number): ResourceStr {
    return vote > 0 ? $r('app.string.comment_vote_up') : $r('app.string.comment_vote_down')
  }

  private voteConfirmText(vote: number): ResourceStr {
    return vote > 0 ? $r('app.string.comment_vote_confirm_up') : $r('app.string.comment_vote_confirm_down')
  }

  private voteSuccessText(vote: number): ResourceStr {
    return vote > 0 ? $r('app.string.comment_vote_up_success') : $r('app.string.comment_vote_down_success')
  }

  private cloneComment(c: EhGalleryComment): EhGalleryComment {
    const next: EhGalleryComment = new EhGalleryComment()
    next.commentId = c.commentId
    next.memberId = c.memberId
    next.author = c.author
    next.postedTime = c.postedTime
    next.contentText = c.contentText
    next.score = c.score
    next.vote = c.vote
    next.canEdit = c.canEdit
    next.canVote = c.canVote
    next.scoreDetails = c.scoreDetails.slice()
    next.isUploader = c.isUploader
    return next
  }

  private applyVoteResult(result: CommentVoteResult): void {
    const nextComments: EhGalleryComment[] = []
    this.comments.forEach((c: EhGalleryComment) => {
      if (c.commentId === result.commentId) {
        const next: EhGalleryComment = this.cloneComment(c)
        next.vote = result.commentVote
        next.score = result.commentScore.toString()
        nextComments.push(next)
      } else {
        nextComments.push(c)
      }
    })
    this.comments = nextComments
  }

  private showVoteToast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().openToast({ message: message }).catch((_error: Error) => {
      // Toast failures are non-critical; the comment state has already been updated or logged.
    })
  }

  private confirmCommentVote(comment: EhGalleryComment, vote: number): void {
    if (!comment.canVote || comment.commentId.length === 0 || this.votingCommentId.length > 0) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: this.voteText(vote),
      message: this.voteConfirmText(vote),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_ok'),
        action: () => {
          this.submitCommentVote(comment.commentId, vote)
        },
      },
    })
  }

  private async submitCommentVote(commentId: string, vote: number): Promise<void> {
    if (this.votingCommentId.length > 0) {
      return
    }
    this.votingCommentId = commentId
    try {
      const result: CommentVoteResult = await EhApiPhpService.voteComment(
        EhConstants.baseUrl(connectSiteMode().isEx),
        this.params.apikey,
        this.params.apiuid,
        this.params.gid,
        this.params.token,
        commentId,
        vote,
      )
      this.applyVoteResult(result)
      this.showVoteToast(this.voteSuccessText(vote))
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'comment_vote_failed', (err as Error).message)
      this.showVoteToast($r('app.string.comment_vote_failed'))
    } finally {
      this.votingCommentId = ''
    }
  }

  private commentsTitleBar(): Record<string, Object> {
    const title: Record<string, Object> = { 'mainTitle': AppStrings.get('gallery_comments') }
    let uploaderOnly: Record<string, Object>
    if (this.uploaderOnly) {
      uploaderOnly = {
        'label': $r('app.string.comment_filter_all'),
        'icon': $r('sys.symbol.list_bullet_square_fill'),
        'symbolEndIcon': new SymbolGlyphModifier($r('sys.symbol.checkmark')),
        'isEnabled': this.comments.length > 0,
        'action': () => {
          this.uploaderOnly = false
        },
      }
    } else {
      uploaderOnly = {
        'label': $r('app.string.comment_filter_uploader_only'),
        'icon': $r('sys.symbol.person'),
        'isEnabled': this.comments.length > 0,
        'action': () => {
          this.uploaderOnly = true
        },
      }
    }
    const items: Record<string, Object>[] = [{ 'content': uploaderOnly }]
    const menu: Record<string, Object> = { 'value': items, 'maxCount': 1 }
    const content: Record<string, Object> = {
      'title': title,
      'menu': menu,
    }
    return immersiveTitleBarOpts(content)
  }

  build() {
    HdsNavDestination() {
      PullRefreshListScaffold({
        scroller: this.scroller,
        listSpace: ThemeConstants.SPACE_MD,
        bottomPadding: ThemeConstants.SPACE_XL,
        controller: this.refreshController,
        onRefresh: async () => {
          await this.refreshComments()
        },
      }) {
        if (this.visibleComments().length > 0) {
          ListItem() {
            // max = 0 → show every comment (the peek on the detail page uses max = 2).
            GalleryCommentsCard({
              comments: this.visibleComments(),
              votingCommentId: this.votingCommentId,
              onAuthor: (name: string) => {
                this.searchUploader(name)
              },
              onVote: (comment: EhGalleryComment, vote: number) => {
                this.confirmCommentVote(comment, vote)
              },
            })
          }
        } else {
          ListItem() {
            CardEmptyState({ message: $r('app.string.common_no_content') })
          }
        }
      }
    }
    .titleBar(this.commentsTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryCommentsParams
      if (p !== undefined) {
        this.params = p
        this.comments = p.comments
      }
    })
  }
}

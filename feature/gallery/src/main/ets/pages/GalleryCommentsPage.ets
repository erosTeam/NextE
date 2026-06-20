import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  EhConstants,
  EhApiService,
  EhApiPhpService,
  EhCookieStore,
  EhGalleryComment,
  CommentVoteResult,
  GalleryCommentsParams,
  PullRefreshListScaffold,
  PullRefreshController,
  CardEmptyState,
  AppModalScaffold,
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
 * reference). Comment voting and bounded new/reply/edit composition are protected EH write lanes.
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
  @Local commentSheetShown: boolean = false;
  @Local commentText: string = '';
  @Local commentReplyToId: string = '';
  @Local commentReplyToAuthor: string = '';
  @Local commentEditId: string = '';
  @Local commentEditOriginal: string = '';
  @Local commentSubmitting: boolean = false;
  @Local commentError: string = '';

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

  private canOpenCommentSheet(): boolean {
    return this.params.gid.length > 0 && this.params.token.length > 0 && EhCookieStore.getInstance().isLogin()
  }

  private canSubmitComment(): boolean {
    if (this.commentText.trim().length < 10 || !this.canOpenCommentSheet() || this.commentSubmitting) {
      return false
    }
    return this.commentEditId.length === 0 || this.commentEditId !== '0'
  }

  private commentSheetTitle(): ResourceStr {
    if (this.commentEditId.length > 0) {
      return $r('app.string.comment_edit_title')
    }
    if (this.commentReplyToId.length > 0) {
      return $r('app.string.comment_reply_title')
    }
    return $r('app.string.comment_new_title')
  }

  private commentPlaceholder(): ResourceStr {
    if (this.commentEditId.length > 0) {
      return $r('app.string.comment_edit_placeholder')
    }
    if (this.commentReplyToId.length > 0) {
      return $r('app.string.comment_reply_placeholder')
    }
    return $r('app.string.comment_new_placeholder')
  }

  private encodeCommentId(id: string): string {
    let out: string = ''
    for (let i = 0; i < id.length; i++) {
      const ch: string = id.charAt(i)
      if (ch === '0') out += '····'
      else if (ch === '1') out += '···-'
      else if (ch === '2') out += '··-·'
      else if (ch === '3') out += '··--'
      else if (ch === '4') out += '·-··'
      else if (ch === '5') out += '·-·-'
      else if (ch === '6') out += '·--·'
      else if (ch === '7') out += '·---'
      else if (ch === '8') out += '-···'
      else if (ch === '9') out += '-··-'
      else out += ch
    }
    return out
  }

  private openNewComment(): void {
    if (!this.canOpenCommentSheet()) {
      this.showCommentToast($r('app.string.comment_login_required'))
      return
    }
    this.commentText = ''
    this.commentReplyToId = ''
    this.commentReplyToAuthor = ''
    this.commentEditId = ''
    this.commentEditOriginal = ''
    this.commentError = ''
    this.commentSheetShown = true
  }

  private openReplyComment(comment: EhGalleryComment): void {
    if (!this.canOpenCommentSheet()) {
      this.showCommentToast($r('app.string.comment_login_required'))
      return
    }
    this.commentReplyToId = comment.commentId
    this.commentReplyToAuthor = comment.author
    this.commentEditId = ''
    this.commentEditOriginal = ''
    this.commentText = `@${comment.author}\n${this.encodeCommentId(comment.commentId)}\n`
    this.commentError = ''
    this.commentSheetShown = true
  }

  private openEditComment(comment: EhGalleryComment): void {
    if (!this.canOpenCommentSheet()) {
      this.showCommentToast($r('app.string.comment_login_required'))
      return
    }
    if (!comment.canEdit || comment.commentId.length === 0 || comment.commentId === '0') {
      return
    }
    this.commentEditId = comment.commentId
    this.commentEditOriginal = comment.contentText
    this.commentReplyToId = ''
    this.commentReplyToAuthor = ''
    this.commentText = comment.contentText
    this.commentError = ''
    this.commentSheetShown = true
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

  private showCommentToast(message: ResourceStr): void {
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
      this.showCommentToast(this.voteSuccessText(vote))
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'comment_vote_failed', (err as Error).message)
      this.showCommentToast($r('app.string.comment_vote_failed'))
    } finally {
      this.votingCommentId = ''
    }
  }

  private async submitComment(): Promise<void> {
    if (!this.canSubmitComment()) {
      return
    }
    this.commentSubmitting = true
    this.commentError = ''
    try {
      await EhApiService.getInstance().postGalleryComment({
        isEx: connectSiteMode().isEx,
        gid: this.params.gid,
        token: this.params.token,
        comment: this.commentText,
        commentId: this.commentEditId,
        isEdit: this.commentEditId.length > 0,
      })
      this.commentSheetShown = false
      this.commentText = ''
      this.commentReplyToId = ''
      this.commentReplyToAuthor = ''
      this.commentEditId = ''
      this.commentEditOriginal = ''
      this.showCommentToast($r('app.string.comment_post_success'))
      await this.refreshComments()
    } catch (err) {
      this.commentError = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'comment_post_failed', (err as Error).message)
      this.showCommentToast($r('app.string.comment_post_failed'))
    } finally {
      this.commentSubmitting = false
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
    const newComment: Record<string, Object> = {
      'label': $r('app.string.comment_new_title'),
      'icon': $r('sys.symbol.doc_plaintext'),
      'isEnabled': this.canOpenCommentSheet() && !this.commentSubmitting,
      'action': () => {
        this.openNewComment()
      },
    }
    const items: Record<string, Object>[] = [{ 'content': newComment }, { 'content': uploaderOnly }]
    const menu: Record<string, Object> = { 'value': items, 'maxCount': 2 }
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
              onReply: (comment: EhGalleryComment) => {
                this.openReplyComment(comment)
              },
              onEdit: (comment: EhGalleryComment) => {
                this.openEditComment(comment)
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
    .bindSheet($$this.commentSheetShown, this.CommentComposeSheet(), {
      detents: [SheetSize.LARGE],
      showClose: false,
    })
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryCommentsParams
      if (p !== undefined) {
        this.params = p
        this.comments = p.comments
      }
    })
  }

  @Builder
  CommentComposeSheet() {
    AppModalScaffold({
      title: this.commentSheetTitle(),
      includeKeyboardPadding: true,
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: $r('app.string.comment_send'),
      confirmEnabled: this.canSubmitComment(),
      confirmLoading: this.commentSubmitting,
      closeAction: () => {
        this.commentSheetShown = false
      },
      confirmAction: () => {
        this.submitComment()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          if (this.commentReplyToAuthor.length > 0) {
            Text($r('app.string.comment_reply_to', this.commentReplyToAuthor))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }
          if (this.commentEditId.length > 0 && this.commentEditOriginal.length > 0) {
            Text($r('app.string.comment_edit_original'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
            Text(this.commentEditOriginal)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          TextArea({
            text: this.commentText,
            placeholder: this.commentPlaceholder(),
          })
            .width('100%')
            .height(220)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
            .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
            .enabled(!this.commentSubmitting)
            .onChange((value: string) => {
              this.commentText = value
            })
          Text($r('app.string.comment_min_length_hint'))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
          if (this.commentError.length > 0) {
            Text(this.commentError)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(Color.Red)
              .width('100%')
          }
        }
        .width('100%')
      }
    }
  }
}

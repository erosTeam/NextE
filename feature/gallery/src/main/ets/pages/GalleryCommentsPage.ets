import { common } from '@kit.AbilityKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  CommentTranslationService,
  CommentTranslationSettingsState,
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
  AppStrings,
  LayoutSafeAreaState,
  connectLayoutSafeArea,
  connectSearchAction,
  connectSiteMode,
  connectCommentVoteMutation,
  DiagnosticLogger,
  EhErrorText,
  connectCommentTranslationSettings,
  immersiveTitleBarOpts,
} from 'shared'
import { GalleryCommentsCard } from '../components/GalleryCommentsCard'
import { GalleryCommentRenderState } from '../model/GalleryCommentRenderState'
import { KeyboardAvoidMode, SymbolGlyphModifier } from '@kit.ArkUI'

const COMMENT_COMPOSER_BOTTOM_RESERVE: number = 136
const COMMENT_COMPOSER_FIELD_ID: string = 'gallery-comments-composer-field'
const COMMENT_COMPOSER_OUTER_GAP: number = ThemeConstants.SPACE_SM
const COMMENT_COMPOSER_INNER_GAP: number = ThemeConstants.SPACE_XS
const COMMENT_COMPOSER_SEND_SIZE: number = 36
const COMMENT_COMPOSER_CLOSE_ICON_SIZE: number = COMMENT_COMPOSER_SEND_SIZE - COMMENT_COMPOSER_INNER_GAP * 2
const COMMENT_COMPOSER_RADIUS: number = COMMENT_COMPOSER_SEND_SIZE / 2 + COMMENT_COMPOSER_INNER_GAP
const COMMENT_COMPOSER_INPUT_MAX_H: number = 148
const COMMENT_COMPOSER_QUOTE_LINE_W: number = 4
const COMMENT_COMPOSER_QUOTE_TEXT_BLOCK_H: number = 22 * 2 + ThemeConstants.SPACE_XS
const COMMENT_COMPOSER_QUOTE_LINE_H: number = COMMENT_COMPOSER_QUOTE_TEXT_BLOCK_H
const COMMENT_COMPOSER_QUOTE_TOP_LIFT: number = COMMENT_COMPOSER_INNER_GAP
const COMMENT_COMPOSER_QUOTE_TOP_GAP: number =
  COMMENT_COMPOSER_RADIUS - COMMENT_COMPOSER_QUOTE_LINE_W / 2 - COMMENT_COMPOSER_INNER_GAP -
  COMMENT_COMPOSER_QUOTE_TOP_LIFT
const COMMENT_COMPOSER_QUOTE_LEFT_GAP: number =
  COMMENT_COMPOSER_RADIUS - COMMENT_COMPOSER_INNER_GAP - COMMENT_COMPOSER_QUOTE_LINE_W / 2
const COMMENT_COMPOSER_CLOSE_RIGHT_GAP: number = COMMENT_COMPOSER_INNER_GAP

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
  @Local commentText: string = '';
  @Local commentReplyToId: string = '';
  @Local commentReplyToAuthor: string = '';
  @Local commentReplyPreview: string = '';
  @Local commentEditId: string = '';
  @Local commentEditOriginal: string = '';
  @Local commentSubmitting: boolean = false;
  @Local commentError: string = '';
  @Local translationSettings: CommentTranslationSettingsState = connectCommentTranslationSettings();
  @Local commentRenderStates: GalleryCommentRenderState[] = [];
  @Local commentRenderVersion: number = 0;
  @Local initialRefreshStarted: boolean = false;
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();

  private requestCommentFocus(): void {
    setTimeout(() => {
      this.getUIContext().getFocusController().requestFocus(COMMENT_COMPOSER_FIELD_ID)
    }, 80)
  }

  private composerBottomPadding(): number {
    if (this.layout.keyboardHeight > 0) {
      return COMMENT_COMPOSER_OUTER_GAP
    }
    return this.layout.bottomAvoidHeight
  }

  private uploaderMemberId(): string {
    const uploader: EhGalleryComment | undefined =
      this.comments.find((c: EhGalleryComment) => c.isUploader || c.score.length === 0)
    return uploader !== undefined ? uploader.memberId : ''
  }

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private scheduleInitialRefreshIfNeeded(): void {
    if (this.initialRefreshStarted || this.comments.length > 0 ||
      this.params.gid.length === 0 || this.params.token.length === 0) {
      return
    }
    this.initialRefreshStarted = true
    setTimeout(() => {
      this.refreshController.triggerTopRefresh()
    }, 0)
  }

  private visibleComments(): EhGalleryComment[] {
    if (!this.uploaderOnly) {
      return this.comments
    }
    const memberId: string = this.uploaderMemberId()
    if (memberId.length > 0) {
      return this.comments.filter((c: EhGalleryComment) => c.memberId === memberId)
    }
    return this.comments.filter((c: EhGalleryComment) => c.isUploader || c.score.length === 0)
  }

  private renderStatesFromComments(comments: EhGalleryComment[]): GalleryCommentRenderState[] {
    const out: GalleryCommentRenderState[] = []
    for (let i = 0; i < comments.length; i++) {
      out.push(new GalleryCommentRenderState(comments[i]))
    }
    return out
  }

  private renderState(commentId: string): GalleryCommentRenderState | undefined {
    for (let i = 0; i < this.commentRenderStates.length; i++) {
      const state: GalleryCommentRenderState = this.commentRenderStates[i]
      if (state.commentId === commentId) {
        return state
      }
    }
    return undefined
  }

  private renderStateFor(comment: EhGalleryComment): GalleryCommentRenderState {
    const current: GalleryCommentRenderState | undefined = this.renderState(comment.commentId)
    if (current !== undefined) {
      return current
    }
    const state: GalleryCommentRenderState = new GalleryCommentRenderState(comment)
    const states: GalleryCommentRenderState[] = this.commentRenderStates.slice()
    states.push(state)
    this.commentRenderStates = states
    return state
  }

  private updateRenderState(comment: EhGalleryComment): void {
    const states: GalleryCommentRenderState[] = this.commentRenderStates.slice()
    for (let i = 0; i < states.length; i++) {
      if (states[i].commentId === comment.commentId) {
        states[i].applyComment(comment)
        this.commentRenderStates = states
        this.commentRenderVersion++
        return
      }
    }
    const state: GalleryCommentRenderState = new GalleryCommentRenderState(comment)
    states.push(state)
    this.commentRenderStates = states
    this.commentRenderVersion++
  }

  private renderVote(comment: EhGalleryComment): number {
    const state: GalleryCommentRenderState | undefined = this.renderState(comment.commentId)
    return state !== undefined ? state.vote : comment.vote
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

  private commentPlaceholder(): ResourceStr {
    if (this.commentEditId.length > 0) {
      return $r('app.string.comment_edit_placeholder')
    }
    if (this.commentReplyToId.length > 0) {
      return $r('app.string.comment_reply_placeholder')
    }
    return $r('app.string.comment_new_placeholder')
  }

  private composerContextTitle(): ResourceStr {
    if (this.commentEditId.length > 0) {
      return $r('app.string.comment_edit_original')
    }
    return $r('app.string.comment_reply_to', this.commentReplyToAuthor)
  }

  private composerContextPreview(): string {
    return this.commentEditId.length > 0 ? this.commentEditOriginal : this.commentReplyPreview
  }

  private hasComposerContext(): boolean {
    return this.commentReplyToAuthor.length > 0 || this.commentEditId.length > 0
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
    this.commentReplyPreview = ''
    this.commentEditId = ''
    this.commentEditOriginal = ''
    this.commentError = ''
    this.requestCommentFocus()
  }

  private openReplyComment(comment: EhGalleryComment): void {
    if (!this.canOpenCommentSheet()) {
      this.showCommentToast($r('app.string.comment_login_required'))
      return
    }
    this.commentReplyToId = comment.commentId
    this.commentReplyToAuthor = comment.author
    this.commentReplyPreview = comment.contentText
    this.commentEditId = ''
    this.commentEditOriginal = ''
    this.commentText = `@${comment.author}\n${this.encodeCommentId(comment.commentId)}\n`
    this.commentError = ''
    this.requestCommentFocus()
  }

  private cancelCommentContext(): void {
    this.commentReplyToId = ''
    this.commentReplyToAuthor = ''
    this.commentReplyPreview = ''
    this.commentEditId = ''
    this.commentEditOriginal = ''
    this.commentError = ''
    this.commentText = ''
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
    this.commentReplyPreview = ''
    this.commentText = comment.contentText
    this.commentError = ''
    this.requestCommentFocus()
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
      this.params.apikey = result.gallery.apikey
      this.params.apiuid = result.gallery.apiuid
      this.params.title = result.gallery.displayTitle(false)
      this.comments = result.comments
      this.commentRenderStates = this.renderStatesFromComments(this.comments)
      this.commentRenderVersion++
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

  private voteSuccessText(requestVote: number, resultVote: number): ResourceStr {
    if (resultVote === 0) {
      return requestVote > 0
        ? $r('app.string.comment_vote_cancel_up_success')
        : $r('app.string.comment_vote_cancel_down_success')
    }
    return resultVote > 0 ? $r('app.string.comment_vote_up_success') : $r('app.string.comment_vote_down_success')
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
    next.translationText = c.translationText
    next.translationShown = c.translationShown
    next.translationLoading = c.translationLoading
    next.translationAutoStarted = c.translationAutoStarted
    return next
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private applyCommentTranslationState(
    commentId: string,
    translated: string | undefined,
    shown: boolean | undefined,
    loading: boolean | undefined,
    autoStarted: boolean | undefined,
  ): void {
    this.getUIContext().animateTo({ duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut }, () => {
      this.replaceComment(commentId, (current: EhGalleryComment) => {
        if (translated !== undefined) {
          current.translationText = translated
        }
        if (shown !== undefined) {
          current.translationShown = shown
        }
        if (loading !== undefined) {
          current.translationLoading = loading
        }
        if (autoStarted !== undefined) {
          current.translationAutoStarted = autoStarted
        }
      })
    })
  }

  private commentById(commentId: string): EhGalleryComment | undefined {
    return this.comments.find((c: EhGalleryComment) => c.commentId === commentId)
  }

  private replaceComment(commentId: string, updater: (comment: EhGalleryComment) => void): EhGalleryComment | undefined {
    for (let i = 0; i < this.comments.length; i++) {
      const current: EhGalleryComment = this.comments[i]
      if (current.commentId === commentId) {
        updater(current)
        const comments: EhGalleryComment[] = this.comments.slice()
        comments[i] = current
        this.comments = comments
        this.updateRenderState(current)
        return current
      }
    }
    return undefined
  }

  private toggleCommentTranslation(comment: EhGalleryComment): void {
    if (comment.commentId.length === 0) {
      return
    }
    const current: EhGalleryComment | undefined = this.commentById(comment.commentId)
    if (current === undefined || current.translationText.length === 0) {
      return
    }
    this.applyCommentTranslationState(
      comment.commentId,
      undefined,
      !current.translationShown,
      false,
      undefined,
    )
  }

  private requestCommentTranslation(comment: EhGalleryComment, sourceText: string, force: boolean): Promise<string> {
    if (comment.commentId.length === 0 || sourceText.trim().length === 0) {
      return Promise.resolve('')
    }
    const current: EhGalleryComment | undefined = this.commentById(comment.commentId)
    if (current !== undefined && current.translationText.length > 0 && !force) {
      return Promise.resolve(current.translationText)
    }
    return CommentTranslationService.translate(this.ctx(), sourceText, force)
      .then((translated: string) => translated)
      .catch((error: Error) => {
        DiagnosticLogger.warn('translation', 'comment_request_failed', `id=${comment.commentId} ${error.message}`)
        this.showCommentToast($r('app.string.comment_translation_failed'))
        return ''
      })
  }

  private applyResolvedCommentTranslation(comment: EhGalleryComment, translated: string): void {
    if (comment.commentId.length === 0 || translated.length === 0) {
      return
    }
    this.applyCommentTranslationState(comment.commentId, translated, true, false, undefined)
  }

  private translateComment(comment: EhGalleryComment, sourceText: string, force: boolean): void {
    if (comment.commentId.length === 0 || sourceText.trim().length === 0) {
      return
    }
    const current: EhGalleryComment | undefined = this.commentById(comment.commentId)
    if (current !== undefined && current.translationLoading) {
      return
    }
    if (current !== undefined && current.translationText.length > 0 && !force) {
      this.toggleCommentTranslation(current)
      return
    }
    this.applyCommentTranslationState(comment.commentId, undefined, true, true, undefined)
    CommentTranslationService.translate(this.ctx(), sourceText, force)
      .then((translated: string) => {
        if (translated.length > 0) {
          this.applyCommentTranslationState(comment.commentId, translated, true, false, undefined)
        }
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('translation', 'comment_request_failed', `id=${comment.commentId} ${error.message}`)
        this.showCommentToast($r('app.string.comment_translation_failed'))
      })
      .finally(() => {
        this.applyCommentTranslationState(comment.commentId, undefined, undefined, false, undefined)
      })
  }

  private autoTranslateComment(comment: EhGalleryComment, sourceText: string): void {
    if (!this.translationSettings.enabled || !this.translationSettings.autoTranslate ||
      comment.commentId.length === 0 || comment.translationAutoStarted || sourceText.trim().length === 0) {
      return
    }
    this.applyCommentTranslationState(comment.commentId, undefined, true, false, true)
    CommentTranslationService.getCached(this.ctx(), sourceText, CommentTranslationService.targetLanguage())
      .then((cached: string) => {
        if (cached.length > 0) {
          this.applyCommentTranslationState(comment.commentId, cached, true, false, undefined)
        } else {
          this.translateComment(comment, sourceText, false)
        }
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('translation', 'comment_auto_cache_failed', `id=${comment.commentId} ${error.message}`)
        this.translateComment(comment, sourceText, false)
      })
  }

  private applyVoteResult(result: CommentVoteResult): void {
    this.replaceComment(result.commentId, (current: EhGalleryComment) => {
      current.vote = result.commentVote
      current.score = result.commentScore.toString()
    })
    connectCommentVoteMutation().publish(
      this.params.gid,
      result.commentId,
      result.commentScore.toString(),
      result.commentVote,
    )
  }

  private applyLocalVote(commentId: string, vote: number): EhGalleryComment | undefined {
    let previous: EhGalleryComment | undefined = undefined
    const current: EhGalleryComment | undefined = this.commentById(commentId)
    if (current !== undefined) {
      previous = this.cloneComment(current)
      this.replaceComment(commentId, (next: EhGalleryComment) => {
        if (next.score.length > 0) {
          const score: number = Number.parseInt(next.score, 10)
          if (!Number.isNaN(score)) {
            next.score = (score + vote - next.vote).toString()
          }
        }
        next.vote = vote
      })
    }
    return previous
  }

  private restoreComment(comment: EhGalleryComment): void {
    this.replaceComment(comment.commentId, (current: EhGalleryComment) => {
      current.score = comment.score
      current.vote = comment.vote
    })
  }

  private showCommentToast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().openToast({ message: message }).catch((_error: Error) => {
      // Toast failures are non-critical; the comment state has already been updated or logged.
    })
  }

  private handleCommentVote(comment: EhGalleryComment, vote: number): void {
    DiagnosticLogger.info(
      'gallery',
      'comment_vote_tap',
      `id=${comment.commentId} canVote=${comment.canVote} current=${this.renderVote(comment)} request=${vote} busy=${this.votingCommentId}`,
    )
    if (!comment.canVote || comment.commentId.length === 0 || this.votingCommentId.length > 0) {
      return
    }
    const targetVote: number = this.renderVote(comment) === vote ? 0 : vote
    this.submitCommentVote(comment.commentId, vote, targetVote, vote)
  }

  private async submitCommentVote(
    commentId: string,
    requestVote: number,
    localVote: number,
    tappedVote: number,
  ): Promise<void> {
    if (this.votingCommentId.length > 0) {
      return
    }
    this.votingCommentId = commentId
    const previous: EhGalleryComment | undefined = this.applyLocalVote(commentId, localVote)
    try {
      DiagnosticLogger.info(
        'gallery',
        'comment_vote_submit',
        `gid=${this.params.gid} id=${commentId} request=${requestVote} local=${localVote}`,
      )
      const result: CommentVoteResult = await EhApiPhpService.voteComment(
        EhConstants.baseUrl(connectSiteMode().isEx),
        this.params.apikey,
        this.params.apiuid,
        this.params.gid,
        this.params.token,
        commentId,
        requestVote,
      )
      DiagnosticLogger.info(
        'gallery',
        'comment_vote_result',
        `id=${result.commentId} score=${result.commentScore} vote=${result.commentVote}`,
      )
      this.applyVoteResult(result)
      this.showCommentToast(this.voteSuccessText(tappedVote, result.commentVote))
    } catch (err) {
      if (previous !== undefined) {
        this.restoreComment(previous)
      }
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
      this.commentText = ''
      this.commentReplyToId = ''
      this.commentReplyToAuthor = ''
      this.commentReplyPreview = ''
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
      Stack({ alignContent: Alignment.Bottom }) {
        PullRefreshListScaffold({
          scroller: this.scroller,
          listSpace: ThemeConstants.SPACE_MD,
          bottomPadding: COMMENT_COMPOSER_BOTTOM_RESERVE,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.refreshComments()
          },
        }) {
          if (this.visibleComments().length > 0) {
            ListItem() {
              this.CommentsHeader()
            }
            ForEach(
              this.visibleComments(),
              (comment: EhGalleryComment) => {
                ListItem() {
                  GalleryCommentsCard({
                    comments: [comment],
                    referenceComments: this.comments,
                    useSingleComment: true,
                    singleComment: comment,
                    renderState: this.renderStateFor(comment),
                    renderVersion: this.commentRenderVersion,
                    parentManagedActions: true,
                    showHeader: false,
                    onAuthor: (author: string) => {
                      this.searchUploader(author)
                    },
                    onVote: (selectedComment: EhGalleryComment, vote: number) => {
                      this.handleCommentVote(selectedComment, vote)
                    },
                    onReply: (selectedComment: EhGalleryComment) => {
                      this.openReplyComment(selectedComment)
                    },
                    onEdit: (selectedComment: EhGalleryComment) => {
                      this.openEditComment(selectedComment)
                    },
                    onTranslate: (selectedComment: EhGalleryComment, sourceText: string) => {
                      return this.requestCommentTranslation(selectedComment, sourceText, false)
                    },
                    onTranslationResolved: (selectedComment: EhGalleryComment, translated: string) => {
                      this.applyResolvedCommentTranslation(selectedComment, translated)
                    },
                    onToggleTranslation: (selectedComment: EhGalleryComment) => {
                      this.toggleCommentTranslation(selectedComment)
                    },
                    onAutoTranslate: (selectedComment: EhGalleryComment, sourceText: string) => {
                      this.autoTranslateComment(selectedComment, sourceText)
                    },
                  })
                }
              },
              (comment: EhGalleryComment) => comment.commentId,
            )
          } else {
            ListItem() {
              CardEmptyState({ message: $r('app.string.common_no_content') })
            }
          }
        }
        this.CommentComposer()
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(this.commentsTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryCommentsParams
      if (p !== undefined) {
        this.params = p
        this.comments = p.comments
        this.commentRenderStates = this.renderStatesFromComments(this.comments)
        this.scheduleInitialRefreshIfNeeded()
      }
    })
  }

  @Builder
  CommentsHeader() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      Text($r('app.string.gallery_comments'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      Text(`(${this.visibleComments().length})`)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
  }

  @Builder
  CommentComposer() {
    Column() {
      Column({ space: ThemeConstants.SPACE_SM }) {
        if (this.hasComposerContext()) {
          Row({ space: ThemeConstants.SPACE_SM }) {
            Blank()
              .width(COMMENT_COMPOSER_QUOTE_LINE_W)
              .height(COMMENT_COMPOSER_QUOTE_LINE_H)
              .backgroundColor(ThemeConstants.BRAND_PRIMARY)
              .borderRadius(COMMENT_COMPOSER_QUOTE_LINE_W / 2)
            Column({ space: ThemeConstants.SPACE_XS }) {
              Text(this.composerContextTitle())
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_emphasize'))
                .textAlign(TextAlign.Start)
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.composerContextPreview())
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .textAlign(TextAlign.Start)
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Row() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(COMMENT_COMPOSER_CLOSE_ICON_SIZE)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .width(COMMENT_COMPOSER_SEND_SIZE)
            .height(COMMENT_COMPOSER_SEND_SIZE)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.cancelCommentContext()
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: COMMENT_COMPOSER_QUOTE_LEFT_GAP,
            right: COMMENT_COMPOSER_CLOSE_RIGHT_GAP,
            top: COMMENT_COMPOSER_QUOTE_TOP_GAP,
          })
        }
        Row({ space: ThemeConstants.SPACE_SM }) {
          TextArea({
            text: this.commentText,
            placeholder: this.commentPlaceholder(),
          })
            .id(COMMENT_COMPOSER_FIELD_ID)
            .constraintSize({ maxHeight: COMMENT_COMPOSER_INPUT_MAX_H })
            .maxLines(8)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .enabled(!this.commentSubmitting && this.canOpenCommentSheet())
            .onChange((value: string) => {
              this.commentText = value
            })
          SymbolGlyph($r('sys.symbol.location_north_up_right_circle_fill'))
            .fontSize(COMMENT_COMPOSER_SEND_SIZE)
            .fontColor([this.canSubmitComment() ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_tertiary')])
            .opacity(this.canSubmitComment() ? 1 : 0.45)
            .onClick(() => {
              this.submitComment()
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        if (this.commentError.length > 0) {
          Text(this.commentError)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor(Color.Red)
            .width('100%')
        }
      }
      .width('100%')
      .padding({
        left: COMMENT_COMPOSER_INNER_GAP,
        right: COMMENT_COMPOSER_INNER_GAP,
        top: COMMENT_COMPOSER_INNER_GAP,
        bottom: COMMENT_COMPOSER_INNER_GAP,
      })
      .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
      .borderRadius(COMMENT_COMPOSER_RADIUS)
      .shadow(ShadowStyle.OUTER_DEFAULT_MD)
    }
    .width('100%')
    .padding({
      left: COMMENT_COMPOSER_OUTER_GAP,
      right: COMMENT_COMPOSER_OUTER_GAP,
      bottom: this.composerBottomPadding(),
    })
  }
}

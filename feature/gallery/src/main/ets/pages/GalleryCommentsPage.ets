import { common } from '@kit.AbilityKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  CommentStructuredTranslation,
  COMMENT_TRANSLATION_PRIORITY_AUTO,
  COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
  CommentTranslationService,
  CommentTranslationSettingsState,
  BasicDataSource,
  LocalBlockService,
  LocalBlockSettings,
  LocalBlockCommentActionService,
  COMMENT_AUTHOR_BLOCK_BY_MEMBER_ID,
  COMMENT_AUTHOR_BLOCK_BY_NAME,
  COMMENT_BLOCK_ACTION_AUTHOR,
  COMMENT_BLOCK_ACTION_THIS,
  COMMENT_BLOCK_ACTION_CONTENT,
  CommentWordSegmentService,
  LocalBlockState,
  connectLocalBlock,
  ThemeConstants,
  EhConstants,
  EhApiService,
  EhApiPhpService,
  EhCookieStore,
  EhGalleryComment,
  EhGalleryCommentTextSpan,
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
  connectGalleryDetailRefreshMutation,
  DiagnosticLogger,
  EhErrorText,
  ThemeDisplayState,
  connectThemeDisplay,
  connectCommentTranslationSettings,
  immersiveTitleBarOpts,
  appSheetOptions,
  AppModalScaffold,
} from 'shared'
import { GalleryCommentsCard } from '../components/GalleryCommentsCard'
import { GalleryCommentRenderState } from '../model/GalleryCommentRenderState'
import { KeyboardAvoidMode, SymbolGlyphModifier } from '@kit.ArkUI'

// Word-panel chips: snug padding so a short token hugs its text instead of becoming a wide pill, and a
// small gap so a wrapped run reads as one sentence rather than a spaced-out list.
const WORD_CHIP_PADDING_H: number = 10
const WORD_CHIP_PADDING_V: number = 5
const WORD_CHIP_GAP: number = 6
const COMMENT_COMPOSER_BOTTOM_RESERVE: number = 136
const COMMENT_COMPOSER_FIELD_ID: string = 'gallery-comments-composer-field'
const COMMENT_COMPOSER_OUTER_GAP: number = ThemeConstants.SPACE_SM
const COMMENT_COMPOSER_INNER_GAP: number = ThemeConstants.SPACE_XS
const COMMENT_COMPOSER_SEND_SIZE: number = 36
const COMMENT_COMPOSER_CLOSE_ICON_SIZE: number =
  COMMENT_COMPOSER_SEND_SIZE - COMMENT_COMPOSER_INNER_GAP * 2
const COMMENT_COMPOSER_RADIUS: number = COMMENT_COMPOSER_SEND_SIZE / 2 + COMMENT_COMPOSER_INNER_GAP
const COMMENT_COMPOSER_INPUT_MAX_H: number = 148
const COMMENT_COMPOSER_QUOTE_LINE_W: number = 4
const COMMENT_COMPOSER_QUOTE_TEXT_BLOCK_H: number = 22 * 2 + ThemeConstants.SPACE_XS
const COMMENT_COMPOSER_QUOTE_LINE_H: number = COMMENT_COMPOSER_QUOTE_TEXT_BLOCK_H
const COMMENT_COMPOSER_QUOTE_TOP_LIFT: number = COMMENT_COMPOSER_INNER_GAP
const COMMENT_COMPOSER_QUOTE_TOP_GAP: number =
  COMMENT_COMPOSER_RADIUS -
  COMMENT_COMPOSER_QUOTE_LINE_W / 2 -
  COMMENT_COMPOSER_INNER_GAP -
  COMMENT_COMPOSER_QUOTE_TOP_LIFT
const COMMENT_COMPOSER_QUOTE_LEFT_GAP: number =
  COMMENT_COMPOSER_RADIUS - COMMENT_COMPOSER_INNER_GAP - COMMENT_COMPOSER_QUOTE_LINE_W / 2
const COMMENT_COMPOSER_CLOSE_RIGHT_GAP: number = COMMENT_COMPOSER_INNER_GAP

// Snapshot of a comment's vote/score for optimistic-vote rollback (the render state is the source of truth).
class CommentVoteSnapshot {
  commentId: string = ''
  vote: number = 0
  score: string = ''
}

/** Each word owns observable selection; stable ForEach keys never depend on selection. */
@ObservedV2
class CommentWordChoice {
  text: string = ''
  start: number = 0
  end: number = 0
  @Trace selected: boolean = false

  constructor(text: string, start: number) {
    this.text = text
    this.start = start
    this.end = start + text.length
  }
}

/** Chip bounds relative to the word-flow container, unaffected by sheet transforms. */
class WordChipBounds {
  index: number = 0
  left: number = 0
  top: number = 0
  right: number = 0
  bottom: number = 0
}

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
  // LazyForEach virtualizes the comment list: only visible cards mount (so only visible comments
  // auto-translate) and the source reloads ONLY on refresh / filter change — never on a translation
  // completion. Per-comment reactive state lives on the @ObservedV2 render states (stable, kept in a Map),
  // so one completion re-renders exactly one card instead of the whole list. Source is kept out of @Trace
  // (BasicDataSource contract); commentCount mirrors its size so build() re-evaluates the empty branch.
  private commentSource: BasicDataSource<EhGalleryComment> = new BasicDataSource();
  private renderStateMap: Map<string, GalleryCommentRenderState> = new Map();
  private referenceRenderStates: GalleryCommentRenderState[] = [];
  @Local commentCount: number = 0;
  @Local initialRefreshStarted: boolean = false;
  @Local localBlock: LocalBlockState = connectLocalBlock();
  // "Block by content" panel: the comment being processed plus its segmented candidates.
  @Local wordPanelShown: boolean = false;
  @Local wordPanelLoading: boolean = false;
  @Local wordPanelSaving: boolean = false;
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();

  // Rebuild the virtualized list from the current comments + filter. A filter toggle preserves existing
  // render states by id (so in-flight translations survive); a refresh (resetStates) rebuilds them from the
  // fresh comments. The render state — NOT the EhGalleryComment — is the single source of truth for the
  // reactive translation/vote fields.
  private rebuildCommentList(resetStates: boolean = false): void {
    const visible: EhGalleryComment[] = this.visibleComments()
    // Keep render states for ALL comments, not just the currently-visible subset, so a filter toggle
    // (uploaderOnly) or block-rule change never discards an off-filter comment's vote/translation state —
    // the render state is the single source of truth and the comment objects are not written back.
    const nextMap: Map<string, GalleryCommentRenderState> = new Map()
    const nextStates: GalleryCommentRenderState[] = []
    for (let i = 0; i < this.comments.length; i++) {
      const c: EhGalleryComment = this.comments[i]
      const existing: GalleryCommentRenderState | undefined = this.renderStateMap.get(c.commentId)
      if (existing !== undefined && !resetStates) {
        nextMap.set(c.commentId, existing)
        nextStates.push(existing)
      } else {
        const state: GalleryCommentRenderState = new GalleryCommentRenderState(c)
        nextMap.set(c.commentId, state)
        nextStates.push(state)
      }
    }
    this.renderStateMap = nextMap
    this.referenceRenderStates = nextStates
    this.commentSource.setData(visible)
    this.commentCount = visible.length
  }

  private renderStateById(commentId: string): GalleryCommentRenderState | undefined {
    return this.renderStateMap.get(commentId)
  }

  @Monitor('uploaderOnly')
  onUploaderOnlyChange(): void {
    this.rebuildCommentList()
  }

  // Block rules / display-mode / score filter changed elsewhere (LocalBlockSettingsPage) while this page
  // stays mounted: re-apply the filter so the snapshot list + count stay live (the pre-virtualization
  // build() re-filtered on every render). Preserves render states (resetStates defaults to false).
  @Monitor('localBlock.version')
  onLocalBlockChange(): void {
    this.rebuildCommentList()
  }

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

  private composerBlurTint(): ResourceColor {
    return this.themeDisplay.effectiveDark
      ? ThemeConstants.FROSTED_SURFACE_DARK_TINT
      : ThemeConstants.FROSTED_SURFACE_LIGHT_TINT
  }

  private composerBorderWidth(): number {
    return this.themeDisplay.effectiveDark ? ThemeConstants.FROSTED_SURFACE_BORDER_WIDTH : 0
  }

  private composerBorderColor(): ResourceColor {
    return this.themeDisplay.effectiveDark ? ThemeConstants.FROSTED_SURFACE_DARK_BORDER : Color.Transparent
  }

  private uploaderMemberId(): string {
    const uploader: EhGalleryComment | undefined = this.comments.find(
      (c: EhGalleryComment) => c.isUploader || c.score.length === 0,
    )
    return uploader !== undefined ? uploader.memberId : ''
  }

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private scheduleInitialRefreshIfNeeded(): void {
    if (
      this.initialRefreshStarted ||
      this.comments.length > 0 ||
      this.params.gid.length === 0 ||
      this.params.token.length === 0
    ) {
      return
    }
    this.initialRefreshStarted = true
    setTimeout(() => {
      this.refreshController.triggerTopRefresh()
    }, 0)
  }

  private visibleComments(): EhGalleryComment[] {
    let source: EhGalleryComment[] = this.comments
    if (this.uploaderOnly) {
      const memberId: string = this.uploaderMemberId()
      if (memberId.length > 0) {
        source = this.comments.filter((c: EhGalleryComment) => c.memberId === memberId)
      } else {
        source = this.comments.filter((c: EhGalleryComment) => c.isUploader || c.score.length === 0)
      }
    }
    return LocalBlockService.filterComments(source)
  }

  // The LazyForEach builder asks for a comment's render state; it is guaranteed present after
  // rebuildCommentList, but create-and-insert defensively if a card ever mounts ahead of a rebuild.
  private renderStateFor(comment: EhGalleryComment): GalleryCommentRenderState {
    const current: GalleryCommentRenderState | undefined = this.renderStateMap.get(
      comment.commentId,
    )
    if (current !== undefined) {
      return current
    }
    const state: GalleryCommentRenderState = new GalleryCommentRenderState(comment)
    this.renderStateMap.set(comment.commentId, state)
    return state
  }

  private renderVote(comment: EhGalleryComment): number {
    const state: GalleryCommentRenderState | undefined = this.renderStateById(comment.commentId)
    return state !== undefined ? state.vote : comment.vote
  }

  private canOpenCommentSheet(): boolean {
    return (
      this.params.gid.length > 0 &&
      this.params.token.length > 0 &&
      EhCookieStore.getInstance().isLogin()
    )
  }

  private canSubmitComment(): boolean {
    if (
      this.commentText.trim().length < 10 ||
      !this.canOpenCommentSheet() ||
      this.commentSubmitting
    ) {
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
      const isEx: boolean = connectSiteMode().isEx
      const result = await EhApiService.getInstance().getGalleryDetail(
        this.params.gid,
        this.params.token,
        isEx,
      )
      if (connectSiteMode().isEx !== isEx) {
        return
      }
      // Bad/interstitial response (no previews and no comments): keep the existing comments instead of
      // wiping them to a blank list.
      if (result.images.length === 0 && result.comments.length === 0 && this.comments.length > 0) {
        DiagnosticLogger.warn(
          'gallery',
          'comments_refresh_empty_skip',
          `gid=${this.params.gid} bad response, keeping existing comments`,
        )
        return
      }
      this.params.apikey = result.gallery.apikey
      this.params.apiuid = result.gallery.apiuid
      this.params.title = result.gallery.displayTitle(false)
      this.comments = result.comments
      if (this.visibleComments().length === 0) {
        this.uploaderOnly = false
      }
      this.rebuildCommentList(true)
      connectGalleryDetailRefreshMutation().publish(
        this.params.gid,
        this.params.token,
        isEx,
        result,
      )
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
    return resultVote > 0
      ? $r('app.string.comment_vote_up_success')
      : $r('app.string.comment_vote_down_success')
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // All reactive comment state mutations go through the per-comment @ObservedV2 render state (a @Trace
  // write re-renders exactly that one card). No comments-array slice, no global version bump. Set the fields
  // SYNCHRONOUSLY here — the animation is owned by the card (it mirrors these into its @Local inside its own
  // animateTo, which is what actually captures the card's height/content change; a page-side animateTo
  // across components does not).
  private applyCommentTranslationState(
    commentId: string,
    translated: string | undefined,
    translatedSpans: EhGalleryCommentTextSpan[] | undefined,
    shown: boolean | undefined,
    loading: boolean | undefined,
    autoStarted: boolean | undefined,
  ): void {
    const state: GalleryCommentRenderState | undefined = this.renderStateById(commentId)
    if (state === undefined) {
      return
    }
    if (translated !== undefined) {
      state.translationText = translated
    }
    if (translatedSpans !== undefined) {
      state.translationSpans = translatedSpans
    }
    if (shown !== undefined) {
      state.translationShown = shown
    }
    if (loading !== undefined) {
      state.translationLoading = loading
    }
    if (autoStarted !== undefined) {
      state.translationAutoStarted = autoStarted
    }
  }

  private toggleCommentTranslation(comment: EhGalleryComment): void {
    if (comment.commentId.length === 0) {
      return
    }
    const state: GalleryCommentRenderState | undefined = this.renderStateById(comment.commentId)
    if (state === undefined || state.translationText.length === 0) {
      return
    }
    this.applyCommentTranslationState(
      comment.commentId,
      undefined,
      undefined,
      !state.translationShown,
      false,
      undefined,
    )
  }

  private applyResolvedCommentTranslation(comment: EhGalleryComment, translated: string): void {
    if (comment.commentId.length === 0 || translated.length === 0) {
      return
    }
    this.applyCommentTranslationState(comment.commentId, translated, undefined, true, false, undefined)
  }

  private handleCommentTranslationError(commentId: string, error: Error, priority: number): void {
    if (priority === COMMENT_TRANSLATION_PRIORITY_AUTO && CommentTranslationService.isQueueCapacityError(error)) {
      DiagnosticLogger.info(
        'translation',
        'comment_auto_queue_discarded',
        `id=${commentId} ${error.message}`,
      )
      return
    }
    DiagnosticLogger.warn(
      'translation',
      'comment_request_failed',
      `id=${commentId} ${error.message}`,
    )
    this.showCommentToast($r('app.string.comment_translation_failed'))
  }

  private translateComment(
    comment: EhGalleryComment,
    sourceText: string,
    force: boolean,
    priority: number = COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
  ): void {
    if (comment.commentId.length === 0 || sourceText.trim().length === 0) {
      return
    }
    const state: GalleryCommentRenderState | undefined = this.renderStateById(comment.commentId)
    if (state !== undefined && state.translationLoading) {
      return
    }
    if (state !== undefined && state.translationText.length > 0 && !force) {
      this.toggleCommentTranslation(comment)
      return
    }
    this.applyCommentTranslationState(comment.commentId, undefined, undefined, true, true, undefined)
    if (comment.contentSpans.length > 0 && sourceText === comment.contentText) {
      CommentTranslationService.translateStructured(
        this.ctx(),
        sourceText,
        comment.contentSpans,
        force,
        priority,
      )
        .then((translated: CommentStructuredTranslation) => {
          if (translated.text.length > 0) {
            this.applyCommentTranslationState(
              comment.commentId,
              translated.text,
              translated.spans,
              true,
              false,
              undefined,
            )
          }
        })
        .catch((error: Error) => {
          this.handleCommentTranslationError(comment.commentId, error, priority)
        })
        .finally(() => {
          this.applyCommentTranslationState(comment.commentId, undefined, undefined, undefined, false, undefined)
        })
      return
    }
    CommentTranslationService.translate(this.ctx(), sourceText, force, priority)
      .then((translated: string) => {
        if (translated.length > 0) {
          this.applyCommentTranslationState(comment.commentId, translated, [], true, false, undefined)
        }
      })
      .catch((error: Error) => {
        this.handleCommentTranslationError(comment.commentId, error, priority)
      })
      .finally(() => {
        this.applyCommentTranslationState(comment.commentId, undefined, undefined, undefined, false, undefined)
      })
  }

  private ensureCommentTranslation(comment: EhGalleryComment, sourceText: string): void {
    if (comment.commentId.length === 0 || sourceText.trim().length === 0) {
      return
    }
    const state: GalleryCommentRenderState | undefined = this.renderStateById(comment.commentId)
    if (state === undefined || state.translationLoading) {
      return
    }
    if (state.translationText.length > 0) {
      this.applyCommentTranslationState(comment.commentId, undefined, undefined, true, false, undefined)
      return
    }
    this.translateComment(comment, sourceText, false)
  }

  private autoTranslateComment(comment: EhGalleryComment, sourceText: string): void {
    const state: GalleryCommentRenderState | undefined = this.renderStateById(comment.commentId)
    if (
      !this.translationSettings.enabled ||
      !this.translationSettings.autoTranslate ||
      comment.commentId.length === 0 ||
      (state !== undefined && state.translationAutoStarted) ||
      sourceText.trim().length === 0
    ) {
      return
    }
    this.applyCommentTranslationState(comment.commentId, undefined, undefined, true, false, true)
    if (comment.contentSpans.length > 0 && sourceText === comment.contentText) {
      this.translateComment(comment, sourceText, false, COMMENT_TRANSLATION_PRIORITY_AUTO)
      return
    }
    CommentTranslationService.getCached(
      this.ctx(),
      sourceText,
      CommentTranslationService.targetLanguage(),
    )
      .then((cached: string) => {
        if (cached.length > 0) {
          this.applyCommentTranslationState(comment.commentId, cached, [], true, false, undefined)
        } else {
          this.translateComment(comment, sourceText, false, COMMENT_TRANSLATION_PRIORITY_AUTO)
        }
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn(
          'translation',
          'comment_auto_cache_failed',
          `id=${comment.commentId} ${error.message}`,
        )
        this.translateComment(comment, sourceText, false, COMMENT_TRANSLATION_PRIORITY_AUTO)
      })
  }

  private applyVoteResult(result: CommentVoteResult): void {
    this.applyVoteState(result.commentId, result.commentScore.toString(), result.commentVote)
    const details: string[] = this.scoreDetailsFor(result.commentId)
    connectCommentVoteMutation().publish(
      this.params.gid,
      result.commentId,
      result.commentScore.toString(),
      result.commentVote,
      details,
    )
  }

  private scoreDetailsFor(commentId: string): string[] {
    const state: GalleryCommentRenderState | undefined = this.renderStateById(commentId)
    if (state !== undefined) {
      return state.scoreDetails.slice()
    }
    for (let i = 0; i < this.comments.length; i++) {
      if (this.comments[i].commentId === commentId) {
        return this.comments[i].scoreDetails.slice()
      }
    }
    return []
  }

  private notifyCommentRowChanged(commentId: string): void {
    const visible: EhGalleryComment[] = this.commentSource.getAll()
    for (let i = 0; i < visible.length; i++) {
      if (visible[i].commentId === commentId) {
        this.commentSource.notifyDataChanged(i)
        return
      }
    }
  }

  private applyVoteState(
    commentId: string,
    score: string,
    vote: number,
    scoreDetails?: string[],
  ): void {
    for (let i = 0; i < this.comments.length; i++) {
      const c: EhGalleryComment = this.comments[i]
      if (c.commentId === commentId) {
        c.score = score
        c.vote = vote
        if (scoreDetails !== undefined) {
          c.scoreDetails = scoreDetails.slice()
        }
        break
      }
    }
    const state: GalleryCommentRenderState | undefined = this.renderStateById(commentId)
    if (state !== undefined) {
      state.score = score
      state.vote = vote
      if (scoreDetails !== undefined) {
        state.scoreDetails = scoreDetails.slice()
      }
    }
    // Voting does not change comment ordering or the regular list membership. Reloading the whole
    // LazyForEach here can race the row-level change notification and leave the card with its old score;
    // the stable render state above is already the reactive source of truth for this row.
    this.notifyCommentRowChanged(commentId)
  }

  private async refreshCommentVoteDetails(
    commentId: string,
    acceptedScore: string,
    acceptedVote: number,
  ): Promise<void> {
    const result = await EhApiService.getInstance().getGalleryDetail(
      this.params.gid,
      this.params.token,
      connectSiteMode().isEx,
    )
    for (let i = 0; i < result.comments.length; i++) {
      const comment: EhGalleryComment = result.comments[i]
      if (comment.commentId !== commentId) {
        continue
      }
      // The vote endpoint returns the accepted aggregate score immediately. The follow-up HTML
      // fetch is only used to obtain score details; it can still carry the previous aggregate while
      // the server-side comment page catches up, so do not overwrite the accepted score/vote here.
      this.applyVoteState(commentId, acceptedScore, acceptedVote, comment.scoreDetails)
      connectCommentVoteMutation().publish(
        this.params.gid,
        commentId,
        acceptedScore,
        acceptedVote,
        comment.scoreDetails,
      )
      DiagnosticLogger.info(
        'gallery',
        'comment_vote_details_refreshed',
        `id=${commentId} score=${acceptedScore} details=${comment.scoreDetails.length}`,
      )
      return
    }
    DiagnosticLogger.warn(
      'gallery',
      'comment_vote_details_missing',
      `id=${commentId} comments=${result.comments.length}`,
    )
  }

  private applyLocalVote(commentId: string, vote: number): CommentVoteSnapshot | undefined {
    const state: GalleryCommentRenderState | undefined = this.renderStateById(commentId)
    if (state === undefined) {
      return undefined
    }
    const previous: CommentVoteSnapshot = new CommentVoteSnapshot()
    previous.commentId = commentId
    previous.vote = state.vote
    previous.score = state.score
    let nextScore: string = state.score
    if (state.score.length > 0) {
      const score: number = Number.parseInt(state.score, 10)
      if (!Number.isNaN(score)) {
        nextScore = (score + vote - state.vote).toString()
      }
    }
    this.applyVoteState(commentId, nextScore, vote)
    return previous
  }

  private restoreComment(snapshot: CommentVoteSnapshot): void {
    this.applyVoteState(snapshot.commentId, snapshot.score, snapshot.vote)
  }

  private showCommentToast(message: ResourceStr): void {
    this.getUIContext()
      .getPromptAction()
      .openToast({ message: message })
      .catch((_error: Error) => {
        // Toast failures are non-critical; the comment state has already been updated or logged.
      })
  }

  /**
   * Comment-row block menu. Writing the rule bumps LocalBlockState.version, which this page observes to
   * rebuild the list, so no extra refresh call is needed here.
   */
  private handleCommentBlock(comment: EhGalleryComment, action: string): void {
    if (action === COMMENT_BLOCK_ACTION_AUTHOR) {
      LocalBlockCommentActionService.blockCommentAuthor(this.ctx(), comment)
        .then((basis: string) => {
          if (basis === COMMENT_AUTHOR_BLOCK_BY_MEMBER_ID) {
            this.showCommentToast($r('app.string.comment_block_author_success'))
            return
          }
          this.showCommentToast(basis === COMMENT_AUTHOR_BLOCK_BY_NAME
            ? $r('app.string.comment_block_author_by_name_success')
            : $r('app.string.comment_block_this_unavailable'))
        })
        .catch(() => {
          this.showCommentToast($r('app.string.comment_block_failed'))
        })
      return
    }
    if (action === COMMENT_BLOCK_ACTION_THIS) {
      LocalBlockCommentActionService.blockComment(this.ctx(), comment)
        .then((blocked: boolean) => {
          this.showCommentToast(blocked
            ? $r('app.string.comment_block_this_success')
            : $r('app.string.comment_block_this_unavailable'))
        })
        .catch(() => {
          this.showCommentToast($r('app.string.comment_block_failed'))
        })
      return
    }
    if (action === COMMENT_BLOCK_ACTION_CONTENT) {
      this.openWordPanel(comment.contentText)
    }
  }

  @Local wordTokens: CommentWordChoice[] = [];
  private wordSource: string = '';
  private wordRequest: number = 0;
  private wordChipBounds: WordChipBounds[] = [];
  private wordTouchSelecting: boolean = true;
  private wordTouchLastIndex: number = -1;

  private openWordPanel(content: string): void {
    const request: number = ++this.wordRequest
    const source: string = LocalBlockSettings.cleanText(content)
    this.wordSource = source
    this.wordTokens = []
    this.wordChipBounds = []
    this.wordPanelLoading = true
    this.wordPanelShown = true
    CommentWordSegmentService.segment(source)
      .then((words: string[]) => {
        if (!this.wordPanelShown || request !== this.wordRequest) {
          return
        }
        const choices: CommentWordChoice[] = []
        let offset: number = 0
        for (const word of words) {
          const start: number = source.indexOf(word, offset)
          if (start >= 0) {
            choices.push(new CommentWordChoice(word, start))
            offset = start + word.length
          }
        }
        this.wordTokens = choices
        this.wordPanelLoading = false
      })
      .catch(() => {
        if (request === this.wordRequest) {
          this.wordPanelLoading = false
        }
      })
  }

  private selectAllWords(): void {
    for (const word of this.wordTokens) {
      word.selected = true
    }
  }

  private clearWordSelection(): void {
    for (const word of this.wordTokens) {
      word.selected = false
    }
  }

  private recordWordChipBounds(index: number, area: Area): void {
    const bounds: WordChipBounds = new WordChipBounds()
    bounds.index = index
    bounds.left = Number(area.position.x)
    bounds.top = Number(area.position.y)
    bounds.right = bounds.left + Number(area.width)
    bounds.bottom = bounds.top + Number(area.height)
    this.wordChipBounds[index] = bounds
  }

  private wordChipIndexAt(x: number, y: number): number {
    for (const bounds of this.wordChipBounds) {
      if (bounds !== undefined && x >= bounds.left && x <= bounds.right &&
        y >= bounds.top && y <= bounds.bottom) {
        return bounds.index
      }
    }
    return -1
  }

  private beginWordTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down || event.touches.length === 0) {
      return
    }
    const touch: TouchObject = event.touches[0]
    const index: number = this.wordChipIndexAt(touch.x, touch.y)
    this.wordTouchLastIndex = index
    this.wordTouchSelecting = index >= 0 ? !this.wordTokens[index].selected : true
  }

  private paintWordDrag(event: GestureEvent): void {
    if (event.fingerList.length === 0 || this.wordTouchLastIndex < 0) {
      return
    }
    const finger: FingerInfo = event.fingerList[0]
    const index: number = this.wordChipIndexAt(finger.localX, finger.localY)
    if (index < 0) {
      return
    }
    const start: number = Math.min(this.wordTouchLastIndex, index)
    const end: number = Math.max(this.wordTouchLastIndex, index)
    for (let i: number = start; i <= end; i++) {
      this.wordTokens[i].selected = this.wordTouchSelecting
    }
    this.wordTouchLastIndex = index
  }

  /** Preview and persistence share the same flat source, preserving word separators without hard breaks. */
  private wordBlockPhrases(): string[] {
    const phrases: string[] = []
    let start: number = -1
    let end: number = 0
    for (const word of this.wordTokens) {
      if (word.selected) {
        if (start < 0) {
          start = word.start
        }
        end = word.end
      } else if (start >= 0) {
        phrases.push(this.wordSource.substring(start, end))
        start = -1
      }
    }
    if (start >= 0) {
      phrases.push(this.wordSource.substring(start, end))
    }
    return phrases.filter((phrase: string, index: number) =>
      phrases.findIndex((item: string) => item.toLowerCase() === phrase.toLowerCase()) === index)
  }

  private wordSelectedCount(): number {
    return this.wordTokens.filter((word: CommentWordChoice) => word.selected).length
  }

  private wordConfirmText(): ResourceStr {
    const phrases: number = this.wordBlockPhrases().length
    return phrases === 0 ? $r('app.string.comment_word_panel_confirm')
      : AppStrings.get('comment_word_panel_confirm_count').replace('%d', `${phrases}`)
  }

  private closeWordPanel(): void {
    this.wordRequest++
    this.wordPanelShown = false
    this.wordTokens = []
    this.wordSource = ''
    this.wordChipBounds = []
    this.wordTouchLastIndex = -1
    this.wordPanelLoading = false
    this.wordPanelSaving = false
  }

  private confirmWordBlock(): void {
    if (this.wordPanelSaving) {
      return
    }
    const phrases: string[] = this.wordBlockPhrases()
    if (phrases.length === 0) {
      this.showCommentToast($r('app.string.comment_word_block_none'))
      return
    }
    DiagnosticLogger.info('local_block', 'word_block_confirm', `tokens=${this.wordSelectedCount()} phrases=${phrases.length}`)
    const request: number = this.wordRequest
    this.wordPanelSaving = true
    LocalBlockCommentActionService.blockCommentWords(this.ctx(), phrases)
      .then((count: number) => {
        if (request === this.wordRequest) {
          this.closeWordPanel()
        }
        DiagnosticLogger.info('local_block', 'word_block_saved', `phrases=${count}`)
        this.showCommentToast(AppStrings.get('comment_word_block_success').replace('%d', `${count}`))
      })
      .catch((error: Error) => {
        if (request === this.wordRequest) {
          this.wordPanelSaving = false
        }
        DiagnosticLogger.warn('local_block', 'word_block_failed', error.message)
        this.showCommentToast($r('app.string.comment_block_failed'))
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
    const previous: CommentVoteSnapshot | undefined = this.applyLocalVote(commentId, localVote)
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
      try {
        await this.refreshCommentVoteDetails(
          result.commentId,
          result.commentScore.toString(),
          result.commentVote,
        )
      } catch (detailsError) {
        DiagnosticLogger.warn(
          'gallery',
          'comment_vote_details_refresh_failed',
          (detailsError as Error).message,
        )
      }
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
        'icon': $r('sys.symbol.message_on_message_fill'),
        'symbolEndIcon': new SymbolGlyphModifier($r('sys.symbol.checkmark')),
        'isEnabled': this.comments.length > 0,
        'action': () => {
          this.uploaderOnly = false
          this.showCommentToast($r('app.string.comment_filter_all'))
        },
      }
    } else {
      uploaderOnly = {
        'label': $r('app.string.comment_filter_uploader_only'),
        'icon': $r('sys.symbol.message_on_message'),
        'isEnabled': this.comments.length > 0,
        'action': () => {
          this.uploaderOnly = true
          this.showCommentToast($r('app.string.comment_filter_uploader_only'))
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
          bottomPadding: COMMENT_COMPOSER_BOTTOM_RESERVE,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.refreshComments()
          },
        }) {
          if (this.commentCount > 0) {
            ListItem() {
              this.CommentsHeader()
            }
            LazyForEach(
              this.commentSource,
              (comment: EhGalleryComment) => {
                ListItem() {
                  GalleryCommentsCard({
                    comments: this.comments,
                    referenceComments: this.comments,
                    useSingleComment: true,
                    singleComment: comment,
                    renderState: this.renderStateFor(comment),
                    referenceRenderStates: this.referenceRenderStates,
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
                    onBlock: (selectedComment: EhGalleryComment, action: string) => {
                      this.handleCommentBlock(selectedComment, action)
                    },
                    onTranslate: (selectedComment: EhGalleryComment, sourceText: string) => {
                      this.translateComment(selectedComment, sourceText, false)
                      return Promise.resolve('')
                    },
                    onEnsureTranslation: (selectedComment: EhGalleryComment, sourceText: string) => {
                      this.ensureCommentTranslation(selectedComment, sourceText)
                    },
                    onTranslationResolved: (
                      selectedComment: EhGalleryComment,
                      translated: string,
                    ) => {
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
    .bindSheet(this.wordPanelShown, this.WordBlockPanel(), this.wordPanelSheetOptions())
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryCommentsParams
      if (p !== undefined) {
        this.params = p
        this.comments = p.comments
        this.rebuildCommentList(true)
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
      Text(`(${this.commentCount})`)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
  }

  @Builder
  private CommentComposerFields() {
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
        .fontColor([
          this.canSubmitComment()
            ? ThemeConstants.BRAND_PRIMARY
            : $r('sys.color.font_tertiary'),
        ])
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

  @Builder
  private CommentComposerSurface() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      this.CommentComposerFields()
    }
    .width('100%')
    .padding({
      left: COMMENT_COMPOSER_INNER_GAP,
      right: COMMENT_COMPOSER_INNER_GAP,
      top: COMMENT_COMPOSER_INNER_GAP,
      bottom: COMMENT_COMPOSER_INNER_GAP,
    })
    .backdropBlur(ThemeConstants.FROSTED_SURFACE_BLUR_RADIUS)
    .backgroundColor(this.composerBlurTint())
    .border({ width: this.composerBorderWidth(), color: this.composerBorderColor() })
    .borderRadius(COMMENT_COMPOSER_RADIUS)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }

  @Builder
  CommentComposer() {
    Column() {
      this.CommentComposerSurface()
    }
    .width('100%')
    .padding({
      left: COMMENT_COMPOSER_OUTER_GAP,
      right: COMMENT_COMPOSER_OUTER_GAP,
      bottom: this.composerBottomPadding(),
    })
  }

  private wordPanelSheetOptions(): SheetOptions {
    return appSheetOptions({
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: false,
      onDisappear: () => {
        if (this.wordPanelShown) {
          this.closeWordPanel()
        }
      },
    })
  }

  @Builder
  private WordBlockPanel() {
    AppModalScaffold({
      title: $r('app.string.comment_word_panel_title'),
      confirmText: this.wordConfirmText(),
      confirmEnabled: this.wordSelectedCount() > 0 && !this.wordPanelSaving,
      contentOwnsScrolling: true,
      closeAction: () => {
        this.closeWordPanel()
      },
      confirmAction: () => {
        this.confirmWordBlock()
      },
    }) {
      Scroll() {
        Column({ space: ThemeConstants.SPACE_SM }) {
          Row({ space: ThemeConstants.SPACE_SM }) {
            Text(AppStrings.get('comment_word_panel_selected')
              .replace('%d', `${this.wordSelectedCount()}`))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            this.WordPanelAction($r('app.string.comment_word_panel_select_all'), () => {
              this.selectAllWords()
            })
            this.WordPanelAction($r('app.string.comment_word_panel_clear'), () => {
              this.clearWordSelection()
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text($r('app.string.comment_word_panel_hint'))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')

          if (this.wordPanelLoading) {
            Row() {
              LoadingProgress().width(24).height(24)
            }
            .width('100%')
            .height(96)
            .justifyContent(FlexAlign.Center)
          } else if (this.wordTokens.length === 0) {
            Text($r('app.string.comment_word_panel_empty'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          } else {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(
                this.wordTokens,
                (word: CommentWordChoice, index: number) => {
                  this.WordChip(word, index)
                },
                (word: CommentWordChoice) => `${word.start}_${word.end}`,
              )
            }
            .width('100%')
            .id('comment-word-flow')
            .onTouch((event: TouchEvent) => {
              this.beginWordTouch(event)
            })
            .gesture(
              PanGesture({ direction: PanDirection.Horizontal })
                .onActionStart((event: GestureEvent) => {
                  this.paintWordDrag(event)
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.paintWordDrag(event)
                })
                .onActionEnd(() => {
                  this.wordTouchLastIndex = -1
                })
                .onActionCancel(() => {
                  this.wordTouchLastIndex = -1
                }),
            )
          }
          if (this.wordSelectedCount() > 0) {
            Text(AppStrings.get('comment_word_panel_preview')
              .replace('%s', this.wordBlockPhrases().join('；')))
              .id('comment-word-preview')
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: ThemeConstants.SPACE_MD, bottom: ThemeConstants.SPACE_XL })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
    }
  }

  @Builder
  private WordPanelAction(label: ResourceStr, action: () => void) {
    Text(label)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor(ThemeConstants.BRAND_PRIMARY)
      .padding({
        left: ThemeConstants.SPACE_SM,
        right: ThemeConstants.SPACE_SM,
        top: ThemeConstants.SPACE_XS,
        bottom: ThemeConstants.SPACE_XS,
      })
      .onClick(action)
  }

  @Builder
  private WordChip(word: CommentWordChoice, index: number) {
    Text(word.text)
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor(word.selected ? ThemeConstants.TEXT_ON_BRAND : $r('sys.color.font_primary'))
      .backgroundColor(word.selected
        ? ThemeConstants.BRAND_PRIMARY
        : Color.Transparent)
      .border({ width: 1, color: word.selected ? ThemeConstants.BRAND_PRIMARY : ThemeConstants.TEXT_TERTIARY })
      .borderRadius(ThemeConstants.RADIUS_ROUND)
      .padding({
        left: WORD_CHIP_PADDING_H,
        right: WORD_CHIP_PADDING_H,
        top: WORD_CHIP_PADDING_V,
        bottom: WORD_CHIP_PADDING_V,
      })
      .margin({ right: WORD_CHIP_GAP, bottom: WORD_CHIP_GAP })
      .constraintSize({ maxWidth: '100%' })
      .id(`comment-word-${index}`)
      .accessibilitySelected(word.selected)
      .onClick(() => {
        word.selected = !word.selected
      })
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.recordWordChipBounds(index, area)
      })
  }
}

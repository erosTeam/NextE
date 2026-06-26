import {
  COMMENT_TRANSLATION_DISPLAY_BILINGUAL,
  CommentTranslationSettingsState,
  CommentTranslationService,
  EhConstants,
  EhGalleryComment,
  EhUrlRouter,
  GalleryWebParams,
  LocalBlockService,
  ThemeConstants,
  connectCommentTranslationSettings,
  connectNavStack,
  connectSiteMode,
  publishPendingEhUrl,
} from 'shared'
import { GalleryCommentRenderState } from '../model/GalleryCommentRenderState'

const COMMENT_FOOTER_ACTION_SIZE: number = 30
const COMMENT_FOOTER_ICON_SIZE: number = 16
const COMMENT_LINK_RE: RegExp = /https?:\/\/[^\s<>"'，。！？；、）\]\}]+/g

class CommentTextSegment {
  key: string = ''
  text: string = ''
  url: string = ''
  emphasized: boolean = false

  constructor(key: string = '', text: string = '', url: string = '', emphasized: boolean = false) {
    this.key = key
    this.text = text
    this.url = url
    this.emphasized = emphasized
  }
}

/**
 * Comments list, shared by the detail-page PEEK and the full comments page (eros_fe TopCommentEx +
 * galleryComment). `max > 0` is the peek: it shows the first `max` comments, clamps long text, and
 * any non-empty peek can open the full comments page. `max === 0` shows them all (the page). The peek
 * sits BEFORE the previews on the detail page so comments are reachable without scrolling past every
 * thumbnail.
 */
@ComponentV2
export struct GalleryCommentsCard {
  @Require @Param comments: EhGalleryComment[];
  @Param referenceComments: EhGalleryComment[] = [];
  @Param useSingleComment: boolean = false;
  @Param singleComment: EhGalleryComment = new EhGalleryComment();
  @Param renderState: GalleryCommentRenderState = new GalleryCommentRenderState();
  @Param parentManagedActions: boolean = false;
  @Param max: number = 0;
  @Param showHeader: boolean = true;
  @Event onMore: () => void = () => {};
  @Event onAuthor: (name: string) => void = (_name: string) => {};
  @Event onVote: (comment: EhGalleryComment, vote: number) => void = (
    _comment: EhGalleryComment,
    _vote: number,
  ) => {};
  @Event onReply: (comment: EhGalleryComment) => void = (_comment: EhGalleryComment) => {};
  @Event onEdit: (comment: EhGalleryComment) => void = (_comment: EhGalleryComment) => {};
  @Event onTranslate: (comment: EhGalleryComment, sourceText: string) => Promise<string> = (
    _comment: EhGalleryComment,
    _sourceText: string,
  ) => Promise.resolve('');
  @Event onTranslationResolved: (comment: EhGalleryComment, translated: string) => void = (
    _comment: EhGalleryComment,
    _translated: string,
  ) => {};
  @Event onToggleTranslation: (comment: EhGalleryComment) => void = (
    _comment: EhGalleryComment,
  ) => {};
  @Event onAutoTranslate: (comment: EhGalleryComment, sourceText: string) => void = (
    _comment: EhGalleryComment,
    _sourceText: string,
  ) => {};
  private stack: NavPathStack = connectNavStack().stack;
  @Local translationSettings: CommentTranslationSettingsState = connectCommentTranslationSettings();
  @Local expandedBlockedCommentKeys: string[] = [];
  // Card-local mirror of the page-held render-state translation fields. The body/icon read THESE (in the
  // parentManaged path) and they are synced from renderState inside the card's OWN animateTo (see
  // onRenderStateTranslationChange) — so the height/content change is captured and animated. Routing the
  // animation through the page mutating renderState did not work: a cross-component animateTo doesn't
  // capture the card's layout change, which is why show/hide toggling stopped animating.
  @Local localTranslationText: string = '';
  @Local localTranslationShown: boolean = false;
  @Local localTranslationLoading: boolean = false;
  // Height-measure animation machinery (restored verbatim from the pre-virtualization card): when a
  // translation appears, the translated body is rendered offscreen to MEASURE its target height, then the
  // visible body is locked to the start height and animateTo grows it to the target while the content swaps
  // — giving BOTH a height animation and a content transition. animateTo alone can't do this because the
  // first appearance has no prior height to interpolate from.
  @Local commentBodyMeasuredHeight: number = 0;
  @Local commentBodyAnimatedHeight: number = 0;
  @Local commentBodyHeightLocked: boolean = false;
  @Local pendingTranslationMeasure: boolean = false;
  // Direction of the pending measure-animate: true = animating TO the translation, false = back to original.
  // The offscreen body renders this target so its height is measured before the visible body animates to it.
  @Local pendingShowTranslation: boolean = false;
  // Only a user-initiated translate/toggle animates; auto-translate / cached results sync instantly (as the
  // original did) so opening a comment-heavy page doesn't animate every visible card at once.
  private manualTranslateArmed: boolean = false;
  // Per-instance memo of the full-list-dependent parse work (reply resolution sorts the whole comment
  // array). Stable for an instance's comment(s); reset only if the reference list identity changes. Keeps a
  // translation re-render from re-sorting every comment on every frame.
  private sortedCache: EhGalleryComment[] | null = null;
  private replyRefsCache: Map<string, EhGalleryComment[]> = new Map();
  private displayTextCache: Map<string, string> = new Map();

  // Auto-translate the comment(s) this card actually mounted — under LazyForEach that is only the visible
  // ones, so we translate "what's on screen" instead of the whole list. Also fires when the user flips the
  // auto-translate / enabled settings while viewing.
  @Monitor('translationSettings.enabled', 'translationSettings.autoTranslate')
  onTranslationInputsChanged(): void {
    this.autoTranslateVisibleComments()
  }

  @Monitor('referenceComments')
  onReferenceCommentsChanged(): void {
    this.sortedCache = null
    this.replyRefsCache.clear()
    this.displayTextCache.clear()
  }

  // The page mutates this comment's render state (translate result, toggle show/hide, loading). The card
  // mirrors it into @Local: a user-initiated change (manualTranslateArmed) runs the height-measure animation
  // (applyResolvedTranslation -> offscreen measure -> animate height + content); auto/cached changes sync
  // instantly. The spinner flag always follows immediately.
  @Monitor(
    'renderState.translationText',
    'renderState.translationShown',
    'renderState.translationLoading',
  )
  onRenderStateTranslationChange(): void {
    if (!this.parentManagedActions) {
      return
    }
    this.localTranslationLoading = this.renderState.translationLoading
    const targetText: string = this.renderState.translationText
    const targetShown: boolean = this.renderState.translationShown
    const wantTranslation: boolean = targetShown && targetText.length > 0
    const hasNewText: boolean = targetText.length > 0 && this.localTranslationText !== targetText
    const needShow: boolean = wantTranslation && (!this.localTranslationShown || hasNewText)
    const needHide: boolean = !wantTranslation && this.localTranslationShown
    if (!needShow && !needHide) {
      return
    }
    // Keep the latest translated text available (for the offscreen measure + final render); does not change
    // the visible body while it is still showing the original (localTranslationShown stays false).
    if (hasNewText) {
      this.localTranslationText = targetText
    }
    if (this.manualTranslateArmed) {
      // User-initiated → run the bidirectional height-measure animation.
      this.manualTranslateArmed = false
      this.pendingShowTranslation = needShow
      this.pendingTranslationMeasure = true
    } else {
      // Auto / cached → apply instantly.
      this.localTranslationShown = needShow
    }
  }

  aboutToAppear(): void {
    // Seed the mirror without animation (initial mount / card recycle): the render state may already carry a
    // cached translation, which should appear instantly, not animate in.
    this.localTranslationText = this.renderState.translationText
    this.localTranslationShown = this.renderState.translationShown
    this.localTranslationLoading = this.renderState.translationLoading
    this.autoTranslateVisibleComments()
  }

  // Offscreen measure → lock → animate height + swap content (restored from the original card).
  private updateCommentBodyHeight(area: Area): void {
    if (this.commentBodyHeightLocked) {
      return
    }
    const height: number = area.height as number
    if (height > 0) {
      this.commentBodyMeasuredHeight = height
    }
  }

  private handlePendingTranslationArea(_c: EhGalleryComment, area: Area): void {
    if (!this.pendingTranslationMeasure) {
      return
    }
    const nextHeight: number = area.height as number
    if (nextHeight <= 0) {
      return
    }
    const showTranslation: boolean = this.pendingShowTranslation
    const startHeight: number =
      this.commentBodyMeasuredHeight > 0 ? this.commentBodyMeasuredHeight : nextHeight
    this.pendingTranslationMeasure = false
    this.commentBodyAnimatedHeight = startHeight
    this.commentBodyHeightLocked = true
    setTimeout((): void => {
      this.getUIContext().animateTo(
        { duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut },
        () => {
          // Flip the visible body to the target (translation or original) and grow/shrink to its height.
          this.localTranslationShown = showTranslation
          this.localTranslationLoading = false
          this.commentBodyAnimatedHeight = nextHeight
        },
      )
      setTimeout((): void => {
        this.commentBodyHeightLocked = false
        this.commentBodyAnimatedHeight = 0
        this.commentBodyMeasuredHeight = nextHeight
      }, ThemeConstants.ANIM_DURATION + ThemeConstants.ANIM_DONE_DELAY_MS)
    }, 0)
  }

  private sourceComments(): EhGalleryComment[] {
    if (this.useSingleComment) {
      return [this.singleComment]
    }
    return this.comments
  }

  private referenceSourceComments(): EhGalleryComment[] {
    return this.referenceComments.length > 0 ? this.referenceComments : this.sourceComments()
  }

  private hasMore(): boolean {
    return this.max > 0 && this.sourceComments().length > this.max
  }

  private canOpenFullComments(): boolean {
    return this.max > 0 && this.sourceComments().length > 0
  }

  private shown(): EhGalleryComment[] {
    const source: EhGalleryComment[] = this.sourceComments()
    return this.max > 0 && source.length > this.max ? source.slice(0, this.max) : source
  }

  private showScoreDetails(c: EhGalleryComment): void {
    if (this.max > 0 || c.scoreDetails.length === 0) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.comment_score_details'),
      message: c.scoreDetails.join('\n'),
      primaryButton: {
        value: $r('app.string.common_ok'),
        action: () => {},
      },
    })
  }

  private displayScore(score: string): string {
    const value: string = score.trim()
    if (value.length === 0 || value.startsWith('+') || value.startsWith('-')) {
      return value
    }
    return `+${value}`
  }

  private commentRowKey(c: EhGalleryComment): string {
    return c.commentId
  }

  private blockedCommentKey(c: EhGalleryComment): string {
    if (c.commentId.length > 0) {
      return c.commentId
    }
    return `${c.author}:${c.postedTime}:${c.contentText}`
  }

  private isBlockedComment(c: EhGalleryComment): boolean {
    return (
      LocalBlockService.shouldCollapseBlockedComments() && LocalBlockService.isCommentBlocked(c)
    )
  }

  private isBlockedExpanded(c: EhGalleryComment): boolean {
    // Page path: one card == one comment, expand flag on the page-held render state so it survives
    // LazyForEach recycling. Peek path: one card renders several comments, keyed in the local array.
    if (this.parentManagedActions) {
      return this.renderState.blockedExpanded
    }
    return this.expandedBlockedCommentKeys.indexOf(this.blockedCommentKey(c)) >= 0
  }

  private isBlockedCollapsed(c: EhGalleryComment): boolean {
    return this.isBlockedComment(c) && !this.isBlockedExpanded(c)
  }

  private toggleBlockedComment(c: EhGalleryComment): void {
    if (this.parentManagedActions) {
      this.getUIContext().animateTo(
        { duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut },
        () => {
          this.renderState.blockedExpanded = !this.renderState.blockedExpanded
        },
      )
      return
    }
    const key: string = this.blockedCommentKey(c)
    this.getUIContext().animateTo(
      { duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut },
      () => {
        if (this.expandedBlockedCommentKeys.indexOf(key) >= 0) {
          this.expandedBlockedCommentKeys = this.expandedBlockedCommentKeys.filter(
            (item: string) => item !== key,
          )
        } else {
          const next: string[] = this.expandedBlockedCommentKeys.slice()
          next.push(key)
          this.expandedBlockedCommentKeys = next
        }
      },
    )
  }

  private voteColor(c: EhGalleryComment, vote: number): ResourceColor {
    return this.effectiveVote(c) === vote
      ? ThemeConstants.BRAND_PRIMARY
      : $r('sys.color.font_tertiary')
  }

  private voteIcon(c: EhGalleryComment, vote: number): Resource {
    const currentVote: number = this.effectiveVote(c)
    if (vote > 0) {
      return currentVote > 0 ? $r('sys.symbol.hand_thumbsup_fill') : $r('sys.symbol.hand_thumbsup')
    }
    return currentVote < 0
      ? $r('sys.symbol.hand_thumbsdown_fill')
      : $r('sys.symbol.hand_thumbsdown')
  }

  private canVote(c: EhGalleryComment): boolean {
    return this.max <= 0 && c.canVote
  }

  private codeDigit(code: string): string {
    if (code === '····') return '0'
    if (code === '···-') return '1'
    if (code === '··-·') return '2'
    if (code === '··--') return '3'
    if (code === '·-··') return '4'
    if (code === '·-·-') return '5'
    if (code === '·--·') return '6'
    if (code === '·---') return '7'
    if (code === '-···') return '8'
    if (code === '-··-') return '9'
    return ''
  }

  private normalizeReplyCode(line: string): string {
    let out: string = ''
    for (let i = 0; i < line.length; i++) {
      const ch: string = line.charAt(i)
      if (ch === '·' || ch === '.') {
        out += '·'
      } else if (ch === '-') {
        out += '-'
      }
    }
    return out
  }

  private decodeReplyId(line: string): string {
    const code: string = this.normalizeReplyCode(line)
    if (code.length === 0 || code.length % 4 !== 0) {
      return ''
    }
    let out: string = ''
    for (let i = 0; i < code.length; i += 4) {
      const digit: string = this.codeDigit(code.substring(i, i + 4))
      if (digit.length === 0) {
        return ''
      }
      out += digit
    }
    return out
  }

  private hashReplyId(line: string): string {
    const start: number = line.indexOf('#')
    if (start < 0) {
      return ''
    }
    const end: number = line.indexOf('#', start + 1)
    if (end <= start + 1) {
      return ''
    }
    return line.substring(start + 1, end)
  }

  private commentIdNum(c: EhGalleryComment): number {
    const n: number = Number.parseInt(c.commentId, 10)
    return Number.isNaN(n) ? 0 : n
  }

  private sortedComments(): EhGalleryComment[] {
    if (this.sortedCache !== null) {
      return this.sortedCache
    }
    const out: EhGalleryComment[] = this.referenceSourceComments().slice()
    out.sort(
      (a: EhGalleryComment, b: EhGalleryComment) => this.commentIdNum(b) - this.commentIdNum(a),
    )
    this.sortedCache = out
    return out
  }

  private candidateComments(c: EhGalleryComment): EhGalleryComment[] {
    const sorted: EhGalleryComment[] = this.sortedComments()
    for (let i = 0; i < sorted.length; i++) {
      if (sorted[i].commentId === c.commentId) {
        return sorted.slice(i)
      }
    }
    return []
  }

  private commentById(id: string): EhGalleryComment | undefined {
    const source: EhGalleryComment[] = this.referenceSourceComments()
    for (let i = 0; i < source.length; i++) {
      const candidate: EhGalleryComment = source[i]
      if (candidate.commentId === id) {
        return candidate
      }
    }
    return undefined
  }

  private mentionTail(segment: string): string {
    const at: number = segment.indexOf('@')
    return at >= 0 ? segment.substring(at + 1).trim() : ''
  }

  private mentionToken(segment: string): string {
    const tail: string = this.mentionTail(segment)
    for (let i = 0; i < tail.length; i++) {
      const ch: string = tail.charAt(i)
      if (ch === ' ' || ch === '\n' || ch === '\t' || ch === '\r') {
        return tail.substring(0, i)
      }
    }
    return tail
  }

  private isNameSeparator(ch: string): boolean {
    return (
      ch === ' ' ||
      ch === '\n' ||
      ch === '\t' ||
      ch === '\r' ||
      ch === '+' ||
      ch === ',' ||
      ch === '.' ||
      ch === '，' ||
      ch === '。'
    )
  }

  private nameParts(text: string): string[] {
    const out: string[] = []
    let current: string = ''
    for (let i = 0; i < text.length; i++) {
      const ch: string = text.charAt(i)
      if (this.isNameSeparator(ch)) {
        if (current.length > 0) {
          out.push(current)
          current = ''
        }
      } else {
        current += ch
      }
    }
    if (current.length > 0) {
      out.push(current)
    }
    return out
  }

  private normalizedName(name: string): string {
    return this.nameParts(name).join(' ')
  }

  private findByAuthor(candidates: EhGalleryComment[], name: string): EhGalleryComment | undefined {
    if (name.length === 0) {
      return undefined
    }
    for (let i = 0; i < candidates.length; i++) {
      if (candidates[i].author === name) {
        return candidates[i]
      }
    }
    return undefined
  }

  private findBySpaceAuthor(
    candidates: EhGalleryComment[],
    segment: string,
  ): EhGalleryComment | undefined {
    const parts: string[] = this.nameParts(this.mentionTail(segment))
    for (let count = parts.length; count > 0; count--) {
      const name: string = parts.slice(0, count).join(' ')
      for (let i = 0; i < candidates.length; i++) {
        if (this.normalizedName(candidates[i].author) === name) {
          return candidates[i]
        }
      }
    }
    return undefined
  }

  private namePartsPrefixLength(text: string, count: number): number {
    let seen: number = 0
    let inPart: boolean = false
    for (let i = 0; i < text.length; i++) {
      if (this.isNameSeparator(text.charAt(i))) {
        if (inPart) {
          seen++
          inPart = false
          if (seen === count) {
            return i
          }
        }
      } else {
        inPart = true
      }
    }
    if (inPart) {
      seen++
      if (seen === count) {
        return text.length
      }
    }
    return 0
  }

  private matchedMentionNameLength(candidates: EhGalleryComment[], segment: string): number {
    const tail: string = this.mentionTail(segment)
    const parts: string[] = this.nameParts(tail)
    for (let count = parts.length; count > 0; count--) {
      const name: string = parts.slice(0, count).join(' ')
      for (let i = 0; i < candidates.length; i++) {
        if (this.normalizedName(candidates[i].author) === name) {
          return this.namePartsPrefixLength(tail, count)
        }
      }
    }
    return 0
  }

  private replyTargetId(segment: string): string {
    const hashId: string = this.hashReplyId(segment)
    if (hashId.length > 0) {
      return hashId
    }
    const lines: string[] = segment.split('\n')
    if (lines.length < 2) {
      return ''
    }
    return this.decodeReplyId(lines[1])
  }

  private pushReply(
    out: EhGalleryComment[],
    c: EhGalleryComment,
    reply: EhGalleryComment | undefined,
  ): void {
    if (reply === undefined || reply.commentId.length === 0 || reply.commentId === c.commentId) {
      return
    }
    for (let i = 0; i < out.length; i++) {
      if (out[i].commentId === reply.commentId) {
        return
      }
    }
    out.push(reply)
  }

  private replyReferences(c: EhGalleryComment): EhGalleryComment[] {
    if (c.commentId.length > 0) {
      const cached: EhGalleryComment[] | undefined = this.replyRefsCache.get(c.commentId)
      if (cached !== undefined) {
        return cached
      }
    }
    const segments: string[] = c.contentText.split('@')
    const candidates: EhGalleryComment[] = this.candidateComments(c)
    const out: EhGalleryComment[] = []
    for (let i = 1; i < segments.length; i++) {
      const segment: string = `@${segments[i]}`
      const id: string = this.replyTargetId(segment)
      if (id.length > 0) {
        this.pushReply(out, c, this.commentById(id))
        continue
      }
      const tokenReply: EhGalleryComment | undefined = this.findByAuthor(
        candidates,
        this.mentionToken(segment),
      )
      if (tokenReply !== undefined) {
        this.pushReply(out, c, tokenReply)
        continue
      }
      this.pushReply(out, c, this.findBySpaceAuthor(candidates, segment))
    }
    if (c.commentId.length > 0) {
      this.replyRefsCache.set(c.commentId, out)
    }
    return out
  }

  private mentionHighlightLength(c: EhGalleryComment, segment: string): number {
    const id: string = this.replyTargetId(segment)
    if (id.length > 0 && this.commentById(id) !== undefined) {
      const token: string = this.mentionToken(segment)
      return token.length > 0 ? token.length + 1 : 1
    }
    const candidates: EhGalleryComment[] = this.candidateComments(c)
    const token: string = this.mentionToken(segment)
    if (this.findByAuthor(candidates, token) !== undefined) {
      return token.length + 1
    }
    const nameLength: number = this.matchedMentionNameLength(candidates, segment)
    return nameLength > 0 ? nameLength + 1 : 0
  }

  private displayContentText(c: EhGalleryComment): string {
    if (c.commentId.length > 0) {
      const cached: string | undefined = this.displayTextCache.get(c.commentId)
      if (cached !== undefined) {
        return cached
      }
    }
    const result: string = this.computeDisplayContentText(c)
    if (c.commentId.length > 0) {
      this.displayTextCache.set(c.commentId, result)
    }
    return result
  }

  private computeDisplayContentText(c: EhGalleryComment): string {
    if (this.replyReferences(c).length === 0) {
      return c.contentText
    }
    const lines: string[] = c.contentText.split('\n')
    if (lines.length === 0 || !lines[0].trim().startsWith('@')) {
      return c.contentText
    }
    if (this.hashReplyId(lines[0]).length > 0) {
      return lines.slice(1).join('\n').trim()
    }
    if (lines.length > 1 && this.decodeReplyId(lines[1]).length > 0) {
      return lines.slice(2).join('\n').trim()
    }
    return c.contentText
  }

  private translationEnabled(): boolean {
    return this.max <= 0 && this.translationSettings.enabled
  }

  private translationText(c: EhGalleryComment): string {
    if (this.parentManagedActions) {
      return this.localTranslationText
    }
    return this.useSingleComment ? this.singleComment.translationText : c.translationText
  }

  private isTranslationShown(c: EhGalleryComment): boolean {
    if (this.parentManagedActions) {
      return this.localTranslationShown
    }
    return this.useSingleComment ? this.singleComment.translationShown : c.translationShown
  }

  private shouldShowTranslated(c: EhGalleryComment): boolean {
    return (
      this.translationEnabled() && this.isTranslationShown(c) && this.translationText(c).length > 0
    )
  }

  private shouldShowTranslatedState(translationText: string, translationShown: boolean): boolean {
    return this.translationEnabled() && translationShown && translationText.length > 0
  }

  private activeCommentBodyText(
    c: EhGalleryComment,
    translationText: string,
    translationShown: boolean,
  ): string {
    if (this.shouldShowTranslatedState(translationText, translationShown)) {
      return translationText
    }
    return this.displayContentText(c)
  }

  private translationSourceText(c: EhGalleryComment): string {
    const source: string = this.displayContentText(c)
    const segments: CommentTextSegment[] = this.commentTextSegments(source, c)
    let out: string = ''
    for (let i = 0; i < segments.length; i++) {
      const seg: CommentTextSegment = segments[i]
      out += seg.emphasized ? CommentTranslationService.protectMentionText(seg.text) : seg.text
    }
    return out
  }

  private isTranslationLoading(c: EhGalleryComment): boolean {
    if (this.parentManagedActions) {
      return this.localTranslationLoading
    }
    return this.useSingleComment ? this.singleComment.translationLoading : c.translationLoading
  }

  private effectiveScore(c: EhGalleryComment): string {
    if (this.parentManagedActions) {
      return this.renderState.score
    }
    return this.useSingleComment ? this.singleComment.score : c.score
  }

  private effectiveVote(c: EhGalleryComment): number {
    if (this.parentManagedActions) {
      return this.renderState.vote
    }
    return this.useSingleComment ? this.singleComment.vote : c.vote
  }

  // Manual translate / toggle. In the page (parentManaged) path every state field lives on the render
  // state, mutated by the page handlers (which set the loading flag synchronously so the spinner shows at
  // once) — the card just fires the intent and re-renders reactively off the render state's @Trace fields.
  private toggleOrTranslate(c: EhGalleryComment): void {
    if (!this.translationEnabled() || c.contentText.trim().length === 0) {
      return
    }
    if (this.parentManagedActions) {
      // User-initiated → arm the height-measure animation; the result/toggle lands via renderState and the
      // @Monitor runs the animation.
      this.manualTranslateArmed = true
      if (this.renderState.translationText.length > 0) {
        this.publishToggleTranslation(c)
      } else {
        this.publishTranslate(c, this.translationSourceText(c))
      }
      return
    }
    // Non-parentManaged standalone card (translation is only enabled inside the page today, so this path is
    // effectively unused; kept self-consistent against the comment object).
    if (c.translationText.length > 0) {
      c.translationShown = !c.translationShown
      this.publishToggleTranslation(c)
      return
    }
    c.translationShown = true
    c.translationLoading = true
    this.publishTranslate(c, this.translationSourceText(c))
      .then((translated: string) => {
        c.translationLoading = false
        if (translated.length > 0) {
          c.translationText = translated
          c.translationShown = true
        }
        this.publishTranslationResolved(c, translated)
      })
      .catch(() => {
        c.translationLoading = false
      })
  }

  private autoTranslateStarted(c: EhGalleryComment): boolean {
    if (this.parentManagedActions) {
      return this.renderState.translationAutoStarted
    }
    return c.translationAutoStarted
  }

  private autoTranslateVisibleComments(): void {
    if (!this.translationEnabled() || !this.translationSettings.autoTranslate) {
      return
    }
    const shown: EhGalleryComment[] = this.shown()
    for (let i = 0; i < shown.length; i++) {
      const c: EhGalleryComment = shown[i]
      if (c.contentText.trim().length === 0) {
        continue
      }
      if (this.autoTranslateStarted(c)) {
        continue
      }
      this.publishAutoTranslate(c, this.translationSourceText(c))
    }
  }

  private publishAuthor(author: string): void {
    this.onAuthor(author)
  }

  private publishVote(c: EhGalleryComment, vote: number): void {
    if (this.parentManagedActions) {
      // The page applies the optimistic vote/score on the render state synchronously, so the card
      // re-renders from @Trace — no local mirror needed.
      this.onVote(c, vote)
      return
    }
    if (this.useSingleComment) {
      const targetVote: number = c.vote === vote ? 0 : vote
      if (c.score.length > 0) {
        const score: number = Number.parseInt(c.score, 10)
        if (!Number.isNaN(score)) {
          c.score = (score + targetVote - c.vote).toString()
        }
      }
      c.vote = targetVote
    }
    this.onVote(c, vote)
  }

  private publishReply(c: EhGalleryComment): void {
    this.onReply(c)
  }

  private publishEdit(c: EhGalleryComment): void {
    this.onEdit(c)
  }

  private publishTranslate(c: EhGalleryComment, sourceText: string): Promise<string> {
    return this.onTranslate(c, sourceText)
  }

  private publishTranslationResolved(c: EhGalleryComment, translated: string): void {
    this.onTranslationResolved(c, translated)
  }

  private publishToggleTranslation(c: EhGalleryComment): void {
    this.onToggleTranslation(c)
  }

  private publishAutoTranslate(c: EhGalleryComment, sourceText: string): void {
    this.onAutoTranslate(c, sourceText)
  }

  private quoteExcerpt(text: string): string {
    const clean: string = text.replace(/\n+/g, ' ').trim()
    return clean.length > 120 ? `${clean.substring(0, 120)}...` : clean
  }

  private quoteExcerptText(c: EhGalleryComment): string {
    if (this.translationEnabled() && c.translationShown && c.translationText.length > 0) {
      return c.translationText
    }
    return c.contentText
  }

  private commentGap(): number {
    return ThemeConstants.SPACE_SM - 2
  }

  private commentBottomPadding(): number {
    return this.max > 0 ? ThemeConstants.SPACE_MD : ThemeConstants.SPACE_SM
  }

  private isUrlTailPunctuation(ch: string): boolean {
    return (
      ch === '.' ||
      ch === ',' ||
      ch === ';' ||
      ch === ':' ||
      ch === '，' ||
      ch === '。' ||
      ch === '；' ||
      ch === '：' ||
      ch === '！' ||
      ch === '!' ||
      ch === ')' ||
      ch === '）' ||
      ch === ']' ||
      ch === '}'
    )
  }

  private cleanCommentUrl(raw: string): string {
    let end: number = raw.length
    while (end > 0 && this.isUrlTailPunctuation(raw.charAt(end - 1))) {
      end--
    }
    return raw.substring(0, end)
  }

  private pushCommentTextSegments(
    out: CommentTextSegment[],
    seq: number,
    text: string,
    c: EhGalleryComment,
  ): number {
    let cursor: number = 0
    let nextSeq: number = seq
    while (cursor < text.length) {
      const at: number = text.indexOf('@', cursor)
      if (at < 0) {
        out.push(new CommentTextSegment(`t${nextSeq++}`, text.substring(cursor)))
        break
      }
      if (at > cursor) {
        out.push(new CommentTextSegment(`t${nextSeq++}`, text.substring(cursor, at)))
      }
      const length: number = this.mentionHighlightLength(c, text.substring(at))
      if (length > 1) {
        out.push(new CommentTextSegment(`m${nextSeq++}`, text.substring(at, at + length), '', true))
        cursor = at + length
      } else {
        out.push(new CommentTextSegment(`t${nextSeq++}`, '@'))
        cursor = at + 1
      }
    }
    return nextSeq
  }

  private commentTextSegments(text: string, c: EhGalleryComment): CommentTextSegment[] {
    const out: CommentTextSegment[] = []
    COMMENT_LINK_RE.lastIndex = 0
    let cursor: number = 0
    let seq: number = 0
    let match: RegExpExecArray | null = COMMENT_LINK_RE.exec(text)
    while (match !== null) {
      const raw: string = match[0]
      const start: number = COMMENT_LINK_RE.lastIndex - raw.length
      const end: number = COMMENT_LINK_RE.lastIndex
      const url: string = this.cleanCommentUrl(raw)
      if (start > cursor) {
        seq = this.pushCommentTextSegments(out, seq, text.substring(cursor, start), c)
      }
      if (url.length > 0) {
        out.push(new CommentTextSegment(`u${seq++}`, url, url))
      }
      if (url.length < raw.length) {
        seq = this.pushCommentTextSegments(out, seq, raw.substring(url.length), c)
      }
      cursor = end
      match = COMMENT_LINK_RE.exec(text)
    }
    if (cursor < text.length) {
      this.pushCommentTextSegments(out, seq, text.substring(cursor), c)
    }
    if (out.length === 0) {
      out.push(new CommentTextSegment('t0', text))
    }
    return out
  }

  private commentTextSegmentKey(seg: CommentTextSegment): string {
    return `${seg.key}:${seg.text}:${seg.url}:${seg.emphasized}`
  }

  private currentHostUrl(url: string): string {
    return EhUrlRouter.toCurrentHost(url, EhConstants.baseUrl(connectSiteMode().isEx))
  }

  private openCommentUrl(url: string): void {
    const currentUrl: string = this.currentHostUrl(url)
    if (EhUrlRouter.canHandle(currentUrl)) {
      publishPendingEhUrl(`${Date.now()}:${currentUrl}`)
      return
    }
    this.stack.pushPathByName('GalleryWeb', new GalleryWebParams(currentUrl, currentUrl))
  }

  build() {
    Column({ space: this.commentGap() }) {
      if (this.showHeader) {
        // Header — in peek mode the whole row taps through to the full comments page. It is deliberately
        // outside the comment cards, following Next2V's HotRepliesPanel: the comment itself is the card.
        Row({ space: ThemeConstants.SPACE_XS }) {
          Text($r('app.string.gallery_comments'))
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          if (this.sourceComments().length > 0) {
            Text(`(${this.sourceComments().length})`)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
          }
          Blank()
          if (this.canOpenFullComments()) {
            Text($r('app.string.detail_view_all'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_emphasize'))
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor([$r('sys.color.font_tertiary')])
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
        .onClick(() => {
          if (this.canOpenFullComments()) {
            this.onMore()
          }
        })
      }
      if (this.useSingleComment) {
        this.CommentRow(this.singleComment, true)
      } else {
        ForEach(
          this.shown(),
          (c: EhGalleryComment, index: number) => {
            this.CommentRow(c, index === this.shown().length - 1)
          },
          (c: EhGalleryComment) => this.commentRowKey(c),
        )
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // eros_fe CommentItem(simple): each comment is its own rounded bubble — head (author + UP/score
  // badge on the RIGHT), body (text, capped at 4 lines in the peek so one long comment can't bury the
  // previews), then the time as a small footer. The full comments page (max === 0) shows the whole text.
  @Builder
  CommentRow(c: EhGalleryComment, isLast: boolean) {
    if (this.isBlockedCollapsed(c)) {
      Column({ space: ThemeConstants.SPACE_XS }) {
        this.CollapsedBlockedComment(c)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: ThemeConstants.SPACE_MD,
        right: ThemeConstants.SPACE_MD,
        top: ThemeConstants.SPACE_SM,
        bottom: ThemeConstants.SPACE_SM,
      })
      .borderRadius(ThemeConstants.RADIUS_CARD)
      .backgroundColor($r('app.color.card_background'))
      .onClick(() => {
        this.toggleBlockedComment(c)
      })
    } else if (this.canOpenFullComments()) {
      Column({ space: ThemeConstants.SPACE_XS }) {
        if (this.isBlockedComment(c)) {
          this.ExpandedBlockedHeader(c)
        }
        this.CommentRowContent(c)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: ThemeConstants.SPACE_MD,
        right: ThemeConstants.SPACE_MD,
        top: ThemeConstants.SPACE_MD,
        bottom: this.commentBottomPadding(),
      })
      .borderRadius(ThemeConstants.RADIUS_CARD)
      .backgroundColor($r('app.color.card_background'))
      .onClick(() => {
        if (!this.isBlockedComment(c)) {
          this.onMore()
        }
      })
    } else {
      Column({ space: ThemeConstants.SPACE_XS }) {
        if (this.isBlockedComment(c)) {
          this.ExpandedBlockedHeader(c)
        }
        this.CommentRowContent(c)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: ThemeConstants.SPACE_MD,
        right: ThemeConstants.SPACE_MD,
        top: ThemeConstants.SPACE_MD,
        bottom: this.commentBottomPadding(),
      })
      .borderRadius(ThemeConstants.RADIUS_CARD)
      .backgroundColor($r('app.color.card_background'))
    }
  }

  @Builder
  CollapsedBlockedComment(c: EhGalleryComment) {
    Row({ space: ThemeConstants.SPACE_SM }) {
      Row() {
        SymbolGlyph($r('sys.symbol.eye_slash'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width(24)
      .height(24)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      Row({ space: 0 }) {
        Text($r('app.string.local_block_comment_collapsed'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .lineHeight(24)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.collapsedBlockedSubtitle(c).length > 0) {
          Text(` · ${this.collapsedBlockedSubtitle(c)}`)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .lineHeight(24)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      Row() {
        SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width(24)
      .height(24)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ right: ThemeConstants.SPACE_XS })
  }

  @Builder
  ExpandedBlockedHeader(c: EhGalleryComment) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      SymbolGlyph($r('sys.symbol.eye_slash'))
        .fontSize(14)
        .fontColor([$r('sys.color.font_tertiary')])
      Text($r('app.string.local_block_comment_collapsed'))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .layoutWeight(1)
      Text($r('app.string.local_block_comment_collapse'))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_emphasize'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.toggleBlockedComment(c)
    })
  }

  private collapsedBlockedSubtitle(c: EhGalleryComment): string {
    if (c.author.length > 0 && c.postedTime.length > 0) {
      return `${c.author} · ${c.postedTime}`
    }
    if (c.author.length > 0) {
      return c.author
    }
    return c.postedTime
  }

  @Builder
  CommentRowContent(c: EhGalleryComment) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      // Head — author (left) with the UP/score badge pinned right (eros_fe _CommentHead).
      Row({ space: ThemeConstants.SPACE_SM }) {
        Row() {
          Text(c.author)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_emphasize'))
            .constraintSize({ maxWidth: '100%' })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              this.publishAuthor(c.author)
            })
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        // Uploader comments carry an UP badge. The numeric community score is shown only on the FULL
        // comments page (max === 0): eros_fe's CommentItem(simple) gates the score chip behind `!simple`,
        // so the PEEK deliberately suppresses it (author + body + time only, UP for the uploader).
        if (c.isUploader) {
          this.CommentBadge($r('app.string.comment_uploader'), true)
        } else if (this.effectiveScore(c).length > 0 && this.max <= 0) {
          this.CommentScoreBadge(c)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      this.ReplyReferences(c)
      this.CommentBody(c)
      // Time/actions footer (eros_fe _CommentTail): full comments expose bounded vote actions.
      Row() {
        Text(c.postedTime)
          .fontSize(ThemeConstants.FONT_SIZE_TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.translationEnabled() && c.contentText.trim().length > 0) {
          this.TranslationAction(c)
        }
        if (this.max <= 0 && c.canEdit && c.commentId.length > 0 && c.commentId !== '0') {
          this.EditAction(c)
        }
        if (this.max <= 0 && c.canVote) {
          this.VoteAction(c, 1)
          this.VoteAction(c, -1)
        }
        if (this.max <= 0 && c.commentId.length > 0 && c.commentId !== '0') {
          this.ReplyAction(c)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  CommentBody(c: EhGalleryComment) {
    if (this.commentBodyHeightLocked) {
      // During the appear animation the height is explicitly driven from measured start->target and clipped.
      Stack({ alignContent: Alignment.TopStart }) {
        this.CommentBodyStackContent(c)
      }
      .width('100%')
      .height(this.commentBodyAnimatedHeight)
      .clip(true)
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        this.CommentBodyStackContent(c)
      }.width('100%')
    }
  }

  @Builder
  CommentBodyStackContent(c: EhGalleryComment) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      this.CommentBodyContent(c)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.updateCommentBodyHeight(area)
    })
    // Offscreen copy of the TARGET body (translation when showing, original when hiding) — measured
    // (onAreaChange) to get the target height before the visible body animates to it.
    if (this.parentManagedActions && this.pendingTranslationMeasure) {
      Column({ space: ThemeConstants.SPACE_XS }) {
        this.PendingTranslationBodyContent(c)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .position({ x: 0, y: 0 })
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.handlePendingTranslationArea(c, area)
      })
    }
  }

  @Builder
  PendingTranslationBodyContent(c: EhGalleryComment) {
    if (!this.pendingShowTranslation) {
      // Animating back to the original.
      this.CommentText(c, this.displayContentText(c), this.max > 0, $r('sys.color.font_primary'))
    } else if (this.translationSettings.displayMode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL) {
      this.CommentText(c, this.displayContentText(c), this.max > 0, $r('sys.color.font_secondary'))
      Divider().strokeWidth(0.5).color($r('sys.color.ohos_id_color_list_separator'))
      this.CommentText(c, this.localTranslationText, false, $r('sys.color.font_primary'))
    } else {
      this.CommentText(c, this.localTranslationText, false, $r('sys.color.font_primary'))
    }
  }

  @Builder
  CommentBodyContent(c: EhGalleryComment) {
    if (
      this.parentManagedActions &&
      this.translationEnabled() &&
      this.localTranslationShown &&
      this.localTranslationText.length > 0 &&
      this.translationSettings.displayMode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL
    ) {
      this.CommentText(c, this.displayContentText(c), this.max > 0, $r('sys.color.font_secondary'))
      Divider().strokeWidth(0.5).color($r('sys.color.ohos_id_color_list_separator'))
      this.CommentText(c, this.localTranslationText, false, $r('sys.color.font_primary'))
    } else if (this.parentManagedActions) {
      if (
        this.translationEnabled() &&
        this.localTranslationShown &&
        this.localTranslationText.length > 0
      ) {
        this.CommentText(c, this.localTranslationText, false, $r('sys.color.font_primary'))
      } else {
        this.CommentText(c, this.displayContentText(c), this.max > 0, $r('sys.color.font_primary'))
      }
    } else if (
      this.shouldShowTranslated(c) &&
      this.translationSettings.displayMode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL
    ) {
      this.CommentText(c, this.displayContentText(c), this.max > 0, $r('sys.color.font_secondary'))
      Divider().strokeWidth(0.5).color($r('sys.color.ohos_id_color_list_separator'))
      this.CommentText(c, this.translationText(c), false, $r('sys.color.font_primary'))
    } else {
      this.CommentText(
        c,
        this.activeCommentBodyText(c, this.translationText(c), this.isTranslationShown(c)),
        this.max > 0,
        $r('sys.color.font_primary'),
      )
    }
  }

  @Builder
  CommentText(c: EhGalleryComment, text: string, clamp: boolean, color: ResourceColor) {
    if (clamp) {
      Text() {
        ForEach(
          this.commentTextSegments(text, c),
          (seg: CommentTextSegment) => {
            if (seg.url.length > 0) {
              Span(seg.text)
                .fontColor($r('sys.color.font_emphasize'))
                .decoration({
                  type: TextDecorationType.Underline,
                  color: $r('sys.color.font_emphasize'),
                })
            } else if (seg.emphasized) {
              Span(seg.text).fontColor($r('sys.color.font_emphasize'))
            } else {
              Span(seg.text)
            }
          },
          (seg: CommentTextSegment) => this.commentTextSegmentKey(seg),
        )
      }
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor(color)
      .width('100%')
      .maxLines(4)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else {
      Text() {
        ForEach(
          this.commentTextSegments(text, c),
          (seg: CommentTextSegment) => {
            if (seg.url.length > 0) {
              Span(seg.text)
                .fontColor($r('sys.color.font_emphasize'))
                .decoration({
                  type: TextDecorationType.Underline,
                  color: $r('sys.color.font_emphasize'),
                })
                .onClick(() => {
                  this.openCommentUrl(seg.url)
                })
            } else if (seg.emphasized) {
              Span(seg.text).fontColor($r('sys.color.font_emphasize'))
            } else {
              Span(seg.text)
            }
          },
          (seg: CommentTextSegment) => this.commentTextSegmentKey(seg),
        )
      }
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor(color)
      .width('100%')
    }
  }

  @Builder
  ReplyReferences(c: EhGalleryComment) {
    ForEach(
      this.replyReferences(c),
      (r: EhGalleryComment) => {
        this.ReplyQuote(r)
      },
      (r: EhGalleryComment) => r.commentId,
    )
  }

  @Builder
  ReplyQuote(c: EhGalleryComment) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(c.author)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_emphasize'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.quoteExcerpt(this.quoteExcerptText(c)))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ThemeConstants.SPACE_SM)
    .borderRadius(ThemeConstants.COMMENT_QUOTE_RADIUS)
    .backgroundColor(ThemeConstants.BG_SUB)
  }

  @Builder
  EditAction(c: EhGalleryComment) {
    this.FooterAction(
      $r('sys.symbol.square_and_pencil'),
      $r('sys.color.font_tertiary'),
      false,
      () => {
        this.publishEdit(c)
      },
    )
  }

  @Builder
  ReplyAction(c: EhGalleryComment) {
    this.FooterAction(
      $r('sys.symbol.ellipsis_message'),
      $r('sys.color.font_tertiary'),
      false,
      () => {
        this.publishReply(c)
      },
    )
  }

  @Builder
  CommentScoreBadge(c: EhGalleryComment) {
    Row() {
      this.CommentBadge(this.displayScore(this.effectiveScore(c)), false)
    }
    .onClick(() => {
      this.showScoreDetails(c)
    })
  }

  @Builder
  VoteAction(c: EhGalleryComment, vote: number) {
    if (this.effectiveVote(c) === vote) {
      this.FooterAction(this.voteIcon(c, vote), ThemeConstants.BRAND_PRIMARY, false, () => {
        if (this.canVote(c)) {
          this.publishVote(c, vote)
        }
      })
    } else {
      this.FooterAction(this.voteIcon(c, vote), $r('sys.color.font_tertiary'), false, () => {
        if (this.canVote(c)) {
          this.publishVote(c, vote)
        }
      })
    }
  }

  @Builder
  TranslationAction(c: EhGalleryComment) {
    if (this.isTranslationLoading(c)) {
      this.FooterAction($r('sys.symbol.translate'), $r('sys.color.font_tertiary'), true, () => {
        this.toggleOrTranslate(c)
      })
    } else if (this.isTranslationShown(c) && this.translationText(c).length > 0) {
      this.FooterAction($r('sys.symbol.translate'), ThemeConstants.BRAND_PRIMARY, false, () => {
        this.toggleOrTranslate(c)
      })
    } else {
      this.FooterAction($r('sys.symbol.translate'), $r('sys.color.font_tertiary'), false, () => {
        this.toggleOrTranslate(c)
      })
    }
  }

  @Builder
  FooterAction(icon: Resource, color: ResourceColor, disabled: boolean, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      if (disabled) {
        LoadingProgress().width(COMMENT_FOOTER_ICON_SIZE).height(COMMENT_FOOTER_ICON_SIZE)
      } else {
        SymbolGlyph(icon).fontSize(COMMENT_FOOTER_ICON_SIZE).fontColor([color])
      }
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(Color.Transparent)
    .width(COMMENT_FOOTER_ACTION_SIZE)
    .height(COMMENT_FOOTER_ACTION_SIZE)
    .enabled(!disabled)
    .opacity(1)
    .onClick(action)
  }

  @Builder
  CommentBadge(label: ResourceStr, primary: boolean) {
    Text(label)
      .fontSize(ThemeConstants.FONT_SIZE_TINY)
      .fontWeight(FontWeight.Medium)
      .fontColor(primary ? ThemeConstants.TEXT_ON_BRAND : $r('sys.color.font_secondary'))
      .backgroundColor(primary ? ThemeConstants.BRAND_PRIMARY : ThemeConstants.BG_SUB)
      .borderRadius(ThemeConstants.COMMENT_BADGE_RADIUS)
      .constraintSize({ minWidth: ThemeConstants.COMMENT_BADGE_MIN_WIDTH })
      .height(ThemeConstants.COMMENT_BADGE_HEIGHT)
      .padding({
        left: ThemeConstants.COMMENT_BADGE_PADDING_H,
        right: ThemeConstants.COMMENT_BADGE_PADDING_H,
      })
      .textAlign(TextAlign.Center)
  }
}

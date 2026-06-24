import {
  COMMENT_TRANSLATION_DISPLAY_BILINGUAL,
  CommentTranslationSettingsState,
  EhConstants,
  EhGalleryComment,
  EhUrlRouter,
  GalleryCommentActionState,
  GalleryWebParams,
  GALLERY_COMMENT_ACTION_RENDER_STATE,
  ThemeConstants,
  connectGalleryCommentAction,
  connectCommentTranslationSettings,
  connectNavStack,
  connectSiteMode,
  publishPendingEhUrl,
} from 'shared'

const COMMENT_FOOTER_ACTION_SIZE: number = 30
const COMMENT_FOOTER_ICON_SIZE: number = 16
const COMMENT_LINK_RE: RegExp = /https?:\/\/[^\s<>"'，。！？；、）\]\}]+/g

class CommentTextSegment {
  key: string = ''
  text: string = ''
  url: string = ''

  constructor(key: string = '', text: string = '', url: string = '') {
    this.key = key
    this.text = text
    this.url = url
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
  @Param useSingleComment: boolean = false;
  @Param singleComment: EhGalleryComment = new EhGalleryComment();
  @Param renderVersion: number = 0;
  @Param singleTranslationText: string = '';
  @Param singleTranslationShown: boolean = false;
  @Param singleTranslationLoading: boolean = false;
  @Param singleScore: string = '';
  @Param singleVote: number = 0;
  @Param max: number = 0;
  @Param showHeader: boolean = true;
  @Param actionScope: string = '';
  @Event onMore: () => void = () => {};
  @Event onAuthor: (name: string) => void = (_name: string) => {};
  @Event onVote: (comment: EhGalleryComment, vote: number) => void = (_comment: EhGalleryComment, _vote: number) => {};
  @Event onReply: (comment: EhGalleryComment) => void = (_comment: EhGalleryComment) => {};
  @Event onEdit: (comment: EhGalleryComment) => void = (_comment: EhGalleryComment) => {};
  @Event onTranslate: (comment: EhGalleryComment, sourceText: string) => void =
    (_comment: EhGalleryComment, _sourceText: string) => {};
  @Event onToggleTranslation: (comment: EhGalleryComment) => void = (_comment: EhGalleryComment) => {};
  @Event onAutoTranslate: (comment: EhGalleryComment, sourceText: string) => void =
    (_comment: EhGalleryComment, _sourceText: string) => {};
  private stack: NavPathStack = connectNavStack().stack;
  @Local translationSettings: CommentTranslationSettingsState = connectCommentTranslationSettings();
  @Local commentAction: GalleryCommentActionState = connectGalleryCommentAction();
  @Local liveTranslationText: string = '';
  @Local liveTranslationShown: boolean = false;
  @Local liveTranslationLoading: boolean = false;
  @Local liveScore: string = '';
  @Local liveVote: number = 0;

  @Monitor('commentAction.version')
  onCommentRenderStateChanged(): void {
    if (!this.useSingleComment || this.commentAction.action !== GALLERY_COMMENT_ACTION_RENDER_STATE ||
      this.commentAction.scopeId !== this.actionScope || this.commentAction.commentId !== this.singleComment.commentId) {
      return
    }
    this.getUIContext().animateTo({ duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut }, () => {
      this.liveTranslationText = this.commentAction.translationText
      this.liveTranslationShown = this.commentAction.translationShown
      this.liveTranslationLoading = this.commentAction.translationLoading
      this.liveScore = this.commentAction.score
      this.liveVote = this.commentAction.vote
    })
  }

  @Monitor('comments', 'translationSettings.enabled', 'translationSettings.autoTranslate')
  onTranslationInputsChanged(): void {
    this.autoTranslateVisibleComments()
  }

  aboutToAppear(): void {
    if (this.useSingleComment) {
      this.liveTranslationText = this.singleTranslationText
      this.liveTranslationShown = this.singleTranslationShown
      this.liveTranslationLoading = this.singleTranslationLoading
      this.liveScore = this.singleScore
      this.liveVote = this.singleVote
    }
    this.autoTranslateVisibleComments()
  }

  private sourceComments(): EhGalleryComment[] {
    if (this.useSingleComment) {
      return [this.singleComment]
    }
    return this.comments
  }

  private hasMore(): boolean {
    return this.max > 0 && this.sourceComments().length > this.max
  }

  private canOpenFullComments(): boolean {
    return this.max > 0 && this.sourceComments().length > 0
  }

  private shown(): EhGalleryComment[] {
    const source: EhGalleryComment[] = this.sourceComments()
    return this.max > 0 && source.length > this.max
      ? source.slice(0, this.max)
      : source
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

  private voteColor(c: EhGalleryComment, vote: number): ResourceColor {
    return this.effectiveVote(c) === vote ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_tertiary')
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
    const out: EhGalleryComment[] = this.sourceComments().slice()
    out.sort((a: EhGalleryComment, b: EhGalleryComment) => this.commentIdNum(b) - this.commentIdNum(a))
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
    const source: EhGalleryComment[] = this.sourceComments()
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
    return ch === ' ' || ch === '\n' || ch === '\t' || ch === '\r' ||
      ch === '+' || ch === ',' || ch === '.' || ch === '，' || ch === '。'
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

  private findBySpaceAuthor(candidates: EhGalleryComment[], segment: string): EhGalleryComment | undefined {
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

  private pushReply(out: EhGalleryComment[], c: EhGalleryComment, reply: EhGalleryComment | undefined): void {
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
      const tokenReply: EhGalleryComment | undefined = this.findByAuthor(candidates, this.mentionToken(segment))
      if (tokenReply !== undefined) {
        this.pushReply(out, c, tokenReply)
        continue
      }
      this.pushReply(out, c, this.findBySpaceAuthor(candidates, segment))
    }
    if (out.length > 0) {
      return out
    }
    return out
  }

  private displayContentText(c: EhGalleryComment): string {
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
    return this.useSingleComment ? this.liveTranslationText : c.translationText
  }

  private isTranslationShown(c: EhGalleryComment): boolean {
    return this.useSingleComment ? this.liveTranslationShown : c.translationShown
  }

  private shouldShowTranslated(c: EhGalleryComment): boolean {
    if (this.renderVersion < 0) {
      return false
    }
    return this.translationEnabled() && this.isTranslationShown(c) && this.translationText(c).length > 0
  }

  private activeCommentBodyText(c: EhGalleryComment): string {
    if (this.shouldShowTranslated(c)) {
      return this.translationText(c)
    }
    return this.displayContentText(c)
  }

  private isTranslationLoading(c: EhGalleryComment): boolean {
    return this.useSingleComment ? this.liveTranslationLoading : c.translationLoading
  }

  private beginTranslationLoading(c: EhGalleryComment): void {
    if (this.useSingleComment) {
      this.getUIContext().animateTo({ duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut }, () => {
        this.liveTranslationShown = true
        this.liveTranslationLoading = true
      })
      return
    }
    c.translationShown = true
    c.translationLoading = true
  }

  private effectiveScore(c: EhGalleryComment): string {
    return this.useSingleComment ? this.liveScore : c.score
  }

  private effectiveVote(c: EhGalleryComment): number {
    return this.useSingleComment ? this.liveVote : c.vote
  }

  private toggleOrTranslate(c: EhGalleryComment): void {
    if (!this.translationEnabled() || c.contentText.trim().length === 0) {
      return
    }
    if (this.translationText(c).length > 0) {
      if (this.useSingleComment) {
        this.getUIContext().animateTo({ duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut }, () => {
          this.liveTranslationShown = !this.liveTranslationShown
          this.liveTranslationLoading = false
        })
      }
      this.publishToggleTranslation(c)
      return
    }
    const sourceText: string = this.displayContentText(c)
    this.beginTranslationLoading(c)
    this.publishTranslate(c, sourceText)
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
      if (c.translationAutoStarted) {
        continue
      }
      this.publishAutoTranslate(c, this.displayContentText(c))
    }
  }

  private publishAuthor(author: string): void {
    if (this.actionScope.length > 0) {
      this.commentAction.requestAuthor(this.actionScope, author)
      return
    }
    this.onAuthor(author)
  }

  private publishVote(c: EhGalleryComment, vote: number): void {
    if (this.useSingleComment) {
      const targetVote: number = this.liveVote === vote ? 0 : vote
      if (this.liveScore.length > 0) {
        const score: number = Number.parseInt(this.liveScore, 10)
        if (!Number.isNaN(score)) {
          this.liveScore = (score + targetVote - this.liveVote).toString()
        }
      }
      this.liveVote = targetVote
    }
    if (this.actionScope.length > 0) {
      this.commentAction.requestVote(this.actionScope, c.commentId, vote)
      return
    }
    this.onVote(c, vote)
  }

  private publishReply(c: EhGalleryComment): void {
    if (this.actionScope.length > 0) {
      this.commentAction.requestReply(this.actionScope, c.commentId)
      return
    }
    this.onReply(c)
  }

  private publishEdit(c: EhGalleryComment): void {
    if (this.actionScope.length > 0) {
      this.commentAction.requestEdit(this.actionScope, c.commentId)
      return
    }
    this.onEdit(c)
  }

  private publishTranslate(c: EhGalleryComment, sourceText: string): void {
    if (this.actionScope.length > 0) {
      this.commentAction.requestTranslate(this.actionScope, c.commentId, sourceText)
      return
    }
    this.onTranslate(c, sourceText)
  }

  private publishToggleTranslation(c: EhGalleryComment): void {
    if (this.actionScope.length > 0) {
      this.commentAction.requestToggleTranslation(this.actionScope, c.commentId)
      return
    }
    this.onToggleTranslation(c)
  }

  private publishAutoTranslate(c: EhGalleryComment, sourceText: string): void {
    if (this.actionScope.length > 0) {
      this.commentAction.requestAutoTranslate(this.actionScope, c.commentId, sourceText)
      return
    }
    this.onAutoTranslate(c, sourceText)
  }

  private quoteExcerpt(text: string): string {
    const clean: string = text.replace(/\n+/g, ' ').trim()
    return clean.length > 120 ? `${clean.substring(0, 120)}...` : clean
  }

  private commentGap(): number {
    return ThemeConstants.SPACE_SM - 2
  }

  private commentBottomPadding(): number {
    return this.max > 0 ? ThemeConstants.SPACE_MD : ThemeConstants.SPACE_SM
  }

  private isUrlTailPunctuation(ch: string): boolean {
    return ch === '.' || ch === ',' || ch === ';' || ch === ':' ||
      ch === '，' || ch === '。' || ch === '；' || ch === '：' ||
      ch === '！' || ch === '!' || ch === ')' || ch === '）' ||
      ch === ']' || ch === '}'
  }

  private cleanCommentUrl(raw: string): string {
    let end: number = raw.length
    while (end > 0 && this.isUrlTailPunctuation(raw.charAt(end - 1))) {
      end--
    }
    return raw.substring(0, end)
  }

  private commentTextSegments(text: string): CommentTextSegment[] {
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
        out.push(new CommentTextSegment(`t${seq++}`, text.substring(cursor, start)))
      }
      if (url.length > 0) {
        out.push(new CommentTextSegment(`u${seq++}`, url, url))
      }
      if (url.length < raw.length) {
        out.push(new CommentTextSegment(`t${seq++}`, raw.substring(url.length)))
      }
      cursor = end
      match = COMMENT_LINK_RE.exec(text)
    }
    if (cursor < text.length) {
      out.push(new CommentTextSegment(`t${seq++}`, text.substring(cursor)))
    }
    if (out.length === 0) {
      out.push(new CommentTextSegment('t0', text))
    }
    return out
  }

  private hasCommentLink(text: string): boolean {
    COMMENT_LINK_RE.lastIndex = 0
    const found: boolean = COMMENT_LINK_RE.test(text)
    COMMENT_LINK_RE.lastIndex = 0
    return found
  }

  private firstCommentUrl(text: string): string {
    const segments: CommentTextSegment[] = this.commentTextSegments(text)
    for (let i = 0; i < segments.length; i++) {
      if (segments[i].url.length > 0) {
        return segments[i].url
      }
    }
    return ''
  }

  private commentContainsLink(c: EhGalleryComment): boolean {
    return this.hasCommentLink(this.displayContentText(c)) || this.hasCommentLink(this.translationText(c))
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
    Column({ space: ThemeConstants.SPACE_XS }) {
      // Head — author (left) with the UP/score badge pinned right (eros_fe _CommentHead).
      Row({ space: ThemeConstants.SPACE_SM }) {
        Text(c.author)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_emphasize'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            this.publishAuthor(c.author)
          })
        // Uploader comments carry an UP badge. The numeric community score is shown only on the FULL
        // comments page (max === 0): eros_fe's CommentItem(simple) gates the score chip behind `!simple`,
        // so the PEEK deliberately suppresses it (author + body + time only, UP for the uploader).
        if (c.isUploader) {
          this.CommentBadge($r('app.string.comment_uploader'), true)
    } else if (this.effectiveScore(c).length > 0 && this.max <= 0) {
      Row() {
        this.CommentBadge(this.displayScore(this.effectiveScore(c)), false)
      }
            .onClick(() => {
              this.showScoreDetails(c)
            })
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
          this.VoteAction(c, 1, this.effectiveVote(c) > 0 ? $r('sys.symbol.hand_thumbsup_fill') : $r('sys.symbol.hand_thumbsup'))
          this.VoteAction(c, -1, this.effectiveVote(c) < 0 ? $r('sys.symbol.hand_thumbsdown_fill') : $r('sys.symbol.hand_thumbsdown'))
        }
        if (this.max <= 0 && c.commentId.length > 0 && c.commentId !== '0') {
          this.ReplyAction(c)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
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
      if (this.canOpenFullComments() && !this.commentContainsLink(c)) {
        this.onMore()
      }
    })
  }

  @Builder
  CommentBody(c: EhGalleryComment) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      if (this.useSingleComment && this.liveTranslationShown && this.liveTranslationText.length > 0 &&
        this.translationSettings.displayMode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL) {
        this.CommentText(this.displayContentText(c), this.max > 0, $r('sys.color.font_secondary'))
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.ohos_id_color_list_separator'))
        this.CommentText(this.liveTranslationText, false, $r('sys.color.font_primary'))
      } else if (this.useSingleComment && this.liveTranslationShown && this.liveTranslationText.length > 0) {
        this.CommentText(this.liveTranslationText, this.max > 0, $r('sys.color.font_primary'))
      } else if (this.shouldShowTranslated(c) &&
        this.translationSettings.displayMode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL) {
        this.CommentText(this.displayContentText(c), this.max > 0, $r('sys.color.font_secondary'))
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.ohos_id_color_list_separator'))
        this.CommentText(this.translationText(c), false, $r('sys.color.font_primary'))
      } else {
        this.CommentText(this.activeCommentBodyText(c), this.max > 0, $r('sys.color.font_primary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  CommentText(text: string, clamp: boolean, color: ResourceColor) {
    if (clamp) {
      Text() {
        ForEach(
          this.commentTextSegments(text),
          (seg: CommentTextSegment) => {
            if (seg.url.length > 0) {
              Span(seg.text)
                .fontColor($r('sys.color.font_emphasize'))
                .decoration({ type: TextDecorationType.Underline, color: $r('sys.color.font_emphasize') })
            } else {
              Span(seg.text)
            }
          },
          (seg: CommentTextSegment) => seg.key,
        )
      }
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(color)
        .width('100%')
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .gesture(
          TapGesture({ count: 1 })
            .onAction(() => {
              const url: string = this.firstCommentUrl(text)
              if (url.length > 0) {
                this.openCommentUrl(url)
              }
            }),
        )
    } else {
      Text() {
        ForEach(
          this.commentTextSegments(text),
          (seg: CommentTextSegment) => {
            if (seg.url.length > 0) {
              Span(seg.text)
                .fontColor($r('sys.color.font_emphasize'))
                .decoration({ type: TextDecorationType.Underline, color: $r('sys.color.font_emphasize') })
            } else {
              Span(seg.text)
            }
          },
          (seg: CommentTextSegment) => seg.key,
        )
      }
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(color)
        .width('100%')
        .gesture(
          TapGesture({ count: 1 })
            .onAction(() => {
              const url: string = this.firstCommentUrl(text)
              if (url.length > 0) {
                this.openCommentUrl(url)
              }
            }),
        )
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
      Text(this.quoteExcerpt(c.contentText))
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
    this.FooterAction($r('sys.symbol.square_and_pencil'), $r('sys.color.font_tertiary'), false, () => {
      this.publishEdit(c)
    })
  }

  @Builder
  ReplyAction(c: EhGalleryComment) {
    this.FooterAction($r('sys.symbol.ellipsis_message'), $r('sys.color.font_tertiary'), false, () => {
      this.publishReply(c)
    })
  }

  @Builder
  VoteAction(c: EhGalleryComment, vote: number, icon: Resource) {
    this.FooterAction(icon, this.voteColor(c, vote), false, () => {
      if (this.canVote(c)) {
        this.publishVote(c, vote)
      }
    })
  }

  @Builder
  TranslationAction(c: EhGalleryComment) {
    if (this.useSingleComment && this.liveTranslationShown && this.liveTranslationText.length > 0) {
      this.FooterAction($r('sys.symbol.translate'), ThemeConstants.BRAND_PRIMARY, this.liveTranslationLoading, () => {
        this.toggleOrTranslate(c)
      })
    } else if (!this.useSingleComment && c.translationShown && c.translationText.length > 0) {
      this.FooterAction($r('sys.symbol.translate'), ThemeConstants.BRAND_PRIMARY, c.translationLoading, () => {
        this.toggleOrTranslate(c)
      })
    } else {
      this.FooterAction($r('sys.symbol.translate'), $r('sys.color.font_tertiary'), this.isTranslationLoading(c), () => {
        this.toggleOrTranslate(c)
      })
    }
  }

  @Builder
  FooterAction(icon: Resource, color: ResourceColor, disabled: boolean, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      if (disabled) {
        LoadingProgress()
          .width(COMMENT_FOOTER_ICON_SIZE)
          .height(COMMENT_FOOTER_ICON_SIZE)
      } else {
        SymbolGlyph(icon)
          .fontSize(COMMENT_FOOTER_ICON_SIZE)
          .fontColor([color])
      }
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(Color.Transparent)
    .width(COMMENT_FOOTER_ACTION_SIZE)
    .height(COMMENT_FOOTER_ACTION_SIZE)
    .enabled(!disabled)
    .opacity(disabled ? 0.45 : 1)
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
      .padding({ left: ThemeConstants.COMMENT_BADGE_PADDING_H, right: ThemeConstants.COMMENT_BADGE_PADDING_H })
      .textAlign(TextAlign.Center)
  }
}

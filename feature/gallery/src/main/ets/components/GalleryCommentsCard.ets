import { ThemeConstants, EhGalleryComment } from 'shared'

const COMMENT_FOOTER_ACTION_SIZE: number = 30
const COMMENT_FOOTER_ICON_SIZE: number = 16

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
  @Param max: number = 0;
  @Event onMore: () => void = () => {};
  @Event onAuthor: (name: string) => void = (_name: string) => {};
  @Event onVote: (comment: EhGalleryComment, vote: number) => void = (_comment: EhGalleryComment, _vote: number) => {};
  @Event onReply: (comment: EhGalleryComment) => void = (_comment: EhGalleryComment) => {};
  @Event onEdit: (comment: EhGalleryComment) => void = (_comment: EhGalleryComment) => {};

  private hasMore(): boolean {
    return this.max > 0 && this.comments.length > this.max
  }

  private canOpenFullComments(): boolean {
    return this.max > 0 && this.comments.length > 0
  }

  private shown(): EhGalleryComment[] {
    return this.max > 0 && this.comments.length > this.max
      ? this.comments.slice(0, this.max)
      : this.comments
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
    return `${c.commentId}:${c.vote}:${c.score}`
  }

  private voteColor(c: EhGalleryComment, vote: number): ResourceColor {
    return c.vote === vote ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_tertiary')
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

  private replyTargetId(text: string): string {
    const lines: string[] = text.split('\n')
    if (lines.length === 0) {
      return ''
    }
    const first: string = lines[0].trim()
    if (!first.startsWith('@')) {
      return ''
    }
    const hashId: string = this.hashReplyId(first)
    if (hashId.length > 0) {
      return hashId
    }
    return lines.length > 1 ? this.decodeReplyId(lines[1]) : ''
  }

  private replyReferences(c: EhGalleryComment): EhGalleryComment[] {
    const id: string = this.replyTargetId(c.contentText)
    if (id.length === 0 || id === c.commentId) {
      return []
    }
    const out: EhGalleryComment[] = []
    for (let i = 0; i < this.comments.length; i++) {
      const candidate: EhGalleryComment = this.comments[i]
      if (candidate.commentId === id) {
        out.push(candidate)
        break
      }
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

  private quoteExcerpt(text: string): string {
    const clean: string = text.replace(/\n+/g, ' ').trim()
    return clean.length > 120 ? `${clean.substring(0, 120)}...` : clean
  }

  private commentGap(): number {
    return ThemeConstants.SPACE_SM - 2
  }

  build() {
    Column({ space: this.commentGap() }) {
      // Header — in peek mode the whole row taps through to the full comments page. It is deliberately
      // outside the comment cards, following Next2V's HotRepliesPanel: the comment itself is the card.
      Row({ space: ThemeConstants.SPACE_XS }) {
        Text($r('app.string.gallery_comments'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        if (this.comments.length > 0) {
          Text(`(${this.comments.length})`)
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
      ForEach(
        this.shown(),
        (c: EhGalleryComment, index: number) => {
          this.CommentRow(c, index === this.shown().length - 1)
        },
        (c: EhGalleryComment) => this.commentRowKey(c),
      )
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
            this.onAuthor(c.author)
          })
        // Uploader comments carry an UP badge. The numeric community score is shown only on the FULL
        // comments page (max === 0): eros_fe's CommentItem(simple) gates the score chip behind `!simple`,
        // so the PEEK deliberately suppresses it (author + body + time only, UP for the uploader).
        if (c.isUploader) {
          this.CommentBadge($r('app.string.comment_uploader'), true)
        } else if (c.score.length > 0 && this.max <= 0) {
          Row() {
            this.CommentBadge(this.displayScore(c.score), false)
          }
            .onClick(() => {
              this.showScoreDetails(c)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      this.ReplyReferences(c)
      // EH comments are predominantly text + line breaks + URLs (bare or as `<a>` whose link text
      // is the URL). The native URL data-detector turns those into tappable, brand-colored links
      // (eros_fe linkifies bare URLs too) without a heavy HTML/web renderer. In the peek the text is
      // capped at eros_fe's 4 lines; the full page (max === 0) shows it all.
      if (this.max > 0) {
        Text(this.displayContentText(c))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .enableDataDetector(true)
          .dataDetectorConfig({
            types: [TextDataDetectorType.URL],
            color: $r('sys.color.font_emphasize'),
          })
      } else {
        Text(this.displayContentText(c))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .enableDataDetector(true)
          .dataDetectorConfig({
            types: [TextDataDetectorType.URL],
            color: $r('sys.color.font_emphasize'),
          })
      }
      // Time/actions footer (eros_fe _CommentTail): full comments expose bounded vote actions.
      Row() {
        Text(c.postedTime)
          .fontSize(ThemeConstants.FONT_SIZE_TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.max <= 0 && c.canEdit && c.commentId.length > 0 && c.commentId !== '0') {
          this.EditAction(c)
        }
        if (this.max <= 0 && c.canVote) {
          this.VoteAction(c, 1, c.vote > 0 ? $r('sys.symbol.hand_thumbsup_fill') : $r('sys.symbol.hand_thumbsup'))
          this.VoteAction(c, -1, c.vote < 0 ? $r('sys.symbol.hand_thumbsdown_fill') : $r('sys.symbol.hand_thumbsdown'))
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
      bottom: ThemeConstants.SPACE_SM,
    })
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      if (this.canOpenFullComments()) {
        this.onMore()
      }
    })
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
      this.onEdit(c)
    })
  }

  @Builder
  ReplyAction(c: EhGalleryComment) {
    this.FooterAction($r('sys.symbol.ellipsis_message'), $r('sys.color.font_tertiary'), false, () => {
      this.onReply(c)
    })
  }

  @Builder
  VoteAction(c: EhGalleryComment, vote: number, icon: Resource) {
    this.FooterAction(icon, this.voteColor(c, vote), false, () => {
      if (this.canVote(c)) {
        this.onVote(c, vote)
      }
    })
  }

  @Builder
  FooterAction(icon: Resource, color: ResourceColor, disabled: boolean, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(COMMENT_FOOTER_ICON_SIZE)
        .fontColor([color])
    }
    .width(COMMENT_FOOTER_ACTION_SIZE)
    .height(COMMENT_FOOTER_ACTION_SIZE)
    .justifyContent(FlexAlign.Center)
    .opacity(disabled ? 0.45 : 1)
    .onClick(() => {
      if (!disabled) {
        action()
      }
    })
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

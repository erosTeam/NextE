import { ThemeConstants, EhGalleryComment, GroupedListSection } from 'shared'

/**
 * Comments card, shared by the detail-page PEEK and the full comments page (eros_fe TopCommentEx +
 * galleryComment). `max > 0` is the peek: it shows the first `max` comments, the "评论" header turns
 * into a tappable "查看全部 (N)" entry, and `onMore` opens the full page. `max === 0` shows them all
 * (the page). The peek sits BEFORE the previews on the detail page so comments are reachable without
 * scrolling past every thumbnail. v1 read-only; shares the GroupedListSection chrome.
 */
@ComponentV2
export struct GalleryCommentsCard {
  @Require @Param comments: EhGalleryComment[];
  @Param max: number = 0;
  @Event onMore: () => void = () => {};
  @Event onAuthor: (name: string) => void = (_name: string) => {};

  private hasMore(): boolean {
    return this.max > 0 && this.comments.length > this.max
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

  build() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_MD }) {
        // Header — in peek mode the whole row taps through to the full comments page.
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
          if (this.hasMore()) {
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
        .onClick(() => {
          if (this.hasMore()) {
            this.onMore()
          }
        })
        ForEach(
          this.shown(),
          (c: EhGalleryComment, index: number) => {
            this.CommentRow(c, index === this.shown().length - 1)
          },
          (c: EhGalleryComment) => c.commentId,
        )
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
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
          Text($r('app.string.comment_uploader'))
            .fontSize(ThemeConstants.FONT_SIZE_TINY)
            .fontColor(ThemeConstants.TEXT_ON_BRAND)
            .backgroundColor(ThemeConstants.BRAND_PRIMARY)
            .borderRadius(ThemeConstants.RADIUS_SM)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        } else if (c.score.length > 0 && this.max <= 0) {
          Text(c.score)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeConstants.TEXT_ON_BRAND)
            .backgroundColor(
              c.score.startsWith('-')
                ? $r('app.color.score_negative')
                : $r('app.color.score_positive'),
            )
            .borderRadius(ThemeConstants.RADIUS_SM)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .onClick(() => {
              this.showScoreDetails(c)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // EH comments are predominantly text + line breaks + URLs (bare or as `<a>` whose link text
      // is the URL). The native URL data-detector turns those into tappable, brand-colored links
      // (eros_fe linkifies bare URLs too) without a heavy HTML/web renderer. In the peek the text is
      // capped at eros_fe's 4 lines; the full page (max === 0) shows it all.
      if (this.max > 0) {
        Text(c.contentText)
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
        Text(c.contentText)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .enableDataDetector(true)
          .dataDetectorConfig({
            types: [TextDataDetectorType.URL],
            color: $r('sys.color.font_emphasize'),
          })
      }
      // Time footer (eros_fe _CommentTail): small, muted, below the body.
      Text(c.postedTime)
        .fontSize(ThemeConstants.FONT_SIZE_TINY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ThemeConstants.SPACE_SM)
    .borderRadius(ThemeConstants.RADIUS_MD)
    .backgroundColor(ThemeConstants.BG_SUB)
  }
}

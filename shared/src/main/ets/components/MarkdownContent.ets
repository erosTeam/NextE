import {
  MarkdownBlock,
  MarkdownDocument,
  MarkdownInline,
  MARKDOWN_BLOCK_BULLET,
  MARKDOWN_BLOCK_CODE,
  MARKDOWN_BLOCK_DIVIDER,
  MARKDOWN_BLOCK_HEADING,
  MARKDOWN_BLOCK_ORDERED,
  MARKDOWN_BLOCK_QUOTE,
} from '../parser/MarkdownDocument'
import { ThemeConstants } from '../theme/ThemeConstants'

function markdownExternalUrl(value: string): string {
  return MarkdownDocument.externalHttpUrl(value)
}

function markdownSpanColor(segment: MarkdownInline, color: ResourceColor): ResourceColor {
  if (markdownExternalUrl(segment.url).length > 0) {
    return ThemeConstants.TEXT_LINK
  }
  if (segment.code) {
    return $r('sys.color.font_secondary')
  }
  return color
}

function markdownSpanDecoration(segment: MarkdownInline): TextDecorationType {
  if (markdownExternalUrl(segment.url).length > 0) {
    return TextDecorationType.Underline
  }
  if (segment.strike) {
    return TextDecorationType.LineThrough
  }
  return TextDecorationType.None
}

function markdownHeadingSize(level: number): number {
  if (level <= 2) {
    return ThemeConstants.FONT_SIZE_HEADING
  }
  return ThemeConstants.FONT_SIZE_BODY
}

function openMarkdownExternalLink(value: string, onLinkClick: (url: string) => void): void {
  const url: string = markdownExternalUrl(value)
  if (url.length > 0) {
    onLinkClick(url)
  }
}

@Builder
function MarkdownSpans(
  segments: MarkdownInline[],
  color: ResourceColor,
  emphasized: boolean,
  onLinkClick: (url: string) => void,
) {
  ForEach(segments, (segment: MarkdownInline) => {
    Span(segment.text)
      .fontColor(markdownSpanColor(segment, color))
      .fontWeight(
        segment.bold || emphasized
          ? FontWeight.Bold
          : (segment.code ? FontWeight.Medium : FontWeight.Regular),
      )
      .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
      .decoration({ type: markdownSpanDecoration(segment) })
      .onClick(() => {
        openMarkdownExternalLink(segment.url, onLinkClick)
      })
  }, (segment: MarkdownInline) => segment.key)
}

// These helpers are global on purpose. `MarkdownContent` can be mounted through a V2 dialog's
// @BuilderParam; a global builder does not rely on an instance `this` surviving that boundary.
@Builder
function MarkdownInlineText(
  segments: MarkdownInline[],
  fontSize: number,
  color: ResourceColor,
  emphasized: boolean,
  onLinkClick: (url: string) => void,
) {
  Text() {
    MarkdownSpans(segments, color, emphasized, onLinkClick)
  }
  .fontSize(fontSize)
  .fontColor(color)
  .width('100%')
}

@Builder
function MarkdownPrefixedBlockView(
  block: MarkdownBlock,
  leftPadding: number,
  onLinkClick: (url: string) => void,
) {
  Row({ space: ThemeConstants.SPACE_XS }) {
    Text(block.prefix)
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor($r('sys.color.font_secondary'))
    Text() {
      MarkdownSpans(
        block.segments,
        $r('sys.color.font_secondary'),
        false,
        onLinkClick,
      )
    }
    .fontSize(ThemeConstants.FONT_SIZE_BODY)
    .fontColor($r('sys.color.font_secondary'))
    .layoutWeight(1)
  }
  .width('100%')
  .alignItems(VerticalAlign.Top)
  .padding({ left: leftPadding })
}

@Builder
function MarkdownBlockView(block: MarkdownBlock, onLinkClick: (url: string) => void) {
  if (block.kind === MARKDOWN_BLOCK_HEADING) {
    MarkdownInlineText(
      block.segments,
      markdownHeadingSize(block.level),
      $r('sys.color.font_primary'),
      true,
      onLinkClick,
    )
  } else if (block.kind === MARKDOWN_BLOCK_BULLET || block.kind === MARKDOWN_BLOCK_ORDERED) {
    MarkdownPrefixedBlockView(
      block,
      block.indent * ThemeConstants.SPACE_MD,
      onLinkClick,
    )
  } else if (block.kind === MARKDOWN_BLOCK_QUOTE) {
    MarkdownPrefixedBlockView(block, ThemeConstants.SPACE_SM, onLinkClick)
  } else if (block.kind === MARKDOWN_BLOCK_CODE) {
    Text(block.text)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor($r('sys.color.font_secondary'))
      .fontWeight(FontWeight.Medium)
      .width('100%')
  } else if (block.kind === MARKDOWN_BLOCK_DIVIDER) {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
  } else {
    MarkdownInlineText(
      block.segments,
      ThemeConstants.FONT_SIZE_BODY,
      $r('sys.color.font_secondary'),
      false,
      onLinkClick,
    )
  }
}

/**
 * Shared native ArkUI Markdown renderer.
 *
 * The input stays raw Markdown so pages do not need their own parser, model,
 * rich-span loop, or block layout. Link ownership remains with the host via
 * `onLinkClick`; only external HTTP(S) URLs are emitted.
 */
@ComponentV2
export struct MarkdownContent {
  @Param markdown: string = ''
  @Event onLinkClick: (url: string) => void = (_url: string) => {}

  private blocks(): MarkdownBlock[] {
    return MarkdownDocument.parse(this.markdown)
  }

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      ForEach(
        this.blocks(),
        (block: MarkdownBlock) => {
          MarkdownBlockView(block, this.onLinkClick)
        },
        (block: MarkdownBlock) => block.key,
      )
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

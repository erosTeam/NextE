export const MARKDOWN_BLOCK_PARAGRAPH: string = 'paragraph'
export const MARKDOWN_BLOCK_HEADING: string = 'heading'
export const MARKDOWN_BLOCK_BULLET: string = 'bullet'
export const MARKDOWN_BLOCK_ORDERED: string = 'ordered'
export const MARKDOWN_BLOCK_QUOTE: string = 'quote'
export const MARKDOWN_BLOCK_CODE: string = 'code'
export const MARKDOWN_BLOCK_DIVIDER: string = 'divider'

export class MarkdownInline {
  key: string = ''
  text: string = ''
  url: string = ''
  bold: boolean = false
  italic: boolean = false
  code: boolean = false
  strike: boolean = false
}

export class MarkdownBlock {
  key: string = ''
  kind: string = MARKDOWN_BLOCK_PARAGRAPH
  text: string = ''
  segments: MarkdownInline[] = []
  level: number = 0
  indent: number = 0
  prefix: string = ''
}

/**
 * Dependency-free Markdown document parser for native ArkUI surfaces.
 *
 * It produces a small render-neutral document model so every consumer has the
 * same block/inline semantics instead of adding page-local Markdown handling.
 */
export class MarkdownDocument {
  static parse(markdown: string): MarkdownBlock[] {
    const blocks: MarkdownBlock[] = []
    const paragraph: string[] = []
    const codeLines: string[] = []
    const lines: string[] = markdown.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')
    let sequence: number = 0
    let inCodeBlock: boolean = false
    for (let index: number = 0; index < lines.length; index++) {
      const rawLine: string = lines[index]
      const trimmedLine: string = rawLine.trim()
      if (trimmedLine.startsWith('```')) {
        sequence = MarkdownDocument.appendParagraph(blocks, paragraph, sequence)
        if (inCodeBlock) {
          sequence = MarkdownDocument.appendBlock(
            blocks,
            sequence,
            MARKDOWN_BLOCK_CODE,
            codeLines.join('\n'),
          )
          codeLines.length = 0
          inCodeBlock = false
        } else {
          inCodeBlock = true
        }
        continue
      }
      if (inCodeBlock) {
        codeLines.push(rawLine)
        continue
      }
      if (trimmedLine.length === 0) {
        sequence = MarkdownDocument.appendParagraph(blocks, paragraph, sequence)
        continue
      }
      const heading: RegExpExecArray | null = /^(#{1,6})\s+(.+?)(?:\s+#+)?$/.exec(trimmedLine)
      if (heading !== null) {
        sequence = MarkdownDocument.appendParagraph(blocks, paragraph, sequence)
        sequence = MarkdownDocument.appendBlock(
          blocks,
          sequence,
          MARKDOWN_BLOCK_HEADING,
          heading[2],
          heading[1].length,
        )
        continue
      }
      const bullet: RegExpExecArray | null = /^(\s*)[-+*]\s+(.+)$/.exec(rawLine)
      if (bullet !== null) {
        sequence = MarkdownDocument.appendParagraph(blocks, paragraph, sequence)
        sequence = MarkdownDocument.appendBlock(
          blocks,
          sequence,
          MARKDOWN_BLOCK_BULLET,
          bullet[2],
          0,
          Math.floor(bullet[1].length / 2),
          '•',
        )
        continue
      }
      const ordered: RegExpExecArray | null = /^(\s*)(\d+)[.)]\s+(.+)$/.exec(rawLine)
      if (ordered !== null) {
        sequence = MarkdownDocument.appendParagraph(blocks, paragraph, sequence)
        sequence = MarkdownDocument.appendBlock(
          blocks,
          sequence,
          MARKDOWN_BLOCK_ORDERED,
          ordered[3],
          0,
          Math.floor(ordered[1].length / 2),
          ordered[2] + '.',
        )
        continue
      }
      const quote: RegExpExecArray | null = /^>\s?(.+)$/.exec(trimmedLine)
      if (quote !== null) {
        sequence = MarkdownDocument.appendParagraph(blocks, paragraph, sequence)
        sequence = MarkdownDocument.appendBlock(
          blocks,
          sequence,
          MARKDOWN_BLOCK_QUOTE,
          quote[1],
          0,
          0,
          '›',
        )
        continue
      }
      if (/^(?:-{3,}|\*{3,}|_{3,})$/.test(trimmedLine)) {
        sequence = MarkdownDocument.appendParagraph(blocks, paragraph, sequence)
        sequence = MarkdownDocument.appendBlock(
          blocks,
          sequence,
          MARKDOWN_BLOCK_DIVIDER,
          '-',
        )
        continue
      }
      paragraph.push(trimmedLine)
    }
    sequence = MarkdownDocument.appendParagraph(blocks, paragraph, sequence)
    if (inCodeBlock) {
      MarkdownDocument.appendBlock(
        blocks,
        sequence,
        MARKDOWN_BLOCK_CODE,
        codeLines.join('\n'),
      )
    }
    return blocks
  }

  static externalHttpUrl(value: string): string {
    const url: string = value.trim()
    if (url.startsWith('https://') || url.startsWith('http://')) {
      return url
    }
    return ''
  }

  private static appendParagraph(blocks: MarkdownBlock[], lines: string[], sequence: number): number {
    if (lines.length === 0) {
      return sequence
    }
    const text: string = lines.join(' ')
    lines.length = 0
    return MarkdownDocument.appendBlock(blocks, sequence, MARKDOWN_BLOCK_PARAGRAPH, text)
  }

  private static appendBlock(
    blocks: MarkdownBlock[],
    sequence: number,
    kind: string,
    text: string,
    level: number = 0,
    indent: number = 0,
    prefix: string = '',
  ): number {
    const content: string = kind === MARKDOWN_BLOCK_CODE ? text : text.trim()
    if (content.length === 0) {
      return sequence
    }
    const block: MarkdownBlock = new MarkdownBlock()
    block.key = kind + '_' + sequence
    block.kind = kind
    block.text = content
    block.level = level
    block.indent = indent
    block.prefix = prefix
    if (kind !== MARKDOWN_BLOCK_CODE && kind !== MARKDOWN_BLOCK_DIVIDER) {
      block.segments = MarkdownDocument.parseInline(content)
    }
    blocks.push(block)
    return sequence + 1
  }

  private static parseInline(value: string): MarkdownInline[] {
    const segments: MarkdownInline[] = []
    const tokens: RegExp = /\[([^\]]+)\]\(([^)\s]+)\)|(\*\*|__)([^*_\n]+?)\3|`([^`\n]+)`|~~([^~\n]+)~~|(\*|_)([^*_\n]+?)\7/g
    let sequence: number = 0
    let cursor: number = 0
    let match: RegExpExecArray | null = tokens.exec(value)
    while (match !== null) {
      if (match.index > cursor) {
        sequence = MarkdownDocument.appendInline(segments, sequence, value.substring(cursor, match.index))
      }
      const inline: MarkdownInline = new MarkdownInline()
      inline.key = 'inline_' + sequence
      if (match[1] && match[2]) {
        inline.text = match[1]
        inline.url = match[2]
      } else if (match[4]) {
        inline.text = match[4]
        inline.bold = true
      } else if (match[5]) {
        inline.text = match[5]
        inline.code = true
      } else if (match[6]) {
        inline.text = match[6]
        inline.strike = true
      } else if (match[8]) {
        inline.text = match[8]
        inline.italic = true
      } else {
        inline.text = match[0]
      }
      if (inline.text.length > 0) {
        segments.push(inline)
        sequence += 1
      }
      cursor = match.index + match[0].length
      match = tokens.exec(value)
    }
    if (cursor < value.length) {
      MarkdownDocument.appendInline(segments, sequence, value.substring(cursor))
    }
    return segments
  }

  private static appendInline(segments: MarkdownInline[], sequence: number, text: string): number {
    if (text.length === 0) {
      return sequence
    }
    const inline: MarkdownInline = new MarkdownInline()
    inline.key = 'inline_' + sequence
    inline.text = text
    segments.push(inline)
    return sequence + 1
  }
}

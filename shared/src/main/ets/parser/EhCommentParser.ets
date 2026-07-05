import {
  EhGalleryComment,
  EhGalleryCommentLink,
  EhGalleryCommentTextSpan,
} from '../model/EhGalleryComment'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

class CommentBodyParseResult {
  text: string = ''
  links: EhGalleryCommentLink[] = []
  spans: EhGalleryCommentTextSpan[] = []
}

class CommentInlineStyle {
  url: string = ''
  bold: boolean = false
  italic: boolean = false
  underline: boolean = false
  strike: boolean = false
  color: string = ''

  copy(): CommentInlineStyle {
    const next: CommentInlineStyle = new CommentInlineStyle()
    next.url = this.url
    next.bold = this.bold
    next.italic = this.italic
    next.underline = this.underline
    next.strike = this.strike
    next.color = this.color
    return next
  }

  hasRenderStyle(): boolean {
    return (
      this.url.length > 0 ||
      this.bold ||
      this.italic ||
      this.underline ||
      this.strike ||
      this.color.length > 0
    )
  }
}

/**
 * Parses the gallery-detail comment list. Each comment is a `<div class="c1">` block holding a
 * `<div class="c3">Posted on <DATE> by: <a>AUTHOR</a> …</div>` header and a
 * `<div class="c6" id="comment_N">BODY</div>` body. It strips the body to plain text and also
 * preserves the metadata eros_fe uses for the full comments page: member id, current vote,
 * edit/vote capability, score details, and device-local post time. Keep in sync with
 * scripts/test_comment_parser_contract.mjs.
 */
export class EhCommentParser {
  private static readonly RE_BLOCK: string =
    '<div class="c1">[\\s\\S]*?<div class="c6" id="comment_(\\d+)">([\\s\\S]*?)</div>([\\s\\S]*?)(?=<a name="c\\d+"></a><div class="c1">|$)'
  private static readonly RE_DATE: RegExp = /Posted on ([^<]+?) by:/
  private static readonly RE_AUTHOR: RegExp = /by:\s*(?:&nbsp;\s*)*<a[^>]*>([^<]+)<\/a>/
  private static readonly RE_MEMBER_ID: RegExp = /index\.php\?showuser=(\d+)/
  // c5 holds "Score +N"/"Score -N"; capture the signed number. Uploader comment has no c5.
  private static readonly RE_SCORE: RegExp = /<div class="c5 nosel"[^>]*>[\s\S]*?([+-]\d+)/
  private static readonly RE_C4: RegExp = /<div class="c4 nosel"[^>]*>([\s\S]*?)<\/div>/
  private static readonly RE_C7: RegExp = /<div class="c7"[^>]*>([\s\S]*?)<\/div>/
  private static readonly RE_SPAN: RegExp = /<span[^>]*>([\s\S]*?)<\/span>/g
  private static readonly RE_FIRST_TAG: RegExp = /<[^>]+>/
  private static readonly RE_BODY_LINK: RegExp =
    /<a\b[^>]*\bhref=(["'])([^"']+)\1[^>]*>([\s\S]*?)<\/a>/gi
  private static readonly RE_POSTED_PARTS: RegExp =
    /(\d{1,2})\s+([A-Za-z]+)\s+(\d{4}),\s+(\d{1,2}):(\d{2})/

  static parse(html: string): EhGalleryComment[] {
    const out: EhGalleryComment[] = []
    const re: RegExp = new RegExp(EhCommentParser.RE_BLOCK, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (m[1] !== undefined && m[2] !== undefined) {
        const c: EhGalleryComment = new EhGalleryComment()
        const body: CommentBodyParseResult = EhCommentParser.parseBody(m[2])
        c.commentId = m[1]
        c.contentText = body.text
        c.contentLinks = body.links
        c.contentSpans = body.spans
        c.postedTime = EhCommentParser.localPostedTime(
          HtmlSelectorUtils.group1(m[0], EhCommentParser.RE_DATE).trim(),
        )
        c.author = HtmlSelectorUtils.group1(m[0], EhCommentParser.RE_AUTHOR).trim()
        c.memberId = HtmlSelectorUtils.group1(m[0], EhCommentParser.RE_MEMBER_ID).trim()
        c.score = HtmlSelectorUtils.group1(m[0], EhCommentParser.RE_SCORE).trim()
        const c4: string = HtmlSelectorUtils.group1(m[0], EhCommentParser.RE_C4)
        c.canEdit = c4.indexOf('edit_') >= 0
        c.canVote = c4.indexOf('vote_') >= 0
        c.vote = EhCommentParser.parseVote(c4)
        c.scoreDetails = EhCommentParser.parseScoreDetails(m[3] !== undefined ? m[3] : '')
        // eros_fe treats the uploader comment as the score-less row; the literal marker is not
        // guaranteed to be present on every captured page shape.
        c.isUploader = m[0].includes('Uploader Comment') || c.score.length === 0
        // Skip empty-body comments: a real EH comment always has text, so an empty c6 body means a
        // bad/partial response (e.g. an interstitial/throttle page that still matched the comment shell).
        // Keeping them rendered N blank rows.
        if (c.contentText.length > 0) {
          out.push(c)
        }
      }
      m = re.exec(html)
    }
    return out
  }

  private static parseVote(c4: string): number {
    if (c4.length === 0) {
      return 0
    }
    const style1: string = EhCommentParser.nthAnchorStyle(c4, 1)
    const style2: string = EhCommentParser.nthAnchorStyle(c4, 2)
    if (style1.length > 0) {
      return 1
    }
    if (style2.length > 0) {
      return -1
    }
    return 0
  }

  private static nthAnchorStyle(html: string, n: number): string {
    const re: RegExp = /<a[^>]*>/g
    let index: number = 0
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      index += 1
      if (index === n && m[0] !== undefined) {
        const style: RegExpMatchArray | null = m[0].match(/style="([^"]*)"/)
        if (style !== null && style[1] !== undefined) {
          return style[1].trim()
        }
        return ''
      }
      m = re.exec(html)
    }
    return ''
  }

  private static parseScoreDetails(trailingHtml: string): string[] {
    const c7: string = HtmlSelectorUtils.group1(trailingHtml, EhCommentParser.RE_C7)
    if (c7.length === 0) {
      return []
    }
    const out: string[] = []
    const firstTag: RegExpMatchArray | null = c7.match(EhCommentParser.RE_FIRST_TAG)
    const leadHtml: string =
      firstTag !== null && firstTag.index !== undefined ? c7.substring(0, firstTag.index) : c7
    const lead: string = EhCommentParser.stripHtml(leadHtml).replace(/,\s*$/, '').trim()
    if (lead.length > 0) {
      out.push(lead)
    }
    const re: RegExp = new RegExp(EhCommentParser.RE_SPAN.source, 'g')
    let m: RegExpExecArray | null = re.exec(c7)
    while (m !== null) {
      if (m[1] !== undefined) {
        const text: string = EhCommentParser.stripHtml(m[1])
        if (text.length > 0) {
          out.push(text)
        }
      }
      m = re.exec(c7)
    }
    return out
  }

  private static localPostedTime(raw: string): string {
    const m: RegExpMatchArray | null = raw.match(EhCommentParser.RE_POSTED_PARTS)
    if (
      m === null ||
      m[1] === undefined ||
      m[2] === undefined ||
      m[3] === undefined ||
      m[4] === undefined ||
      m[5] === undefined
    ) {
      return raw
    }
    const month: number = EhCommentParser.monthIndex(m[2])
    if (month < 0) {
      return raw
    }
    const day: number = Number.parseInt(m[1], 10)
    const year: number = Number.parseInt(m[3], 10)
    const hour: number = Number.parseInt(m[4], 10)
    const minute: number = Number.parseInt(m[5], 10)
    const dt: Date = new Date(Date.UTC(year, month, day, hour, minute, 0))
    return `${dt.getFullYear()}-${EhCommentParser.pad2(dt.getMonth() + 1)}-${EhCommentParser.pad2(dt.getDate())} ${EhCommentParser.pad2(dt.getHours())}:${EhCommentParser.pad2(dt.getMinutes())}`
  }

  private static monthIndex(month: string): number {
    switch (month) {
      case 'January':
        return 0
      case 'February':
        return 1
      case 'March':
        return 2
      case 'April':
        return 3
      case 'May':
        return 4
      case 'June':
        return 5
      case 'July':
        return 6
      case 'August':
        return 7
      case 'September':
        return 8
      case 'October':
        return 9
      case 'November':
        return 10
      case 'December':
        return 11
      default:
        return -1
    }
  }

  private static pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`
  }

  private static stripHtml(html: string): string {
    return EhCommentParser.stripHtmlNoLinks(html)
  }

  private static stripHtmlNoLinks(html: string): string {
    return EhCommentParser.stripHtmlFragment(html).trim()
  }

  private static stripHtmlFragment(html: string): string {
    let s: string = html
    s = s.replace(/<br\s*\/?>/g, '\n')
    s = s.replace(/<[^>]+>/g, '')
    return HtmlSelectorUtils.htmlUnescape(s).replace(/\u00A0/g, ' ')
  }

  private static parseBody(html: string): CommentBodyParseResult {
    const result: CommentBodyParseResult = new CommentBodyParseResult()
    EhCommentParser.parseInlineHtml(html, new CommentInlineStyle(), result)
    return EhCommentParser.trimBodyParseResult(result.text, result.links, result.spans)
  }

  private static parseInlineHtml(html: string, style: CommentInlineStyle, result: CommentBodyParseResult): void {
    let cursor: number = 0
    while (cursor < html.length) {
      const tagStart: number = html.indexOf('<', cursor)
      if (tagStart < 0) {
        EhCommentParser.appendStyledText(result, html.substring(cursor), style)
        return
      }
      if (tagStart > cursor) {
        EhCommentParser.appendStyledText(result, html.substring(cursor, tagStart), style)
      }
      const tagEnd: number = html.indexOf('>', tagStart + 1)
      if (tagEnd < 0) {
        EhCommentParser.appendStyledText(result, html.substring(tagStart), style)
        return
      }
      const tag: string = html.substring(tagStart, tagEnd + 1)
      const name: string = EhCommentParser.tagName(tag)
      if (tag.startsWith('</')) {
        cursor = tagEnd + 1
        continue
      }
      if (name === 'br') {
        EhCommentParser.appendStyledText(result, '\n', style)
        cursor = tagEnd + 1
        continue
      }
      const closeStart: number = EhCommentParser.findClosingTag(html, tagEnd + 1, name)
      if (closeStart < 0 || !EhCommentParser.supportedInlineTag(name)) {
        cursor = tagEnd + 1
        continue
      }
      const nextStyle: CommentInlineStyle = EhCommentParser.styleForTag(name, tag, style)
      const beforeLength: number = result.text.length
      EhCommentParser.parseInlineHtml(html.substring(tagEnd + 1, closeStart), nextStyle, result)
      if (name === 'a' && result.text.length === beforeLength && nextStyle.url.length > 0) {
        EhCommentParser.appendStyledText(result, nextStyle.url, nextStyle)
      }
      const closeEnd: number = html.indexOf('>', closeStart + 1)
      cursor = closeEnd < 0 ? html.length : closeEnd + 1
    }
  }

  private static appendStyledText(
    result: CommentBodyParseResult,
    raw: string,
    style: CommentInlineStyle,
  ): void {
    if (raw.length === 0) {
      return
    }
    const text: string = HtmlSelectorUtils.htmlUnescape(raw).replace(/\u00A0/g, ' ')
    if (text.length === 0) {
      return
    }
    const start: number = result.text.length
    result.text += text
    const end: number = result.text.length
    if (style.url.length > 0) {
      const link: EhGalleryCommentLink = new EhGalleryCommentLink()
      link.start = start
      link.end = end
      link.url = style.url
      result.links.push(link)
    }
    if (style.hasRenderStyle()) {
      const span: EhGalleryCommentTextSpan = new EhGalleryCommentTextSpan()
      span.start = start
      span.end = end
      span.url = style.url
      span.bold = style.bold
      span.italic = style.italic
      span.underline = style.underline
      span.strike = style.strike
      span.color = style.color
      result.spans.push(span)
    }
  }

  private static tagName(tag: string): string {
    const m: RegExpMatchArray | null = tag.match(/^<\s*\/?\s*([A-Za-z0-9]+)/)
    if (m !== null && m[1] !== undefined) {
      return m[1].toLowerCase()
    }
    return ''
  }

  private static supportedInlineTag(name: string): boolean {
    return (
      name === 'a' ||
      name === 'strong' ||
      name === 'b' ||
      name === 'em' ||
      name === 'i' ||
      name === 'u' ||
      name === 'del' ||
      name === 's' ||
      name === 'strike' ||
      name === 'span'
    )
  }

  private static findClosingTag(html: string, from: number, name: string): number {
    if (name.length === 0) {
      return -1
    }
    const re: RegExp = new RegExp(`<\\s*\\/?\\s*${name}\\b[^>]*>`, 'gi')
    re.lastIndex = from
    let depth: number = 1
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      const token: string = m[0]
      if (token.startsWith('</')) {
        depth--
        if (depth === 0) {
          return m.index !== undefined ? m.index : -1
        }
      } else if (!token.endsWith('/>')) {
        depth++
      }
      m = re.exec(html)
    }
    return -1
  }

  private static styleForTag(name: string, tag: string, parent: CommentInlineStyle): CommentInlineStyle {
    const style: CommentInlineStyle = parent.copy()
    if (name === 'a') {
      style.url = EhCommentParser.attrValue(tag, 'href')
    } else if (name === 'strong' || name === 'b') {
      style.bold = true
    } else if (name === 'em' || name === 'i') {
      style.italic = true
    } else if (name === 'u') {
      style.underline = true
    } else if (name === 'del' || name === 's' || name === 'strike') {
      style.strike = true
    } else if (name === 'span') {
      EhCommentParser.applyCssStyle(style, EhCommentParser.attrValue(tag, 'style'))
    }
    return style
  }

  private static attrValue(tag: string, name: string): string {
    const re: RegExp = new RegExp(`${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i')
    const m: RegExpMatchArray | null = tag.match(re)
    if (m === null) {
      return ''
    }
    let value: string = ''
    if (m[1] !== undefined) {
      value = m[1]
    } else if (m[2] !== undefined) {
      value = m[2]
    } else if (m[3] !== undefined) {
      value = m[3]
    }
    return HtmlSelectorUtils.htmlUnescape(value).replace(/\u00A0/g, ' ').trim()
  }

  private static applyCssStyle(style: CommentInlineStyle, raw: string): void {
    const css: string = raw.toLowerCase()
    if (css.indexOf('font-weight') >= 0 && (css.indexOf('bold') >= 0 || css.indexOf('700') >= 0)) {
      style.bold = true
    }
    if (css.indexOf('font-style') >= 0 && css.indexOf('italic') >= 0) {
      style.italic = true
    }
    if (css.indexOf('text-decoration') >= 0) {
      if (css.indexOf('underline') >= 0) {
        style.underline = true
      }
      if (css.indexOf('line-through') >= 0) {
        style.strike = true
      }
    }
    const colorMatch: RegExpMatchArray | null = raw.match(/(?:^|;)\s*color\s*:\s*(#[0-9a-fA-F]{3,8})/)
    if (colorMatch !== null && colorMatch[1] !== undefined) {
      style.color = colorMatch[1]
    }
  }

  private static trimBodyParseResult(
    text: string,
    links: EhGalleryCommentLink[],
    spans: EhGalleryCommentTextSpan[],
  ): CommentBodyParseResult {
    const result: CommentBodyParseResult = new CommentBodyParseResult()
    const startTrim: number = EhCommentParser.leadingWhitespace(text)
    const endTrim: number = EhCommentParser.trailingWhitespace(text)
    const end: number = text.length - endTrim
    result.text = startTrim < end ? text.substring(startTrim, end) : ''
    for (let i = 0; i < links.length; i++) {
      const raw: EhGalleryCommentLink = links[i]
      if (raw.end <= startTrim || raw.start >= end) {
        continue
      }
      const link: EhGalleryCommentLink = new EhGalleryCommentLink()
      link.start = raw.start - startTrim
      link.end = raw.end - startTrim
      link.url = raw.url
      result.links.push(link)
    }
    for (let i = 0; i < spans.length; i++) {
      const raw: EhGalleryCommentTextSpan = spans[i]
      if (raw.end <= startTrim || raw.start >= end) {
        continue
      }
      const span: EhGalleryCommentTextSpan = new EhGalleryCommentTextSpan()
      span.start = raw.start - startTrim
      span.end = raw.end - startTrim
      span.url = raw.url
      span.bold = raw.bold
      span.italic = raw.italic
      span.underline = raw.underline
      span.strike = raw.strike
      span.color = raw.color
      result.spans.push(span)
    }
    return result
  }

  private static leadingWhitespace(text: string): number {
    let count: number = 0
    while (count < text.length && text.charAt(count).trim().length === 0) {
      count++
    }
    return count
  }

  private static trailingWhitespace(text: string): number {
    let count: number = 0
    while (count < text.length && text.charAt(text.length - count - 1).trim().length === 0) {
      count++
    }
    return count
  }
}

import { EhGalleryComment } from '../model/EhGalleryComment'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

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
  private static readonly RE_POSTED_PARTS: RegExp =
    /(\d{1,2})\s+([A-Za-z]+)\s+(\d{4}),\s+(\d{1,2}):(\d{2})/

  static parse(html: string): EhGalleryComment[] {
    const out: EhGalleryComment[] = []
    const re: RegExp = new RegExp(EhCommentParser.RE_BLOCK, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (m[1] !== undefined && m[2] !== undefined) {
        const c: EhGalleryComment = new EhGalleryComment()
        c.commentId = m[1]
        c.contentText = EhCommentParser.stripHtml(m[2])
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
        out.push(c)
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
    const leadHtml: string = firstTag !== null && firstTag.index !== undefined
      ? c7.substring(0, firstTag.index)
      : c7
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
    let s: string = html
    s = s.replace(/<br\s*\/?>/g, '\n')
    s = s.replace(/<[^>]+>/g, '')
    s = s.replace(/&nbsp;/g, ' ')
    s = s.replace(/&lt;/g, '<')
    s = s.replace(/&gt;/g, '>')
    s = s.replace(/&quot;/g, '"')
    s = s.replace(/&#039;/g, "'")
    s = s.replace(/&amp;/g, '&')
    return s.trim()
  }
}

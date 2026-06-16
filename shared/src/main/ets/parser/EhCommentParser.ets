import { EhGalleryComment } from '../model/EhGalleryComment'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

/**
 * Parses the gallery-detail comment list. Each comment is a `<div class="c1">` block holding a
 * `<div class="c3">Posted on <DATE> by: <a>AUTHOR</a> …</div>` header and a
 * `<div class="c6" id="comment_N">BODY</div>` body. v1 strips the body to plain text (comments
 * are br/links/text — no nested divs). Validated against a real authed detail fixture; keep in
 * sync with scripts/test_comment_parser_contract.mjs.
 */
export class EhCommentParser {
  private static readonly RE_BLOCK: string =
    '<div class="c1">[\\s\\S]*?<div class="c6" id="comment_(\\d+)">([\\s\\S]*?)</div>'
  private static readonly RE_DATE: RegExp = /Posted on ([^<]+?) by:/
  private static readonly RE_AUTHOR: RegExp = /by:\s*(?:&nbsp;\s*)*<a[^>]*>([^<]+)<\/a>/
  // c5 holds "Score +N"/"Score -N"; capture the signed number. Uploader comment has no c5.
  private static readonly RE_SCORE: RegExp = /<div class="c5 nosel"[^>]*>[\s\S]*?([+-]\d+)/

  static parse(html: string): EhGalleryComment[] {
    const out: EhGalleryComment[] = []
    const re: RegExp = new RegExp(EhCommentParser.RE_BLOCK, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (m[1] !== undefined && m[2] !== undefined) {
        const c: EhGalleryComment = new EhGalleryComment()
        c.commentId = m[1]
        c.contentText = EhCommentParser.stripHtml(m[2])
        c.postedTime = HtmlSelectorUtils.group1(m[0], EhCommentParser.RE_DATE).trim()
        c.author = HtmlSelectorUtils.group1(m[0], EhCommentParser.RE_AUTHOR).trim()
        c.score = HtmlSelectorUtils.group1(m[0], EhCommentParser.RE_SCORE).trim()
        // The uploader's own comment carries an `Uploader Comment` marker (and no score).
        c.isUploader = m[0].includes('Uploader Comment')
        out.push(c)
      }
      m = re.exec(html)
    }
    return out
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

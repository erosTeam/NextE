import { EhGalleryArchiverItem, EhGalleryArchiverQuote, EhGalleryArchiverSubmitResult } from '../model/EhGalleryArchiver'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

/** Parser for /archiver.php. Grounded in eros_fe common/parser/archiver_parser.dart. */
export class EhGalleryArchiverParser {
  private static readonly RE_FUNDS: RegExp = /([0-9,]+)\s+GP[\s\S]*?([0-9,]+)\s+Credits/i
  private static readonly RE_DLTYPES: RegExp = /name=["']dltype["'][^>]*value=["']([^"']+)["']|value=["']([^"']+)["'][^>]*name=["']dltype["']/gi
  private static readonly RE_HATH_ROW: RegExp = /<td\b[^>]*>([\s\S]*?)<\/td>\s*<td\b[^>]*>([\s\S]*?)<\/td>\s*<td\b[^>]*>([\s\S]*?)<\/td>/gi
  private static readonly RE_ARCHIVE_RES: RegExp = /\('([^']+)'\)/
  private static readonly RE_LOCAL_REDIRECT: RegExp = /document\.location\s*=\s*["']([^"']+)["']/
  private static readonly RE_DB_P: RegExp = /<div\b[^>]*id=["']db["'][^>]*>[\s\S]*?<p\b[^>]*>([\s\S]*?)<\/p>/i

  static parse(html: string): EhGalleryArchiverQuote {
    const quote: EhGalleryArchiverQuote = new EhGalleryArchiverQuote()
    const funds: RegExpMatchArray | null = html.match(EhGalleryArchiverParser.RE_FUNDS)
    if (funds !== null) {
      quote.gp = funds[1] !== undefined ? funds[1].replace(/,/g, '') : ''
      quote.credits = funds[2] !== undefined ? funds[2].replace(/,/g, '') : ''
    }
    quote.downloadItems = EhGalleryArchiverParser.parseDownloadItems(html)
    quote.hathItems = EhGalleryArchiverParser.parseHathItems(html)
    return quote
  }

  static parseLocalSubmit(html: string): EhGalleryArchiverSubmitResult {
    const result: EhGalleryArchiverSubmitResult = new EhGalleryArchiverSubmitResult()
    const match: RegExpMatchArray | null = html.match(EhGalleryArchiverParser.RE_LOCAL_REDIRECT)
    if (match !== null && match[1] !== undefined) {
      let url: string = HtmlSelectorUtils.htmlUnescape(match[1]).trim()
      if (url.length > 0 && url.indexOf('start=1') < 0) {
        url = url.indexOf('?') >= 0 ? `${url}&start=1` : `${url}?start=1`
      }
      result.localDownloadUrl = url
    }
    result.message = result.localDownloadUrl.length > 0
      ? result.localDownloadUrl
      : EhGalleryArchiverParser.parseSubmitMessage(html)
    return result
  }

  static parseHathSubmit(html: string): EhGalleryArchiverSubmitResult {
    const result: EhGalleryArchiverSubmitResult = new EhGalleryArchiverSubmitResult()
    result.message = EhGalleryArchiverParser.parseSubmitMessage(html)
    return result
  }

  private static parseDownloadItems(html: string): EhGalleryArchiverItem[] {
    const out: EhGalleryArchiverItem[] = []
    let match: RegExpExecArray | null = EhGalleryArchiverParser.RE_DLTYPES.exec(html)
    while (match !== null) {
      const dltype: string = match[1] !== undefined ? match[1] : (match[2] !== undefined ? match[2] : '')
      if (dltype.length > 0 && !EhGalleryArchiverParser.hasDltype(out, dltype)) {
        const start: number = Math.max(0, match.index - 360)
        const end: number = Math.min(html.length, match.index + match[0].length + 360)
        const window: string = html.substring(start, end)
        const item: EhGalleryArchiverItem = new EhGalleryArchiverItem()
        item.dltype = dltype
        item.resolution = dltype === 'org' ? 'Original Archive' : 'Resample Archive'
        item.priceText = EhGalleryArchiverParser.labelValue(window, 'Cost')
        item.sizeText = EhGalleryArchiverParser.labelValue(window, 'Size')
        out.push(item)
      }
      match = EhGalleryArchiverParser.RE_DLTYPES.exec(html)
    }
    return out
  }

  private static parseHathItems(html: string): EhGalleryArchiverItem[] {
    const out: EhGalleryArchiverItem[] = []
    let match: RegExpExecArray | null = EhGalleryArchiverParser.RE_HATH_ROW.exec(html)
    while (match !== null) {
      const first: string = match[1] !== undefined ? match[1] : ''
      const size: string = match[2] !== undefined ? EhGalleryArchiverParser.cleanText(match[2]) : ''
      const price: string = match[3] !== undefined ? EhGalleryArchiverParser.cleanText(match[3]) : ''
      const res: string = EhGalleryArchiverParser.cleanText(first)
      const action: RegExpMatchArray | null = first.match(EhGalleryArchiverParser.RE_ARCHIVE_RES)
      const dlres: string = action !== null && action[1] !== undefined ? action[1] : ''
      if (dlres.length > 0 && size.toUpperCase() !== 'N/A') {
        const item: EhGalleryArchiverItem = new EhGalleryArchiverItem()
        item.dltype = dlres
        item.resolution = res
        item.sizeText = size
        item.priceText = price
        out.push(item)
      }
      match = EhGalleryArchiverParser.RE_HATH_ROW.exec(html)
    }
    return out
  }

  private static hasDltype(items: EhGalleryArchiverItem[], dltype: string): boolean {
    return items.some((it: EhGalleryArchiverItem) => it.dltype === dltype)
  }

  private static labelValue(html: string, label: string): string {
    const text: string = EhGalleryArchiverParser.cleanText(html)
    const needle: string = `${label}:`
    const pos: number = text.indexOf(needle)
    if (pos < 0) {
      return ''
    }
    const start: number = pos + needle.length
    let end: number = text.length
    const labels: string[] = ['Cost:', 'Size:', 'Download:', 'Original Archive', 'Resample Archive']
    for (let i: number = 0; i < labels.length; i++) {
      const idx: number = text.indexOf(labels[i], start)
      if (idx >= 0 && idx < end) {
        end = idx
      }
    }
    return text.substring(start, end).replace(/!$/, '').trim()
  }

  private static cleanText(raw: string): string {
    let text: string = raw.replace(/<[^>]+>/g, '')
    text = HtmlSelectorUtils.htmlUnescape(text)
    return text.replace(/\s+/g, ' ').trim()
  }

  private static parseSubmitMessage(html: string): string {
    const match: RegExpMatchArray | null = html.match(EhGalleryArchiverParser.RE_DB_P)
    if (match !== null && match[1] !== undefined) {
      return EhGalleryArchiverParser.cleanText(match[1])
    }
    return EhGalleryArchiverParser.cleanText(html)
  }
}

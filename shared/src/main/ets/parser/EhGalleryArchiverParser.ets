import { EhGalleryArchiverItem, EhGalleryArchiverQuote, EhGalleryArchiverSubmitResult } from '../model/EhGalleryArchiver'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

/** Parser for /archiver.php. Grounded in eros_fe common/parser/archiver_parser.dart. */
export class EhGalleryArchiverParser {
  private static readonly RE_FUNDS: RegExp = /([0-9,]+)\s+GP[\s\S]*?([0-9,]+)\s+Credits/i
  private static readonly RE_FORM: RegExp = /<form\b[\s\S]*?<\/form>/gi
  private static readonly RE_HATH_CELL: RegExp = /<td\b[^>]*>([\s\S]*?)<\/td>/gi
  private static readonly RE_P: RegExp = /<p\b[^>]*>([\s\S]*?)<\/p>/gi
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
    let match: RegExpExecArray | null = EhGalleryArchiverParser.RE_FORM.exec(html)
    while (match !== null) {
      const form: string = match[0]
      const dltype: string = EhGalleryArchiverParser.inputValue(form, 'dltype')
      if (dltype.length > 0 && !EhGalleryArchiverParser.hasDltype(out, dltype)) {
        const start: number = Math.max(0, match.index - 360)
        const end: number = Math.min(html.length, match.index + match[0].length + 360)
        const window: string = html.substring(start, end)
        const beforeForm: string = html.substring(start, match.index)
        const afterForm: string = html.substring(match.index + match[0].length, end)
        const dlcheck: string = EhGalleryArchiverParser.inputValue(form, 'dlcheck')
        const item: EhGalleryArchiverItem = new EhGalleryArchiverItem()
        item.dltype = dltype
        item.dlcheck = dlcheck
        item.resolution = EhGalleryArchiverParser.localResolution(dltype, dlcheck)
        item.priceText = EhGalleryArchiverParser.labelValueLast(beforeForm, 'Download Cost')
        if (item.priceText.length === 0) {
          item.priceText = EhGalleryArchiverParser.labelValueLast(beforeForm, 'Cost')
        }
        if (item.priceText.length === 0) {
          item.priceText = EhGalleryArchiverParser.labelValue(window, 'Download Cost')
        }
        item.sizeText = EhGalleryArchiverParser.labelValue(afterForm, 'Estimated Size')
        if (item.sizeText.length === 0) {
          item.sizeText = EhGalleryArchiverParser.labelValue(afterForm, 'Size')
        }
        if (item.sizeText.length === 0) {
          item.sizeText = EhGalleryArchiverParser.labelValue(window, 'Estimated Size')
        }
        out.push(item)
      }
      match = EhGalleryArchiverParser.RE_FORM.exec(html)
    }
    return out
  }

  private static parseHathItems(html: string): EhGalleryArchiverItem[] {
    const out: EhGalleryArchiverItem[] = []
    let match: RegExpExecArray | null = EhGalleryArchiverParser.RE_HATH_CELL.exec(html)
    while (match !== null) {
      const cell: string = match[1] !== undefined ? match[1] : ''
      const action: RegExpMatchArray | null = cell.match(EhGalleryArchiverParser.RE_ARCHIVE_RES)
      const dlres: string = action !== null && action[1] !== undefined ? action[1] : ''
      const lines: string[] = EhGalleryArchiverParser.paragraphTexts(cell)
      const res: string = lines.length > 0 ? lines[0] : EhGalleryArchiverParser.cleanText(cell)
      const size: string = lines.length > 1 ? lines[1] : ''
      const price: string = lines.length > 2 ? lines[2] : ''
      if (dlres.length > 0 && size.toUpperCase() !== 'N/A') {
        const item: EhGalleryArchiverItem = new EhGalleryArchiverItem()
        item.dltype = dlres
        item.resolution = res
        item.sizeText = size
        item.priceText = price
        out.push(item)
      }
      match = EhGalleryArchiverParser.RE_HATH_CELL.exec(html)
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
    return EhGalleryArchiverParser.labelValueFromText(text, needle, pos)
  }

  private static labelValueLast(html: string, label: string): string {
    const text: string = EhGalleryArchiverParser.cleanText(html)
    const needle: string = `${label}:`
    const pos: number = text.lastIndexOf(needle)
    if (pos < 0) {
      return ''
    }
    return EhGalleryArchiverParser.labelValueFromText(text, needle, pos)
  }

  private static labelValueFromText(text: string, needle: string, pos: number): string {
    const start: number = pos + needle.length
    let end: number = text.length
    const labels: string[] = [
      'Download Cost:',
      'Estimated Size:',
      'Cost:',
      'Size:',
      'Download:',
      'Original Archive',
      'Resample Archive',
      'H@H Downloader',
      'H@H',
    ]
    for (let i: number = 0; i < labels.length; i++) {
      const idx: number = text.indexOf(labels[i], start)
      if (idx >= 0 && idx < end) {
        end = idx
      }
    }
    const value: string = text.substring(start, end).replace(/!$/, '').trim()
    if (needle.indexOf('Size:') >= 0) {
      const size: RegExpMatchArray | null = value.match(/^([0-9][0-9.,]*\s*(?:KiB|MiB|GiB|KB|MB|GB|B))/i)
      if (size !== null && size[1] !== undefined) {
        return size[1].trim()
      }
    }
    return value
  }

  private static inputValue(html: string, name: string): string {
    const nameBeforeValue: RegExp = new RegExp(
      `name=["']${name}["'][^>]*value=["']([^"']*)["']`,
      'i',
    )
    const valueBeforeName: RegExp = new RegExp(
      `value=["']([^"']*)["'][^>]*name=["']${name}["']`,
      'i',
    )
    let match: RegExpMatchArray | null = html.match(nameBeforeValue)
    if (match !== null && match[1] !== undefined) {
      return HtmlSelectorUtils.htmlUnescape(match[1]).trim()
    }
    match = html.match(valueBeforeName)
    if (match !== null && match[1] !== undefined) {
      return HtmlSelectorUtils.htmlUnescape(match[1]).trim()
    }
    return ''
  }

  private static localResolution(dltype: string, dlcheck: string): string {
    if (dlcheck.length > 0) {
      if (dlcheck.startsWith('Download ')) {
        return dlcheck.substring('Download '.length).trim()
      }
      return dlcheck
    }
    return dltype === 'org' ? 'Original Archive' : 'Resample Archive'
  }

  private static paragraphTexts(html: string): string[] {
    const out: string[] = []
    let match: RegExpExecArray | null = EhGalleryArchiverParser.RE_P.exec(html)
    while (match !== null) {
      if (match[1] !== undefined) {
        out.push(EhGalleryArchiverParser.cleanText(match[1]))
      }
      match = EhGalleryArchiverParser.RE_P.exec(html)
    }
    return out
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

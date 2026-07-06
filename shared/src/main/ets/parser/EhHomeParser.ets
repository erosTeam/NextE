import { EhHome } from '../model/EhHome'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

/**
 * Parses EH home.php account limit panel. FE reads body > div.stuffbox > div.homebox and the strong
 * values inside it; this keeps the same semantic selectors with scoped regex and no HTML dependency.
 */
export class EhHomeParser {
  static parse(html: string): EhHome {
    const homebox: string = EhHomeParser.homebox(html)
    const text: string = HtmlSelectorUtils.htmlUnescape(homebox.replace(/<[^>]*>/g, ' '))
    const highResolutionLimited: boolean =
      text.indexOf('high-resolution images can be limited') >= 0
    const values: number[] = EhHomeParser.strongNumbers(homebox.length > 0 ? homebox : html)
    const action: EhHomeResetAction = EhHomeParser.resetAction(homebox.length > 0 ? homebox : html)
    if (values.length < 3) {
      return new EhHome(0, 0, 0, '', '', '', highResolutionLimited, values.length > 0 ? values[0] : 0)
    }
    return new EhHome(values[0], values[1], values[2], action.url, action.method, action.body, highResolutionLimited, 0)
  }

  private static homebox(html: string): string {
    const block: string = HtmlSelectorUtils.group1(
      html,
      /<div[^>]*class="[^"]*\bhomebox\b[^"]*"[^>]*>([\s\S]*?)<\/div>/,
    )
    return block
  }

  private static strongNumbers(html: string): number[] {
    const out: number[] = []
    const re: RegExp = /<strong[^>]*>([\s\S]*?)<\/strong>/g
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      const raw: string = HtmlSelectorUtils.htmlUnescape(m[1].replace(/<[^>]*>/g, '').trim())
      const numeric: string = raw.replace(/,/g, '')
      const value: number = Number.parseInt(numeric, 10)
      if (!Number.isNaN(value)) {
        out.push(value)
      }
      m = re.exec(html)
    }
    return out
  }

  private static resetAction(html: string): EhHomeResetAction {
    const form: string = EhHomeParser.resetForm(html)
    if (form.length > 0) {
      const url: string = EhHomeParser.resolveUrl(EhHomeParser.attr(form, 'action'))
      const methodRaw: string = EhHomeParser.attr(form, 'method').toUpperCase()
      const method: string = methodRaw === 'POST' ? 'POST' : 'GET'
      return new EhHomeResetAction(url.length > 0 ? url : 'https://e-hentai.org/home.php', method, EhHomeParser.formBody(form))
    }
    const href: string = HtmlSelectorUtils.group1(
      html,
      /<a\b[^>]*href="([^"]*(?:reset|limit)[^"]*)"[^>]*>[\s\S]*?(?:Reset|reset|重置|リセット)[\s\S]*?<\/a>/,
    )
    if (href.length > 0) {
      return new EhHomeResetAction(EhHomeParser.resolveUrl(href), 'GET', '')
    }
    return new EhHomeResetAction()
  }

  private static resetForm(html: string): string {
    const re: RegExp = /<form\b[\s\S]*?<\/form>/g
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      const form: string = m[0]
      const text: string = HtmlSelectorUtils.htmlUnescape(form.replace(/<[^>]*>/g, ' '))
      const action: string = EhHomeParser.attr(form, 'action')
      if (
        text.indexOf('Reset') >= 0 ||
        text.indexOf('reset') >= 0 ||
        form.indexOf('Reset') >= 0 ||
        form.indexOf('reset') >= 0 ||
        text.indexOf('重置') >= 0 ||
        text.indexOf('リセット') >= 0 ||
        action.indexOf('reset') >= 0
      ) {
        return form
      }
      m = re.exec(html)
    }
    return ''
  }

  private static formBody(form: string): string {
    const parts: string[] = []
    const re: RegExp = /<input\b[^>]*>/g
    let m: RegExpExecArray | null = re.exec(form)
    while (m !== null) {
      const input: string = m[0]
      const name: string = EhHomeParser.attr(input, 'name')
      if (name.length > 0) {
        const value: string = EhHomeParser.attr(input, 'value')
        parts.push(`${encodeURIComponent(name)}=${encodeURIComponent(value)}`)
      }
      m = re.exec(form)
    }
    return parts.join('&')
  }

  private static attr(tag: string, name: string): string {
    const re: RegExp = new RegExp(`${name}=["']([^"']*)["']`, 'i')
    return HtmlSelectorUtils.group1(tag, re)
  }

  private static resolveUrl(raw: string): string {
    if (raw.indexOf('https://') === 0 || raw.indexOf('http://') === 0) {
      return raw
    }
    if (raw.indexOf('/') === 0) {
      return `https://e-hentai.org${raw}`
    }
    if (raw.length > 0) {
      return `https://e-hentai.org/${raw}`
    }
    return ''
  }
}

class EhHomeResetAction {
  url: string = ''
  method: string = ''
  body: string = ''

  constructor(url: string = '', method: string = '', body: string = '') {
    this.url = url
    this.method = method
    this.body = body
  }
}

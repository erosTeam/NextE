import { EhAssetBalance } from '../model/EhAssetBalance'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

export class EhAssetBalanceParser {
  private static readonly CURRENT_BALANCE_LABEL: RegExp =
    /(current\s+(funds?|balance)|currently\s+have|you\s+(currently\s+)?have|available\s+(funds?|balance)|account\s+balance)/i

  static parse(html: string): EhAssetBalance {
    const exchangeText: string = EhAssetBalanceParser.visibleText(EhAssetBalanceParser.cleanedHtml(html))
    const exchangeGpText: string = EhAssetBalanceParser.findAvailableAmountInRange(
      exchangeText,
      /Sell\s+GP!?/i,
      /(Active\s+Orders|Bid\s+\(Buyers\)|Ask\s+\(Sellers\))/i,
      '[A-Za-z]*GP',
    )
    const exchangeCreditText: string = EhAssetBalanceParser.findAvailableAmountInRange(
      exchangeText,
      /Buy\s+GP!?/i,
      /Sell\s+GP!?/i,
      'Credits?|C',
    )
    if (exchangeGpText.length > 0 || exchangeCreditText.length > 0) {
      return new EhAssetBalance(exchangeGpText, exchangeCreditText)
    }

    const text: string = EhAssetBalanceParser.balanceText(html)
    if (text.length === 0) {
      return new EhAssetBalance()
    }
    const gpText: string = EhAssetBalanceParser.findAmountWithUnit(text, '[A-Za-z]*GP')
    const creditText: string = EhAssetBalanceParser.findAmountWithUnit(text, 'Credits?|C')
    return new EhAssetBalance(gpText, creditText)
  }

  private static findAvailableAmountInRange(
    text: string,
    startPattern: RegExp,
    endPattern: RegExp,
    unitPattern: string,
  ): string {
    const startIndex: number = text.search(startPattern)
    if (startIndex < 0) {
      return ''
    }
    const afterStart: string = text.substring(startIndex)
    const endIndex: number = afterStart.search(endPattern)
    const segment: string = endIndex > 0 ? afterStart.substring(0, endIndex) : afterStart
    const re: RegExp = new RegExp('Available\\s*:\\s*([0-9][0-9,.]*\\s*(?:' + unitPattern + ')\\b)', 'i')
    const match: RegExpMatchArray | null = segment.match(re)
    if (match === null || match.length < 2 || match[1] === undefined) {
      return ''
    }
    return match[1].replace(/\s+/g, ' ').trim()
  }

  private static balanceText(html: string): string {
    const blocks: string[] = EhAssetBalanceParser.visibleBlocks(html)
    for (let i: number = 0; i < blocks.length; i++) {
      const block: string = blocks[i]
      const labelIndex: number = block.search(EhAssetBalanceParser.CURRENT_BALANCE_LABEL)
      if (labelIndex >= 0) {
        const afterLabel: string = block.substring(labelIndex)
        if (EhAssetBalanceParser.hasGpAndCredits(afterLabel)) {
          return afterLabel
        }
      }
    }
    return ''
  }

  private static hasGpAndCredits(text: string): boolean {
    return /[0-9][0-9,.]*\s*[A-Za-z]*GP\b/i.test(text) && /[0-9][0-9,.]*\s*Credits?\b/i.test(text)
  }

  private static findAmountWithUnit(text: string, unitPattern: string): string {
    const re: RegExp = new RegExp('[0-9][0-9,.]*\\s*(?:' + unitPattern + ')\\b', 'i')
    const match: RegExpMatchArray | null = text.match(re)
    if (match === null || match.length < 1 || match[0] === undefined) {
      return ''
    }
    return match[0].replace(/\s+/g, ' ').trim()
  }

  private static visibleBlocks(html: string): string[] {
    const cleaned: string = EhAssetBalanceParser.cleanedHtml(html)
    const re: RegExp = /<(p|div|td|th|li|span)[^>]*>[\s\S]*?<\/\1>/gi
    const out: string[] = []
    let match: RegExpExecArray | null = re.exec(cleaned)
    while (match !== null) {
      const text: string = EhAssetBalanceParser.visibleText(match[0])
      if (text.length > 0) {
        out.push(text)
      }
      match = re.exec(cleaned)
    }
    const whole: string = EhAssetBalanceParser.visibleText(cleaned)
    if (whole.length > 0) {
      out.push(whole)
    }
    return out
  }

  private static cleanedHtml(html: string): string {
    return html
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<option[\s\S]*?<\/option>/gi, ' ')
      .replace(/<input\b[^>]*>/gi, ' ')
      .replace(/<textarea[\s\S]*?<\/textarea>/gi, ' ')
  }

  private static visibleText(html: string): string {
    return HtmlSelectorUtils.htmlUnescape(html.replace(/<[^>]+>/g, ' '))
      .replace(/\s+/g, ' ')
      .trim()
  }
}

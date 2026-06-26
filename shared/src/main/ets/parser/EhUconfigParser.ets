import { HtmlSelectorUtils } from './HtmlSelectorUtils'
import { EhProfile, EhProfileSettings, EhUconfigToggleItem } from '../model/EhProfileSettings'

/**
 * Parses EH uconfig.php (GET) into EhProfileSettings and serializes it back into the POST body.
 *
 * Mirrors eros_fe's profile_parser + extension.postParam: radio groups (uh/xr/tl/…) carry the selected
 * index as the form value; text inputs (rx/ry/ru/ft/wt/tp/vp/hh) and the xu textarea are raw strings;
 * xn_ / xl_ checkboxes post `=on` when excluded; favorite_0..9 are names. Profile selection rides the
 * `sp` cookie, NOT this body. In-house regex (no HTML lib), per shared parser convention.
 *
 * ponytail: ct_* (front-page category visibility) + the xu quota readout are deferred — eros_fe omits
 * ct too, and posting a guessed ct mapping is destructive; both get added after inspecting a live page.
 */
export class EhUconfigParser {
  static parse(html: string): EhProfileSettings {
    const s: EhProfileSettings = new EhProfileSettings()

    // ── Profiles: #profile_form > select (name="profile_set") ──
    let selectBlock: string = HtmlSelectorUtils.group1(
      html,
      /<select[^>]*name="profile_set"[^>]*>([\s\S]*?)<\/select>/,
    )
    if (selectBlock.length === 0) {
      selectBlock = HtmlSelectorUtils.group1(html, /<select[^>]*>([\s\S]*?)<\/select>/)
    }
    const optionRe: RegExp = /<option[^>]*value="(\d+)"([^>]*)>([\s\S]*?)<\/option>/g
    let om: RegExpExecArray | null = optionRe.exec(selectBlock)
    while (om !== null) {
      const value: number = Number.parseInt(om[1], 10)
      const attrs: string = om[2]
      const rawText: string = HtmlSelectorUtils.htmlUnescape(om[3].replace(/<[^>]*>/g, '').trim())
      const isDefault: boolean = rawText.endsWith('(Default)')
      const name: string = isDefault ? rawText.replace(/\(Default\)\s*$/, '').trim() : rawText
      const selected: boolean = attrs.includes('selected')
      s.profiles.push(new EhProfile(name, value, selected, isDefault))
      if (selected) {
        s.selectedProfile = value
      }
      if (isDefault) {
        s.defaultProfile = value
      }
      om = optionRe.exec(selectBlock)
    }

    // ── Radio groups (selected index == form value) ──
    s.loadImageThroughHAtH = EhUconfigParser.parseRadio(html, 'uh')
    s.imageSize = EhUconfigParser.parseRadio(html, 'xr')
    s.galleryNameDisplay = EhUconfigParser.parseRadio(html, 'tl')
    s.archiverSettings = EhUconfigParser.parseRadio(html, 'ar')
    s.frontPageSettings = EhUconfigParser.parseRadio(html, 'dm')
    s.sortOrderFavorites = EhUconfigParser.parseRadio(html, 'fs')
    s.searchResultCount = EhUconfigParser.parseRadio(html, 'rc')
    s.mouseOverThumbnails = EhUconfigParser.parseRadio(html, 'lt')
    s.thumbnailSize = EhUconfigParser.parseRadio(html, 'ts')
    s.thumbnailRows = EhUconfigParser.parseRadio(html, 'tr')
    s.sortOrderComments = EhUconfigParser.parseRadio(html, 'cs')
    s.showCommentVotes = EhUconfigParser.parseRadio(html, 'sc')
    s.sortOrderTags = EhUconfigParser.parseRadio(html, 'tb')
    s.showGalleryPageNumbers = EhUconfigParser.parseRadio(html, 'pn')
    s.originalImages = EhUconfigParser.parseRadio(html, 'oi')
    s.alwaysUseMpv = EhUconfigParser.parseRadio(html, 'qb')
    s.mpvStyle = EhUconfigParser.parseRadio(html, 'ms')
    s.mpvThumbnailPane = EhUconfigParser.parseRadio(html, 'mt')

    // ── Text inputs ──
    s.imageSizeHorizontal = EhUconfigParser.parseInput(html, 'rx')
    s.imageSizeVertical = EhUconfigParser.parseInput(html, 'ry')
    s.ratings = EhUconfigParser.parseInput(html, 'ru')
    s.tagFilteringThreshold = EhUconfigParser.parseInput(html, 'ft')
    s.tagWatchingThreshold = EhUconfigParser.parseInput(html, 'wt')
    s.thumbnailScaling = EhUconfigParser.parseInput(html, 'tp')
    s.viewportOverride = EhUconfigParser.parseInput(html, 'vp')
    s.hentaiAtHomeLocalNetworkHost = EhUconfigParser.parseInput(html, 'hh')
    s.excludedUploaders = EhUconfigParser.parseTextarea(html, 'xu')

    // ── Favorites: favorite_0..9 names ──
    for (let i: number = 0; i <= 9; i++) {
      s.favorites.push(EhUconfigParser.parseInput(html, `favorite_${i}`))
    }

    // ── Excluded namespaces (xn_*) + languages (xl_* table) ──
    s.excludedNamespaces = EhUconfigParser.parseToggles(html, 'xn')
    s.excludedLanguages = EhUconfigParser.parseLanguages(html)

    return s
  }

  // The Excluded Languages section is a table: each <tr> has the language name in its first <td>, then
  // checkboxes for original (id < 1024) / translated (1024..2047) / rewrite (>= 2048). Build one toggle
  // per present checkbox carrying the language name + variant column.
  private static parseLanguages(html: string): EhUconfigToggleItem[] {
    const out: EhUconfigToggleItem[] = []
    const start: number = html.indexOf('Excluded Languages')
    if (start < 0) {
      return out
    }
    const end: number = html.indexOf('</table>', start)
    const region: string = end > start ? html.substring(start, end) : html.substring(start)
    const rows: string[] = HtmlSelectorUtils.rows(region)
    for (let r: number = 0; r < rows.length; r++) {
      const row: string = rows[r]
      if (!row.includes('xl_')) {
        continue
      }
      const cell: string = HtmlSelectorUtils.group1(row, /<td[^>]*>([\s\S]*?)<\/td>/)
      const lang: string = HtmlSelectorUtils.htmlUnescape(cell.replace(/<[^>]*>/g, '').trim())
      const re: RegExp = /<input[^>]*name="xl_(\d+)"[^>]*>/g
      let m: RegExpExecArray | null = re.exec(row)
      while (m !== null) {
        const ser: number = Number.parseInt(m[1], 10)
        const excluded: boolean = m[0].includes('checked')
        const variant: number = ser >= 2048 ? 2 : ser >= 1024 ? 1 : 0
        out.push(new EhUconfigToggleItem(ser, lang, excluded, variant))
        m = re.exec(row)
      }
    }
    return out
  }

  /** Build the application/x-www-form-urlencoded POST body. Profile selection is NOT here (sp cookie). */
  static buildPostBody(s: EhProfileSettings): string {
    const parts: string[] = []
    parts.push(`uh=${s.loadImageThroughHAtH}`)
    parts.push(`xr=${s.imageSize}`)
    parts.push(`tl=${s.galleryNameDisplay}`)
    parts.push(`ar=${s.archiverSettings}`)
    parts.push(`dm=${s.frontPageSettings}`)
    parts.push(`fs=${s.sortOrderFavorites}`)
    parts.push(`rc=${s.searchResultCount}`)
    parts.push(`lt=${s.mouseOverThumbnails}`)
    parts.push(`ts=${s.thumbnailSize}`)
    parts.push(`tr=${s.thumbnailRows}`)
    parts.push(`cs=${s.sortOrderComments}`)
    parts.push(`sc=${s.showCommentVotes}`)
    parts.push(`tb=${s.sortOrderTags}`)
    parts.push(`pn=${s.showGalleryPageNumbers}`)
    parts.push(`oi=${s.originalImages}`)
    parts.push(`qb=${s.alwaysUseMpv}`)
    parts.push(`ms=${s.mpvStyle}`)
    parts.push(`mt=${s.mpvThumbnailPane}`)
    EhUconfigParser.pushText(parts, 'rx', s.imageSizeHorizontal)
    EhUconfigParser.pushText(parts, 'ry', s.imageSizeVertical)
    EhUconfigParser.pushText(parts, 'ru', s.ratings)
    EhUconfigParser.pushText(parts, 'ft', s.tagFilteringThreshold)
    EhUconfigParser.pushText(parts, 'wt', s.tagWatchingThreshold)
    EhUconfigParser.pushText(parts, 'tp', s.thumbnailScaling)
    EhUconfigParser.pushText(parts, 'vp', s.viewportOverride)
    EhUconfigParser.pushText(parts, 'hh', s.hentaiAtHomeLocalNetworkHost)
    EhUconfigParser.pushText(parts, 'xu', s.excludedUploaders)
    for (let i: number = 0; i < s.favorites.length; i++) {
      EhUconfigParser.pushText(parts, `favorite_${i}`, s.favorites[i])
    }
    for (let i: number = 0; i < s.excludedNamespaces.length; i++) {
      const x: EhUconfigToggleItem = s.excludedNamespaces[i]
      if (x.excluded) {
        parts.push(`xn_${x.ser}=on`)
      }
    }
    for (let i: number = 0; i < s.excludedLanguages.length; i++) {
      const x: EhUconfigToggleItem = s.excludedLanguages[i]
      if (x.excluded) {
        parts.push(`xl_${x.ser}=on`)
      }
    }
    parts.push('apply=apply')
    return parts.join('&')
  }

  private static pushText(parts: string[], code: string, value: string): void {
    parts.push(`${code}=${encodeURIComponent(value)}`)
  }

  // The selected radio's value (== index). 0 when none is checked.
  private static parseRadio(html: string, name: string): number {
    const re: RegExp = new RegExp(`<input[^>]*name="${name}"[^>]*>`, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      const tag: string = m[0]
      if (tag.includes('checked')) {
        const v: string = HtmlSelectorUtils.group1(tag, /value="(\d+)"/)
        return v.length > 0 ? Number.parseInt(v, 10) : 0
      }
      m = re.exec(html)
    }
    return 0
  }

  private static parseInput(html: string, name: string): string {
    const m: RegExpMatchArray | null = html.match(new RegExp(`<input[^>]*name="${name}"[^>]*>`))
    if (m === null) {
      return ''
    }
    return HtmlSelectorUtils.htmlUnescape(HtmlSelectorUtils.group1(m[0], /value="([^"]*)"/))
  }

  private static parseTextarea(html: string, name: string): string {
    const inner: string = HtmlSelectorUtils.group1(
      html,
      new RegExp(`<textarea[^>]*name="${name}"[^>]*>([\\s\\S]*?)</textarea>`),
    )
    return HtmlSelectorUtils.htmlUnescape(inner.trim())
  }

  // All present xn_*/xl_* checkboxes (ser + name + excluded). Name is the label/trailing text, best-effort.
  private static parseToggles(html: string, prefix: string): EhUconfigToggleItem[] {
    const out: EhUconfigToggleItem[] = []
    const re: RegExp = new RegExp(`(<input[^>]*id="${prefix}_(\\d+)"[^>]*>)([^<]*)`, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      const tag: string = m[1]
      const ser: number = Number.parseInt(m[2], 10)
      const excluded: boolean = tag.includes('checked')
      const name: string = HtmlSelectorUtils.htmlUnescape(m[3].trim())
      out.push(new EhUconfigToggleItem(ser, name, excluded))
      m = re.exec(html)
    }
    return out
  }
}

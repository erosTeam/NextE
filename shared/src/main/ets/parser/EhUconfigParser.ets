import { HtmlSelectorUtils } from './HtmlSelectorUtils'
import {
  EhProfile,
  EhProfileSettings,
  EhRadioOption,
  EhUconfigCategory,
  EhUconfigToggleItem,
} from '../model/EhProfileSettings'

/**
 * Parses EH uconfig.php (GET) into EhProfileSettings and serializes it back into the POST body.
 *
 * Mirrors eros_fe's profile_parser + extension.postParam: radio groups (uh/xr/tl/…) carry the selected
 * index as the form value; text inputs (rx/ry/ru/ft/wt/tp/vp/hh) and the xu textarea are raw strings;
 * xn_ / xl_ checkboxes post `=on` when excluded; favorite_0..9 are names. Profile selection rides the
 * `sp` cookie, NOT this body. In-house regex (no HTML lib), per shared parser convention.
 *
 * Front-page categories and the xu quota readout are parsed from the same stable EH controls as eros_fe.
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
    const xuQuota: number[] = EhUconfigParser.parseXuQuota(html)
    s.xuQuotaUsing = xuQuota.length > 0 ? xuQuota[0] : 0
    s.xuQuotaMax = xuQuota.length > 1 ? xuQuota[1] : 0

    // ── Favorites: favorite_0..9 names ──
    for (let i: number = 0; i <= 9; i++) {
      s.favorites.push(EhUconfigParser.parseInput(html, `favorite_${i}`))
    }

    // ── Enabled options straight from the page + field presence/editability ──
    s.radioGroups = EhUconfigParser.parseControlOptions(html)
    s.fieldNames = EhUconfigParser.parseFieldNames(html)
    s.enabledFieldNames = EhUconfigParser.parseEnabledFieldNames(html)

    // ── Front-page categories (ct_*) ──
    s.categories = EhUconfigParser.parseCategories(html)

    // ── Excluded namespaces (xn_*) + languages (xl_* table) ──
    s.excludedNamespaces = EhUconfigParser.parseToggles(html, 'xn')
    s.excludedLanguages = EhUconfigParser.parseLanguages(html)

    return s
  }

  // Every enabled radio/select option on the page, with its real label. EH keeps perk-gated options in
  // the DOM with `disabled`, so presence alone is not capability evidence.
  private static parseControlOptions(html: string): Map<string, EhRadioOption[]> {
    const map: Map<string, EhRadioOption[]> = new Map<string, EhRadioOption[]>()
    const push = (code: string, value: number, label: string): void => {
      let arr: EhRadioOption[] | undefined = map.get(code)
      if (arr === undefined) {
        arr = []
        map.set(code, arr)
      }
      for (let i: number = 0; i < arr.length; i++) {
        if (arr[i].value === value) {
          return
        }
      }
      arr.push(new EhRadioOption(value, HtmlSelectorUtils.htmlUnescape(label.trim())))
    }
    // Radios: <label class="lr"><input type="radio" name="C" value="V" ...><span></span> LABEL</label>
    const rre: RegExp =
      /(<input type="radio" name="([a-z]+)" value="(\d+)"[^>]*>)\s*(?:<span><\/span>)?\s*([^<]*)<\/label>/g
    let m: RegExpExecArray | null = rre.exec(html)
    while (m !== null) {
      if (!EhUconfigParser.disabled(m[1])) {
        push(m[2], Number.parseInt(m[3], 10), m[4])
      }
      m = rre.exec(html)
    }
    // Numeric <select name="C">: each <option value="V">LABEL</option> (e.g. MPV display style).
    const sre: RegExp = /(<select name="([a-z]+)"[^>]*>)([\s\S]*?)<\/select>/g
    let sm: RegExpExecArray | null = sre.exec(html)
    while (sm !== null) {
      if (!EhUconfigParser.disabled(sm[1])) {
        const code: string = sm[2]
        const ore: RegExp = /(<option value="(\d+)"[^>]*>)([\s\S]*?)<\/option>/g
        let om: RegExpExecArray | null = ore.exec(sm[3])
        while (om !== null) {
          if (!EhUconfigParser.disabled(om[1])) {
            push(code, Number.parseInt(om[2], 10), om[3].replace(/<[^>]*>/g, ''))
          }
          om = ore.exec(sm[3])
        }
      }
      sm = sre.exec(html)
    }
    return map
  }

  // Every input/select/textarea name present, so absent fields (e.g. oi for accounts without it) hide.
  private static parseFieldNames(html: string): string[] {
    const out: string[] = []
    const re: RegExp = /<(?:input|select|textarea)[^>]*name="([a-z0-9_-]+)"/g
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (out.indexOf(m[1]) < 0) {
        out.push(m[1])
      }
      m = re.exec(html)
    }
    return out
  }

  // A name is editable when at least one matching form control is not disabled. This preserves field
  // presence for display while separately preventing writes to missing/disabled controls.
  private static parseEnabledFieldNames(html: string): string[] {
    const out: string[] = []
    const re: RegExp = /<(?:input|select|textarea)[^>]*name="([a-z0-9_-]+)"[^>]*>/g
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (!EhUconfigParser.disabled(m[0]) && out.indexOf(m[1]) < 0) {
        out.push(m[1])
      }
      m = re.exec(html)
    }
    return out
  }

  private static disabled(tag: string): boolean {
    return /(?:^|\s)disabled(?:\s*=|\s|>)/.test(tag)
  }

  // eros_fe reads #xu.parent.nextElementSibling strong[0..1]. Scoped fallback: first post-xu block with
  // at least two strong numeric values. Defaults to 0/0 when the account/page omits the quota readout.
  private static parseXuQuota(html: string): number[] {
    const marker: RegExpMatchArray | null = html.match(/<textarea[^>]*(?:name|id)="xu"[\s\S]*?<\/textarea>/)
    if (marker === null || marker.index === undefined) {
      return []
    }
    const tail: string = html.substring(marker.index + marker[0].length)
    const re: RegExp = /<strong[^>]*>([\s\S]*?)<\/strong>/g
    const out: number[] = []
    let m: RegExpExecArray | null = re.exec(tail)
    while (m !== null && out.length < 2) {
      const raw: string = HtmlSelectorUtils.htmlUnescape(m[1].replace(/<[^>]*>/g, '').trim())
      const value: number = Number.parseInt(raw.replace(/,/g, ''), 10)
      if (!Number.isNaN(value)) {
        out.push(value)
      }
      m = re.exec(tail)
    }
    return out
  }

  // Front-page category visibility: hidden inputs ct_<key>=0|1 (1 = hidden), label from the sibling div.
  private static parseCategories(html: string): EhUconfigCategory[] {
    const out: EhUconfigCategory[] = []
    const re: RegExp = /<input[^>]*name="ct_([a-z-]+)"[^>]*value="(\d)"[^>]*>/g
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (!EhUconfigParser.disabled(m[0])) {
        const slug: string = m[1]
        const hidden: boolean = m[2] === '1'
        const label: string = HtmlSelectorUtils.htmlUnescape(
          HtmlSelectorUtils.group1(
            html,
            new RegExp(`<div[^>]*id="ct_${slug}_div"[^>]*>([^<]*)</div>`),
          ).trim(),
        )
        out.push(new EhUconfigCategory(`ct_${slug}`, label.length > 0 ? label : slug, hidden))
      }
      m = re.exec(html)
    }
    return out
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
        if (!EhUconfigParser.disabled(m[0])) {
          const ser: number = Number.parseInt(m[1], 10)
          const excluded: boolean = m[0].includes('checked')
          const variant: number = ser >= 2048 ? 2 : ser >= 1024 ? 1 : 0
          out.push(new EhUconfigToggleItem(ser, lang, excluded, variant))
        }
        m = re.exec(row)
      }
    }
    return out
  }

  /** Build the application/x-www-form-urlencoded POST body. Profile selection is NOT here (sp cookie). */
  static buildPostBody(s: EhProfileSettings): string {
    const parts: string[] = []
    EhUconfigParser.pushRadio(parts, s, 'uh', s.loadImageThroughHAtH)
    EhUconfigParser.pushRadio(parts, s, 'xr', s.imageSize)
    EhUconfigParser.pushRadio(parts, s, 'tl', s.galleryNameDisplay)
    EhUconfigParser.pushRadio(parts, s, 'ar', s.archiverSettings)
    EhUconfigParser.pushRadio(parts, s, 'dm', s.frontPageSettings)
    EhUconfigParser.pushRadio(parts, s, 'fs', s.sortOrderFavorites)
    EhUconfigParser.pushRadio(parts, s, 'rc', s.searchResultCount)
    EhUconfigParser.pushRadio(parts, s, 'lt', s.mouseOverThumbnails)
    EhUconfigParser.pushRadio(parts, s, 'ts', s.thumbnailSize)
    EhUconfigParser.pushRadio(parts, s, 'tr', s.thumbnailRows)
    EhUconfigParser.pushRadio(parts, s, 'cs', s.sortOrderComments)
    EhUconfigParser.pushRadio(parts, s, 'sc', s.showCommentVotes)
    EhUconfigParser.pushRadio(parts, s, 'tb', s.sortOrderTags)
    EhUconfigParser.pushRadio(parts, s, 'pn', s.showGalleryPageNumbers)
    EhUconfigParser.pushRadio(parts, s, 'oi', s.originalImages)
    EhUconfigParser.pushRadio(parts, s, 'qb', s.alwaysUseMpv)
    EhUconfigParser.pushRadio(parts, s, 'ms', s.mpvStyle)
    EhUconfigParser.pushRadio(parts, s, 'mt', s.mpvThumbnailPane)
    EhUconfigParser.pushText(parts, s, 'rx', s.imageSizeHorizontal)
    EhUconfigParser.pushText(parts, s, 'ry', s.imageSizeVertical)
    EhUconfigParser.pushText(parts, s, 'ru', s.ratings)
    EhUconfigParser.pushText(parts, s, 'ft', s.tagFilteringThreshold)
    EhUconfigParser.pushText(parts, s, 'wt', s.tagWatchingThreshold)
    EhUconfigParser.pushText(parts, s, 'tp', s.thumbnailScaling)
    EhUconfigParser.pushText(parts, s, 'vp', s.viewportOverride)
    EhUconfigParser.pushText(parts, s, 'hh', s.hentaiAtHomeLocalNetworkHost)
    EhUconfigParser.pushText(parts, s, 'xu', s.excludedUploaders)
    for (let i: number = 0; i < s.favorites.length; i++) {
      EhUconfigParser.pushText(parts, s, `favorite_${i}`, s.favorites[i])
    }
    for (let i: number = 0; i < s.categories.length; i++) {
      const c: EhUconfigCategory = s.categories[i]
      parts.push(`${c.key}=${c.hidden ? '1' : '0'}`)
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

  private static pushRadio(parts: string[], s: EhProfileSettings, code: string, value: number): void {
    if (s.radioValueEnabled(code, value)) {
      parts.push(`${code}=${value}`)
    }
  }

  private static pushText(parts: string[], s: EhProfileSettings, code: string, value: string): void {
    if (s.enabledFieldNames.indexOf(code) >= 0) {
      parts.push(`${code}=${encodeURIComponent(value)}`)
    }
  }

  // The selected radio's value (== index). 0 when none is checked.
  // The selected value of a radio group (checked input) or a <select> (selected <option>). 0 if none.
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
    // <select> fallback: the option carrying `selected`.
    const sel: string = HtmlSelectorUtils.group1(
      html,
      new RegExp(`<select name="${name}"[^>]*>([\\s\\S]*?)</select>`),
    )
    if (sel.length > 0) {
      const v: string = HtmlSelectorUtils.group1(sel, /<option value="(\d+)"[^>]*selected/)
      return v.length > 0 ? Number.parseInt(v, 10) : 0
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
      if (!EhUconfigParser.disabled(tag)) {
        const ser: number = Number.parseInt(m[2], 10)
        const excluded: boolean = tag.includes('checked')
        const name: string = HtmlSelectorUtils.htmlUnescape(m[3].trim())
        out.push(new EhUconfigToggleItem(ser, name, excluded))
      }
      m = re.exec(html)
    }
    return out
  }
}

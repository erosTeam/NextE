import { EhMytags, EhUsertag, EhMytagSet } from '../model/EhMytags'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

/**
 * Parses the My Tags page (mytags) into EhMytags. Each tag renders as
 * `<div id="tagpreview_N" style="...border-color:#X..." title="ns:tag">display</div>` inside a
 * `usertag_N` row, with `tagwatch_N`/`taghide_N` checkboxes (the `checked` attr = current state)
 * and a `tagweight_N` input. The two-level structure adds a `change_tagset` `<select>` of the
 * user's tag sets (id → name + count). `apiuid`/`apikey` come from inline JS vars (needed for
 * future edit calls). Validated against a real authed mytags fixture; keep in sync with
 * scripts/test_mytags_parser_contract.mjs.
 */
export class EhMytagsParser {
  private static readonly RE_TAG: string =
    '<div id="tagpreview_(\\d+)"[^>]*style="([^"]*)"[^>]*title="([^"]+)">([^<]*)</div>'
  private static readonly RE_TAGSET_SELECT: RegExp =
    /<select onchange="change_tagset[^>]*>([\s\S]*?)<\/select>/
  private static readonly RE_TAGSET_OPTION: string =
    '<option value="(\\d+)"([^>]*)>([^(<]*?)\\s*\\((\\d+)\\)</option>'

  static parse(html: string): EhMytags {
    const result: EhMytags = new EhMytags()
    const re: RegExp = new RegExp(EhMytagsParser.RE_TAG, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (m[1] !== undefined && m[2] !== undefined && m[3] !== undefined && m[4] !== undefined) {
        const t: EhUsertag = new EhUsertag()
        t.tagId = m[1]
        t.tag = m[3]
        t.display = m[4]
        // EH style e.g. `color:#f1f1f1;border-color:#1357df;background:radial-gradient(#1357df,#3377FF)`.
        const col: RegExpMatchArray | null = m[2].match(/border-color:\s*(#[0-9a-fA-F]+)/)
        t.color = col !== null && col[1] !== undefined ? col[1] : ''
        // Text color: a `color:` NOT preceded by `-` (so it isn't the `border-color`).
        const txt: RegExpMatchArray | null = m[2].match(/(?:^|;)\s*color:\s*(#[0-9a-fA-F]+)/)
        t.textColor = txt !== null && txt[1] !== undefined ? txt[1] : ''
        // Fill: first hex inside `background[-color]:` (the gradient start); fall back to the border.
        const fill: RegExpMatchArray | null = m[2].match(/background[^:]*:[^;]*?(#[0-9a-fA-F]+)/)
        t.fillColor = fill !== null && fill[1] !== undefined ? fill[1] : t.color
        const wM: RegExpMatchArray | null = html.match(
          new RegExp(`id="tagweight_${m[1]}"[^>]*value="([^"]*)"`),
        )
        t.tagWeight = wM !== null && wM[1] !== undefined ? wM[1] : ''
        const parsedWeight: number = Number.parseInt(t.tagWeight, 10)
        t.weight = Number.isNaN(parsedWeight) ? 10 : parsedWeight
        const colorM: RegExpMatchArray | null = html.match(
          new RegExp(`id="tagcolor_${m[1]}"[^>]*value="([^"]*)"`),
        )
        t.defaultColor = colorM === null || colorM[1] === undefined || colorM[1].replace('#', '').trim().length === 0
        t.watched = new RegExp(`id="tagwatch_${m[1]}"[^>]*\\schecked`).test(html)
        t.hidden = new RegExp(`id="taghide_${m[1]}"[^>]*\\schecked`).test(html)
        result.tags.push(t)
      }
      m = re.exec(html)
    }
    result.tagSets = EhMytagsParser.parseTagSets(html)
    result.currentTagset = EhMytagsParser.selectedTagset(html)
    result.canDelete = html.indexOf('do_tagset_delete()') >= 0
    result.apiuid = HtmlSelectorUtils.group1(html, /var apiuid\s*=\s*(\d+)/)
    result.apikey = HtmlSelectorUtils.group1(html, /var apikey\s*=\s*"([0-9a-f]+)"/)
    return result
  }

  /** Parse the `change_tagset` `<select>` into the user's tag sets (id, name, count). */
  private static parseTagSets(html: string): EhMytagSet[] {
    const sel: RegExpMatchArray | null = html.match(EhMytagsParser.RE_TAGSET_SELECT)
    if (sel === null || sel[1] === undefined) {
      return []
    }
    const sets: EhMytagSet[] = []
    const re: RegExp = new RegExp(EhMytagsParser.RE_TAGSET_OPTION, 'g')
    let m: RegExpExecArray | null = re.exec(sel[1])
    while (m !== null) {
      if (m[1] !== undefined && m[3] !== undefined && m[4] !== undefined) {
        sets.push(new EhMytagSet(m[1], m[3].trim(), Number.parseInt(m[4], 10)))
      }
      m = re.exec(sel[1])
    }
    // eros_fe orders tag sets by numeric id ascending — keep a deterministic order across loads
    // (the DOM option order is not guaranteed sorted). Defensive against a non-numeric id like
    // eros_fe's int.tryParse(...) ?? 0: an unguarded NaN in the comparator scrambles the whole list.
    sets.sort((a: EhMytagSet, b: EhMytagSet) => {
      const av: number = Number.parseInt(a.tagsetId, 10)
      const bv: number = Number.parseInt(b.tagsetId, 10)
      return (Number.isNaN(av) ? 0 : av) - (Number.isNaN(bv) ? 0 : bv)
    })
    return sets
  }

  /** The tagset id marked `selected` in the change_tagset select; '' if none. */
  private static selectedTagset(html: string): string {
    const sel: RegExpMatchArray | null = html.match(EhMytagsParser.RE_TAGSET_SELECT)
    if (sel === null || sel[1] === undefined) {
      return ''
    }
    const m: RegExpMatchArray | null = sel[1].match(/<option value="(\d+)"[^>]*selected/)
    return m !== null && m[1] !== undefined ? m[1] : ''
  }
}

import { Favcat } from '../model/Favcat'

/**
 * Parses the favcat selector bar on favorites.php into Favcat[] (slots 0-9). Each category is
 * a `<div class="fp" onclick="...favcat=N'...">` with three child divs: [0]=count,
 * [1]=`<div class="i" ... title="NAME">` (color swatch + name), [2]=name text. We take favId
 * from the onclick `favcat=N`, count from the first numeric div, and the name from the swatch
 * `title` attr (full, unstyled). Validated against a real authed favorites.php fixture; keep in
 * sync with scripts/test_favcatlist_parser_contract.mjs.
 */
export class EhFavcatListParser {
  private static readonly RE_FP: string =
    '<div class="fp"[^>]*favcat=(\\d+)\'[^>]*>\\s*<div[^>]*>(\\d+)</div>\\s*<div class="i"[^>]*title="([^"]*)"'

  static parse(html: string): Favcat[] {
    const out: Favcat[] = []
    const re: RegExp = new RegExp(EhFavcatListParser.RE_FP, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (m[1] !== undefined && m[2] !== undefined && m[3] !== undefined) {
        out.push(new Favcat(m[1], m[3], Number.parseInt(m[2], 10)))
      }
      m = re.exec(html)
    }
    return out
  }
}

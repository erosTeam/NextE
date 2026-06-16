/**
 * Lightweight per-block regex helpers for the in-house parsers (no external HTML lib,
 * mirroring V2Next). EH page structure is regular enough that scoped regex over a row/
 * block is reliable; heavy whole-page parses run on a TaskPool worker.
 */
export class HtmlSelectorUtils {
  /** First capture group of `re` in `text`, or '' if no match. */
  static group1(text: string, re: RegExp): string {
    const m: RegExpMatchArray | null = text.match(re)
    if (m !== null && m.length > 1 && m[1] !== undefined) {
      return m[1]
    }
    return ''
  }

  // Named HTML entities that appear in EH display text (titles carry `&amp;` heavily — 314 on one
  // toplist page — plus `&lt; &gt; &quot; &apos; &nbsp;`). `&#NN;`/`&#xHH;` go through the numeric path.
  private static readonly NAMED_ENTITIES: Map<string, string> = new Map<string, string>([
    ['amp', '&'],
    ['lt', '<'],
    ['gt', '>'],
    ['quot', '"'],
    ['apos', "'"],
    ['nbsp', ' '],
  ])

  /**
   * Decode HTML character references in display text. EH page source escapes titles/tag labels
   * (`Koumi-jima 2&amp;3` → `2&3`), which would otherwise render the raw entity. Single regex pass so
   * `&amp;lt;` stays `&lt;` (no double-decode); unknown entities are left verbatim. Mirror this in any
   * parser contract test that asserts on decoded display strings.
   */
  static htmlUnescape(s: string): string {
    if (s.length === 0 || s.indexOf('&') < 0) {
      return s
    }
    return s.replace(
      // `#[xX]` — hex marker is case-insensitive per the HTML spec (`&#X41;` is valid); the callback
      // already handles an uppercase 'X', so the regex must admit it too.
      /&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]*);/g,
      (match: string, ent: string): string => {
        if (ent.charAt(0) === '#') {
          const isHex: boolean = ent.charAt(1) === 'x' || ent.charAt(1) === 'X'
          const code: number = isHex
            ? Number.parseInt(ent.substring(2), 16)
            : Number.parseInt(ent.substring(1), 10)
          if (Number.isNaN(code) || code <= 0 || code > 0x10ffff) {
            return match
          }
          return String.fromCodePoint(code)
        }
        const named: string | undefined = HtmlSelectorUtils.NAMED_ENTITIES.get(ent)
        return named !== undefined ? named : match
      },
    )
  }

  /**
   * Safe percent-decode. EH carries some fields inside URL paths (e.g. `/uploader/marki%C3%B1o`),
   * which must be decoded for display (`markiño`); returns the input unchanged on malformed input.
   */
  static urlDecode(s: string): string {
    if (s.length === 0) {
      return s
    }
    try {
      return decodeURIComponent(s)
    } catch (e) {
      return s
    }
  }

  /** All occurrences of capture group 1 for a global pattern. */
  static groupAll(text: string, pattern: string): string[] {
    const re: RegExp = new RegExp(pattern, 'g')
    const out: string[] = []
    let m: RegExpExecArray | null = re.exec(text)
    while (m !== null) {
      if (m.length > 1 && m[1] !== undefined) {
        out.push(m[1])
      }
      m = re.exec(text)
    }
    return out
  }

  /** Split a table body into its <tr>…</tr> rows (EH rows never nest). */
  static rows(tableHtml: string): string[] {
    const re: RegExp = new RegExp('<tr[^>]*>[\\s\\S]*?</tr>', 'g')
    const out: string[] = []
    let m: RegExpExecArray | null = re.exec(tableHtml)
    while (m !== null) {
      out.push(m[0])
      m = re.exec(tableHtml)
    }
    return out
  }
}

/**
 * E-Hentai / ExHentai integration constants (ported 1:1 from eros_fe const.dart EHConst).
 *
 * Site switching is driven by a single reactive boolean (SiteModeState.isEx); the
 * baseUrl/thumbHost helpers resolve every host from it, exactly like eros_fe's
 * Api.getBaseUrl({isSiteEx}). Maps are lazily built once (ArkTS forbids mixed-type
 * array/object literals, so we populate via Map.set rather than `new Map([[...]])`).
 * Values flagged "verify-live" carry EH page-structure assumptions — confirm against a
 * live fixture before relying.
 */
export class EhConstants {
  // Hosts
  static readonly EH_BASE_URL: string = 'https://e-hentai.org'
  static readonly EX_BASE_URL: string = 'https://exhentai.org'
  static readonly EH_BASE_HOST: string = 'e-hentai.org'
  static readonly EX_BASE_HOST: string = 'exhentai.org'
  static readonly EH_TORRENT_URL: string = 'https://ehtracker.org/get'
  static readonly EX_TORRENT_URL: string = 'https://exhentai.org/torrent'
  static readonly API_PATH: string = '/api.php'
  static readonly FORUMS_LOGIN_URL: string =
    'https://forums.e-hentai.org/index.php?act=Login&CODE=01'

  // Thumbnail hosts differ per site
  static readonly EH_THUMB_HOST: string = 'https://ehgt.org'
  static readonly EX_THUMB_HOST: string = 'https://s.exhentai.org'

  // Auth cookie names (isLogin = ipb_member_id && ipb_pass_hash; ex also needs igneous)
  static readonly COOKIE_MEMBER_ID: string = 'ipb_member_id'
  static readonly COOKIE_PASS_HASH: string = 'ipb_pass_hash'
  static readonly COOKIE_IGNEOUS: string = 'igneous'
  static readonly COOKIE_SK: string = 'sk'
  static readonly COOKIE_STAR: string = 'star'
  static readonly COOKIE_NW: string = 'nw' // always forced to '1' to skip the content-warning interstitial

  // Favorites ordering query values
  static readonly FAV_ORDER_FAV: string = 'fs_f'
  static readonly FAV_ORDER_POSTED: string = 'fs_p'
  // inline_set value forcing the Minimal (list) display mode — the only favorites layout the gltc
  // table parser understands. Used to recover when the account's mode is Thumbnail (an `itg gld` div).
  static readonly FAV_DISPLAY_LIST: string = 'dm_l'

  // A desktop Chrome UA — EH serves the desktop layout the parsers expect.
  static readonly USER_AGENT: string =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
  static readonly ACCEPT: string =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8'
  static readonly ACCEPT_LANGUAGE: string = 'zh-CN,zh;q=0.9,en;q=0.8,en-US;q=0.6'

  // 509 = per-IP image bandwidth quota exhausted (distinct from 429 rate limit).
  static readonly REG_509_URL: string = '\\.org/.+/509s?\\.gif'

  // All categories selected (bitmask sum). f_cats encodes categories to EXCLUDE.
  static readonly SUM_CATS: number = 1023

  // Display order of categories (eros_fe catList).
  static readonly CATEGORIES: string[] = [
    'Misc',
    'Doujinshi',
    'Manga',
    'Artist CG',
    'Game CG',
    'Image Set',
    'Cosplay',
    'Asian Porn',
    'Non-H',
    'Western',
  ]

  // Direct fallback IPs (DoH-resolved at runtime too). Domain fronting is NOT used.
  static readonly FALLBACK_HOSTS: string[] = []

  private static catsMap: Map<string, number> | null = null
  private static favCatMap: Map<string, string> | null = null
  private static iso936Map: Map<string, string> | null = null

  /** Language tag name (e.g. 'chinese') → 2-letter display code ('ZH'). eros_fe EHConst.iso936. */
  static iso936(): Map<string, string> {
    if (EhConstants.iso936Map === null) {
      const m: Map<string, string> = new Map<string, string>()
      m.set('japanese', 'JP')
      m.set('english', 'EN')
      m.set('chinese', 'ZH')
      m.set('dutch', 'NL')
      m.set('french', 'FR')
      m.set('german', 'DE')
      m.set('hungarian', 'HU')
      m.set('italian', 'IT')
      m.set('korean', 'KR')
      m.set('polish', 'PL')
      m.set('portuguese', 'PT')
      m.set('russian', 'RU')
      m.set('spanish', 'ES')
      m.set('thai', 'TH')
      m.set('vietnamese', 'VI')
      EhConstants.iso936Map = m
    }
    return EhConstants.iso936Map
  }

  /** Resolve a language tag name to its 2-letter code; '' if not a known language. */
  static languageAbbr(name: string): string {
    const code: string | undefined = EhConstants.iso936().get(name.toLowerCase().trim())
    return code !== undefined ? code : ''
  }

  /**
   * Normalize a thumbnail URL to the public ehgt.org CDN. On ExHentai the parsed thumb host is
   * `s.exhentai.org` (auth-gated, and DNS-blackholed on some networks); ehgt.org mirrors the
   * identical `/w/...` path publicly, so covers load reliably without the EX cookie. Full reader
   * images (hath hosts) are untouched.
   */
  static cdnThumb(url: string): string {
    return url.indexOf('s.exhentai.org') >= 0 ? url.replace('s.exhentai.org', 'ehgt.org') : url
  }

  private static catColorMap: Map<string, ResourceColor> | null = null
  private static tagNsColorMap: Map<string, ResourceColor> | null = null
  private static tagNsLabelMap: Map<string, Resource> | null = null
  private static nsPrefixMap: Map<string, string> | null = null

  /**
   * Expand EH's short namespace prefixes to their full names (eros_fe prefixToNameSpaceMap):
   * 'a'→'artist', 'f'→'female', 'cos'→'cosplayer', … . EH writes a tag's namespace as EITHER the
   * full word ('artist:x') OR the abbreviation ('a:x'); bucketing and coloring must treat both the
   * same. Full names (and anything unknown) pass through unchanged after lower/trim normalization.
   */
  static expandNamespace(ns: string): string {
    if (EhConstants.nsPrefixMap === null) {
      const m: Map<string, string> = new Map<string, string>()
      m.set('a', 'artist')
      m.set('c', 'character')
      m.set('f', 'female')
      m.set('g', 'group')
      m.set('l', 'language')
      m.set('m', 'male')
      m.set('p', 'parody')
      m.set('r', 'reclass')
      m.set('o', 'other')
      m.set('x', 'mixed')
      m.set('cos', 'cosplayer')
      m.set('misc', 'misc')
      EhConstants.nsPrefixMap = m
    }
    const key: string = ns.toLowerCase().trim()
    const full: string | undefined = EhConstants.nsPrefixMap.get(key)
    return full !== undefined ? full : key
  }

  /** Full namespace → EH short query prefix (eros_fe `shortName` extension). */
  static compactNamespace(ns: string): string {
    const full: string = EhConstants.expandNamespace(ns)
    if (full === 'artist') {
      return 'a'
    }
    if (full === 'character') {
      return 'c'
    }
    if (full === 'female') {
      return 'f'
    }
    if (full === 'group') {
      return 'g'
    }
    if (full === 'language') {
      return 'l'
    }
    if (full === 'male') {
      return 'm'
    }
    if (full === 'parody') {
      return 'p'
    }
    if (full === 'reclass') {
      return 'r'
    }
    if (full === 'other') {
      return 'o'
    }
    if (full === 'mixed') {
      return 'x'
    }
    if (full === 'cosplayer') {
      return 'cos'
    }
    return full
  }

  /**
   * Tag namespace → chip background color (eros_fe ThemeColors.tagColorTagType, pastel light /
   * muted dark). Unmapped namespaces (e.g. 'mixed') fall back to misc grey.
   * Short prefixes are expanded first so 'a:'/'artist:' share one color.
   */
  static tagNamespaceColor(ns: string): ResourceColor {
    if (EhConstants.tagNsColorMap === null) {
      const m: Map<string, ResourceColor> = new Map<string, ResourceColor>()
      m.set('artist', $r('app.color.tagns_artist'))
      m.set('female', $r('app.color.tagns_female'))
      m.set('male', $r('app.color.tagns_male'))
      m.set('parody', $r('app.color.tagns_parody'))
      m.set('character', $r('app.color.tagns_character'))
      m.set('group', $r('app.color.tagns_group'))
      m.set('language', $r('app.color.tagns_language'))
      m.set('reclass', $r('app.color.tagns_reclass'))
      m.set('cosplayer', $r('app.color.tagns_cosplayer'))
      m.set('other', $r('app.color.tagns_other'))
      m.set('temp', $r('app.color.tagns_temp'))
      m.set('misc', $r('app.color.tagns_misc'))
      EhConstants.tagNsColorMap = m
    }
    const c: ResourceColor | undefined = EhConstants.tagNsColorMap.get(EhConstants.expandNamespace(ns))
    return c !== undefined ? c : $r('app.color.tagns_misc')
  }

  /**
   * Tag namespace → localized display label (eros_fe EHConst.translateTagType): the type header on the
   * detail page reads '作者/女性/男性…' for zh, capitalized English for en, Japanese for ja, instead of
   * the raw 'artist/female/male'. Driven by app i18n resources so it follows the system locale. An
   * unmapped namespace passes through unchanged (raw lowercase word) rather than showing blank.
   */
  static tagNamespaceLabel(ns: string): ResourceStr {
    if (EhConstants.tagNsLabelMap === null) {
      const m: Map<string, Resource> = new Map<string, Resource>()
      m.set('artist', $r('app.string.tag_ns_artist'))
      m.set('female', $r('app.string.tag_ns_female'))
      m.set('male', $r('app.string.tag_ns_male'))
      m.set('parody', $r('app.string.tag_ns_parody'))
      m.set('character', $r('app.string.tag_ns_character'))
      m.set('group', $r('app.string.tag_ns_group'))
      m.set('language', $r('app.string.tag_ns_language'))
      m.set('reclass', $r('app.string.tag_ns_reclass'))
      m.set('cosplayer', $r('app.string.tag_ns_cosplayer'))
      m.set('misc', $r('app.string.tag_ns_misc'))
      m.set('other', $r('app.string.tag_ns_other'))
      m.set('mixed', $r('app.string.tag_ns_mixed'))
      m.set('uploader', $r('app.string.tag_ns_uploader'))
      m.set('temp', $r('app.string.tag_ns_temp'))
      EhConstants.tagNsLabelMap = m
    }
    const r: Resource | undefined = EhConstants.tagNsLabelMap.get(EhConstants.expandNamespace(ns))
    return r !== undefined ? r : ns
  }

  /**
   * Category name → its badge color (eros_fe ThemeColors.catColor, light/dark via app.color).
   * Name is normalized (lowercase, letters only): 'Artist CG'→artistcg, 'Non-H'→nonh. Misc fallback.
   */
  static categoryColor(name: string): ResourceColor {
    if (EhConstants.catColorMap === null) {
      const m: Map<string, ResourceColor> = new Map<string, ResourceColor>()
      m.set('doujinshi', $r('app.color.cat_doujinshi'))
      m.set('manga', $r('app.color.cat_manga'))
      m.set('artistcg', $r('app.color.cat_artistcg'))
      m.set('gamecg', $r('app.color.cat_gamecg'))
      m.set('western', $r('app.color.cat_western'))
      m.set('nonh', $r('app.color.cat_nonh'))
      m.set('imageset', $r('app.color.cat_imageset'))
      m.set('cosplay', $r('app.color.cat_cosplay'))
      m.set('asianporn', $r('app.color.cat_asianporn'))
      m.set('misc', $r('app.color.cat_misc'))
      m.set('private', $r('app.color.cat_private'))
      EhConstants.catColorMap = m
    }
    const key: string = name.toLowerCase().replace(/[^a-z]/g, '')
    const c: ResourceColor | undefined = EhConstants.catColorMap.get(key)
    return c !== undefined ? c : $r('app.color.cat_misc')
  }

  /** Category name → bitmask (eros_fe EHConst.cats). Lazily built once. */
  static cats(): Map<string, number> {
    if (EhConstants.catsMap === null) {
      const m: Map<string, number> = new Map<string, number>()
      m.set('Misc', 1)
      m.set('Doujinshi', 2)
      m.set('Manga', 4)
      m.set('Artist CG', 8)
      m.set('Game CG', 16)
      m.set('Image Set', 32)
      m.set('Cosplay', 64)
      m.set('Asian Porn', 128)
      m.set('Non-H', 256)
      m.set('Western', 512)
      EhConstants.catsMap = m
    }
    return EhConstants.catsMap
  }

  /** Favorite border-color (e.g. '#f00') → favcat slot index ('1'). Lazily built once. */
  static favCat(): Map<string, string> {
    if (EhConstants.favCatMap === null) {
      const m: Map<string, string> = new Map<string, string>()
      m.set('#000', '0')
      m.set('#f00', '1')
      m.set('#fa0', '2')
      m.set('#dd0', '3')
      m.set('#080', '4')
      m.set('#9f4', '5')
      m.set('#4bf', '6')
      m.set('#00f', '7')
      m.set('#508', '8')
      m.set('#e8e', '9')
      EhConstants.favCatMap = m
    }
    return EhConstants.favCatMap
  }

  // Favcat slot index ('0'..'9') → its heart/border color (the inverse of favCat()).
  private static readonly FAV_COLORS: string[] = [
    '#000000',
    '#ee0000',
    '#ffaa00',
    '#dddd00',
    '#008800',
    '#99ff44',
    '#4499ff',
    '#0000ff',
    '#550088',
    '#ee88ee',
  ]

  /** Favcat slot index ('0'..'9') → its display color; '' for an out-of-range/empty slot. */
  static favCatColor(slot: string): string {
    const i: number = Number.parseInt(slot, 10)
    return i >= 0 && i < EhConstants.FAV_COLORS.length ? EhConstants.FAV_COLORS[i] : ''
  }

  /**
   * Rating-star fill colour for a gallery's `colorRating` variant (eros_fe ThemeColors.colorRatingMap):
   * community/default 'ir' → orange #FF962E; the personally-rated variants 'irr'/'irg'/'irb' →
   * red/green/blue. Returned as an app.color resource so dark mode resolves too.
   */
  static ratingStarColor(colorRating: string): ResourceColor {
    const v: string = colorRating.trim()
    if (v === 'irr') {
      return $r('app.color.rating_star_red')
    }
    if (v === 'irg') {
      return $r('app.color.rating_star_green')
    }
    if (v === 'irb') {
      return $r('app.color.rating_star_blue')
    }
    return $r('app.color.rating_star_orange')
  }

  /** f_cats value to show ONLY the selected categories (EH encodes the inverse: bits to exclude). */
  static fCats(selected: string[]): number {
    if (selected.length === 0) {
      return 0
    }
    let includeBits: number = 0
    const map: Map<string, number> = EhConstants.cats()
    selected.forEach((name: string) => {
      const bit: number | undefined = map.get(name)
      if (bit !== undefined) {
        includeBits = includeBits | bit
      }
    })
    return EhConstants.SUM_CATS & ~includeBits
  }

  /** Resolve the request origin for the current site mode. */
  static baseUrl(isEx: boolean): string {
    return isEx ? EhConstants.EX_BASE_URL : EhConstants.EH_BASE_URL
  }

  static torrentBaseUrl(isEx: boolean): string {
    return isEx ? EhConstants.EX_TORRENT_URL : EhConstants.EH_TORRENT_URL
  }

  /** Resolve the request host for the current site mode. */
  static baseHost(isEx: boolean): string {
    return isEx ? EhConstants.EX_BASE_HOST : EhConstants.EH_BASE_HOST
  }

  /** Resolve the thumbnail CDN host for the current site mode. */
  static thumbHost(isEx: boolean): string {
    return isEx ? EhConstants.EX_THUMB_HOST : EhConstants.EH_THUMB_HOST
  }
}

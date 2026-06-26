/**
 * EH user config (uconfig.php) model — ports eros_fe's EhSettings onto V2 reactive state so the native
 * editor binds directly. Radio groups are stored as the selected index (== EH's form value); text
 * inputs as strings; category/namespace/language toggles as booleans. See EhUconfigParser for the
 * read (GET /uconfig.php) and write (POST /uconfig.php with 2-letter codes) mapping.
 */

/** One radio/select option parsed straight from the uconfig page: form value + the page's label text. */
export class EhRadioOption {
  value: number = 0
  label: string = ''

  constructor(value: number, label: string) {
    this.value = value
    this.label = label
  }
}

@ObservedV2
export class EhProfile {
  @Trace name: string = ''
  // The EH `sp` profile value (the <option value>). Selection is applied via the `sp` cookie.
  value: number = 0
  @Trace selected: boolean = false
  @Trace isDefault: boolean = false

  constructor(name: string, value: number, selected: boolean, isDefault: boolean) {
    this.name = name
    this.value = value
    this.selected = selected
    this.isDefault = isDefault
  }
}

// A single excluded-namespace (xn_*) or excluded-language (xl_*) toggle. For languages, `variant` is
// the column (0 original / 1 translated / 2 rewrite); -1 when not applicable (namespaces).
@ObservedV2
export class EhUconfigToggleItem {
  ser: number = 0
  name: string = ''
  @Trace excluded: boolean = false
  variant: number = -1

  constructor(ser: number, name: string, excluded: boolean, variant: number = -1) {
    this.ser = ser
    this.name = name
    this.excluded = excluded
    this.variant = variant
  }
}

// Front-page category visibility (ct_*). EH stores "1" = hidden on front page.
@ObservedV2
export class EhUconfigCategory {
  // The EH form key, e.g. 'ct_doujinshi' / 'ct_non-h'.
  key: string = ''
  label: string = ''
  @Trace hidden: boolean = false

  constructor(key: string, label: string, hidden: boolean) {
    this.key = key
    this.label = label
    this.hidden = hidden
  }
}

@ObservedV2
export class EhProfileSettings {
  // ── Profiles ──
  @Trace profiles: EhProfile[] = []
  @Trace selectedProfile: number = 0
  @Trace defaultProfile: number = 0

  // ── Radio groups (selected index == EH form value) ──
  @Trace loadImageThroughHAtH: number = 0 // uh
  @Trace imageSize: number = 0 // xr (auto/2400/1600/1280/780)
  @Trace galleryNameDisplay: number = 0 // tl (default title / japanese title)
  @Trace archiverSettings: number = 0 // ar
  @Trace frontPageSettings: number = 0 // dm (minimal/compact/extended/thumbnail)
  @Trace sortOrderFavorites: number = 0 // fs (favorited time / publish time)
  @Trace searchResultCount: number = 0 // rc (25/50/100/200, Hath-perk gated)
  @Trace mouseOverThumbnails: number = 0 // lt (on load / on mouse-over)
  @Trace thumbnailSize: number = 0 // ts (normal/large)
  @Trace thumbnailRows: number = 0 // tr (4/10/20/40)
  @Trace sortOrderComments: number = 0 // cs (by time / by score)
  @Trace showCommentVotes: number = 0 // sc
  @Trace sortOrderTags: number = 0 // tb (alphabetical / by power)
  @Trace showGalleryPageNumbers: number = 0 // pn
  @Trace originalImages: number = 0 // oi
  @Trace alwaysUseMpv: number = 0 // qb
  @Trace mpvStyle: number = 0 // ms
  @Trace mpvThumbnailPane: number = 0 // mt

  // ── Text inputs ──
  @Trace imageSizeHorizontal: string = '' // rx (max width, px)
  @Trace imageSizeVertical: string = '' // ry (max height, px)
  @Trace ratings: string = '' // ru (rating colors RRGGB)
  @Trace tagFilteringThreshold: string = '' // ft
  @Trace tagWatchingThreshold: string = '' // wt
  @Trace thumbnailScaling: string = '' // tp
  @Trace viewportOverride: string = '' // vp
  @Trace hentaiAtHomeLocalNetworkHost: string = '' // hh
  @Trace excludedUploaders: string = '' // xu (newline-separated)
  xuQuotaUsing: number = 0
  xuQuotaMax: number = 0

  // ── Composite ──
  @Trace categories: EhUconfigCategory[] = [] // ct_*
  @Trace favorites: string[] = [] // favorite_0..9 names
  @Trace excludedNamespaces: EhUconfigToggleItem[] = [] // xn_1..50
  @Trace excludedLanguages: EhUconfigToggleItem[] = [] // xl_* (only the ones present on the page)

  // ── Options parsed straight from the page (value + the page's own label) ──
  // Per radio/select code, exactly the options this account's page exposes — so the UI shows EH's real
  // current choices (correct resolutions etc.), not a stale hard-coded list, and Hath/permission gating
  // is automatic (absent options simply aren't here).
  radioGroups: Map<string, EhRadioOption[]> = new Map<string, EhRadioOption[]>()
  // All input/select/textarea field names present (so absent toggles/text/selects are hidden).
  fieldNames: string[] = []

  copy(): EhProfileSettings {
    const out: EhProfileSettings = new EhProfileSettings()
    out.profiles = this.profiles.map(
      (p: EhProfile) => new EhProfile(p.name, p.value, p.selected, p.isDefault),
    )
    out.selectedProfile = this.selectedProfile
    out.defaultProfile = this.defaultProfile
    out.loadImageThroughHAtH = this.loadImageThroughHAtH
    out.imageSize = this.imageSize
    out.galleryNameDisplay = this.galleryNameDisplay
    out.archiverSettings = this.archiverSettings
    out.frontPageSettings = this.frontPageSettings
    out.sortOrderFavorites = this.sortOrderFavorites
    out.searchResultCount = this.searchResultCount
    out.mouseOverThumbnails = this.mouseOverThumbnails
    out.thumbnailSize = this.thumbnailSize
    out.thumbnailRows = this.thumbnailRows
    out.sortOrderComments = this.sortOrderComments
    out.showCommentVotes = this.showCommentVotes
    out.sortOrderTags = this.sortOrderTags
    out.showGalleryPageNumbers = this.showGalleryPageNumbers
    out.originalImages = this.originalImages
    out.alwaysUseMpv = this.alwaysUseMpv
    out.mpvStyle = this.mpvStyle
    out.mpvThumbnailPane = this.mpvThumbnailPane
    out.imageSizeHorizontal = this.imageSizeHorizontal
    out.imageSizeVertical = this.imageSizeVertical
    out.ratings = this.ratings
    out.tagFilteringThreshold = this.tagFilteringThreshold
    out.tagWatchingThreshold = this.tagWatchingThreshold
    out.thumbnailScaling = this.thumbnailScaling
    out.viewportOverride = this.viewportOverride
    out.hentaiAtHomeLocalNetworkHost = this.hentaiAtHomeLocalNetworkHost
    out.excludedUploaders = this.excludedUploaders
    out.xuQuotaUsing = this.xuQuotaUsing
    out.xuQuotaMax = this.xuQuotaMax
    out.categories = this.categories.map(
      (c: EhUconfigCategory) => new EhUconfigCategory(c.key, c.label, c.hidden),
    )
    out.favorites = this.favorites.slice()
    out.excludedNamespaces = this.excludedNamespaces.map(
      (x: EhUconfigToggleItem) => new EhUconfigToggleItem(x.ser, x.name, x.excluded, x.variant),
    )
    out.excludedLanguages = this.excludedLanguages.map(
      (x: EhUconfigToggleItem) => new EhUconfigToggleItem(x.ser, x.name, x.excluded, x.variant),
    )
    out.radioGroups = this.radioGroups
    out.fieldNames = this.fieldNames.slice()
    return out
  }
}

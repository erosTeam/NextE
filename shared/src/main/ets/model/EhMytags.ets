import { EhConstants } from '../constants/EhConstants'

/**
 * One watched/hidden/flagged tag from the My Tags page (mytags). `tag` is the full
 * namespace:tag (e.g. "artist:dittaya"), `display` the short label, `translate` the optional
 * localized tag label, `color` the EH border color hex. `watched`/`hidden` reflect the row's
 * checkboxes (a tag with neither is
 * color-flagged only).
 */
export class EhUsertag {
  tagId: string = ''
  tag: string = ''
  display: string = ''
  translate: string = ''
  // EH gives each tag THREE colors via inline style (color:text, border-color, background fill).
  // Rendering the fill with the EH-supplied text color keeps custom light-fill tags readable
  // (forcing white text on a light fill is the bug this replaces). `color` = border (kept for compat).
  color: string = '' // border color
  fillColor: string = '' // background fill (first gradient stop)
  textColor: string = '' // EH-chosen readable text color
  defaultColor: boolean = true // true when EH's custom-color input is empty
  // Raw EH tag weight value. Kept as a string so future setusertag writes can round-trip the
  // server form value exactly like eros_fe's tagWeight field.
  tagWeight: string = ''
  weight: number = 10 // numeric compatibility value for current read-only display/sort paths
  watched: boolean = false
  hidden: boolean = false

  /**
   * Namespace part of `ns:tag` (e.g. 'artist'); 'misc' when the tag has no namespace. EH may write
   * the short prefix ('a:dittaya'), so expand it to the full name (eros_fe) for stable grouping.
   */
  namespace(): string {
    const idx: number = this.tag.indexOf(':')
    const raw: string = idx > 0 ? this.tag.substring(0, idx) : 'misc'
    return EhConstants.expandNamespace(raw)
  }
}

/** One My Tags set (the user can keep several, switched via the mytags `?tagset=` selector). */
export class EhMytagSet {
  tagsetId: string = ''
  name: string = ''
  count: number = 0

  constructor(tagsetId: string = '', name: string = '', count: number = 0) {
    this.tagsetId = tagsetId
    this.name = name
    this.count = count
  }
}

/** The user's My Tags set: the tag rows + the available sets + the API credentials for edits. */
export class EhMytags {
  tags: EhUsertag[] = []
  tagSets: EhMytagSet[] = []
  currentTagset: string = ''
  canDelete: boolean = false
  apiuid: string = ''
  apikey: string = ''
}

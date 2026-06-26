import { util } from '@kit.ArkTS'

/** All 10 EH category bits OR'd together (Misc..Western = 1+2+…+512). */
const ALL_CATS: number = 1023

/** Allowed list types for a custom home sub-tab (eros_fe GalleryListType). */
export const PROFILE_TYPE_GALLERY: string = 'gallery'
export const PROFILE_TYPE_POPULAR: string = 'popular'
export const PROFILE_TYPE_WATCHED: string = 'watched'
export const PROFILE_TYPE_TOPLIST: string = 'toplist'
export const PROFILE_TYPE_FAVORITE: string = 'favorite'

/** displayMode sentinel: follow the global ListModeState (vs a pinned ListMode value). */
export const PROFILE_DISPLAY_GLOBAL: string = 'global'

/** Stable reserved uuids for the three seeded built-in tabs — keep migration/seeding idempotent. */
export const BUILTIN_DEFAULT_UUID: string = 'builtin-default'
export const BUILTIN_POPULAR_UUID: string = 'builtin-popular'
export const BUILTIN_WATCHED_UUID: string = 'builtin-watched'

/**
 * One user-defined home sub-tab — eros_fe `CustomProfile` ported FLAT (ArkTS forbids the nested
 * AdvanceSearch object pattern; flatten the advanced fields exactly like SearchFilterState so the editor
 * can bind a transient SearchFilterState and copy fields 1:1). A profile is a saved gallery view:
 * a list type + search query + category mask + the same advanced-search payload SearchFilterState holds,
 * plus per-type pins (favcat for favorite, toplistTl for toplist) and an optional per-tab display mode.
 *
 * Plain class (no @ObservedV2) like TabItem and the other ported eros_fe models — reactivity comes from
 * the @Trace `profiles` ARRAY in CustomProfilesState, which is REASSIGNED on every edit (CustomProfiles
 * Settings is the single writer); never mutate a profile in place and expect the bar to redraw.
 * `selectedCats` is the INCLUDE bitmask (identical to SearchFilterState); fCats() inverts to EH's f_cats.
 */
export class CustomProfile {
  uuid: string = ''
  name: string = ''
  listType: string = PROFILE_TYPE_GALLERY
  searchText: string = ''
  selectedCats: number = 0
  advancedEnabled: boolean = false
  minRating: number = 0
  pagesFrom: number = 0
  pagesTo: number = 0
  requireTorrent: boolean = false
  showExpunged: boolean = false
  disableLanguageFilter: boolean = false
  disableUploaderFilter: boolean = false
  disableTagFilter: boolean = false
  favcat: string = 'a'
  toplistTl: number = 15
  displayMode: string = PROFILE_DISPLAY_GLOBAL
  hidden: boolean = false
  builtin: boolean = false
  lastEditTime: number = 0

  /** EH f_cats = sum of EXCLUDED categories; 0 when nothing or everything is selected. */
  fCats(): number {
    if (this.selectedCats === 0 || this.selectedCats === ALL_CATS) {
      return 0
    }
    return ALL_CATS - this.selectedCats
  }

  /** watched / favorite list types require a logged-in account. */
  requiresLogin(): boolean {
    return this.listType === PROFILE_TYPE_WATCHED || this.listType === PROFILE_TYPE_FAVORITE
  }

  /** Hand-written deep copy (ArkTS has no spread/Object.assign for class instances). */
  copy(): CustomProfile {
    const c: CustomProfile = new CustomProfile()
    c.uuid = this.uuid
    c.name = this.name
    c.listType = this.listType
    c.searchText = this.searchText
    c.selectedCats = this.selectedCats
    c.advancedEnabled = this.advancedEnabled
    c.minRating = this.minRating
    c.pagesFrom = this.pagesFrom
    c.pagesTo = this.pagesTo
    c.requireTorrent = this.requireTorrent
    c.showExpunged = this.showExpunged
    c.disableLanguageFilter = this.disableLanguageFilter
    c.disableUploaderFilter = this.disableUploaderFilter
    c.disableTagFilter = this.disableTagFilter
    c.favcat = this.favcat
    c.toplistTl = this.toplistTl
    c.displayMode = this.displayMode
    c.hidden = this.hidden
    c.builtin = this.builtin
    c.lastEditTime = this.lastEditTime
    return c
  }
}

/** True when `t` is one of the five allowed list types. */
export function isValidProfileType(t: string): boolean {
  return (
    t === PROFILE_TYPE_GALLERY ||
    t === PROFILE_TYPE_POPULAR ||
    t === PROFILE_TYPE_WATCHED ||
    t === PROFILE_TYPE_TOPLIST ||
    t === PROFILE_TYPE_FAVORITE
  )
}

/** Generate an RFC4122 v4 uuid for a new custom profile (eros_fe uses UUID v4). */
export function newProfileUuid(): string {
  return util.generateRandomUUID(true)
}

import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { AppStrings } from '../i18n/AppStrings'
import { ListMode } from '../state/ListModeState'
import { connectCustomProfiles, CustomProfilesState } from '../state/CustomProfilesState'
import {
  CustomProfile,
  isValidProfileType,
  newProfileUuid,
  PROFILE_TYPE_GALLERY,
  PROFILE_TYPE_POPULAR,
  PROFILE_TYPE_WATCHED,
  PROFILE_DISPLAY_GLOBAL,
  BUILTIN_DEFAULT_UUID,
  BUILTIN_POPULAR_UUID,
  BUILTIN_WATCHED_UUID,
} from '../model/CustomProfile'

/** Flat persisted snapshot of a CustomProfile (every field, plain types, safe defaults). */
class CustomProfileSnapshot {
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
}

const TOPLIST_PERIODS: number[] = [11, 12, 13, 15]
const DISPLAY_MODES: string[] = [
  PROFILE_DISPLAY_GLOBAL,
  ListMode.LIST,
  ListMode.SIMPLE_LIST,
  ListMode.GRID,
  ListMode.WATERFALL,
  ListMode.COVER_WALL,
]

/**
 * Single writer of CustomProfilesState — restores the persisted home sub-tab profiles (seeding the three
 * built-ins + two starter examples on first run, migrating the legacy HOME_SOURCE selection), and
 * performs every CRUD/reorder mutation followed by a JSON persist. Mirrors SearchHistorySettings /
 * FavcatListSettings (preferences + best-effort try/catch). Built-ins (stable uuids) are hide-only.
 */
export class CustomProfilesSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(StorageKeys.HOME_CUSTOM_PROFILES, '[]') as string
      const state: CustomProfilesState = connectCustomProfiles()
      let profiles: CustomProfile[] = CustomProfilesSettings.parse(raw)
      let selected: string = store.getSync(StorageKeys.HOME_CUSTOM_PROFILES_SELECTED, '') as string
      if (profiles.length === 0) {
        // First run: seed built-ins + starters and map the legacy HOME_SOURCE selection.
        profiles = CustomProfilesSettings.seedDefaults()
        selected = CustomProfilesSettings.migrateSelected(store)
        state.profiles = profiles
        state.selectedUuid = selected
        await CustomProfilesSettings.persistAll(context)
        return
      }
      if (CustomProfilesSettings.indexOfUuid(profiles, selected) < 0) {
        selected = profiles[0].uuid
      }
      state.profiles = profiles
      state.selectedUuid = selected
    } catch (error) {
      DiagnosticLogger.warn('settings', 'custom_profiles_restore_failed', (error as Error).message)
    }
  }

  /** Append a new profile. */
  static async add(context: common.UIAbilityContext, profile: CustomProfile): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const next: CustomProfile[] = CustomProfilesSettings.cloneList(state.profiles)
    profile.lastEditTime = CustomProfilesSettings.now()
    next.push(profile)
    state.profiles = next
    await CustomProfilesSettings.persistAll(context)
  }

  /** Replace the profile with the same uuid (bumps lastEditTime). */
  static async update(context: common.UIAbilityContext, profile: CustomProfile): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const next: CustomProfile[] = []
    state.profiles.forEach((p: CustomProfile) => {
      if (p.uuid === profile.uuid) {
        profile.lastEditTime = CustomProfilesSettings.now()
        next.push(profile)
      } else {
        next.push(p)
      }
    })
    state.profiles = next
    await CustomProfilesSettings.persistAll(context)
  }

  /** Delete a custom (non-built-in) profile; falls back to the first profile if the selected one goes. */
  static async remove(context: common.UIAbilityContext, uuid: string): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const target: CustomProfile | null = state.findByUuid(uuid)
    if (target === null || target.builtin) {
      return
    }
    const next: CustomProfile[] = []
    state.profiles.forEach((p: CustomProfile) => {
      if (p.uuid !== uuid) {
        next.push(p)
      }
    })
    state.profiles = next
    if (state.selectedUuid === uuid) {
      state.selectedUuid = next.length > 0 ? next[0].uuid : ''
    }
    await CustomProfilesSettings.persistAll(context)
  }

  /** Move a profile from one index to another, preserving the rest of the order. */
  static async reorder(context: common.UIAbilityContext, from: number, to: number): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const list: CustomProfile[] = state.profiles
    if (from < 0 || from >= list.length || to < 0 || to >= list.length || from === to) {
      return
    }
    const moved: CustomProfile = list[from]
    const next: CustomProfile[] = []
    list.forEach((p: CustomProfile, i: number) => {
      if (i !== from) {
        next.push(p)
      }
    })
    next.splice(to, 0, moved)
    state.profiles = next
    await CustomProfilesSettings.persistAll(context)
  }

  /** Show/hide a profile in the bar (built-ins are hidden rather than deleted). */
  static async setHidden(
    context: common.UIAbilityContext,
    uuid: string,
    hidden: boolean,
  ): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const next: CustomProfile[] = []
    state.profiles.forEach((p: CustomProfile) => {
      if (p.uuid === uuid) {
        const c: CustomProfile = p.copy()
        c.hidden = hidden
        next.push(c)
      } else {
        next.push(p)
      }
    })
    state.profiles = next
    // If we just hid the selected tab, move the selection to the first still-visible tab so the bar
    // and the active page stay in sync (no stale selection pointing at a hidden tab).
    if (hidden && state.selectedUuid === uuid) {
      state.selectedUuid = CustomProfilesSettings.firstVisibleUuid(next)
    }
    await CustomProfilesSettings.persistAll(context)
  }

  /** uuid of the first non-hidden profile, or '' if all hidden. */
  private static firstVisibleUuid(profiles: CustomProfile[]): string {
    for (let i = 0; i < profiles.length; i++) {
      if (!profiles[i].hidden) {
        return profiles[i].uuid
      }
    }
    return ''
  }

  /** Set the active tab and persist the selection. */
  static async setSelected(context: common.UIAbilityContext, uuid: string): Promise<void> {
    connectCustomProfiles().selectedUuid = uuid
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.HOME_CUSTOM_PROFILES_SELECTED, uuid)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'custom_profiles_select_failed', (error as Error).message)
    }
  }

  // ---- internals ----

  private static async persistAll(context: common.UIAbilityContext): Promise<void> {
    try {
      const state: CustomProfilesState = connectCustomProfiles()
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.HOME_CUSTOM_PROFILES, CustomProfilesSettings.serialize(state.profiles))
      store.putSync(StorageKeys.HOME_CUSTOM_PROFILES_SELECTED, state.selectedUuid)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'custom_profiles_save_failed', (error as Error).message)
    }
  }

  private static seedDefaults(): CustomProfile[] {
    const out: CustomProfile[] = []
    out.push(
      CustomProfilesSettings.builtin(
        BUILTIN_DEFAULT_UUID,
        AppStrings.get('home_source_default'),
        PROFILE_TYPE_GALLERY,
      ),
    )
    out.push(
      CustomProfilesSettings.builtin(
        BUILTIN_POPULAR_UUID,
        AppStrings.get('home_source_popular'),
        PROFILE_TYPE_POPULAR,
      ),
    )
    out.push(
      CustomProfilesSettings.builtin(
        BUILTIN_WATCHED_UUID,
        AppStrings.get('home_source_watched'),
        PROFILE_TYPE_WATCHED,
      ),
    )
    // Two deletable starter examples that show how a saved-search tab works (eros_fe 汉化 / 选集).
    out.push(
      CustomProfilesSettings.starter(AppStrings.get('tab_seed_chinese'), 'language:chinese'),
    )
    out.push(
      CustomProfilesSettings.starter(AppStrings.get('tab_seed_anthology'), 'other:anthology'),
    )
    return out
  }

  private static builtin(uuid: string, name: string, listType: string): CustomProfile {
    const p: CustomProfile = new CustomProfile()
    p.uuid = uuid
    p.name = name
    p.listType = listType
    p.builtin = true
    return p
  }

  private static starter(name: string, searchText: string): CustomProfile {
    const p: CustomProfile = new CustomProfile()
    p.uuid = newProfileUuid()
    p.name = name
    p.listType = PROFILE_TYPE_GALLERY
    p.searchText = searchText
    return p
  }

  /** Map the legacy HOME_SOURCE preference to a built-in uuid (''→default / popular / watched). */
  private static migrateSelected(store: preferences.Preferences): string {
    const legacy: string = store.getSync(StorageKeys.HOME_SOURCE, '') as string
    if (legacy === 'popular') {
      return BUILTIN_POPULAR_UUID
    }
    if (legacy === 'watched') {
      return BUILTIN_WATCHED_UUID
    }
    return BUILTIN_DEFAULT_UUID
  }

  private static serialize(profiles: CustomProfile[]): string {
    const snaps: CustomProfileSnapshot[] = []
    profiles.forEach((p: CustomProfile) => {
      const s: CustomProfileSnapshot = new CustomProfileSnapshot()
      s.uuid = p.uuid
      s.name = p.name
      s.listType = p.listType
      s.searchText = p.searchText
      s.selectedCats = p.selectedCats
      s.advancedEnabled = p.advancedEnabled
      s.minRating = p.minRating
      s.pagesFrom = p.pagesFrom
      s.pagesTo = p.pagesTo
      s.requireTorrent = p.requireTorrent
      s.showExpunged = p.showExpunged
      s.disableLanguageFilter = p.disableLanguageFilter
      s.disableUploaderFilter = p.disableUploaderFilter
      s.disableTagFilter = p.disableTagFilter
      s.favcat = p.favcat
      s.toplistTl = p.toplistTl
      s.displayMode = p.displayMode
      s.hidden = p.hidden
      s.builtin = p.builtin
      s.lastEditTime = p.lastEditTime
      snaps.push(s)
    })
    return JSON.stringify(snaps)
  }

  private static parse(raw: string): CustomProfile[] {
    try {
      const parsed: Object = JSON.parse(raw) as Object
      if (!Array.isArray(parsed)) {
        return []
      }
      const out: CustomProfile[] = []
      const seen: Set<string> = new Set<string>()
      ;(parsed as CustomProfileSnapshot[]).forEach((s: CustomProfileSnapshot) => {
        const uuid: string = typeof s.uuid === 'string' ? s.uuid : ''
        if (uuid.length === 0 || seen.has(uuid)) {
          return
        }
        seen.add(uuid)
        const p: CustomProfile = new CustomProfile()
        p.uuid = uuid
        p.name = typeof s.name === 'string' ? s.name : ''
        p.listType = isValidProfileType(s.listType) ? s.listType : PROFILE_TYPE_GALLERY
        p.searchText = typeof s.searchText === 'string' ? s.searchText : ''
        p.selectedCats = CustomProfilesSettings.num(s.selectedCats, 0)
        p.advancedEnabled = s.advancedEnabled === true
        p.minRating = CustomProfilesSettings.num(s.minRating, 0)
        p.pagesFrom = CustomProfilesSettings.num(s.pagesFrom, 0)
        p.pagesTo = CustomProfilesSettings.num(s.pagesTo, 0)
        p.requireTorrent = s.requireTorrent === true
        p.showExpunged = s.showExpunged === true
        p.disableLanguageFilter = s.disableLanguageFilter === true
        p.disableUploaderFilter = s.disableUploaderFilter === true
        p.disableTagFilter = s.disableTagFilter === true
        p.favcat = CustomProfilesSettings.clampFavcat(s.favcat)
        p.toplistTl = CustomProfilesSettings.clampToplist(s.toplistTl)
        p.displayMode = CustomProfilesSettings.clampDisplayMode(s.displayMode)
        p.hidden = s.hidden === true
        p.builtin = s.builtin === true
        p.lastEditTime = CustomProfilesSettings.num(s.lastEditTime, 0)
        out.push(p)
      })
      return out
    } catch (error) {
      DiagnosticLogger.warn('settings', 'custom_profiles_parse_failed', (error as Error).message)
      return []
    }
  }

  private static num(v: number, fallback: number): number {
    return typeof v === 'number' && !Number.isNaN(v) ? v : fallback
  }

  private static clampFavcat(v: string): string {
    if (typeof v !== 'string') {
      return 'a'
    }
    if (v === 'a') {
      return 'a'
    }
    const n: number = Number.parseInt(v, 10)
    return `${n}` === v && n >= 0 && n <= 9 ? v : 'a'
  }

  private static clampToplist(v: number): number {
    return TOPLIST_PERIODS.indexOf(v) >= 0 ? v : 15
  }

  private static clampDisplayMode(v: string): string {
    return typeof v === 'string' && DISPLAY_MODES.indexOf(v) >= 0 ? v : PROFILE_DISPLAY_GLOBAL
  }

  private static indexOfUuid(profiles: CustomProfile[], uuid: string): number {
    for (let i = 0; i < profiles.length; i++) {
      if (profiles[i].uuid === uuid) {
        return i
      }
    }
    return -1
  }

  private static cloneList(profiles: CustomProfile[]): CustomProfile[] {
    const out: CustomProfile[] = []
    profiles.forEach((p: CustomProfile) => {
      out.push(p)
    })
    return out
  }

  private static now(): number {
    return new Date().getTime()
  }
}

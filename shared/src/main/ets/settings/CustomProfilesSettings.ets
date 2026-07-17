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
  PROFILE_TYPE_GALLERY,
  PROFILE_TYPE_POPULAR,
  PROFILE_TYPE_WATCHED,
  PROFILE_DISPLAY_GLOBAL,
  BUILTIN_DEFAULT_UUID,
  BUILTIN_POPULAR_UUID,
  BUILTIN_WATCHED_UUID,
  STARTER_CHINESE_UUID,
  STARTER_ANTHOLOGY_UUID,
} from '../model/CustomProfile'
import { CustomProfilesRepository } from '../storage/CustomProfilesRepository'
import { SyncScheduler } from '../sync/SyncScheduler'

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

class CustomProfilesNormalizeResult {
  profiles: CustomProfile[] = []
  selectedUuid: string = ''
  changed: boolean = false
}

/** A matched durable pair for backup: profile order and selectedUuid share one RDB queue slot. */
export class CustomProfilesBackupSnapshot {
  profiles: CustomProfile[] = []
  selectedUuid: string = ''
}

/** Serializes every durable Custom Profiles operation while letting a failed write release later work. */
export class CustomProfilesPersistScheduler {
  private writeTail: Promise<void> = Promise.resolve()

  enqueue(write: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.writeTail.then(write, write)
    this.writeTail = next
    return next
  }

  flush(): Promise<void> {
    return this.writeTail
  }
}

const TOPLIST_PERIODS: number[] = [11, 12, 13, 15]
const DISPLAY_MODES: string[] = [
  PROFILE_DISPLAY_GLOBAL,
  ListMode.LIST,
  ListMode.SIMPLE_LIST,
  ListMode.GRID,
  ListMode.WATERFALL,
  ListMode.WATERFALL_COMPACT,
  ListMode.COVER_WALL,
]

/**
 * Single writer of CustomProfilesState — restores the persisted home sub-tab profiles (seeding the three
 * built-ins + two starter examples on first run, migrating the legacy HOME_SOURCE selection), and
 * performs every CRUD/reorder mutation followed by a durable RDB persist. Mirrors SearchHistorySettings /
 * FavcatListSettings (preferences + best-effort try/catch). Built-ins (stable uuids) are hide-only.
 */
export class CustomProfilesSettings {
  // Home tab actions intentionally update live state before awaiting storage. Serialize their snapshots
  // so targeted row writes and selection changes retain user order under rapid consecutive mutations.
  private static readonly rdbWriteScheduler: CustomProfilesPersistScheduler =
    new CustomProfilesPersistScheduler()
  private static mutationRevision: number = 0

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await CustomProfilesSettings.migrateLegacyPreferences(context)
      for (let attempt: number = 0; attempt < 2; attempt++) {
        await CustomProfilesSettings.rdbWriteScheduler.flush()
        const revision: number = CustomProfilesSettings.mutationRevision
        const state: CustomProfilesState = connectCustomProfiles()
        const profiles: CustomProfile[] = await CustomProfilesRepository.loadProfiles(context)
        let selected: string = await CustomProfilesRepository.loadSelected(context)
        if (revision !== CustomProfilesSettings.mutationRevision) {
          continue
        }
        if (profiles.length === 0) {
          // First run: seed built-ins + starters and map the legacy HOME_SOURCE selection.
          const defaults: CustomProfile[] = CustomProfilesSettings.seedDefaults()
          selected = await CustomProfilesSettings.migrateSelected(context)
          if (revision !== CustomProfilesSettings.mutationRevision) {
            continue
          }
          state.profiles = defaults
          state.selectedUuid = selected
          await CustomProfilesSettings.persistAll(context)
          return
        }
        const migratedProfiles: CustomProfile[] = CustomProfilesSettings.migrateStarterNames(profiles)
        const builtinProfiles: CustomProfile[] = CustomProfilesSettings.ensureBuiltins(migratedProfiles)
        const normalized: CustomProfilesNormalizeResult =
          CustomProfilesSettings.normalizeStarterProfiles(builtinProfiles, selected)
        state.profiles = normalized.profiles
        state.selectedUuid = normalized.selectedUuid
        if (migratedProfiles !== profiles || builtinProfiles !== migratedProfiles || normalized.changed) {
          await CustomProfilesSettings.persistAll(context)
        }
        return
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'custom_profiles_restore_failed', (error as Error).message)
    }
  }

  /** Append a new profile. */
  static async add(context: common.UIAbilityContext, profile: CustomProfile): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const next: CustomProfile[] = CustomProfilesSettings.cloneList(state.profiles)
    profile.lastEditTime = CustomProfilesSettings.nextEditTime(profile.lastEditTime)
    next.push(profile)
    state.profiles = next
    CustomProfilesSettings.mutationRevision = CustomProfilesSettings.mutationRevision + 1
    await CustomProfilesSettings.persistChanged(context, next, [profile.uuid])
  }

  /** Replace the profile with the same uuid (bumps lastEditTime). */
  static async update(context: common.UIAbilityContext, profile: CustomProfile): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const next: CustomProfile[] = []
    state.profiles.forEach((p: CustomProfile) => {
      if (p.uuid === profile.uuid) {
        profile.lastEditTime = CustomProfilesSettings.nextEditTime(p.lastEditTime)
        next.push(profile)
      } else {
        next.push(p)
      }
    })
    state.profiles = next
    CustomProfilesSettings.mutationRevision = CustomProfilesSettings.mutationRevision + 1
    await CustomProfilesSettings.persistChanged(context, next, [profile.uuid])
  }

  /** Delete a custom (non-built-in) profile; falls back to the first profile if the selected one goes. */
  static async remove(context: common.UIAbilityContext, uuid: string): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const target: CustomProfile | null = state.findByUuid(uuid)
    if (target === null || target.builtin) {
      return
    }
    const removedIndex: number = CustomProfilesSettings.indexOfUuid(state.profiles, uuid)
    const next: CustomProfile[] = []
    state.profiles.forEach((p: CustomProfile) => {
      if (p.uuid !== uuid) {
        next.push(p)
      }
    })
    const selectionChanged: boolean = state.selectedUuid === uuid
    if (selectionChanged) {
      state.selectedUuid = CustomProfilesSettings.firstVisibleUuid(next)
    }
    const changedUuids: string[] = []
    for (let i: number = removedIndex; i < next.length; i++) {
      const shifted: CustomProfile = next[i].copy()
      shifted.lastEditTime = CustomProfilesSettings.nextEditTime(shifted.lastEditTime)
      next[i] = shifted
      changedUuids.push(shifted.uuid)
    }
    state.profiles = next
    CustomProfilesSettings.mutationRevision = CustomProfilesSettings.mutationRevision + 1
    await CustomProfilesSettings.persistChanged(context, next, changedUuids, uuid, selectionChanged)
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
    const start: number = Math.min(from, to)
    const end: number = Math.max(from, to)
    const changedUuids: string[] = []
    for (let i: number = start; i <= end; i++) {
      const shifted: CustomProfile = next[i].copy()
      shifted.lastEditTime = CustomProfilesSettings.nextEditTime(shifted.lastEditTime)
      next[i] = shifted
      changedUuids.push(shifted.uuid)
    }
    state.profiles = next
    CustomProfilesSettings.mutationRevision = CustomProfilesSettings.mutationRevision + 1
    await CustomProfilesSettings.persistChanged(context, next, changedUuids)
  }

  /** Pin a per-tab display mode ('global' = follow the shared ListModeState). This advances the durable
   * LWW clock; GallerySourcePage uses contentRevision(), so the retained page only re-renders. */
  static async setDisplayMode(
    context: common.UIAbilityContext,
    uuid: string,
    mode: string,
  ): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const next: CustomProfile[] = []
    const changedUuids: string[] = []
    state.profiles.forEach((p: CustomProfile) => {
      if (p.uuid === uuid && p.displayMode !== mode) {
        const c: CustomProfile = p.copy()
        c.displayMode = mode
        c.lastEditTime = CustomProfilesSettings.nextEditTime(p.lastEditTime)
        next.push(c)
        changedUuids.push(c.uuid)
      } else {
        next.push(p)
      }
    })
    state.profiles = next
    CustomProfilesSettings.mutationRevision = CustomProfilesSettings.mutationRevision + 1
    await CustomProfilesSettings.persistChanged(context, next, changedUuids)
  }

  /** Show/hide a profile in the bar (built-ins are hidden rather than deleted). */
  static async setHidden(
    context: common.UIAbilityContext,
    uuid: string,
    hidden: boolean,
  ): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const next: CustomProfile[] = []
    const changedUuids: string[] = []
    state.profiles.forEach((p: CustomProfile) => {
      if (p.uuid === uuid && p.hidden !== hidden) {
        const c: CustomProfile = p.copy()
        c.hidden = hidden
        c.lastEditTime = CustomProfilesSettings.nextEditTime(p.lastEditTime)
        next.push(c)
        changedUuids.push(c.uuid)
      } else {
        next.push(p)
      }
    })
    state.profiles = next
    // If we just hid the selected tab, move the selection to the first still-visible tab so the bar
    // and the active page stay in sync (no stale selection pointing at a hidden tab).
    const selectionChanged: boolean = hidden && state.selectedUuid === uuid
    if (selectionChanged) {
      state.selectedUuid = CustomProfilesSettings.firstVisibleUuid(next)
    }
    CustomProfilesSettings.mutationRevision = CustomProfilesSettings.mutationRevision + 1
    await CustomProfilesSettings.persistChanged(context, next, changedUuids, '', selectionChanged)
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
    CustomProfilesSettings.mutationRevision = CustomProfilesSettings.mutationRevision + 1
    try {
      await CustomProfilesSettings.enqueueRdbWrite(
        (): Promise<void> => CustomProfilesRepository.saveSelected(context, uuid),
      )
      SyncScheduler.requestAfterLocalWrite(context, 'custom_profile_selection')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'custom_profiles_select_failed', (error as Error).message)
    }
  }

  static async exportForBackup(context: common.UIAbilityContext): Promise<CustomProfile[]> {
    return (await CustomProfilesSettings.exportForBackupSnapshot(context)).profiles
  }

  static async exportSelectedForBackup(context: common.UIAbilityContext): Promise<string> {
    return (await CustomProfilesSettings.exportForBackupSnapshot(context)).selectedUuid
  }

  /** Read profiles and selection between queued writers so one backup cannot mix two tab states. */
  static async exportForBackupSnapshot(
    context: common.UIAbilityContext,
  ): Promise<CustomProfilesBackupSnapshot> {
    await CustomProfilesSettings.migrateLegacyPreferences(context)
    const snapshot: CustomProfilesBackupSnapshot = new CustomProfilesBackupSnapshot()
    await CustomProfilesSettings.enqueueRdbWrite(async (): Promise<void> => {
      snapshot.profiles = await CustomProfilesRepository.loadProfiles(context)
      snapshot.selectedUuid = await CustomProfilesRepository.loadSelected(context)
    })
    return snapshot
  }

  static async restoreBackup(
    context: common.UIAbilityContext,
    profiles: CustomProfile[],
    selectedUuid: string,
  ): Promise<void> {
    const snapshot: CustomProfile[] = CustomProfilesSettings.snapshotProfiles(profiles)
    CustomProfilesSettings.mutationRevision = CustomProfilesSettings.mutationRevision + 1
    await CustomProfilesSettings.enqueueRdbWrite(
      (): Promise<void> => CustomProfilesRepository.replaceAll(context, snapshot, selectedUuid),
    )
    await CustomProfilesSettings.deleteLegacyPreferences(context)
    await CustomProfilesSettings.refreshFromStorage(context)
    SyncScheduler.requestAfterLocalWrite(context, 'custom_profiles_restore_backup')
  }

  /** Drain queued writes before backup and sync providers read the custom-profile tables. */
  static async flushForSync(_context: common.UIAbilityContext): Promise<void> {
    await CustomProfilesSettings.rdbWriteScheduler.flush()
  }

  // ---- internals ----

  private static async persistAll(context: common.UIAbilityContext): Promise<void> {
    const state: CustomProfilesState = connectCustomProfiles()
    const profiles: CustomProfile[] = CustomProfilesSettings.snapshotProfiles(state.profiles)
    const selectedUuid: string = state.selectedUuid
    try {
      await CustomProfilesSettings.enqueueRdbWrite(
        (): Promise<void> => CustomProfilesRepository.replaceAll(context, profiles, selectedUuid),
      )
      SyncScheduler.requestAfterLocalWrite(context, 'custom_profiles')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'custom_profiles_save_failed', (error as Error).message)
    }
  }

  private static async persistChanged(
    context: common.UIAbilityContext,
    profiles: CustomProfile[],
    changedUuids: string[],
    deletedUuid: string = '',
    selectionChanged: boolean = false,
  ): Promise<void> {
    const snapshot: CustomProfile[] = CustomProfilesSettings.snapshotProfiles(profiles)
    const selectedUuid: string = connectCustomProfiles().selectedUuid
    const changedSnapshot: string[] = []
    changedUuids.forEach((uuid: string) => changedSnapshot.push(uuid))
    try {
      await CustomProfilesSettings.enqueueRdbWrite(
        (): Promise<void> => CustomProfilesRepository.saveChanges(
          context,
          snapshot,
          changedSnapshot,
          selectedUuid,
          deletedUuid,
          selectionChanged,
        ),
      )
      SyncScheduler.requestAfterLocalWrite(context, 'custom_profiles')
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
    // Two deletable starter examples that show how a saved-search tab works (中文 / 选集).
    out.push(
      CustomProfilesSettings.starter(
        STARTER_CHINESE_UUID,
        AppStrings.get('tab_seed_chinese'),
        'language:chinese',
      ),
    )
    out.push(
      CustomProfilesSettings.starter(
        STARTER_ANTHOLOGY_UUID,
        AppStrings.get('tab_seed_anthology'),
        'other:anthology',
      ),
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

  private static starter(uuid: string, name: string, searchText: string): CustomProfile {
    const p: CustomProfile = new CustomProfile()
    p.uuid = uuid
    p.name = name
    p.listType = PROFILE_TYPE_GALLERY
    p.searchText = searchText
    return p
  }

  private static ensureBuiltins(profiles: CustomProfile[]): CustomProfile[] {
    const out: CustomProfile[] = []
    let changed: boolean = false
    profiles.forEach((p: CustomProfile) => {
      const normalized: CustomProfile = CustomProfilesSettings.normalizeBuiltin(p)
      out.push(normalized)
      if (normalized !== p) {
        changed = true
      }
    })
    changed = CustomProfilesSettings.addMissingBuiltin(
      out,
      BUILTIN_DEFAULT_UUID,
      AppStrings.get('home_source_default'),
      PROFILE_TYPE_GALLERY,
      '',
    ) || changed
    changed = CustomProfilesSettings.addMissingBuiltin(
      out,
      BUILTIN_POPULAR_UUID,
      AppStrings.get('home_source_popular'),
      PROFILE_TYPE_POPULAR,
      BUILTIN_DEFAULT_UUID,
    ) || changed
    changed = CustomProfilesSettings.addMissingBuiltin(
      out,
      BUILTIN_WATCHED_UUID,
      AppStrings.get('home_source_watched'),
      PROFILE_TYPE_WATCHED,
      BUILTIN_POPULAR_UUID,
    ) || changed
    return changed ? out : profiles
  }

  private static normalizeBuiltin(profile: CustomProfile): CustomProfile {
    const listType: string = CustomProfilesSettings.builtinListType(profile.uuid)
    if (listType.length === 0) {
      return profile
    }
    if (profile.builtin && profile.listType === listType && profile.name.length > 0) {
      return profile
    }
    const next: CustomProfile = profile.copy()
    next.builtin = true
    next.listType = listType
    if (next.name.length === 0) {
      next.name = CustomProfilesSettings.builtinName(profile.uuid)
    }
    return next
  }

  private static addMissingBuiltin(
    profiles: CustomProfile[],
    uuid: string,
    name: string,
    listType: string,
    afterUuid: string,
  ): boolean {
    if (CustomProfilesSettings.indexOfUuid(profiles, uuid) >= 0) {
      return false
    }
    const profile: CustomProfile = CustomProfilesSettings.builtin(uuid, name, listType)
    const afterIndex: number =
      afterUuid.length > 0 ? CustomProfilesSettings.indexOfUuid(profiles, afterUuid) : -1
    if (afterIndex >= 0) {
      profiles.splice(afterIndex + 1, 0, profile)
    } else {
      profiles.push(profile)
    }
    return true
  }

  private static builtinListType(uuid: string): string {
    if (uuid === BUILTIN_DEFAULT_UUID) {
      return PROFILE_TYPE_GALLERY
    }
    if (uuid === BUILTIN_POPULAR_UUID) {
      return PROFILE_TYPE_POPULAR
    }
    if (uuid === BUILTIN_WATCHED_UUID) {
      return PROFILE_TYPE_WATCHED
    }
    return ''
  }

  private static builtinName(uuid: string): string {
    if (uuid === BUILTIN_DEFAULT_UUID) {
      return AppStrings.get('home_source_default')
    }
    if (uuid === BUILTIN_POPULAR_UUID) {
      return AppStrings.get('home_source_popular')
    }
    if (uuid === BUILTIN_WATCHED_UUID) {
      return AppStrings.get('home_source_watched')
    }
    return ''
  }

  private static migrateStarterNames(profiles: CustomProfile[]): CustomProfile[] {
    let changed: boolean = false
    const out: CustomProfile[] = []
    profiles.forEach((p: CustomProfile) => {
      if (p.searchText === 'language:chinese' && p.name === '汉化') {
        const c: CustomProfile = p.copy()
        c.name = AppStrings.get('tab_seed_chinese')
        out.push(c)
        changed = true
      } else {
        out.push(p)
      }
    })
    return changed ? out : profiles
  }

  private static normalizeStarterProfiles(
    profiles: CustomProfile[],
    selectedUuid: string,
  ): CustomProfilesNormalizeResult {
    const result: CustomProfilesNormalizeResult = new CustomProfilesNormalizeResult()
    const out: CustomProfile[] = []
    let selected: string = selectedUuid
    let changed: boolean = false
    profiles.forEach((p: CustomProfile) => {
      const canonicalUuid: string = CustomProfilesSettings.canonicalStarterUuid(p)
      if (canonicalUuid.length === 0) {
        out.push(p)
        return
      }
      let next: CustomProfile = p
      if (p.uuid !== canonicalUuid) {
        next = p.copy()
        next.uuid = canonicalUuid
        if (selected === p.uuid) {
          selected = canonicalUuid
        }
        changed = true
      }
      const existingIndex: number = CustomProfilesSettings.indexOfUuid(out, canonicalUuid)
      if (existingIndex < 0) {
        out.push(next)
        return
      }
      if (CustomProfilesSettings.profileTime(next) >= CustomProfilesSettings.profileTime(out[existingIndex])) {
        out[existingIndex] = next
      }
      changed = true
    })

    const selectedIndex: number = CustomProfilesSettings.indexOfUuid(out, selected)
    if (selectedIndex < 0 || out[selectedIndex].hidden) {
      selected = CustomProfilesSettings.firstVisibleUuid(out)
      changed = true
    }
    result.profiles = out
    result.selectedUuid = selected
    result.changed = changed
    return result
  }

  private static canonicalStarterUuid(p: CustomProfile): string {
    if (p.listType !== PROFILE_TYPE_GALLERY) {
      return ''
    }
    if (p.searchText === 'language:chinese') {
      return STARTER_CHINESE_UUID
    }
    if (p.searchText === 'other:anthology') {
      return STARTER_ANTHOLOGY_UUID
    }
    return ''
  }

  private static profileTime(p: CustomProfile): number {
    return Math.floor(p.lastEditTime)
  }

  /** Map the legacy HOME_SOURCE preference to a built-in uuid (''→default / popular / watched). */
  private static async migrateSelected(context: common.UIAbilityContext): Promise<string> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const legacy: string = store.getSync(StorageKeys.HOME_SOURCE, '') as string
    if (legacy === 'popular') {
      return BUILTIN_POPULAR_UUID
    }
    if (legacy === 'watched') {
      return BUILTIN_WATCHED_UUID
    }
    return BUILTIN_DEFAULT_UUID
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const revision: number = CustomProfilesSettings.mutationRevision
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const raw: string = store.getSync(StorageKeys.HOME_CUSTOM_PROFILES, '') as string
    if (raw.length === 0) {
      return
    }
    const profiles: CustomProfile[] = CustomProfilesSettings.parse(raw)
    let selected: string = store.getSync(StorageKeys.HOME_CUSTOM_PROFILES_SELECTED, '') as string
    if (CustomProfilesSettings.indexOfUuid(profiles, selected) < 0) {
      selected = profiles.length > 0 ? profiles[0].uuid : ''
    }
    const snapshot: CustomProfile[] = CustomProfilesSettings.snapshotProfiles(profiles)
    try {
      await CustomProfilesSettings.enqueueRdbWrite(async (): Promise<void> => {
        if (revision !== CustomProfilesSettings.mutationRevision) {
          return
        }
        if (await CustomProfilesRepository.hasPersistedState(context)) {
          return
        }
        if (revision !== CustomProfilesSettings.mutationRevision) {
          return
        }
        await CustomProfilesRepository.replaceAll(context, snapshot, selected)
      })
    } catch (error) {
      DiagnosticLogger.warn('settings', 'custom_profiles_migrate_failed', (error as Error).message)
      // Keep the only legacy copy intact. A later startup can retry once the RDB write succeeds.
      return
    }
    if (revision !== CustomProfilesSettings.mutationRevision) {
      return
    }
    await CustomProfilesSettings.deleteLegacyPreferences(context)
  }

  private static async deleteLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.deleteSync(StorageKeys.HOME_CUSTOM_PROFILES)
    store.deleteSync(StorageKeys.HOME_CUSTOM_PROFILES_SELECTED)
    store.flushSync()
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

  private static snapshotProfiles(profiles: CustomProfile[]): CustomProfile[] {
    const out: CustomProfile[] = []
    profiles.forEach((profile: CustomProfile) => {
      out.push(profile.copy())
    })
    return out
  }

  /** Keep later writes runnable after a failed RDB operation. */
  private static enqueueRdbWrite(work: () => Promise<void>): Promise<void> {
    return CustomProfilesSettings.rdbWriteScheduler.enqueue(work)
  }

  /** Avoid replacing a newer in-memory tab mutation with an older RDB snapshot after backup restore. */
  private static async refreshFromStorage(context: common.UIAbilityContext): Promise<void> {
    for (let attempt: number = 0; attempt < 2; attempt++) {
      await CustomProfilesSettings.rdbWriteScheduler.flush()
      const revision: number = CustomProfilesSettings.mutationRevision
      const profiles: CustomProfile[] = await CustomProfilesRepository.loadProfiles(context)
      const selectedUuid: string = await CustomProfilesRepository.loadSelected(context)
      if (revision === CustomProfilesSettings.mutationRevision) {
        const state: CustomProfilesState = connectCustomProfiles()
        state.profiles = profiles
        state.selectedUuid = selectedUuid
        return
      }
    }
  }

  private static now(): number {
    return new Date().getTime()
  }

  private static nextEditTime(current: number): number {
    const observed: number = Number.isFinite(current) ? Math.floor(current) : 0
    return Math.max(CustomProfilesSettings.now(), observed + 1)
  }
}

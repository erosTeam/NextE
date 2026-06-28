import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import {
  CustomProfile,
  isValidProfileType,
  PROFILE_DISPLAY_GLOBAL,
  PROFILE_TYPE_GALLERY,
} from '../model/CustomProfile'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const SQL_SELECT_PROFILES: string =
  'SELECT profile_uuid AS uuid, name, list_type, search_text, selected_cats, advanced_enabled, min_rating, ' +
  'pages_from, pages_to, require_torrent, show_expunged, disable_language_filter, ' +
  'disable_uploader_filter, disable_tag_filter, favcat, toplist_tl, display_mode, hidden, ' +
  'builtin, last_edit_time FROM custom_profiles WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY position_index ASC, profile_uuid ASC'
const SQL_UPSERT_PROFILE: string =
  'INSERT INTO custom_profiles ' +
  '(scope_key, profile_uuid, position_index, name, list_type, search_text, selected_cats, advanced_enabled, ' +
  'min_rating, pages_from, pages_to, require_torrent, show_expunged, disable_language_filter, ' +
  'disable_uploader_filter, disable_tag_filter, favcat, toplist_tl, display_mode, hidden, builtin, ' +
  'last_edit_time, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0) ' +
  'ON CONFLICT(scope_key, profile_uuid) DO UPDATE SET position_index = excluded.position_index, name = excluded.name, ' +
  'list_type = excluded.list_type, search_text = excluded.search_text, selected_cats = excluded.selected_cats, ' +
  'advanced_enabled = excluded.advanced_enabled, min_rating = excluded.min_rating, pages_from = excluded.pages_from, ' +
  'pages_to = excluded.pages_to, require_torrent = excluded.require_torrent, show_expunged = excluded.show_expunged, ' +
  'disable_language_filter = excluded.disable_language_filter, disable_uploader_filter = excluded.disable_uploader_filter, ' +
  'disable_tag_filter = excluded.disable_tag_filter, favcat = excluded.favcat, toplist_tl = excluded.toplist_tl, ' +
  'display_mode = excluded.display_mode, hidden = excluded.hidden, builtin = excluded.builtin, ' +
  'last_edit_time = excluded.last_edit_time, deleted_at = 0'
const SQL_TOMBSTONE_PROFILES: string =
  'UPDATE custom_profiles SET deleted_at = ? WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_SELECT_SELECTED: string =
  'SELECT selected_uuid FROM custom_profile_selection WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPSERT_SELECTED: string =
  'INSERT INTO custom_profile_selection (scope_key, selected_uuid, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, 0) ON CONFLICT(scope_key) DO UPDATE SET selected_uuid = excluded.selected_uuid, ' +
  'updated_at = excluded.updated_at, deleted_at = 0'

export class CustomProfilesRepository {
  static async loadProfiles(context: common.UIAbilityContext): Promise<CustomProfile[]> {
    const out: CustomProfile[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_PROFILES, [SCOPE_GLOBAL])
    try {
      while (resultSet.goToNextRow()) {
        const profile: CustomProfile = CustomProfilesRepository.readProfile(resultSet)
        if (profile.uuid.length > 0) {
          out.push(profile)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async loadSelected(context: common.UIAbilityContext): Promise<string> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_SELECTED, [SCOPE_GLOBAL])
    try {
      if (resultSet.goToNextRow()) {
        return CustomProfilesRepository.stringColumn(resultSet, 'selected_uuid')
      }
    } finally {
      resultSet.close()
    }
    return ''
  }

  static async replaceAll(
    context: common.UIAbilityContext,
    profiles: CustomProfile[],
    selectedUuid: string,
  ): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_TOMBSTONE_PROFILES, [Date.now(), SCOPE_GLOBAL])
    for (let i: number = 0; i < profiles.length; i++) {
      await CustomProfilesRepository.upsertProfile(store, profiles[i], i)
    }
    await CustomProfilesRepository.saveSelectedWithStore(store, selectedUuid)
  }

  static async saveSelected(context: common.UIAbilityContext, selectedUuid: string): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await CustomProfilesRepository.saveSelectedWithStore(store, selectedUuid)
  }

  private static async upsertProfile(
    store: relationalStore.RdbStore,
    profile: CustomProfile,
    index: number,
  ): Promise<void> {
    if (profile.uuid.length === 0) {
      return
    }
    await store.executeSql(SQL_UPSERT_PROFILE, [
      SCOPE_GLOBAL,
      profile.uuid,
      index,
      profile.name,
      profile.listType,
      profile.searchText,
      profile.selectedCats,
      profile.advancedEnabled ? 1 : 0,
      profile.minRating,
      profile.pagesFrom,
      profile.pagesTo,
      profile.requireTorrent ? 1 : 0,
      profile.showExpunged ? 1 : 0,
      profile.disableLanguageFilter ? 1 : 0,
      profile.disableUploaderFilter ? 1 : 0,
      profile.disableTagFilter ? 1 : 0,
      profile.favcat,
      profile.toplistTl,
      profile.displayMode,
      profile.hidden ? 1 : 0,
      profile.builtin ? 1 : 0,
      profile.lastEditTime,
    ])
  }

  private static async saveSelectedWithStore(
    store: relationalStore.RdbStore,
    selectedUuid: string,
  ): Promise<void> {
    await store.executeSql(SQL_UPSERT_SELECTED, [SCOPE_GLOBAL, selectedUuid, Date.now()])
  }

  private static readProfile(resultSet: relationalStore.ResultSet): CustomProfile {
    const p: CustomProfile = new CustomProfile()
    p.uuid = CustomProfilesRepository.stringColumn(resultSet, 'uuid')
    p.name = CustomProfilesRepository.stringColumn(resultSet, 'name')
    const listType: string = CustomProfilesRepository.stringColumn(resultSet, 'list_type')
    p.listType = isValidProfileType(listType) ? listType : PROFILE_TYPE_GALLERY
    p.searchText = CustomProfilesRepository.stringColumn(resultSet, 'search_text')
    p.selectedCats = Math.floor(CustomProfilesRepository.numberColumn(resultSet, 'selected_cats'))
    p.advancedEnabled = CustomProfilesRepository.numberColumn(resultSet, 'advanced_enabled') > 0
    p.minRating = Math.floor(CustomProfilesRepository.numberColumn(resultSet, 'min_rating'))
    p.pagesFrom = Math.floor(CustomProfilesRepository.numberColumn(resultSet, 'pages_from'))
    p.pagesTo = Math.floor(CustomProfilesRepository.numberColumn(resultSet, 'pages_to'))
    p.requireTorrent = CustomProfilesRepository.numberColumn(resultSet, 'require_torrent') > 0
    p.showExpunged = CustomProfilesRepository.numberColumn(resultSet, 'show_expunged') > 0
    p.disableLanguageFilter = CustomProfilesRepository.numberColumn(resultSet, 'disable_language_filter') > 0
    p.disableUploaderFilter = CustomProfilesRepository.numberColumn(resultSet, 'disable_uploader_filter') > 0
    p.disableTagFilter = CustomProfilesRepository.numberColumn(resultSet, 'disable_tag_filter') > 0
    p.favcat = CustomProfilesRepository.stringColumn(resultSet, 'favcat')
    p.toplistTl = Math.floor(CustomProfilesRepository.numberColumn(resultSet, 'toplist_tl'))
    p.displayMode = CustomProfilesRepository.stringColumn(resultSet, 'display_mode')
    if (p.displayMode.length === 0) {
      p.displayMode = PROFILE_DISPLAY_GLOBAL
    }
    p.hidden = CustomProfilesRepository.numberColumn(resultSet, 'hidden') > 0
    p.builtin = CustomProfilesRepository.numberColumn(resultSet, 'builtin') > 0
    p.lastEditTime = Math.floor(CustomProfilesRepository.numberColumn(resultSet, 'last_edit_time'))
    return p
  }

  private static stringColumn(resultSet: relationalStore.ResultSet, name: string): string {
    const index: number = resultSet.getColumnIndex(name)
    return resultSet.isColumnNull(index) ? '' : resultSet.getString(index)
  }

  private static numberColumn(resultSet: relationalStore.ResultSet, name: string): number {
    const index: number = resultSet.getColumnIndex(name)
    return resultSet.isColumnNull(index) ? 0 : resultSet.getDouble(index)
  }
}

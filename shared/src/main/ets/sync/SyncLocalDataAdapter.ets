import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { LocalDataStore } from '../storage/LocalDataStore'
import {
  PROFILE_TYPE_GALLERY,
  STARTER_ANTHOLOGY_UUID,
  STARTER_CHINESE_UUID,
} from '../model/CustomProfile'
import {
  SYNC_APP_ID,
  SYNC_MAGIC,
  SYNC_MIN_SUPPORTED_SCHEMA_VERSION,
  SYNC_SCHEMA_VERSION,
  SyncCustomProfileRecord,
  SyncCustomProfileSelectionRecord,
  SyncDatasetSelection,
  SyncDatasets,
  SyncEnvelopeV1,
  SyncLocalBlockRuleRecord,
  SyncLocalBlockSettingsRecord,
  SyncLocalFavoriteRecord,
  SyncReadProgressRecord,
  SyncSearchHistoryRecord,
  SyncViewedHistoryRecord,
} from './SyncTypes'

const SQL_SELECT_READ_PROGRESS: string =
  'SELECT scope_key, gid, page_index, updated_at, deleted_at FROM gallery_read_progress'
const SQL_SELECT_VIEWED_HISTORY: string =
  'SELECT scope_key, gid, token, title, title_jp, thumb_url, category, uploader, rating, file_count, viewed_at, deleted_at FROM viewed_history'
const SQL_SELECT_LOCAL_FAVORITES: string =
  'SELECT scope_key, gid, token, url, thumb_url, thumb_url_l, img_width, img_height, english_title, japanese_title, category, uploader, post_time, file_count, rating, rating_fallback, color_rating, fav_note, fav_title, expunged, last_view_time, deleted_at FROM local_favorites'
const SQL_SELECT_SEARCH_HISTORY: string =
  'SELECT scope_key, query_text, position_index, updated_at, deleted_at FROM search_history'
const SQL_SELECT_LOCAL_BLOCK_SETTINGS: string =
  'SELECT scope_key, filter_comments_by_score, score_filtering_threshold, comment_display_mode, updated_at, deleted_at FROM local_block_settings'
const SQL_SELECT_LOCAL_BLOCK_RULES: string =
  'SELECT scope_key, rule_id, position_index, block_type, rule_text, enabled, enable_regex, updated_at, deleted_at FROM local_block_rules'
const SQL_SELECT_CUSTOM_PROFILES: string =
  'SELECT scope_key, profile_uuid AS uuid, position_index, name, list_type, search_text, selected_cats, advanced_enabled, min_rating, pages_from, pages_to, require_torrent, show_expunged, disable_language_filter, disable_uploader_filter, disable_tag_filter, favcat, toplist_tl, display_mode, hidden, builtin, last_edit_time, deleted_at FROM custom_profiles'
const SQL_SELECT_CUSTOM_PROFILE_SELECTION: string =
  'SELECT scope_key, selected_uuid, updated_at, deleted_at FROM custom_profile_selection'

const SQL_APPLY_READ_PROGRESS: string =
  'INSERT INTO gallery_read_progress (scope_key, gid, page_index, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?) ' +
  'ON CONFLICT(scope_key, gid) DO UPDATE SET page_index = excluded.page_index, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at'
const SQL_APPLY_VIEWED_HISTORY: string =
  'INSERT INTO viewed_history (scope_key, gid, token, title, title_jp, thumb_url, category, uploader, rating, file_count, viewed_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ' +
  'ON CONFLICT(scope_key, gid) DO UPDATE SET token = excluded.token, title = excluded.title, title_jp = excluded.title_jp, thumb_url = excluded.thumb_url, category = excluded.category, uploader = excluded.uploader, rating = excluded.rating, file_count = excluded.file_count, viewed_at = excluded.viewed_at, deleted_at = excluded.deleted_at'
const SQL_APPLY_LOCAL_FAVORITE: string =
  'INSERT INTO local_favorites (scope_key, gid, token, url, thumb_url, thumb_url_l, img_width, img_height, english_title, japanese_title, category, uploader, post_time, file_count, rating, rating_fallback, color_rating, fav_note, fav_title, expunged, last_view_time, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ' +
  'ON CONFLICT(scope_key, gid) DO UPDATE SET token = excluded.token, url = excluded.url, thumb_url = excluded.thumb_url, thumb_url_l = excluded.thumb_url_l, img_width = excluded.img_width, img_height = excluded.img_height, english_title = excluded.english_title, japanese_title = excluded.japanese_title, category = excluded.category, uploader = excluded.uploader, post_time = excluded.post_time, file_count = excluded.file_count, rating = excluded.rating, rating_fallback = excluded.rating_fallback, color_rating = excluded.color_rating, fav_note = excluded.fav_note, fav_title = excluded.fav_title, expunged = excluded.expunged, last_view_time = excluded.last_view_time, deleted_at = excluded.deleted_at'
const SQL_APPLY_SEARCH_HISTORY: string =
  'INSERT INTO search_history (scope_key, query_text, position_index, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?) ' +
  'ON CONFLICT(scope_key, query_text) DO UPDATE SET position_index = excluded.position_index, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at'
const SQL_APPLY_LOCAL_BLOCK_SETTINGS: string =
  'INSERT INTO local_block_settings (scope_key, filter_comments_by_score, score_filtering_threshold, comment_display_mode, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?) ' +
  'ON CONFLICT(scope_key) DO UPDATE SET filter_comments_by_score = excluded.filter_comments_by_score, score_filtering_threshold = excluded.score_filtering_threshold, comment_display_mode = excluded.comment_display_mode, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at'
const SQL_APPLY_LOCAL_BLOCK_RULE: string =
  'INSERT INTO local_block_rules (scope_key, rule_id, position_index, block_type, rule_text, enabled, enable_regex, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ' +
  'ON CONFLICT(scope_key, rule_id) DO UPDATE SET position_index = excluded.position_index, block_type = excluded.block_type, rule_text = excluded.rule_text, enabled = excluded.enabled, enable_regex = excluded.enable_regex, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at'
const SQL_APPLY_CUSTOM_PROFILE: string =
  'INSERT INTO custom_profiles (scope_key, profile_uuid, position_index, name, list_type, search_text, selected_cats, advanced_enabled, min_rating, pages_from, pages_to, require_torrent, show_expunged, disable_language_filter, disable_uploader_filter, disable_tag_filter, favcat, toplist_tl, display_mode, hidden, builtin, last_edit_time, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ' +
  'ON CONFLICT(scope_key, profile_uuid) DO UPDATE SET position_index = excluded.position_index, name = excluded.name, list_type = excluded.list_type, search_text = excluded.search_text, selected_cats = excluded.selected_cats, advanced_enabled = excluded.advanced_enabled, min_rating = excluded.min_rating, pages_from = excluded.pages_from, pages_to = excluded.pages_to, require_torrent = excluded.require_torrent, show_expunged = excluded.show_expunged, disable_language_filter = excluded.disable_language_filter, disable_uploader_filter = excluded.disable_uploader_filter, disable_tag_filter = excluded.disable_tag_filter, favcat = excluded.favcat, toplist_tl = excluded.toplist_tl, display_mode = excluded.display_mode, hidden = excluded.hidden, builtin = excluded.builtin, last_edit_time = excluded.last_edit_time, deleted_at = excluded.deleted_at'
const SQL_APPLY_CUSTOM_PROFILE_SELECTION: string =
  'INSERT INTO custom_profile_selection (scope_key, selected_uuid, updated_at, deleted_at) VALUES (?, ?, ?, ?) ' +
  'ON CONFLICT(scope_key) DO UPDATE SET selected_uuid = excluded.selected_uuid, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at'

export class SyncLocalDataAdapter {
  static async exportEnvelope(
    context: common.UIAbilityContext,
    deviceId: string = '',
    selection: SyncDatasetSelection = new SyncDatasetSelection(),
  ): Promise<SyncEnvelopeV1> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const envelope: SyncEnvelopeV1 = new SyncEnvelopeV1()
    envelope.generatedAt = new Date().toISOString()
    envelope.deviceId = deviceId
    if (selection.readProgress) {
      envelope.datasets.readProgress = await SyncLocalDataAdapter.readProgress(store)
    }
    if (selection.viewedHistory) {
      envelope.datasets.viewedHistory = await SyncLocalDataAdapter.readViewedHistory(store)
    }
    if (selection.localFavorites) {
      envelope.datasets.localFavorites = await SyncLocalDataAdapter.readLocalFavorites(store)
    }
    if (selection.searchHistory) {
      envelope.datasets.searchHistory = await SyncLocalDataAdapter.readSearchHistory(store)
    }
    if (selection.localBlock) {
      envelope.datasets.localBlockSettings = await SyncLocalDataAdapter.readLocalBlockSettings(store)
      envelope.datasets.localBlockRules = await SyncLocalDataAdapter.readLocalBlockRules(store)
    }
    if (selection.customProfiles) {
      envelope.datasets.customProfiles = await SyncLocalDataAdapter.readCustomProfiles(store)
      envelope.datasets.customProfileSelection =
        await SyncLocalDataAdapter.readCustomProfileSelection(store)
    }
    return envelope
  }

  static async applyEnvelope(context: common.UIAbilityContext, envelope: SyncEnvelopeV1): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      await SyncLocalDataAdapter.applyReadProgress(store, envelope.datasets.readProgress)
      await SyncLocalDataAdapter.applyViewedHistory(store, envelope.datasets.viewedHistory)
      await SyncLocalDataAdapter.applyLocalFavorites(store, envelope.datasets.localFavorites)
      await SyncLocalDataAdapter.applySearchHistory(store, envelope.datasets.searchHistory)
      await SyncLocalDataAdapter.applyLocalBlockSettings(store, envelope.datasets.localBlockSettings)
      await SyncLocalDataAdapter.applyLocalBlockRules(store, envelope.datasets.localBlockRules)
      await SyncLocalDataAdapter.applyCustomProfiles(store, envelope.datasets.customProfiles)
      await SyncLocalDataAdapter.applyCustomProfileSelection(
        store,
        envelope.datasets.customProfileSelection,
      )
      store.commit()
    } catch (error) {
      store.rollBack()
      const e: Error = error as Error
      throw new Error(e.message || 'Failed to apply sync envelope')
    }
  }

  static mergeEnvelopes(local: SyncEnvelopeV1, remote: SyncEnvelopeV1): SyncEnvelopeV1 {
    const merged: SyncEnvelopeV1 = new SyncEnvelopeV1()
    merged.generatedAt = new Date().toISOString()
    merged.datasets.readProgress =
      SyncLocalDataAdapter.mergeReadProgress(local.datasets.readProgress, remote.datasets.readProgress)
    merged.datasets.viewedHistory =
      SyncLocalDataAdapter.mergeViewedHistory(local.datasets.viewedHistory, remote.datasets.viewedHistory)
    merged.datasets.localFavorites =
      SyncLocalDataAdapter.mergeLocalFavorites(local.datasets.localFavorites, remote.datasets.localFavorites)
    merged.datasets.searchHistory =
      SyncLocalDataAdapter.mergeSearchHistory(local.datasets.searchHistory, remote.datasets.searchHistory)
    merged.datasets.localBlockSettings =
      SyncLocalDataAdapter.mergeLocalBlockSettings(local.datasets.localBlockSettings, remote.datasets.localBlockSettings)
    merged.datasets.localBlockRules =
      SyncLocalDataAdapter.mergeLocalBlockRules(local.datasets.localBlockRules, remote.datasets.localBlockRules)
    merged.datasets.customProfiles =
      SyncLocalDataAdapter.mergeCustomProfiles(local.datasets.customProfiles, remote.datasets.customProfiles)
    merged.datasets.customProfileSelection =
      SyncLocalDataAdapter.mergeCustomProfileSelection(
        local.datasets.customProfileSelection,
        remote.datasets.customProfileSelection,
      )
    return merged
  }

  static mergeSelectedIntoRemote(
    remote: SyncEnvelopeV1,
    selectedMerged: SyncEnvelopeV1,
    selection: SyncDatasetSelection,
    deviceId: string = '',
  ): SyncEnvelopeV1 {
    const out: SyncEnvelopeV1 = new SyncEnvelopeV1()
    out.generatedAt = new Date().toISOString()
    out.deviceId = deviceId
    out.datasets.readProgress = selection.readProgress ?
      selectedMerged.datasets.readProgress : remote.datasets.readProgress
    out.datasets.viewedHistory = selection.viewedHistory ?
      selectedMerged.datasets.viewedHistory : remote.datasets.viewedHistory
    out.datasets.localFavorites = selection.localFavorites ?
      selectedMerged.datasets.localFavorites : remote.datasets.localFavorites
    out.datasets.searchHistory = selection.searchHistory ?
      selectedMerged.datasets.searchHistory : remote.datasets.searchHistory
    out.datasets.localBlockSettings = selection.localBlock ?
      selectedMerged.datasets.localBlockSettings : remote.datasets.localBlockSettings
    out.datasets.localBlockRules = selection.localBlock ?
      selectedMerged.datasets.localBlockRules : remote.datasets.localBlockRules
    out.datasets.customProfiles = selection.customProfiles ?
      selectedMerged.datasets.customProfiles : remote.datasets.customProfiles
    out.datasets.customProfileSelection = selection.customProfiles ?
      selectedMerged.datasets.customProfileSelection : remote.datasets.customProfileSelection
    return out
  }

  static validateEnvelope(envelope: SyncEnvelopeV1): boolean {
    return envelope.magic === SYNC_MAGIC &&
      envelope.appId === SYNC_APP_ID &&
      envelope.schemaVersion === SYNC_SCHEMA_VERSION &&
      envelope.minSupportedSchemaVersion <= SYNC_SCHEMA_VERSION &&
      envelope.datasets !== null
  }

  private static async readProgress(store: relationalStore.RdbStore): Promise<SyncReadProgressRecord[]> {
    const out: SyncReadProgressRecord[] = []
    const rs: relationalStore.ResultSet = await store.querySql(SQL_SELECT_READ_PROGRESS)
    try {
      while (rs.goToNextRow()) {
        const r: SyncReadProgressRecord = new SyncReadProgressRecord()
        r.scopeKey = SyncLocalDataAdapter.stringColumn(rs, 'scope_key')
        r.gid = SyncLocalDataAdapter.stringColumn(rs, 'gid')
        r.pageIndex = SyncLocalDataAdapter.numberColumn(rs, 'page_index')
        r.updatedAt = SyncLocalDataAdapter.numberColumn(rs, 'updated_at')
        r.deletedAt = SyncLocalDataAdapter.numberColumn(rs, 'deleted_at')
        if (r.scopeKey.length > 0 && r.gid.length > 0) {
          out.push(r)
        }
      }
    } finally {
      rs.close()
    }
    return out
  }

  private static async readViewedHistory(store: relationalStore.RdbStore): Promise<SyncViewedHistoryRecord[]> {
    const out: SyncViewedHistoryRecord[] = []
    const rs: relationalStore.ResultSet = await store.querySql(SQL_SELECT_VIEWED_HISTORY)
    try {
      while (rs.goToNextRow()) {
        const r: SyncViewedHistoryRecord = new SyncViewedHistoryRecord()
        r.scopeKey = SyncLocalDataAdapter.stringColumn(rs, 'scope_key')
        r.gid = SyncLocalDataAdapter.stringColumn(rs, 'gid')
        r.token = SyncLocalDataAdapter.stringColumn(rs, 'token')
        r.title = SyncLocalDataAdapter.stringColumn(rs, 'title')
        r.titleJp = SyncLocalDataAdapter.stringColumn(rs, 'title_jp')
        r.thumbUrl = SyncLocalDataAdapter.stringColumn(rs, 'thumb_url')
        r.category = SyncLocalDataAdapter.stringColumn(rs, 'category')
        r.uploader = SyncLocalDataAdapter.stringColumn(rs, 'uploader')
        r.rating = SyncLocalDataAdapter.numberColumn(rs, 'rating')
        r.fileCount = SyncLocalDataAdapter.stringColumn(rs, 'file_count')
        r.viewedAt = SyncLocalDataAdapter.numberColumn(rs, 'viewed_at')
        r.deletedAt = SyncLocalDataAdapter.numberColumn(rs, 'deleted_at')
        if (r.scopeKey.length > 0 && r.gid.length > 0) {
          out.push(r)
        }
      }
    } finally {
      rs.close()
    }
    return out
  }

  private static async readLocalFavorites(store: relationalStore.RdbStore): Promise<SyncLocalFavoriteRecord[]> {
    const out: SyncLocalFavoriteRecord[] = []
    const rs: relationalStore.ResultSet = await store.querySql(SQL_SELECT_LOCAL_FAVORITES)
    try {
      while (rs.goToNextRow()) {
        const r: SyncLocalFavoriteRecord = new SyncLocalFavoriteRecord()
        r.scopeKey = SyncLocalDataAdapter.stringColumn(rs, 'scope_key')
        r.gid = SyncLocalDataAdapter.stringColumn(rs, 'gid')
        r.token = SyncLocalDataAdapter.stringColumn(rs, 'token')
        r.url = SyncLocalDataAdapter.stringColumn(rs, 'url')
        r.thumbUrl = SyncLocalDataAdapter.stringColumn(rs, 'thumb_url')
        r.thumbUrlL = SyncLocalDataAdapter.stringColumn(rs, 'thumb_url_l')
        r.imgWidth = SyncLocalDataAdapter.numberColumn(rs, 'img_width')
        r.imgHeight = SyncLocalDataAdapter.numberColumn(rs, 'img_height')
        r.englishTitle = SyncLocalDataAdapter.stringColumn(rs, 'english_title')
        r.japaneseTitle = SyncLocalDataAdapter.stringColumn(rs, 'japanese_title')
        r.category = SyncLocalDataAdapter.stringColumn(rs, 'category')
        r.uploader = SyncLocalDataAdapter.stringColumn(rs, 'uploader')
        r.postTime = SyncLocalDataAdapter.stringColumn(rs, 'post_time')
        r.fileCount = SyncLocalDataAdapter.stringColumn(rs, 'file_count')
        r.rating = SyncLocalDataAdapter.numberColumn(rs, 'rating')
        r.ratingFallback = SyncLocalDataAdapter.numberColumn(rs, 'rating_fallback')
        r.colorRating = SyncLocalDataAdapter.stringColumn(rs, 'color_rating')
        r.favNote = SyncLocalDataAdapter.stringColumn(rs, 'fav_note')
        r.favTitle = SyncLocalDataAdapter.stringColumn(rs, 'fav_title')
        r.expunged = SyncLocalDataAdapter.numberColumn(rs, 'expunged') > 0
        r.lastViewTime = SyncLocalDataAdapter.numberColumn(rs, 'last_view_time')
        r.deletedAt = SyncLocalDataAdapter.numberColumn(rs, 'deleted_at')
        if (r.scopeKey.length > 0 && r.gid.length > 0) {
          out.push(r)
        }
      }
    } finally {
      rs.close()
    }
    return out
  }

  private static async readSearchHistory(store: relationalStore.RdbStore): Promise<SyncSearchHistoryRecord[]> {
    const out: SyncSearchHistoryRecord[] = []
    const rs: relationalStore.ResultSet = await store.querySql(SQL_SELECT_SEARCH_HISTORY)
    try {
      while (rs.goToNextRow()) {
        const r: SyncSearchHistoryRecord = new SyncSearchHistoryRecord()
        r.scopeKey = SyncLocalDataAdapter.stringColumn(rs, 'scope_key')
        r.queryText = SyncLocalDataAdapter.stringColumn(rs, 'query_text')
        r.positionIndex = SyncLocalDataAdapter.numberColumn(rs, 'position_index')
        r.updatedAt = SyncLocalDataAdapter.numberColumn(rs, 'updated_at')
        r.deletedAt = SyncLocalDataAdapter.numberColumn(rs, 'deleted_at')
        if (r.scopeKey.length > 0 && r.queryText.length > 0) {
          out.push(r)
        }
      }
    } finally {
      rs.close()
    }
    return out
  }

  private static async readLocalBlockSettings(store: relationalStore.RdbStore): Promise<SyncLocalBlockSettingsRecord[]> {
    const out: SyncLocalBlockSettingsRecord[] = []
    const rs: relationalStore.ResultSet = await store.querySql(SQL_SELECT_LOCAL_BLOCK_SETTINGS)
    try {
      while (rs.goToNextRow()) {
        const r: SyncLocalBlockSettingsRecord = new SyncLocalBlockSettingsRecord()
        r.scopeKey = SyncLocalDataAdapter.stringColumn(rs, 'scope_key')
        r.filterCommentsByScore = SyncLocalDataAdapter.numberColumn(rs, 'filter_comments_by_score') > 0
        r.scoreFilteringThreshold = SyncLocalDataAdapter.numberColumn(rs, 'score_filtering_threshold')
        r.commentDisplayMode = SyncLocalDataAdapter.stringColumn(rs, 'comment_display_mode')
        r.updatedAt = SyncLocalDataAdapter.numberColumn(rs, 'updated_at')
        r.deletedAt = SyncLocalDataAdapter.numberColumn(rs, 'deleted_at')
        if (r.scopeKey.length > 0) {
          out.push(r)
        }
      }
    } finally {
      rs.close()
    }
    return out
  }

  private static async readLocalBlockRules(store: relationalStore.RdbStore): Promise<SyncLocalBlockRuleRecord[]> {
    const out: SyncLocalBlockRuleRecord[] = []
    const rs: relationalStore.ResultSet = await store.querySql(SQL_SELECT_LOCAL_BLOCK_RULES)
    try {
      while (rs.goToNextRow()) {
        const r: SyncLocalBlockRuleRecord = new SyncLocalBlockRuleRecord()
        r.scopeKey = SyncLocalDataAdapter.stringColumn(rs, 'scope_key')
        r.ruleId = SyncLocalDataAdapter.stringColumn(rs, 'rule_id')
        r.positionIndex = SyncLocalDataAdapter.numberColumn(rs, 'position_index')
        r.blockType = SyncLocalDataAdapter.stringColumn(rs, 'block_type')
        r.ruleText = SyncLocalDataAdapter.stringColumn(rs, 'rule_text')
        r.enabled = SyncLocalDataAdapter.numberColumn(rs, 'enabled') > 0
        r.enableRegex = SyncLocalDataAdapter.numberColumn(rs, 'enable_regex') > 0
        r.updatedAt = SyncLocalDataAdapter.numberColumn(rs, 'updated_at')
        r.deletedAt = SyncLocalDataAdapter.numberColumn(rs, 'deleted_at')
        if (r.scopeKey.length > 0 && r.ruleId.length > 0) {
          out.push(r)
        }
      }
    } finally {
      rs.close()
    }
    return out
  }

  private static async readCustomProfiles(store: relationalStore.RdbStore): Promise<SyncCustomProfileRecord[]> {
    const out: SyncCustomProfileRecord[] = []
    const rs: relationalStore.ResultSet = await store.querySql(SQL_SELECT_CUSTOM_PROFILES)
    try {
      while (rs.goToNextRow()) {
        const r: SyncCustomProfileRecord = new SyncCustomProfileRecord()
        r.scopeKey = SyncLocalDataAdapter.stringColumn(rs, 'scope_key')
        r.uuid = SyncLocalDataAdapter.stringColumn(rs, 'uuid')
        r.positionIndex = SyncLocalDataAdapter.numberColumn(rs, 'position_index')
        r.name = SyncLocalDataAdapter.stringColumn(rs, 'name')
        r.listType = SyncLocalDataAdapter.stringColumn(rs, 'list_type')
        r.searchText = SyncLocalDataAdapter.stringColumn(rs, 'search_text')
        r.selectedCats = SyncLocalDataAdapter.numberColumn(rs, 'selected_cats')
        r.advancedEnabled = SyncLocalDataAdapter.numberColumn(rs, 'advanced_enabled') > 0
        r.minRating = SyncLocalDataAdapter.numberColumn(rs, 'min_rating')
        r.pagesFrom = SyncLocalDataAdapter.numberColumn(rs, 'pages_from')
        r.pagesTo = SyncLocalDataAdapter.numberColumn(rs, 'pages_to')
        r.requireTorrent = SyncLocalDataAdapter.numberColumn(rs, 'require_torrent') > 0
        r.showExpunged = SyncLocalDataAdapter.numberColumn(rs, 'show_expunged') > 0
        r.disableLanguageFilter = SyncLocalDataAdapter.numberColumn(rs, 'disable_language_filter') > 0
        r.disableUploaderFilter = SyncLocalDataAdapter.numberColumn(rs, 'disable_uploader_filter') > 0
        r.disableTagFilter = SyncLocalDataAdapter.numberColumn(rs, 'disable_tag_filter') > 0
        r.favcat = SyncLocalDataAdapter.stringColumn(rs, 'favcat')
        r.toplistTl = SyncLocalDataAdapter.numberColumn(rs, 'toplist_tl')
        r.displayMode = SyncLocalDataAdapter.stringColumn(rs, 'display_mode')
        r.hidden = SyncLocalDataAdapter.numberColumn(rs, 'hidden') > 0
        r.builtin = SyncLocalDataAdapter.numberColumn(rs, 'builtin') > 0
        r.lastEditTime = SyncLocalDataAdapter.numberColumn(rs, 'last_edit_time')
        r.deletedAt = SyncLocalDataAdapter.numberColumn(rs, 'deleted_at')
        if (r.scopeKey.length > 0 && r.uuid.length > 0) {
          out.push(r)
        }
      }
    } finally {
      rs.close()
    }
    return out
  }

  private static async readCustomProfileSelection(store: relationalStore.RdbStore): Promise<SyncCustomProfileSelectionRecord[]> {
    const out: SyncCustomProfileSelectionRecord[] = []
    const rs: relationalStore.ResultSet = await store.querySql(SQL_SELECT_CUSTOM_PROFILE_SELECTION)
    try {
      while (rs.goToNextRow()) {
        const r: SyncCustomProfileSelectionRecord = new SyncCustomProfileSelectionRecord()
        r.scopeKey = SyncLocalDataAdapter.stringColumn(rs, 'scope_key')
        r.selectedUuid = SyncLocalDataAdapter.stringColumn(rs, 'selected_uuid')
        r.updatedAt = SyncLocalDataAdapter.numberColumn(rs, 'updated_at')
        r.deletedAt = SyncLocalDataAdapter.numberColumn(rs, 'deleted_at')
        if (r.scopeKey.length > 0) {
          out.push(r)
        }
      }
    } finally {
      rs.close()
    }
    return out
  }

  private static async applyReadProgress(store: relationalStore.RdbStore, records: SyncReadProgressRecord[]): Promise<void> {
    for (let i: number = 0; i < records.length; i++) {
      const r: SyncReadProgressRecord = records[i]
      if (r.scopeKey.length > 0 && r.gid.length > 0) {
        await store.executeSql(SQL_APPLY_READ_PROGRESS, [r.scopeKey, r.gid, r.pageIndex, r.updatedAt, r.deletedAt])
      }
    }
  }

  private static async applyViewedHistory(store: relationalStore.RdbStore, records: SyncViewedHistoryRecord[]): Promise<void> {
    for (let i: number = 0; i < records.length; i++) {
      const r: SyncViewedHistoryRecord = records[i]
      if (r.scopeKey.length > 0 && r.gid.length > 0) {
        await store.executeSql(SQL_APPLY_VIEWED_HISTORY, [
          r.scopeKey, r.gid, r.token, r.title, r.titleJp, r.thumbUrl, r.category, r.uploader,
          r.rating, r.fileCount, r.viewedAt, r.deletedAt,
        ])
      }
    }
  }

  private static async applyLocalFavorites(store: relationalStore.RdbStore, records: SyncLocalFavoriteRecord[]): Promise<void> {
    for (let i: number = 0; i < records.length; i++) {
      const r: SyncLocalFavoriteRecord = records[i]
      if (r.scopeKey.length > 0 && r.gid.length > 0) {
        await store.executeSql(SQL_APPLY_LOCAL_FAVORITE, [
          r.scopeKey, r.gid, r.token, r.url, r.thumbUrl, r.thumbUrlL, r.imgWidth, r.imgHeight,
          r.englishTitle, r.japaneseTitle, r.category, r.uploader, r.postTime, r.fileCount,
          r.rating, r.ratingFallback, r.colorRating, r.favNote, r.favTitle, r.expunged ? 1 : 0,
          r.lastViewTime, r.deletedAt,
        ])
      }
    }
  }

  private static async applySearchHistory(store: relationalStore.RdbStore, records: SyncSearchHistoryRecord[]): Promise<void> {
    for (let i: number = 0; i < records.length; i++) {
      const r: SyncSearchHistoryRecord = records[i]
      if (r.scopeKey.length > 0 && r.queryText.length > 0) {
        await store.executeSql(SQL_APPLY_SEARCH_HISTORY, [
          r.scopeKey, r.queryText, r.positionIndex, r.updatedAt, r.deletedAt,
        ])
      }
    }
  }

  private static async applyLocalBlockSettings(store: relationalStore.RdbStore, records: SyncLocalBlockSettingsRecord[]): Promise<void> {
    for (let i: number = 0; i < records.length; i++) {
      const r: SyncLocalBlockSettingsRecord = records[i]
      if (r.scopeKey.length > 0) {
        await store.executeSql(SQL_APPLY_LOCAL_BLOCK_SETTINGS, [
          r.scopeKey, r.filterCommentsByScore ? 1 : 0, r.scoreFilteringThreshold,
          r.commentDisplayMode, r.updatedAt, r.deletedAt,
        ])
      }
    }
  }

  private static async applyLocalBlockRules(store: relationalStore.RdbStore, records: SyncLocalBlockRuleRecord[]): Promise<void> {
    for (let i: number = 0; i < records.length; i++) {
      const r: SyncLocalBlockRuleRecord = records[i]
      if (r.scopeKey.length > 0 && r.ruleId.length > 0) {
        await store.executeSql(SQL_APPLY_LOCAL_BLOCK_RULE, [
          r.scopeKey, r.ruleId, r.positionIndex, r.blockType, r.ruleText, r.enabled ? 1 : 0,
          r.enableRegex ? 1 : 0, r.updatedAt, r.deletedAt,
        ])
      }
    }
  }

  private static async applyCustomProfiles(store: relationalStore.RdbStore, records: SyncCustomProfileRecord[]): Promise<void> {
    for (let i: number = 0; i < records.length; i++) {
      const r: SyncCustomProfileRecord = records[i]
      if (r.scopeKey.length > 0 && r.uuid.length > 0) {
        await store.executeSql(SQL_APPLY_CUSTOM_PROFILE, [
          r.scopeKey, r.uuid, r.positionIndex, r.name, r.listType, r.searchText, r.selectedCats,
          r.advancedEnabled ? 1 : 0, r.minRating, r.pagesFrom, r.pagesTo, r.requireTorrent ? 1 : 0,
          r.showExpunged ? 1 : 0, r.disableLanguageFilter ? 1 : 0, r.disableUploaderFilter ? 1 : 0,
          r.disableTagFilter ? 1 : 0, r.favcat, r.toplistTl, r.displayMode, r.hidden ? 1 : 0,
          r.builtin ? 1 : 0, r.lastEditTime, r.deletedAt,
        ])
      }
    }
  }

  private static async applyCustomProfileSelection(store: relationalStore.RdbStore, records: SyncCustomProfileSelectionRecord[]): Promise<void> {
    for (let i: number = 0; i < records.length; i++) {
      const r: SyncCustomProfileSelectionRecord = records[i]
      if (r.scopeKey.length > 0) {
        await store.executeSql(SQL_APPLY_CUSTOM_PROFILE_SELECTION, [
          r.scopeKey, r.selectedUuid, r.updatedAt, r.deletedAt,
        ])
      }
    }
  }

  private static mergeReadProgress(a: SyncReadProgressRecord[], b: SyncReadProgressRecord[]): SyncReadProgressRecord[] {
    const map: Map<string, SyncReadProgressRecord> = new Map<string, SyncReadProgressRecord>()
    a.forEach((r: SyncReadProgressRecord) => SyncLocalDataAdapter.keepReadProgress(map, r))
    b.forEach((r: SyncReadProgressRecord) => SyncLocalDataAdapter.keepReadProgress(map, r))
    const out: SyncReadProgressRecord[] = []
    map.forEach((r: SyncReadProgressRecord) => out.push(r))
    return out
  }

  private static keepReadProgress(map: Map<string, SyncReadProgressRecord>, r: SyncReadProgressRecord): void {
    const key: string = r.scopeKey + ':' + r.gid
    const prev: SyncReadProgressRecord | undefined = map.get(key)
    if (prev === undefined || SyncLocalDataAdapter.effectiveTime(r.updatedAt, r.deletedAt) >= SyncLocalDataAdapter.effectiveTime(prev.updatedAt, prev.deletedAt)) {
      map.set(key, r)
    }
  }

  private static mergeViewedHistory(a: SyncViewedHistoryRecord[], b: SyncViewedHistoryRecord[]): SyncViewedHistoryRecord[] {
    const map: Map<string, SyncViewedHistoryRecord> = new Map<string, SyncViewedHistoryRecord>()
    a.forEach((r: SyncViewedHistoryRecord) => SyncLocalDataAdapter.keepViewedHistory(map, r))
    b.forEach((r: SyncViewedHistoryRecord) => SyncLocalDataAdapter.keepViewedHistory(map, r))
    const out: SyncViewedHistoryRecord[] = []
    map.forEach((r: SyncViewedHistoryRecord) => out.push(r))
    return out
  }

  private static keepViewedHistory(map: Map<string, SyncViewedHistoryRecord>, r: SyncViewedHistoryRecord): void {
    const key: string = r.scopeKey + ':' + r.gid
    const prev: SyncViewedHistoryRecord | undefined = map.get(key)
    if (prev === undefined || SyncLocalDataAdapter.effectiveTime(r.viewedAt, r.deletedAt) >= SyncLocalDataAdapter.effectiveTime(prev.viewedAt, prev.deletedAt)) {
      map.set(key, r)
    }
  }

  private static mergeLocalFavorites(a: SyncLocalFavoriteRecord[], b: SyncLocalFavoriteRecord[]): SyncLocalFavoriteRecord[] {
    const map: Map<string, SyncLocalFavoriteRecord> = new Map<string, SyncLocalFavoriteRecord>()
    a.forEach((r: SyncLocalFavoriteRecord) => SyncLocalDataAdapter.keepLocalFavorite(map, r))
    b.forEach((r: SyncLocalFavoriteRecord) => SyncLocalDataAdapter.keepLocalFavorite(map, r))
    const out: SyncLocalFavoriteRecord[] = []
    map.forEach((r: SyncLocalFavoriteRecord) => out.push(r))
    return out
  }

  private static keepLocalFavorite(map: Map<string, SyncLocalFavoriteRecord>, r: SyncLocalFavoriteRecord): void {
    const key: string = r.scopeKey + ':' + r.gid
    const prev: SyncLocalFavoriteRecord | undefined = map.get(key)
    if (prev === undefined || SyncLocalDataAdapter.effectiveTime(r.lastViewTime, r.deletedAt) >= SyncLocalDataAdapter.effectiveTime(prev.lastViewTime, prev.deletedAt)) {
      map.set(key, r)
    }
  }

  private static mergeSearchHistory(a: SyncSearchHistoryRecord[], b: SyncSearchHistoryRecord[]): SyncSearchHistoryRecord[] {
    const map: Map<string, SyncSearchHistoryRecord> = new Map<string, SyncSearchHistoryRecord>()
    a.forEach((r: SyncSearchHistoryRecord) => SyncLocalDataAdapter.keepSearchHistory(map, r))
    b.forEach((r: SyncSearchHistoryRecord) => SyncLocalDataAdapter.keepSearchHistory(map, r))
    const out: SyncSearchHistoryRecord[] = []
    map.forEach((r: SyncSearchHistoryRecord) => out.push(r))
    return out
  }

  private static keepSearchHistory(map: Map<string, SyncSearchHistoryRecord>, r: SyncSearchHistoryRecord): void {
    const key: string = r.scopeKey + ':' + r.queryText
    const prev: SyncSearchHistoryRecord | undefined = map.get(key)
    if (prev === undefined || SyncLocalDataAdapter.effectiveTime(r.updatedAt, r.deletedAt) >= SyncLocalDataAdapter.effectiveTime(prev.updatedAt, prev.deletedAt)) {
      map.set(key, r)
    }
  }

  private static mergeLocalBlockSettings(a: SyncLocalBlockSettingsRecord[], b: SyncLocalBlockSettingsRecord[]): SyncLocalBlockSettingsRecord[] {
    const map: Map<string, SyncLocalBlockSettingsRecord> = new Map<string, SyncLocalBlockSettingsRecord>()
    a.forEach((r: SyncLocalBlockSettingsRecord) => SyncLocalDataAdapter.keepLocalBlockSettings(map, r))
    b.forEach((r: SyncLocalBlockSettingsRecord) => SyncLocalDataAdapter.keepLocalBlockSettings(map, r))
    const out: SyncLocalBlockSettingsRecord[] = []
    map.forEach((r: SyncLocalBlockSettingsRecord) => out.push(r))
    return out
  }

  private static keepLocalBlockSettings(map: Map<string, SyncLocalBlockSettingsRecord>, r: SyncLocalBlockSettingsRecord): void {
    const prev: SyncLocalBlockSettingsRecord | undefined = map.get(r.scopeKey)
    if (prev === undefined || SyncLocalDataAdapter.effectiveTime(r.updatedAt, r.deletedAt) >= SyncLocalDataAdapter.effectiveTime(prev.updatedAt, prev.deletedAt)) {
      map.set(r.scopeKey, r)
    }
  }

  private static mergeLocalBlockRules(a: SyncLocalBlockRuleRecord[], b: SyncLocalBlockRuleRecord[]): SyncLocalBlockRuleRecord[] {
    const map: Map<string, SyncLocalBlockRuleRecord> = new Map<string, SyncLocalBlockRuleRecord>()
    a.forEach((r: SyncLocalBlockRuleRecord) => SyncLocalDataAdapter.keepLocalBlockRule(map, r))
    b.forEach((r: SyncLocalBlockRuleRecord) => SyncLocalDataAdapter.keepLocalBlockRule(map, r))
    const out: SyncLocalBlockRuleRecord[] = []
    map.forEach((r: SyncLocalBlockRuleRecord) => out.push(r))
    return out
  }

  private static keepLocalBlockRule(map: Map<string, SyncLocalBlockRuleRecord>, r: SyncLocalBlockRuleRecord): void {
    const key: string = r.scopeKey + ':' + r.ruleId
    const prev: SyncLocalBlockRuleRecord | undefined = map.get(key)
    if (prev === undefined || SyncLocalDataAdapter.effectiveTime(r.updatedAt, r.deletedAt) >= SyncLocalDataAdapter.effectiveTime(prev.updatedAt, prev.deletedAt)) {
      map.set(key, r)
    }
  }

  private static mergeCustomProfiles(a: SyncCustomProfileRecord[], b: SyncCustomProfileRecord[]): SyncCustomProfileRecord[] {
    const map: Map<string, SyncCustomProfileRecord> = new Map<string, SyncCustomProfileRecord>()
    a.forEach((r: SyncCustomProfileRecord) => SyncLocalDataAdapter.keepCustomProfile(map, r))
    b.forEach((r: SyncCustomProfileRecord) => SyncLocalDataAdapter.keepCustomProfile(map, r))
    const out: SyncCustomProfileRecord[] = []
    map.forEach((r: SyncCustomProfileRecord) => out.push(r))
    return out
  }

  private static keepCustomProfile(map: Map<string, SyncCustomProfileRecord>, r: SyncCustomProfileRecord): void {
    const normalized: SyncCustomProfileRecord = SyncLocalDataAdapter.normalizeCustomProfileRecord(r)
    const key: string = normalized.scopeKey + ':' + normalized.uuid
    const prev: SyncCustomProfileRecord | undefined = map.get(key)
    if (prev === undefined || SyncLocalDataAdapter.effectiveTime(normalized.lastEditTime, normalized.deletedAt) >= SyncLocalDataAdapter.effectiveTime(prev.lastEditTime, prev.deletedAt)) {
      map.set(key, normalized)
    }
  }

  private static normalizeCustomProfileRecord(r: SyncCustomProfileRecord): SyncCustomProfileRecord {
    const canonicalUuid: string = SyncLocalDataAdapter.canonicalStarterUuid(r)
    if (canonicalUuid.length === 0 || r.uuid === canonicalUuid) {
      return r
    }
    const copy: SyncCustomProfileRecord = new SyncCustomProfileRecord()
    copy.scopeKey = r.scopeKey
    copy.uuid = canonicalUuid
    copy.positionIndex = r.positionIndex
    copy.name = r.name
    copy.listType = r.listType
    copy.searchText = r.searchText
    copy.selectedCats = r.selectedCats
    copy.advancedEnabled = r.advancedEnabled
    copy.minRating = r.minRating
    copy.pagesFrom = r.pagesFrom
    copy.pagesTo = r.pagesTo
    copy.requireTorrent = r.requireTorrent
    copy.showExpunged = r.showExpunged
    copy.disableLanguageFilter = r.disableLanguageFilter
    copy.disableUploaderFilter = r.disableUploaderFilter
    copy.disableTagFilter = r.disableTagFilter
    copy.favcat = r.favcat
    copy.toplistTl = r.toplistTl
    copy.displayMode = r.displayMode
    copy.hidden = r.hidden
    copy.builtin = r.builtin
    copy.lastEditTime = r.lastEditTime
    copy.deletedAt = r.deletedAt
    return copy
  }

  private static canonicalStarterUuid(r: SyncCustomProfileRecord): string {
    if (r.listType !== PROFILE_TYPE_GALLERY) {
      return ''
    }
    if (r.searchText === 'language:chinese') {
      return STARTER_CHINESE_UUID
    }
    if (r.searchText === 'other:anthology') {
      return STARTER_ANTHOLOGY_UUID
    }
    return ''
  }

  private static mergeCustomProfileSelection(a: SyncCustomProfileSelectionRecord[], b: SyncCustomProfileSelectionRecord[]): SyncCustomProfileSelectionRecord[] {
    const map: Map<string, SyncCustomProfileSelectionRecord> = new Map<string, SyncCustomProfileSelectionRecord>()
    a.forEach((r: SyncCustomProfileSelectionRecord) => SyncLocalDataAdapter.keepCustomProfileSelection(map, r))
    b.forEach((r: SyncCustomProfileSelectionRecord) => SyncLocalDataAdapter.keepCustomProfileSelection(map, r))
    const out: SyncCustomProfileSelectionRecord[] = []
    map.forEach((r: SyncCustomProfileSelectionRecord) => out.push(r))
    return out
  }

  private static keepCustomProfileSelection(map: Map<string, SyncCustomProfileSelectionRecord>, r: SyncCustomProfileSelectionRecord): void {
    const prev: SyncCustomProfileSelectionRecord | undefined = map.get(r.scopeKey)
    if (prev === undefined || SyncLocalDataAdapter.effectiveTime(r.updatedAt, r.deletedAt) >= SyncLocalDataAdapter.effectiveTime(prev.updatedAt, prev.deletedAt)) {
      map.set(r.scopeKey, r)
    }
  }

  private static effectiveTime(updatedAt: number, deletedAt: number): number {
    return Math.max(Math.floor(updatedAt), Math.floor(deletedAt))
  }

  private static stringColumn(rs: relationalStore.ResultSet, name: string): string {
    const index: number = rs.getColumnIndex(name)
    return rs.isColumnNull(index) ? '' : rs.getString(index)
  }

  private static numberColumn(rs: relationalStore.ResultSet, name: string): number {
    const index: number = rs.getColumnIndex(name)
    return rs.isColumnNull(index) ? 0 : Math.floor(rs.getDouble(index))
  }
}

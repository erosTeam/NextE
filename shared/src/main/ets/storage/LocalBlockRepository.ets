import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import {
  LOCAL_BLOCK_COMMENT_DISPLAY_HIDE,
  LOCAL_BLOCK_TYPE_TITLE,
} from '../state/LocalBlockState'
import { LocalDataStore } from './LocalDataStore'

export class LocalBlockRuleSnapshot {
  id: string = ''
  blockType: string = LOCAL_BLOCK_TYPE_TITLE
  ruleText: string = ''
  enabled: boolean = true
  enableRegex: boolean = false
}

export class LocalBlockSettingsSnapshot {
  filterCommentsByScore: boolean = false
  scoreFilteringThreshold: number = -20
  commentDisplayMode: string = LOCAL_BLOCK_COMMENT_DISPLAY_HIDE
  rules: LocalBlockRuleSnapshot[] = []
}

const SCOPE_GLOBAL: string = 'global'
const SQL_SELECT_SETTINGS: string =
  'SELECT filter_comments_by_score, score_filtering_threshold, comment_display_mode FROM local_block_settings ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_SELECT_RULES: string =
  'SELECT rule_id, block_type, rule_text, enabled, enable_regex FROM local_block_rules ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ORDER BY position_index ASC, rule_id ASC'
const SQL_UPSERT_SETTINGS: string =
  'INSERT INTO local_block_settings ' +
  '(scope_key, filter_comments_by_score, score_filtering_threshold, comment_display_mode, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key) DO UPDATE SET ' +
  'filter_comments_by_score = excluded.filter_comments_by_score, ' +
  'score_filtering_threshold = excluded.score_filtering_threshold, comment_display_mode = excluded.comment_display_mode, ' +
  'updated_at = excluded.updated_at, deleted_at = 0 WHERE excluded.updated_at >= ' +
  'CASE WHEN COALESCE(local_block_settings.deleted_at, 0) > COALESCE(local_block_settings.updated_at, 0) ' +
  'THEN COALESCE(local_block_settings.deleted_at, 0) ELSE COALESCE(local_block_settings.updated_at, 0) END'
const SQL_RESTORE_UPSERT_SETTINGS: string =
  'INSERT INTO local_block_settings ' +
  '(scope_key, filter_comments_by_score, score_filtering_threshold, comment_display_mode, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key) DO UPDATE SET ' +
  'filter_comments_by_score = excluded.filter_comments_by_score, ' +
  'score_filtering_threshold = excluded.score_filtering_threshold, ' +
  'comment_display_mode = excluded.comment_display_mode, updated_at = excluded.updated_at, deleted_at = 0'
const SQL_UPSERT_RULE: string =
  'INSERT INTO local_block_rules ' +
  '(scope_key, rule_id, position_index, block_type, rule_text, enabled, enable_regex, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, rule_id) DO UPDATE SET ' +
  'position_index = excluded.position_index, block_type = excluded.block_type, rule_text = excluded.rule_text, ' +
  'enabled = excluded.enabled, enable_regex = excluded.enable_regex, updated_at = excluded.updated_at, deleted_at = 0 ' +
  'WHERE excluded.updated_at >= CASE WHEN COALESCE(local_block_rules.deleted_at, 0) > ' +
  'COALESCE(local_block_rules.updated_at, 0) THEN COALESCE(local_block_rules.deleted_at, 0) ' +
  'ELSE COALESCE(local_block_rules.updated_at, 0) END'
const SQL_RESTORE_UPSERT_RULE: string =
  'INSERT INTO local_block_rules ' +
  '(scope_key, rule_id, position_index, block_type, rule_text, enabled, enable_regex, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, rule_id) DO UPDATE SET ' +
  'position_index = excluded.position_index, block_type = excluded.block_type, rule_text = excluded.rule_text, ' +
  'enabled = excluded.enabled, enable_regex = excluded.enable_regex, updated_at = excluded.updated_at, deleted_at = 0'
const SQL_TOMBSTONE_SETTINGS: string =
  'UPDATE local_block_settings SET deleted_at = ? ' +
  'WHERE scope_key = ?'
const SQL_TOMBSTONE_RULES: string =
  'UPDATE local_block_rules SET deleted_at = ? ' +
  'WHERE scope_key = ?'
const SQL_TOMBSTONE_RULE: string =
  'INSERT INTO local_block_rules (scope_key, rule_id, position_index, updated_at, deleted_at) VALUES (?, ?, 0, 0, ?) ' +
  'ON CONFLICT(scope_key, rule_id) DO UPDATE SET deleted_at = excluded.deleted_at WHERE excluded.deleted_at >= ' +
  'CASE WHEN COALESCE(local_block_rules.deleted_at, 0) > COALESCE(local_block_rules.updated_at, 0) ' +
  'THEN COALESCE(local_block_rules.deleted_at, 0) ELSE COALESCE(local_block_rules.updated_at, 0) END'
const SQL_SELECT_MAX_EFFECTIVE_TIME: string =
  'SELECT MAX(effective_at) AS effective_at FROM (' +
  'SELECT CASE WHEN COALESCE(deleted_at, 0) > COALESCE(updated_at, 0) THEN COALESCE(deleted_at, 0) ' +
  'ELSE COALESCE(updated_at, 0) END AS effective_at FROM local_block_settings WHERE scope_key = ? ' +
  'UNION ALL ' +
  'SELECT CASE WHEN COALESCE(deleted_at, 0) > COALESCE(updated_at, 0) THEN COALESCE(deleted_at, 0) ' +
  'ELSE COALESCE(updated_at, 0) END AS effective_at FROM local_block_rules WHERE scope_key = ?' +
  ')'
const SQL_SELECT_ACTIVE_RULE_POSITION: string =
  'SELECT position_index FROM local_block_rules WHERE scope_key = ? AND rule_id = ? ' +
  'AND COALESCE(deleted_at, 0) = 0'
const SQL_SELECT_MAX_RULE_POSITION: string =
  'SELECT MAX(COALESCE(position_index, 0)) AS max_position FROM local_block_rules ' +
  'WHERE scope_key = ?'
const SQL_HAS_PERSISTED_SETTINGS: string =
  'SELECT 1 AS has_state FROM local_block_settings WHERE scope_key = ? LIMIT 1'
const SQL_HAS_PERSISTED_RULES: string =
  'SELECT 1 AS has_state FROM local_block_rules WHERE scope_key = ? LIMIT 1'

export class LocalBlockRepository {
  /** Any row, including a tombstone, makes RDB the canonical source over a stale legacy JSON copy. */
  static async hasPersistedState(context: common.UIAbilityContext): Promise<boolean> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const settings: relationalStore.ResultSet = await store.querySql(SQL_HAS_PERSISTED_SETTINGS, [SCOPE_GLOBAL])
    try {
      if (settings.goToNextRow()) {
        return true
      }
    } finally {
      settings.close()
    }
    const rules: relationalStore.ResultSet = await store.querySql(SQL_HAS_PERSISTED_RULES, [SCOPE_GLOBAL])
    try {
      return rules.goToNextRow()
    } finally {
      rules.close()
    }
  }

  static async load(context: common.UIAbilityContext): Promise<LocalBlockSettingsSnapshot> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const snapshot: LocalBlockSettingsSnapshot = new LocalBlockSettingsSnapshot()
    const settings: relationalStore.ResultSet = await store.querySql(SQL_SELECT_SETTINGS, [SCOPE_GLOBAL])
    try {
      if (settings.goToNextRow()) {
        snapshot.filterCommentsByScore =
          LocalBlockRepository.numberColumn(settings, 'filter_comments_by_score') > 0
        snapshot.scoreFilteringThreshold =
          Math.floor(LocalBlockRepository.numberColumn(settings, 'score_filtering_threshold'))
        snapshot.commentDisplayMode = LocalBlockRepository.stringColumn(settings, 'comment_display_mode')
      }
    } finally {
      settings.close()
    }
    if (snapshot.commentDisplayMode.length === 0) {
      snapshot.commentDisplayMode = LOCAL_BLOCK_COMMENT_DISPLAY_HIDE
    }
    snapshot.rules = await LocalBlockRepository.loadRules(store)
    return snapshot
  }

  static async replaceAll(
    context: common.UIAbilityContext,
    snapshot: LocalBlockSettingsSnapshot,
  ): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      // Backup restore and legacy migration are intentionally authoritative snapshots. Rebase each
      // table past its active rows and tombstones so omitted values cannot reappear after sync.
      const replacedAt: number = await LocalBlockRepository.nextMutationTime(store, Date.now())
      await store.executeSql(SQL_TOMBSTONE_SETTINGS, [replacedAt, SCOPE_GLOBAL])
      await store.executeSql(SQL_TOMBSTONE_RULES, [replacedAt, SCOPE_GLOBAL])
      await LocalBlockRepository.writeSettings(
        store,
        snapshot,
        replacedAt + 1,
        SQL_RESTORE_UPSERT_SETTINGS,
      )
      for (let i: number = 0; i < snapshot.rules.length; i++) {
        const rule: LocalBlockRuleSnapshot = snapshot.rules[i]
        if (rule.ruleText.length === 0) {
          continue
        }
        await LocalBlockRepository.writeRule(
          store,
          rule,
          rule.id.length > 0 ? rule.id : `rule-${i}`,
          i,
          replacedAt + snapshot.rules.length + 1 - i,
          SQL_RESTORE_UPSERT_RULE,
        )
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Ordinary score/comment-mode changes write only the settings row. */
  static async upsertSettings(
    context: common.UIAbilityContext,
    snapshot: LocalBlockSettingsSnapshot,
  ): Promise<number> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      const updatedAt: number = await LocalBlockRepository.nextMutationTime(store, Date.now())
      await LocalBlockRepository.writeSettings(store, snapshot, updatedAt, SQL_UPSERT_SETTINGS)
      store.commit()
      return updatedAt
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Ordinary rule edits preserve an existing rule's order or append a new durable row. */
  static async upsertRule(
    context: common.UIAbilityContext,
    rule: LocalBlockRuleSnapshot,
  ): Promise<number> {
    if (rule.id.length === 0 || rule.ruleText.length === 0) {
      return 0
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      const updatedAt: number = await LocalBlockRepository.nextMutationTime(store, Date.now())
      const positionIndex: number = await LocalBlockRepository.positionForUpsert(store, rule.id)
      await LocalBlockRepository.writeRule(
        store,
        rule,
        rule.id,
        positionIndex,
        updatedAt,
        SQL_UPSERT_RULE,
      )
      store.commit()
      return updatedAt
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Persist a per-rule tombstone even when an older sync record is the only later arrival. */
  static async tombstoneRule(
    context: common.UIAbilityContext,
    ruleId: string,
    requestedTime: number = Date.now(),
  ): Promise<number> {
    if (ruleId.length === 0) {
      return 0
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      const deletedAt: number = await LocalBlockRepository.nextMutationTime(store, requestedTime)
      await store.executeSql(SQL_TOMBSTONE_RULE, [SCOPE_GLOBAL, ruleId, deletedAt])
      store.commit()
      return deletedAt
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  private static async nextMutationTime(
    store: relationalStore.RdbStore,
    requestedTime: number,
  ): Promise<number> {
    let latest: number = 0
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_MAX_EFFECTIVE_TIME, [
      SCOPE_GLOBAL,
      SCOPE_GLOBAL,
    ])
    try {
      if (resultSet.goToNextRow()) {
        const index: number = resultSet.getColumnIndex('effective_at')
        if (!resultSet.isColumnNull(index)) {
          latest = Math.max(0, Math.floor(resultSet.getDouble(index)))
        }
      }
    } finally {
      resultSet.close()
    }
    const requested: number = requestedTime > 0 ? Math.floor(requestedTime) : 0
    return Math.max(Date.now(), requested, latest + 1)
  }

  private static async positionForUpsert(
    store: relationalStore.RdbStore,
    ruleId: string,
  ): Promise<number> {
    const existing: relationalStore.ResultSet = await store.querySql(SQL_SELECT_ACTIVE_RULE_POSITION, [
      SCOPE_GLOBAL,
      ruleId,
    ])
    try {
      if (existing.goToNextRow()) {
        const index: number = existing.getColumnIndex('position_index')
        if (!existing.isColumnNull(index)) {
          return Math.floor(existing.getDouble(index))
        }
      }
    } finally {
      existing.close()
    }
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_MAX_RULE_POSITION, [
      SCOPE_GLOBAL,
    ])
    try {
      if (resultSet.goToNextRow()) {
        const index: number = resultSet.getColumnIndex('max_position')
        if (!resultSet.isColumnNull(index)) {
          return Math.floor(resultSet.getDouble(index)) + 1
        }
      }
    } finally {
      resultSet.close()
    }
    return 0
  }

  private static async writeSettings(
    store: relationalStore.RdbStore,
    snapshot: LocalBlockSettingsSnapshot,
    updatedAt: number,
    sql: string,
  ): Promise<void> {
    await store.executeSql(sql, [
      SCOPE_GLOBAL,
      snapshot.filterCommentsByScore ? 1 : 0,
      Math.floor(snapshot.scoreFilteringThreshold),
      snapshot.commentDisplayMode,
      updatedAt,
    ])
  }

  private static async writeRule(
    store: relationalStore.RdbStore,
    rule: LocalBlockRuleSnapshot,
    ruleId: string,
    positionIndex: number,
    updatedAt: number,
    sql: string,
  ): Promise<void> {
    await store.executeSql(sql, [
      SCOPE_GLOBAL,
      ruleId,
      positionIndex,
      rule.blockType,
      rule.ruleText,
      rule.enabled ? 1 : 0,
      rule.enableRegex ? 1 : 0,
      updatedAt,
    ])
  }

  private static async loadRules(store: relationalStore.RdbStore): Promise<LocalBlockRuleSnapshot[]> {
    const out: LocalBlockRuleSnapshot[] = []
    const rules: relationalStore.ResultSet = await store.querySql(SQL_SELECT_RULES, [SCOPE_GLOBAL])
    try {
      while (rules.goToNextRow()) {
        const rule: LocalBlockRuleSnapshot = new LocalBlockRuleSnapshot()
        rule.id = LocalBlockRepository.stringColumn(rules, 'rule_id')
        rule.blockType = LocalBlockRepository.stringColumn(rules, 'block_type')
        rule.ruleText = LocalBlockRepository.stringColumn(rules, 'rule_text')
        rule.enabled = LocalBlockRepository.numberColumn(rules, 'enabled') > 0
        rule.enableRegex = LocalBlockRepository.numberColumn(rules, 'enable_regex') > 0
        if (rule.ruleText.length > 0) {
          out.push(rule)
        }
      }
    } finally {
      rules.close()
    }
    return out
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

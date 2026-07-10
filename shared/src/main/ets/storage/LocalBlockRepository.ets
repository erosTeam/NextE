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
  'score_filtering_threshold = excluded.score_filtering_threshold, ' +
  'comment_display_mode = excluded.comment_display_mode, updated_at = excluded.updated_at, deleted_at = 0'
const SQL_UPSERT_RULE: string =
  'INSERT INTO local_block_rules ' +
  '(scope_key, rule_id, position_index, block_type, rule_text, enabled, enable_regex, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, rule_id) DO UPDATE SET ' +
  'position_index = excluded.position_index, block_type = excluded.block_type, rule_text = excluded.rule_text, ' +
  'enabled = excluded.enabled, enable_regex = excluded.enable_regex, updated_at = excluded.updated_at, deleted_at = 0'
const SQL_TOMBSTONE_SETTINGS: string =
  'UPDATE local_block_settings SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_TOMBSTONE_RULES: string =
  'UPDATE local_block_rules SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'

export class LocalBlockRepository {
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
    const now: number = Date.now()
    store.beginTransaction()
    try {
      await store.executeSql(SQL_TOMBSTONE_SETTINGS, [now, now, SCOPE_GLOBAL])
      await store.executeSql(SQL_TOMBSTONE_RULES, [now, now, SCOPE_GLOBAL])
      await store.executeSql(SQL_UPSERT_SETTINGS, [
        SCOPE_GLOBAL,
        snapshot.filterCommentsByScore ? 1 : 0,
        Math.floor(snapshot.scoreFilteringThreshold),
        snapshot.commentDisplayMode,
        now,
      ])
      for (let i: number = 0; i < snapshot.rules.length; i++) {
        const rule: LocalBlockRuleSnapshot = snapshot.rules[i]
        if (rule.ruleText.length === 0) {
          continue
        }
        await store.executeSql(SQL_UPSERT_RULE, [
          SCOPE_GLOBAL,
          rule.id.length > 0 ? rule.id : `rule-${i}`,
          i,
          rule.blockType,
          rule.ruleText,
          rule.enabled ? 1 : 0,
          rule.enableRegex ? 1 : 0,
          now + i + 1,
        ])
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
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

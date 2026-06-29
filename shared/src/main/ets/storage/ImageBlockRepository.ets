import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import {
  IMAGE_BLOCK_ALGORITHM_DCT64_V1,
  IMAGE_BLOCK_DEFAULT_THRESHOLD,
  IMAGE_BLOCK_SCOPE_WHOLE,
  IMAGE_BLOCK_SOURCE_LOCAL,
  IMAGE_BLOCK_SOURCE_SUBSCRIPTION,
  ImageBlockFeed,
  ImageBlockFeedItem,
  ImageBlockRule,
  ImageBlockWhitelistItem,
} from '../model/ImageBlockRule'
import { PHashService } from '../services/PHashService'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const SQL_SELECT_SUBSCRIPTIONS: string =
  'SELECT feed_id, title, url, algorithm, default_threshold, updated_at, synced_at, sha256, rule_count, enabled ' +
  'FROM image_block_subscriptions WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY feed_id ASC'
const SQL_SELECT_ENABLED_RULES: string =
  'SELECT r.rule_id, r.hash, ' +
  'CASE WHEN COALESCE(o.threshold_override, -1) >= 0 THEN o.threshold_override ELSE r.threshold END AS threshold, ' +
  'r.label, r.scope, r.feed_id, r.source_type, ' +
  'r.source_url, r.source_page, r.preview_path, r.enabled, r.updated_at, r.deleted_at ' +
  'FROM image_block_rules r LEFT JOIN image_block_subscriptions s ' +
  'ON s.scope_key = r.scope_key AND s.feed_id = r.feed_id AND COALESCE(s.deleted_at, 0) = 0 ' +
  'LEFT JOIN image_block_rule_overrides o ' +
  'ON o.scope_key = r.scope_key AND o.rule_id = r.rule_id AND COALESCE(o.deleted_at, 0) = 0 ' +
  'WHERE r.scope_key = ? AND r.enabled > 0 AND COALESCE(r.deleted_at, 0) = 0 ' +
  'AND (r.source_type <> ? OR COALESCE(s.enabled, 0) > 0) ' +
  'AND COALESCE(o.enabled_override, -1) <> 0 ' +
  'ORDER BY r.source_type ASC, r.feed_id ASC, r.rule_id ASC'
const SQL_SELECT_SUBSCRIPTION_RULES: string =
  'SELECT r.rule_id, r.hash, ' +
  'CASE WHEN COALESCE(o.threshold_override, -1) >= 0 THEN o.threshold_override ELSE r.threshold END AS threshold, ' +
  'r.label, r.scope, r.feed_id, r.source_type, r.source_url, r.source_page, r.preview_path, ' +
  'CASE WHEN COALESCE(o.enabled_override, -1) >= 0 THEN o.enabled_override ELSE r.enabled END AS enabled, ' +
  'r.updated_at, r.deleted_at ' +
  'FROM image_block_rules r LEFT JOIN image_block_rule_overrides o ' +
  'ON o.scope_key = r.scope_key AND o.rule_id = r.rule_id AND COALESCE(o.deleted_at, 0) = 0 ' +
  'WHERE r.scope_key = ? AND r.feed_id = ? AND r.source_type = ? AND COALESCE(r.deleted_at, 0) = 0 ' +
  'ORDER BY r.rule_id ASC'
const SQL_SELECT_WHITELIST: string =
  'SELECT hash FROM image_block_whitelist WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY hash ASC'
const SQL_SELECT_WHITELIST_ITEMS: string =
  'SELECT hash, preview_path, updated_at FROM image_block_whitelist ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ORDER BY updated_at DESC, hash ASC'
const SQL_SELECT_LOCAL_RULE_COUNT: string =
  'SELECT COUNT(*) AS rule_count FROM image_block_rules ' +
  'WHERE scope_key = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_SELECT_LOCAL_RULES: string =
  'SELECT rule_id, hash, threshold, label, scope, feed_id, source_type, source_url, source_page, ' +
  'preview_path, enabled, updated_at, deleted_at ' +
  'FROM image_block_rules ' +
  'WHERE scope_key = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY updated_at DESC, rule_id ASC'
const SQL_SELECT_FILE_HASH: string =
  'SELECT hash FROM image_block_hash_cache ' +
  'WHERE scope_key = ? AND file_path = ? AND bytes = ? AND algorithm = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPSERT_SUBSCRIPTION: string =
  'INSERT INTO image_block_subscriptions ' +
  '(scope_key, feed_id, title, url, algorithm, default_threshold, updated_at, synced_at, sha256, rule_count, enabled, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, feed_id) DO UPDATE SET ' +
  'title = excluded.title, url = excluded.url, algorithm = excluded.algorithm, ' +
  'default_threshold = excluded.default_threshold, updated_at = excluded.updated_at, ' +
  'synced_at = excluded.synced_at, sha256 = excluded.sha256, rule_count = excluded.rule_count, ' +
  'enabled = image_block_subscriptions.enabled, deleted_at = 0'
const SQL_UPSERT_RULE: string =
  'INSERT INTO image_block_rules ' +
  '(scope_key, rule_id, hash, threshold, label, scope, feed_id, source_type, source_url, source_page, preview_path, enabled, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, rule_id) DO UPDATE SET ' +
  'hash = excluded.hash, threshold = excluded.threshold, label = excluded.label, scope = excluded.scope, ' +
  'feed_id = excluded.feed_id, source_type = excluded.source_type, source_url = excluded.source_url, ' +
  'source_page = excluded.source_page, preview_path = excluded.preview_path, ' +
  'enabled = excluded.enabled, updated_at = excluded.updated_at, deleted_at = 0'
const SQL_TOMBSTONE_SUBSCRIPTION: string =
  'UPDATE image_block_subscriptions SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND feed_id = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_TOMBSTONE_SUBSCRIPTION_RULES: string =
  'UPDATE image_block_rules SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND feed_id = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_SET_SUBSCRIPTION_ENABLED: string =
  'UPDATE image_block_subscriptions SET enabled = ?, updated_at = ?, deleted_at = 0 ' +
  'WHERE scope_key = ? AND feed_id = ?'
const SQL_TOMBSTONE_LOCAL_RULE: string =
  'UPDATE image_block_rules SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPDATE_LOCAL_RULE_THRESHOLD: string =
  'UPDATE image_block_rules SET threshold = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPDATE_LOCAL_RULE_ENABLED: string =
  'UPDATE image_block_rules SET enabled = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_TOMBSTONE_WHITELIST: string =
  'UPDATE image_block_whitelist SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_TOMBSTONE_ONE_WHITELIST: string =
  'UPDATE image_block_whitelist SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND hash = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPSERT_WHITELIST: string =
  'INSERT INTO image_block_whitelist (scope_key, hash, preview_path, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, 0) ON CONFLICT(scope_key, hash) DO UPDATE SET ' +
  'preview_path = CASE WHEN excluded.preview_path <> \'\' THEN excluded.preview_path ELSE image_block_whitelist.preview_path END, ' +
  'updated_at = excluded.updated_at, deleted_at = 0'
const SQL_UPSERT_RULE_ENABLED_OVERRIDE: string =
  'INSERT INTO image_block_rule_overrides ' +
  '(scope_key, rule_id, hash, source_type, enabled_override, threshold_override, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, -1, ?, 0) ON CONFLICT(scope_key, rule_id) DO UPDATE SET ' +
  'hash = excluded.hash, source_type = excluded.source_type, ' +
  'enabled_override = excluded.enabled_override, updated_at = excluded.updated_at, deleted_at = 0'
const SQL_UPSERT_RULE_THRESHOLD_OVERRIDE: string =
  'INSERT INTO image_block_rule_overrides ' +
  '(scope_key, rule_id, hash, source_type, enabled_override, threshold_override, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, -1, ?, ?, 0) ON CONFLICT(scope_key, rule_id) DO UPDATE SET ' +
  'hash = excluded.hash, source_type = excluded.source_type, ' +
  'threshold_override = excluded.threshold_override, updated_at = excluded.updated_at, deleted_at = 0'
const SQL_UPSERT_FILE_HASH: string =
  'INSERT INTO image_block_hash_cache ' +
  '(scope_key, file_path, bytes, hash, algorithm, hashed_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, file_path) DO UPDATE SET ' +
  'bytes = excluded.bytes, hash = excluded.hash, algorithm = excluded.algorithm, ' +
  'hashed_at = excluded.hashed_at, deleted_at = 0'

export class ImageBlockRepository {
  static async loadSubscriptions(context: common.UIAbilityContext): Promise<ImageBlockFeed[]> {
    const out: ImageBlockFeed[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_SUBSCRIPTIONS, [SCOPE_GLOBAL])
    try {
      while (resultSet.goToNextRow()) {
        const feed: ImageBlockFeed = new ImageBlockFeed()
        feed.id = ImageBlockRepository.stringColumn(resultSet, 'feed_id')
        feed.title = ImageBlockRepository.stringColumn(resultSet, 'title')
        feed.url = ImageBlockRepository.stringColumn(resultSet, 'url')
        feed.algorithm = ImageBlockRepository.stringColumn(resultSet, 'algorithm')
        feed.defaultThreshold = PHashService.clampThreshold(
          Math.floor(ImageBlockRepository.numberColumn(resultSet, 'default_threshold')),
          IMAGE_BLOCK_DEFAULT_THRESHOLD,
        )
        feed.updatedAt = Math.floor(ImageBlockRepository.numberColumn(resultSet, 'updated_at'))
        feed.sha256 = ImageBlockRepository.stringColumn(resultSet, 'sha256')
        feed.count = Math.floor(ImageBlockRepository.numberColumn(resultSet, 'rule_count'))
        feed.enabled = Math.floor(ImageBlockRepository.numberColumn(resultSet, 'enabled')) > 0
        if (feed.id.length > 0) {
          out.push(feed)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async loadEnabledRules(context: common.UIAbilityContext): Promise<ImageBlockRule[]> {
    const out: ImageBlockRule[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_ENABLED_RULES, [
      SCOPE_GLOBAL,
      IMAGE_BLOCK_SOURCE_SUBSCRIPTION,
    ])
    try {
      while (resultSet.goToNextRow()) {
        const rule: ImageBlockRule = ImageBlockRepository.readRule(resultSet)
        if (rule.hash.length > 0) {
          out.push(rule)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async loadWhitelist(context: common.UIAbilityContext): Promise<string[]> {
    const out: string[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_WHITELIST, [SCOPE_GLOBAL])
    try {
      while (resultSet.goToNextRow()) {
        const hash: string = PHashService.normalizeHex64(ImageBlockRepository.stringColumn(resultSet, 'hash'))
        if (hash.length > 0) {
          out.push(hash)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async loadWhitelistItems(context: common.UIAbilityContext): Promise<ImageBlockWhitelistItem[]> {
    const out: ImageBlockWhitelistItem[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_WHITELIST_ITEMS, [SCOPE_GLOBAL])
    try {
      while (resultSet.goToNextRow()) {
        const item: ImageBlockWhitelistItem = new ImageBlockWhitelistItem()
        item.hash = PHashService.normalizeHex64(ImageBlockRepository.stringColumn(resultSet, 'hash'))
        item.previewPath = ImageBlockRepository.stringColumn(resultSet, 'preview_path')
        item.updatedAt = Math.floor(ImageBlockRepository.numberColumn(resultSet, 'updated_at'))
        if (item.hash.length > 0) {
          out.push(item)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async loadLocalRuleCount(context: common.UIAbilityContext): Promise<number> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_LOCAL_RULE_COUNT, [
      SCOPE_GLOBAL,
      IMAGE_BLOCK_SOURCE_LOCAL,
    ])
    try {
      if (resultSet.goToNextRow()) {
        return Math.floor(ImageBlockRepository.numberColumn(resultSet, 'rule_count'))
      }
    } finally {
      resultSet.close()
    }
    return 0
  }

  static async loadLocalRules(context: common.UIAbilityContext): Promise<ImageBlockRule[]> {
    const out: ImageBlockRule[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_LOCAL_RULES, [
      SCOPE_GLOBAL,
      IMAGE_BLOCK_SOURCE_LOCAL,
    ])
    try {
      while (resultSet.goToNextRow()) {
        const rule: ImageBlockRule = ImageBlockRepository.readRule(resultSet)
        if (rule.hash.length > 0) {
          out.push(rule)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async loadSubscriptionRules(
    context: common.UIAbilityContext,
    feedId: string,
  ): Promise<ImageBlockRule[]> {
    const out: ImageBlockRule[] = []
    if (feedId.length === 0) {
      return out
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_SUBSCRIPTION_RULES, [
      SCOPE_GLOBAL,
      feedId,
      IMAGE_BLOCK_SOURCE_SUBSCRIPTION,
    ])
    try {
      while (resultSet.goToNextRow()) {
        const rule: ImageBlockRule = ImageBlockRepository.readRule(resultSet)
        if (rule.hash.length > 0) {
          out.push(rule)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async loadCachedFileHash(
    context: common.UIAbilityContext,
    filePath: string,
    bytes: number,
  ): Promise<string> {
    if (filePath.length === 0 || bytes <= 0) {
      return ''
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_FILE_HASH, [
      SCOPE_GLOBAL,
      filePath,
      bytes,
      IMAGE_BLOCK_ALGORITHM_DCT64_V1,
    ])
    try {
      if (resultSet.goToNextRow()) {
        return PHashService.normalizeHex64(ImageBlockRepository.stringColumn(resultSet, 'hash'))
      }
    } finally {
      resultSet.close()
    }
    return ''
  }

  static async replaceSubscription(context: common.UIAbilityContext, feed: ImageBlockFeed): Promise<void> {
    if (feed.id.length === 0) {
      throw new Error('Image block feed id is required')
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const now: number = Date.now()
    store.beginTransaction()
    try {
      await store.executeSql(SQL_TOMBSTONE_SUBSCRIPTION, [now, now, SCOPE_GLOBAL, feed.id])
      await store.executeSql(SQL_TOMBSTONE_SUBSCRIPTION_RULES, [
        now,
        now,
        SCOPE_GLOBAL,
        feed.id,
        IMAGE_BLOCK_SOURCE_SUBSCRIPTION,
      ])
      await store.executeSql(SQL_UPSERT_SUBSCRIPTION, [
        SCOPE_GLOBAL,
        feed.id,
        feed.title,
        feed.url,
        feed.algorithm.length > 0 ? feed.algorithm : IMAGE_BLOCK_ALGORITHM_DCT64_V1,
        PHashService.clampThreshold(feed.defaultThreshold),
        feed.updatedAt,
        now,
        feed.sha256,
        feed.items.length,
        feed.enabled ? 1 : 0,
      ])
      for (let i: number = 0; i < feed.items.length; i++) {
        await ImageBlockRepository.upsertSubscriptionItem(store, feed, feed.items[i], now + i + 1)
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      const e: Error = error as Error
      throw new Error(e.message || 'Failed to replace image block subscription')
    }
  }

  static async setSubscriptionEnabled(
    context: common.UIAbilityContext,
    feedId: string,
    enabled: boolean,
  ): Promise<void> {
    if (feedId.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_SET_SUBSCRIPTION_ENABLED, [enabled ? 1 : 0, Date.now(), SCOPE_GLOBAL, feedId])
  }

  static async upsertLocalRule(context: common.UIAbilityContext, rule: ImageBlockRule): Promise<void> {
    const normalizedHash: string = PHashService.normalizeHex64(rule.hash)
    if (normalizedHash.length === 0) {
      throw new Error('Image block rule hash must be 16 hex characters')
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const now: number = Date.now()
    await store.executeSql(SQL_UPSERT_RULE, [
      SCOPE_GLOBAL,
      rule.id.length > 0 ? rule.id : 'local:' + normalizedHash,
      normalizedHash,
      PHashService.clampThreshold(rule.threshold),
      rule.label.length > 0 ? rule.label : 'local',
      rule.scope.length > 0 ? rule.scope : IMAGE_BLOCK_SCOPE_WHOLE,
      '',
      IMAGE_BLOCK_SOURCE_LOCAL,
      rule.sourceUrl,
      rule.sourcePage > 0 ? Math.floor(rule.sourcePage) : 0,
      rule.previewPath,
      rule.enabled ? 1 : 0,
      now,
    ])
  }

  static async removeLocalRule(context: common.UIAbilityContext, ruleId: string): Promise<void> {
    if (ruleId.length === 0) {
      return
    }
    const now: number = Date.now()
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_TOMBSTONE_LOCAL_RULE, [
      now,
      now,
      SCOPE_GLOBAL,
      ruleId,
      IMAGE_BLOCK_SOURCE_LOCAL,
    ])
  }

  static async setLocalRuleThreshold(
    context: common.UIAbilityContext,
    ruleId: string,
    threshold: number,
  ): Promise<void> {
    if (ruleId.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_UPDATE_LOCAL_RULE_THRESHOLD, [
      PHashService.clampThreshold(threshold),
      Date.now(),
      SCOPE_GLOBAL,
      ruleId,
      IMAGE_BLOCK_SOURCE_LOCAL,
    ])
  }

  static async setLocalRuleEnabled(
    context: common.UIAbilityContext,
    ruleId: string,
    enabled: boolean,
  ): Promise<void> {
    if (ruleId.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_UPDATE_LOCAL_RULE_ENABLED, [
      enabled ? 1 : 0,
      Date.now(),
      SCOPE_GLOBAL,
      ruleId,
      IMAGE_BLOCK_SOURCE_LOCAL,
    ])
  }

  static async replaceWhitelist(context: common.UIAbilityContext, hashes: string[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const now: number = Date.now()
    store.beginTransaction()
    try {
      await store.executeSql(SQL_TOMBSTONE_WHITELIST, [now, now, SCOPE_GLOBAL])
      for (let i: number = 0; i < hashes.length; i++) {
        const hash: string = PHashService.normalizeHex64(hashes[i])
        if (hash.length > 0) {
          await store.executeSql(SQL_UPSERT_WHITELIST, [SCOPE_GLOBAL, hash, '', now + i + 1])
        }
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      const e: Error = error as Error
      throw new Error(e.message || 'Failed to replace image block whitelist')
    }
  }

  static async upsertWhitelistHash(
    context: common.UIAbilityContext,
    hash: string,
    previewPath: string = '',
  ): Promise<string> {
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    if (normalizedHash.length === 0) {
      throw new Error('Image block whitelist hash must be 16 hex characters')
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_UPSERT_WHITELIST, [SCOPE_GLOBAL, normalizedHash, previewPath, Date.now()])
    return normalizedHash
  }

  static async ignoreRule(
    context: common.UIAbilityContext,
    ruleId: string,
    hash: string,
    sourceType: string,
  ): Promise<void> {
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    if (ruleId.length === 0 || normalizedHash.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_UPSERT_RULE_ENABLED_OVERRIDE, [
      SCOPE_GLOBAL,
      ruleId,
      normalizedHash,
      sourceType,
      0,
      Date.now(),
    ])
  }

  static async setRuleEnabledOverride(
    context: common.UIAbilityContext,
    ruleId: string,
    hash: string,
    sourceType: string,
    enabled: boolean,
  ): Promise<void> {
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    if (ruleId.length === 0 || normalizedHash.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_UPSERT_RULE_ENABLED_OVERRIDE, [
      SCOPE_GLOBAL,
      ruleId,
      normalizedHash,
      sourceType,
      enabled ? 1 : 0,
      Date.now(),
    ])
  }

  static async setRuleThresholdOverride(
    context: common.UIAbilityContext,
    ruleId: string,
    hash: string,
    sourceType: string,
    threshold: number,
  ): Promise<void> {
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    if (ruleId.length === 0 || normalizedHash.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_UPSERT_RULE_THRESHOLD_OVERRIDE, [
      SCOPE_GLOBAL,
      ruleId,
      normalizedHash,
      sourceType,
      PHashService.clampThreshold(threshold),
      Date.now(),
    ])
  }

  static async removeWhitelistHash(context: common.UIAbilityContext, hash: string): Promise<void> {
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    if (normalizedHash.length === 0) {
      return
    }
    const now: number = Date.now()
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_TOMBSTONE_ONE_WHITELIST, [
      now,
      now,
      SCOPE_GLOBAL,
      normalizedHash,
    ])
  }

  static async upsertFileHash(
    context: common.UIAbilityContext,
    filePath: string,
    bytes: number,
    hash: string,
  ): Promise<void> {
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    if (filePath.length === 0 || bytes <= 0 || normalizedHash.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_UPSERT_FILE_HASH, [
      SCOPE_GLOBAL,
      filePath,
      bytes,
      normalizedHash,
      IMAGE_BLOCK_ALGORITHM_DCT64_V1,
      Date.now(),
    ])
  }

  private static async upsertSubscriptionItem(
    store: relationalStore.RdbStore,
    feed: ImageBlockFeed,
    item: ImageBlockFeedItem,
    updatedAt: number,
  ): Promise<void> {
    const hash: string = PHashService.normalizeHex64(item.hash)
    if (hash.length === 0) {
      return
    }
    await store.executeSql(SQL_UPSERT_RULE, [
      SCOPE_GLOBAL,
      feed.id + ':' + hash,
      hash,
      PHashService.clampThreshold(item.threshold, feed.defaultThreshold),
      item.label.length > 0 ? item.label : 'scanlator-ad',
      item.scope.length > 0 ? item.scope : IMAGE_BLOCK_SCOPE_WHOLE,
      feed.id,
      IMAGE_BLOCK_SOURCE_SUBSCRIPTION,
      '',
      0,
      '',
      1,
      updatedAt,
    ])
  }

  private static readRule(resultSet: relationalStore.ResultSet): ImageBlockRule {
    const rule: ImageBlockRule = new ImageBlockRule()
    rule.id = ImageBlockRepository.stringColumn(resultSet, 'rule_id')
    rule.hash = PHashService.normalizeHex64(ImageBlockRepository.stringColumn(resultSet, 'hash'))
    rule.threshold = PHashService.clampThreshold(
      Math.floor(ImageBlockRepository.numberColumn(resultSet, 'threshold')),
      IMAGE_BLOCK_DEFAULT_THRESHOLD,
    )
    rule.label = ImageBlockRepository.stringColumn(resultSet, 'label')
    rule.scope = ImageBlockRepository.stringColumn(resultSet, 'scope')
    if (rule.scope.length === 0) {
      rule.scope = IMAGE_BLOCK_SCOPE_WHOLE
    }
    rule.feedId = ImageBlockRepository.stringColumn(resultSet, 'feed_id')
    rule.sourceType = ImageBlockRepository.stringColumn(resultSet, 'source_type')
    rule.sourceUrl = ImageBlockRepository.stringColumn(resultSet, 'source_url')
    rule.sourcePage = Math.floor(ImageBlockRepository.numberColumn(resultSet, 'source_page'))
    rule.previewPath = ImageBlockRepository.stringColumn(resultSet, 'preview_path')
    rule.enabled = Math.floor(ImageBlockRepository.numberColumn(resultSet, 'enabled')) > 0
    rule.updatedAt = Math.floor(ImageBlockRepository.numberColumn(resultSet, 'updated_at'))
    rule.deletedAt = Math.floor(ImageBlockRepository.numberColumn(resultSet, 'deleted_at'))
    return rule
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

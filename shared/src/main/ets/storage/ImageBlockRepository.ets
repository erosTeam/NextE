import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import {
  IMAGE_BLOCK_ALGORITHM_DCT64_V1,
  IMAGE_BLOCK_DEFAULT_THRESHOLD,
  IMAGE_BLOCK_SCOPE_WHOLE,
  IMAGE_BLOCK_SOURCE_ALLOW,
  IMAGE_BLOCK_SOURCE_LOCAL,
  IMAGE_BLOCK_SOURCE_SUBSCRIPTION,
  ImageBlockFeed,
  ImageBlockFeedItem,
  ImageBlockRule,
  ImageBlockWhitelistItem,
} from '../model/ImageBlockRule'
import { PHashService } from '../services/PHashService'
import { SyncScheduler } from '../sync/SyncScheduler'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const SQL_SELECT_SUBSCRIPTIONS: string =
  'SELECT feed_id, title, url, algorithm, default_threshold, updated_at, synced_at, sha256, rule_count, enabled ' +
  'FROM image_block_subscriptions WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY feed_id ASC'
const SQL_SELECT_ENABLED_RULES: string =
  'SELECT rule_id, hash, threshold, label, scope, feed_id, source_type, source_url, source_page, ' +
  'preview_path, enabled, updated_at, deleted_at FROM image_block_user_rules ' +
  'WHERE scope_key = ? AND enabled > 0 AND COALESCE(deleted_at, 0) = 0 ' +
  'AND COALESCE(source_type, \'\') <> ? ' +
  'UNION ALL SELECT r.rule_id, r.hash, ' +
  'CASE WHEN COALESCE(u.threshold, -1) >= 0 THEN u.threshold ELSE r.threshold END AS threshold, ' +
  'r.label, r.scope, r.feed_id, r.source_type, r.source_url, r.source_page, r.preview_path, ' +
  'CASE WHEN COALESCE(u.enabled, -1) >= 0 THEN u.enabled ELSE r.enabled END AS enabled, ' +
  'CASE WHEN COALESCE(u.updated_at, 0) > COALESCE(r.updated_at, 0) THEN u.updated_at ELSE r.updated_at END AS updated_at, ' +
  'CASE WHEN COALESCE(u.deleted_at, 0) > COALESCE(r.deleted_at, 0) THEN u.deleted_at ELSE r.deleted_at END AS deleted_at ' +
  'FROM image_block_rules r LEFT JOIN image_block_subscriptions s ' +
  'ON s.scope_key = r.scope_key AND s.feed_id = r.feed_id AND COALESCE(s.deleted_at, 0) = 0 ' +
  'LEFT JOIN image_block_user_rules u ON u.scope_key = r.scope_key AND u.rule_id = r.rule_id ' +
  'AND u.hash = r.hash AND u.source_type = r.source_type AND COALESCE(u.deleted_at, 0) = 0 ' +
  'WHERE r.scope_key = ? AND r.source_type = ? AND COALESCE(r.deleted_at, 0) = 0 ' +
  'AND COALESCE(s.enabled, 0) > 0 ' +
  'AND CASE WHEN COALESCE(u.enabled, -1) >= 0 THEN u.enabled ELSE r.enabled END > 0 ' +
  'ORDER BY source_type ASC, feed_id ASC, rule_id ASC'
const SQL_SELECT_SUBSCRIPTION_RULES: string =
  'SELECT r.rule_id, r.hash, ' +
  'CASE WHEN COALESCE(u.threshold, -1) >= 0 THEN u.threshold ELSE r.threshold END AS threshold, ' +
  'r.label, r.scope, r.feed_id, r.source_type, r.source_url, r.source_page, r.preview_path, ' +
  'CASE WHEN COALESCE(u.enabled, -1) >= 0 THEN u.enabled ELSE r.enabled END AS enabled, ' +
  'CASE WHEN COALESCE(u.updated_at, 0) > COALESCE(r.updated_at, 0) THEN u.updated_at ELSE r.updated_at END AS updated_at, ' +
  'CASE WHEN COALESCE(u.deleted_at, 0) > COALESCE(r.deleted_at, 0) THEN u.deleted_at ELSE r.deleted_at END AS deleted_at ' +
  'FROM image_block_rules r LEFT JOIN image_block_user_rules u ON u.scope_key = r.scope_key ' +
  'AND u.rule_id = r.rule_id AND u.hash = r.hash AND u.source_type = r.source_type ' +
  'AND COALESCE(u.deleted_at, 0) = 0 ' +
  'WHERE r.scope_key = ? AND r.feed_id = ? AND r.source_type = ? AND COALESCE(r.deleted_at, 0) = 0 ' +
  'ORDER BY r.rule_id ASC'
const SQL_SELECT_WHITELIST: string =
  'SELECT hash FROM image_block_user_rules WHERE scope_key = ? AND source_type = ? AND enabled > 0 ' +
  'AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY hash ASC'
const SQL_SELECT_WHITELIST_ITEMS: string =
  'SELECT hash, preview_path, updated_at FROM image_block_user_rules ' +
  'WHERE scope_key = ? AND source_type = ? AND enabled > 0 AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY updated_at DESC, hash ASC'
const SQL_SELECT_LOCAL_RULE_COUNT: string =
  'SELECT COUNT(*) AS rule_count FROM image_block_user_rules ' +
  'WHERE scope_key = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_SELECT_LOCAL_RULES: string =
  'SELECT rule_id, hash, threshold, label, scope, feed_id, source_type, source_url, source_page, ' +
  'preview_path, enabled, updated_at, deleted_at ' +
  'FROM image_block_user_rules ' +
  'WHERE scope_key = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY updated_at DESC, rule_id ASC'
const SQL_SELECT_FILE_HASH: string =
  'SELECT hash FROM image_block_hash_cache ' +
  'WHERE scope_key = ? AND file_path = ? AND bytes = ? AND algorithm = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_SELECT_FILE_HASH_BY_PATH: string =
  'SELECT hash FROM image_block_hash_cache ' +
  'WHERE scope_key = ? AND file_path = ? AND algorithm = ? AND COALESCE(deleted_at, 0) = 0'
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
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(rule_id, scope_key) DO UPDATE SET ' +
  'hash = excluded.hash, ' +
  'threshold = CASE WHEN image_block_rules.source_type = \'subscription\' THEN image_block_rules.threshold ELSE excluded.threshold END, ' +
  'label = excluded.label, scope = excluded.scope, ' +
  'feed_id = excluded.feed_id, source_type = excluded.source_type, source_url = excluded.source_url, ' +
  'source_page = excluded.source_page, ' +
  'preview_path = CASE WHEN excluded.preview_path <> \'\' THEN excluded.preview_path ELSE image_block_rules.preview_path END, ' +
  'enabled = CASE WHEN image_block_rules.source_type = \'subscription\' THEN image_block_rules.enabled ELSE excluded.enabled END, ' +
  'updated_at = excluded.updated_at, deleted_at = 0'
const SQL_UPDATE_RULE_PREVIEW: string =
  'UPDATE image_block_rules SET preview_path = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND COALESCE(deleted_at, 0) = 0 AND ? <> \'\''
const SQL_UPDATE_USER_RULE_PREVIEW: string =
  'UPDATE image_block_user_rules SET preview_path = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND COALESCE(deleted_at, 0) = 0 AND ? <> \'\''
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
  'UPDATE image_block_user_rules SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPDATE_LOCAL_RULE_THRESHOLD: string =
  'UPDATE image_block_user_rules SET threshold = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPDATE_LOCAL_RULE_ENABLED: string =
  'UPDATE image_block_user_rules SET enabled = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_TOMBSTONE_ALLOW_RULES: string =
  'UPDATE image_block_user_rules SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_TOMBSTONE_ONE_ALLOW_RULE: string =
  'UPDATE image_block_user_rules SET deleted_at = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND source_type = ? AND hash = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPDATE_RULE_ENABLED: string =
  'UPDATE image_block_rules SET enabled = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND hash = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPDATE_RULE_THRESHOLD: string =
  'UPDATE image_block_rules SET threshold = ?, updated_at = ? ' +
  'WHERE scope_key = ? AND rule_id = ? AND hash = ? AND source_type = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_UPSERT_FILE_HASH: string =
  'INSERT INTO image_block_hash_cache ' +
  '(scope_key, file_path, bytes, hash, algorithm, hashed_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, file_path) DO UPDATE SET ' +
  'bytes = excluded.bytes, hash = excluded.hash, algorithm = excluded.algorithm, ' +
  'hashed_at = excluded.hashed_at, deleted_at = 0'
const SQL_UPSERT_USER_RULE_OVERRIDE: string =
  'INSERT INTO image_block_user_rules ' +
  '(scope_key, rule_id, hash, threshold, label, scope, feed_id, source_type, source_url, source_page, preview_path, enabled, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, \'\', \'\', \'\', ?, \'\', 0, \'\', ?, ?, 0) ' +
  'ON CONFLICT(rule_id, scope_key) DO UPDATE SET ' +
  'hash = excluded.hash, source_type = excluded.source_type, ' +
  'threshold = CASE WHEN excluded.threshold >= 0 THEN excluded.threshold ELSE image_block_user_rules.threshold END, ' +
  'enabled = CASE WHEN excluded.enabled >= 0 THEN excluded.enabled ELSE image_block_user_rules.enabled END, ' +
  'updated_at = excluded.updated_at, deleted_at = 0'
const SQL_UPSERT_USER_RULE: string =
  'INSERT INTO image_block_user_rules ' +
  '(scope_key, rule_id, hash, threshold, label, scope, feed_id, source_type, source_url, source_page, preview_path, enabled, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(rule_id, scope_key) DO UPDATE SET ' +
  'hash = excluded.hash, threshold = excluded.threshold, label = excluded.label, scope = excluded.scope, ' +
  'feed_id = excluded.feed_id, source_type = excluded.source_type, source_url = excluded.source_url, ' +
  'source_page = excluded.source_page, ' +
  'preview_path = CASE WHEN excluded.preview_path <> \'\' THEN excluded.preview_path ELSE image_block_user_rules.preview_path END, ' +
  'enabled = excluded.enabled, updated_at = excluded.updated_at, deleted_at = 0'
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
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_WHITELIST, [
      SCOPE_GLOBAL,
      IMAGE_BLOCK_SOURCE_ALLOW,
    ])
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
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_WHITELIST_ITEMS, [
      SCOPE_GLOBAL,
      IMAGE_BLOCK_SOURCE_ALLOW,
    ])
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

  static async loadCachedFileHashByPath(
    context: common.UIAbilityContext,
    filePath: string,
  ): Promise<string> {
    if (filePath.length === 0) {
      return ''
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_FILE_HASH_BY_PATH, [
      SCOPE_GLOBAL,
      filePath,
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
      ImageBlockRepository.requestSync(context, 'image_block_subscription')
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
    ImageBlockRepository.requestSync(context, 'image_block_subscription')
  }

  static async upsertLocalRule(context: common.UIAbilityContext, rule: ImageBlockRule): Promise<void> {
    const normalizedHash: string = PHashService.normalizeHex64(rule.hash)
    if (normalizedHash.length === 0) {
      throw new Error('Image block rule hash must be 16 hex characters')
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const now: number = Date.now()
    const ruleId: string = rule.id.length > 0 ? rule.id : 'local:' + normalizedHash
    await store.executeSql(SQL_UPSERT_USER_RULE, [
      SCOPE_GLOBAL,
      ruleId,
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
    ImageBlockRepository.requestSync(context, 'image_block_rule')
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
    ImageBlockRepository.requestSync(context, 'image_block_rule')
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
    ImageBlockRepository.requestSync(context, 'image_block_rule')
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
    ImageBlockRepository.requestSync(context, 'image_block_rule')
  }

  static async rememberRulePreview(
    context: common.UIAbilityContext,
    ruleId: string,
    previewPath: string,
  ): Promise<void> {
    if (ruleId.length === 0 || previewPath.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_UPDATE_RULE_PREVIEW, [previewPath, Date.now(), SCOPE_GLOBAL, ruleId, previewPath])
    await store.executeSql(SQL_UPDATE_USER_RULE_PREVIEW, [previewPath, Date.now(), SCOPE_GLOBAL, ruleId, previewPath])
    ImageBlockRepository.requestSync(context, 'image_block_rule_preview')
  }

  static async replaceWhitelist(context: common.UIAbilityContext, hashes: string[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const now: number = Date.now()
    store.beginTransaction()
    try {
      await store.executeSql(SQL_TOMBSTONE_ALLOW_RULES, [
        now,
        now,
        SCOPE_GLOBAL,
        IMAGE_BLOCK_SOURCE_ALLOW,
      ])
      for (let i: number = 0; i < hashes.length; i++) {
        const hash: string = PHashService.normalizeHex64(hashes[i])
        if (hash.length > 0) {
          await ImageBlockRepository.upsertAllowRule(store, hash, '', now + i + 1)
        }
      }
      store.commit()
      ImageBlockRepository.requestSync(context, 'image_block_allow')
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
    await ImageBlockRepository.upsertAllowRule(store, normalizedHash, previewPath, Date.now())
    ImageBlockRepository.requestSync(context, 'image_block_allow')
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
    const now: number = Date.now()
    await store.executeSql(SQL_UPDATE_RULE_ENABLED, [0, now, SCOPE_GLOBAL, ruleId, normalizedHash, sourceType])
    await ImageBlockRepository.upsertSubscriptionOverride(store, ruleId, normalizedHash, sourceType, -1, 0, now)
    ImageBlockRepository.requestSync(context, 'image_block_rule_override')
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
    const now: number = Date.now()
    await store.executeSql(SQL_UPDATE_RULE_ENABLED, [
      enabled ? 1 : 0,
      now,
      SCOPE_GLOBAL,
      ruleId,
      normalizedHash,
      sourceType,
    ])
    await ImageBlockRepository.upsertSubscriptionOverride(
      store,
      ruleId,
      normalizedHash,
      sourceType,
      -1,
      enabled ? 1 : 0,
      now,
    )
    ImageBlockRepository.requestSync(context, 'image_block_rule_override')
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
    const now: number = Date.now()
    await store.executeSql(SQL_UPDATE_RULE_THRESHOLD, [
      PHashService.clampThreshold(threshold),
      now,
      SCOPE_GLOBAL,
      ruleId,
      normalizedHash,
      sourceType,
    ])
    await ImageBlockRepository.upsertSubscriptionOverride(
      store,
      ruleId,
      normalizedHash,
      sourceType,
      PHashService.clampThreshold(threshold),
      -1,
      now,
    )
    ImageBlockRepository.requestSync(context, 'image_block_rule_override')
  }

  static async removeWhitelistHash(context: common.UIAbilityContext, hash: string): Promise<void> {
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    if (normalizedHash.length === 0) {
      return
    }
    const now: number = Date.now()
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_TOMBSTONE_ONE_ALLOW_RULE, [
      now,
      now,
      SCOPE_GLOBAL,
      IMAGE_BLOCK_SOURCE_ALLOW,
      normalizedHash,
    ])
    ImageBlockRepository.requestSync(context, 'image_block_allow')
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
      item.sourceUrl,
      item.sourcePage > 0 ? Math.floor(item.sourcePage) : 0,
      '',
      1,
      updatedAt,
    ])
  }

  private static async upsertSubscriptionOverride(
    store: relationalStore.RdbStore,
    ruleId: string,
    hash: string,
    sourceType: string,
    threshold: number,
    enabled: number,
    updatedAt: number,
  ): Promise<void> {
    if (sourceType !== IMAGE_BLOCK_SOURCE_SUBSCRIPTION) {
      return
    }
    await store.executeSql(SQL_UPSERT_USER_RULE_OVERRIDE, [
      SCOPE_GLOBAL,
      ruleId,
      hash,
      threshold,
      IMAGE_BLOCK_SOURCE_SUBSCRIPTION,
      enabled,
      updatedAt,
    ])
  }

  private static requestSync(context: common.UIAbilityContext, reason: string): void {
    SyncScheduler.requestAfterLocalWrite(context, reason)
  }

  private static async upsertAllowRule(
    store: relationalStore.RdbStore,
    hash: string,
    previewPath: string,
    updatedAt: number,
  ): Promise<void> {
    await store.executeSql(SQL_UPSERT_USER_RULE, [
      SCOPE_GLOBAL,
      'allow:' + hash,
      hash,
      0,
      'allow',
      IMAGE_BLOCK_SCOPE_WHOLE,
      '',
      IMAGE_BLOCK_SOURCE_ALLOW,
      '',
      0,
      previewPath,
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

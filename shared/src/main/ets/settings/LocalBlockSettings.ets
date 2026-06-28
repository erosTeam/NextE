import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE,
  LOCAL_BLOCK_COMMENT_DISPLAY_HIDE,
  LOCAL_BLOCK_TYPE_COMMENT,
  LOCAL_BLOCK_TYPE_COMMENTATOR,
  LOCAL_BLOCK_TYPE_TITLE,
  LOCAL_BLOCK_TYPE_UPLOADER,
  LocalBlockRule,
  LocalBlockState,
  connectLocalBlock,
} from '../state/LocalBlockState'
import {
  LocalBlockRepository,
  LocalBlockRuleSnapshot,
  LocalBlockSettingsSnapshot,
} from '../storage/LocalBlockRepository'
import { HuaweiCloudSyncScheduler } from '../sync/HuaweiCloudSyncScheduler'

export class LocalBlockSettings {
  private static bumpVersion(state: LocalBlockState): void {
    state.version = state.version + 1
  }

  static normalizeType(type: string): string {
    if (type === LOCAL_BLOCK_TYPE_UPLOADER ||
      type === LOCAL_BLOCK_TYPE_COMMENTATOR ||
      type === LOCAL_BLOCK_TYPE_COMMENT) {
      return type
    }
    return LOCAL_BLOCK_TYPE_TITLE
  }

  static normalizeCommentDisplayMode(mode: string): string {
    return mode === LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE
      ? LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE
      : LOCAL_BLOCK_COMMENT_DISPLAY_HIDE
  }

  static cleanText(text: string): string {
    return text.trim().replace(/\n+/g, ' ')
  }

  static cloneRule(rule: LocalBlockRule): LocalBlockRule {
    const out: LocalBlockRule = new LocalBlockRule()
    out.id = rule.id
    out.blockType = LocalBlockSettings.normalizeType(rule.blockType)
    out.ruleText = LocalBlockSettings.cleanText(rule.ruleText)
    out.enabled = rule.enabled
    out.enableRegex = rule.enableRegex
    return out
  }

  private static current(): LocalBlockSettingsSnapshot {
    const state: LocalBlockState = connectLocalBlock()
    const snapshot: LocalBlockSettingsSnapshot = new LocalBlockSettingsSnapshot()
    snapshot.filterCommentsByScore = state.filterCommentsByScore
    snapshot.scoreFilteringThreshold = state.scoreFilteringThreshold
    snapshot.commentDisplayMode = LocalBlockSettings.normalizeCommentDisplayMode(state.commentDisplayMode)
    snapshot.rules = LocalBlockSettings.snapshotRules(state.rules)
    return snapshot
  }

  private static apply(snapshot: LocalBlockSettingsSnapshot): void {
    const state: LocalBlockState = connectLocalBlock()
    state.filterCommentsByScore = snapshot.filterCommentsByScore
    state.scoreFilteringThreshold = Number.isFinite(snapshot.scoreFilteringThreshold)
      ? Math.floor(snapshot.scoreFilteringThreshold)
      : -20
    state.commentDisplayMode = LocalBlockSettings.normalizeCommentDisplayMode(snapshot.commentDisplayMode)
    state.rules = LocalBlockSettings.rulesFromSnapshot(snapshot.rules)
    LocalBlockSettings.bumpVersion(state)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await LocalBlockSettings.migrateLegacyPreferences(context)
      LocalBlockSettings.apply(await LocalBlockRepository.load(context))
    } catch (error) {
      DiagnosticLogger.warn('settings', 'local_block_restore_failed', (error as Error).message)
      LocalBlockSettings.apply(new LocalBlockSettingsSnapshot())
    }
  }

  static async save(context: common.UIAbilityContext): Promise<void> {
    try {
      await LocalBlockRepository.replaceAll(context, LocalBlockSettings.current())
      HuaweiCloudSyncScheduler.requestAfterLocalWrite(context, 'local_block')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'local_block_save_failed', (error as Error).message)
    }
  }

  static async exportForBackup(context: common.UIAbilityContext): Promise<LocalBlockSettingsSnapshot> {
    await LocalBlockSettings.migrateLegacyPreferences(context)
    return LocalBlockRepository.load(context)
  }

  static async restoreBackup(
    context: common.UIAbilityContext,
    snapshot: LocalBlockSettingsSnapshot,
  ): Promise<void> {
    await LocalBlockRepository.replaceAll(context, snapshot)
    await LocalBlockSettings.deleteLegacyPreference(context)
    LocalBlockSettings.apply(await LocalBlockRepository.load(context))
    HuaweiCloudSyncScheduler.requestAfterLocalWrite(context, 'local_block_restore_backup')
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
    const raw: string = store.getSync(StorageKeys.LOCAL_BLOCK_RULES, '') as string
    if (raw.length === 0) {
      return
    }
    try {
      await LocalBlockRepository.replaceAll(context, LocalBlockSettings.parseSnapshot(raw))
    } catch (error) {
      DiagnosticLogger.warn('settings', 'local_block_migrate_failed', (error as Error).message)
    }
    store.deleteSync(StorageKeys.LOCAL_BLOCK_RULES)
    store.flushSync()
  }

  static async setScoreFilter(
    context: common.UIAbilityContext,
    enabled: boolean,
    threshold: number,
  ): Promise<void> {
    const state: LocalBlockState = connectLocalBlock()
    state.filterCommentsByScore = enabled
    state.scoreFilteringThreshold = Math.floor(threshold)
    LocalBlockSettings.bumpVersion(state)
    await LocalBlockSettings.save(context)
  }

  static async setCommentDisplayMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const state: LocalBlockState = connectLocalBlock()
    state.commentDisplayMode = LocalBlockSettings.normalizeCommentDisplayMode(mode)
    LocalBlockSettings.bumpVersion(state)
    await LocalBlockSettings.save(context)
  }

  static async upsertRule(context: common.UIAbilityContext, rule: LocalBlockRule): Promise<void> {
    const next: LocalBlockRule = LocalBlockSettings.cloneRule(rule)
    if (next.ruleText.length === 0) {
      return
    }
    if (next.id.length === 0) {
      next.id = `${Date.now()}-${Math.floor(Math.random() * 1000000)}`
    }
    const state: LocalBlockState = connectLocalBlock()
    const rules: LocalBlockRule[] = []
    let replaced: boolean = false
    state.rules.forEach((item: LocalBlockRule) => {
      if (item.id === next.id) {
        rules.push(next)
        replaced = true
      } else {
        rules.push(LocalBlockSettings.cloneRule(item))
      }
    })
    if (!replaced) {
      rules.push(next)
    }
    state.rules = rules
    LocalBlockSettings.bumpVersion(state)
    await LocalBlockSettings.save(context)
  }

  static async removeRule(context: common.UIAbilityContext, ruleId: string): Promise<void> {
    const state: LocalBlockState = connectLocalBlock()
    state.rules = state.rules
      .filter((rule: LocalBlockRule) => rule.id !== ruleId)
      .map((rule: LocalBlockRule) => LocalBlockSettings.cloneRule(rule))
    LocalBlockSettings.bumpVersion(state)
    await LocalBlockSettings.save(context)
  }

  static async setRuleEnabled(context: common.UIAbilityContext, ruleId: string, enabled: boolean): Promise<void> {
    const state: LocalBlockState = connectLocalBlock()
    state.rules = state.rules.map((rule: LocalBlockRule) => {
      const next: LocalBlockRule = LocalBlockSettings.cloneRule(rule)
      if (next.id === ruleId) {
        next.enabled = enabled
      }
      return next
    })
    LocalBlockSettings.bumpVersion(state)
    await LocalBlockSettings.save(context)
  }

  private static parseRules(items: Object[]): LocalBlockRuleSnapshot[] {
    const out: LocalBlockRuleSnapshot[] = []
    items.forEach((item: Object) => {
      const rec = item as Record<string, Object>
      const rule: LocalBlockRuleSnapshot = new LocalBlockRuleSnapshot()
      rule.id = typeof rec.id === 'string' ? rec.id as string : ''
      rule.blockType = typeof rec.blockType === 'string'
        ? LocalBlockSettings.normalizeType(rec.blockType as string)
        : LOCAL_BLOCK_TYPE_TITLE
      rule.ruleText = typeof rec.ruleText === 'string'
        ? LocalBlockSettings.cleanText(rec.ruleText as string)
        : ''
      rule.enabled = typeof rec.enabled === 'boolean' ? rec.enabled as boolean : true
      rule.enableRegex = typeof rec.enableRegex === 'boolean' ? rec.enableRegex as boolean : false
      if (rule.ruleText.length > 0) {
        out.push(rule)
      }
    })
    return out
  }

  private static rulesFromSnapshot(items: LocalBlockRuleSnapshot[]): LocalBlockRule[] {
    const out: LocalBlockRule[] = []
    items.forEach((item: LocalBlockRuleSnapshot, index: number) => {
      const rule: LocalBlockRule = new LocalBlockRule()
      rule.id = item.id.length > 0 ? item.id : `restored-${index}`
      rule.blockType = LocalBlockSettings.normalizeType(item.blockType)
      rule.ruleText = LocalBlockSettings.cleanText(item.ruleText)
      rule.enabled = item.enabled
      rule.enableRegex = item.enableRegex
      if (rule.ruleText.length > 0) {
        out.push(rule)
      }
    })
    return out
  }

  private static snapshotRules(items: LocalBlockRule[]): LocalBlockRuleSnapshot[] {
    const out: LocalBlockRuleSnapshot[] = []
    items.forEach((rule: LocalBlockRule) => {
      const clean: LocalBlockRule = LocalBlockSettings.cloneRule(rule)
      if (clean.ruleText.length === 0) {
        return
      }
      const snapshot: LocalBlockRuleSnapshot = new LocalBlockRuleSnapshot()
      snapshot.id = clean.id
      snapshot.blockType = clean.blockType
      snapshot.ruleText = clean.ruleText
      snapshot.enabled = clean.enabled
      snapshot.enableRegex = clean.enableRegex
      out.push(snapshot)
    })
    return out
  }

  private static parseSnapshot(raw: string): LocalBlockSettingsSnapshot {
    const parsed = JSON.parse(raw) as Record<string, Object>
    const snapshot: LocalBlockSettingsSnapshot = new LocalBlockSettingsSnapshot()
    snapshot.filterCommentsByScore = typeof parsed.filterCommentsByScore === 'boolean'
      ? parsed.filterCommentsByScore as boolean
      : false
    snapshot.scoreFilteringThreshold = typeof parsed.scoreFilteringThreshold === 'number'
      ? parsed.scoreFilteringThreshold as number
      : -20
    snapshot.commentDisplayMode = typeof parsed.commentDisplayMode === 'string'
      ? LocalBlockSettings.normalizeCommentDisplayMode(parsed.commentDisplayMode as string)
      : LOCAL_BLOCK_COMMENT_DISPLAY_HIDE
    if (Array.isArray(parsed.rules)) {
      snapshot.rules = LocalBlockSettings.parseRules(parsed.rules as Object[])
    }
    return snapshot
  }

  private static async deleteLegacyPreference(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
    store.deleteSync(StorageKeys.LOCAL_BLOCK_RULES)
    store.flushSync()
  }
}

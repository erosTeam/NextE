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
import { SyncScheduler } from '../sync/SyncScheduler'

export class LocalBlockSettings {
  // Settings-page callbacks are fire-and-forget. Serialize their durable order so a rapid
  // add/toggle/delete sequence cannot let an older durable mutation win later.
  private static rdbWriteTail: Promise<void> = Promise.resolve()
  private static mutationRevision: number = 0

  private static bumpVersion(state: LocalBlockState): void {
    state.version = state.version + 1
    DiagnosticLogger.info('settings', 'local_block_version', `version=${state.version} rules=${state.rules.length}`)
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
    const next: LocalBlockSettingsSnapshot = LocalBlockSettings.normalizeSnapshot(snapshot)
    if (LocalBlockSettings.snapshotEquals(LocalBlockSettings.current(), next)) {
      DiagnosticLogger.info('settings', 'local_block_apply_unchanged', `version=${state.version} rules=${state.rules.length}`)
      return
    }
    state.filterCommentsByScore = next.filterCommentsByScore
    state.scoreFilteringThreshold = next.scoreFilteringThreshold
    state.commentDisplayMode = next.commentDisplayMode
    state.rules = LocalBlockSettings.rulesFromSnapshot(next.rules)
    LocalBlockSettings.bumpVersion(state)
  }

  private static normalizeSnapshot(snapshot: LocalBlockSettingsSnapshot): LocalBlockSettingsSnapshot {
    const out: LocalBlockSettingsSnapshot = new LocalBlockSettingsSnapshot()
    out.filterCommentsByScore = snapshot.filterCommentsByScore
    out.scoreFilteringThreshold = Number.isFinite(snapshot.scoreFilteringThreshold)
      ? Math.floor(snapshot.scoreFilteringThreshold)
      : -20
    out.commentDisplayMode = LocalBlockSettings.normalizeCommentDisplayMode(snapshot.commentDisplayMode)
    out.rules = LocalBlockSettings.snapshotRules(LocalBlockSettings.rulesFromSnapshot(snapshot.rules))
    return out
  }

  private static snapshotEquals(a: LocalBlockSettingsSnapshot, b: LocalBlockSettingsSnapshot): boolean {
    if (a.filterCommentsByScore !== b.filterCommentsByScore ||
      Math.floor(a.scoreFilteringThreshold) !== Math.floor(b.scoreFilteringThreshold) ||
      LocalBlockSettings.normalizeCommentDisplayMode(a.commentDisplayMode) !==
        LocalBlockSettings.normalizeCommentDisplayMode(b.commentDisplayMode) ||
      a.rules.length !== b.rules.length) {
      return false
    }
    for (let i: number = 0; i < a.rules.length; i++) {
      if (!LocalBlockSettings.ruleEquals(a.rules[i], b.rules[i])) {
        return false
      }
    }
    return true
  }

  private static ruleEquals(a: LocalBlockRuleSnapshot, b: LocalBlockRuleSnapshot): boolean {
    return a.id === b.id &&
      LocalBlockSettings.normalizeType(a.blockType) === LocalBlockSettings.normalizeType(b.blockType) &&
      LocalBlockSettings.cleanText(a.ruleText) === LocalBlockSettings.cleanText(b.ruleText) &&
      a.enabled === b.enabled &&
      a.enableRegex === b.enableRegex
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await LocalBlockSettings.migrateLegacyPreferences(context)
      await LocalBlockSettings.refreshFromStorage(context)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'local_block_restore_failed', (error as Error).message)
      LocalBlockSettings.apply(new LocalBlockSettingsSnapshot())
    }
  }

  static async exportForBackup(context: common.UIAbilityContext): Promise<LocalBlockSettingsSnapshot> {
    await LocalBlockSettings.migrateLegacyPreferences(context)
    await LocalBlockSettings.flushForSync(context)
    return LocalBlockRepository.load(context)
  }

  static async restoreBackup(
    context: common.UIAbilityContext,
    snapshot: LocalBlockSettingsSnapshot,
  ): Promise<void> {
    LocalBlockSettings.mutationRevision = LocalBlockSettings.mutationRevision + 1
    await LocalBlockSettings.enqueueRdbWrite(
      (): Promise<void> => LocalBlockRepository.replaceAll(context, snapshot),
    )
    await LocalBlockSettings.deleteLegacyPreference(context)
    await LocalBlockSettings.refreshFromStorage(context)
    SyncScheduler.requestAfterLocalWrite(context, 'local_block_restore_backup')
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const revision: number = LocalBlockSettings.mutationRevision
    const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
    const raw: string = store.getSync(StorageKeys.LOCAL_BLOCK_RULES, '') as string
    if (raw.length === 0) {
      return
    }
    try {
      await LocalBlockSettings.enqueueRdbWrite(async (): Promise<void> => {
        if (revision !== LocalBlockSettings.mutationRevision) {
          return
        }
        if (await LocalBlockRepository.hasPersistedState(context)) {
          return
        }
        if (revision !== LocalBlockSettings.mutationRevision) {
          return
        }
        await LocalBlockRepository.replaceAll(context, LocalBlockSettings.parseSnapshot(raw))
      })
    } catch (error) {
      DiagnosticLogger.warn('settings', 'local_block_migrate_failed', (error as Error).message)
      // Keep the only legacy copy intact. A later startup can retry once the RDB write succeeds.
      return
    }
    if (revision !== LocalBlockSettings.mutationRevision) {
      return
    }
    await LocalBlockSettings.deleteLegacyPreference(context)
  }

  /** Drain queued local block writes before backup and sync providers read either durable table. */
  static async flushForSync(_context: common.UIAbilityContext): Promise<void> {
    await LocalBlockSettings.rdbWriteTail
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
    LocalBlockSettings.mutationRevision = LocalBlockSettings.mutationRevision + 1
    await LocalBlockSettings.persistSettings(context)
  }

  static async setCommentDisplayMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const state: LocalBlockState = connectLocalBlock()
    state.commentDisplayMode = LocalBlockSettings.normalizeCommentDisplayMode(mode)
    LocalBlockSettings.bumpVersion(state)
    LocalBlockSettings.mutationRevision = LocalBlockSettings.mutationRevision + 1
    await LocalBlockSettings.persistSettings(context)
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
    LocalBlockSettings.mutationRevision = LocalBlockSettings.mutationRevision + 1
    await LocalBlockSettings.persistRule(context, next)
  }

  static async removeRule(context: common.UIAbilityContext, ruleId: string): Promise<void> {
    const state: LocalBlockState = connectLocalBlock()
    const existing: boolean = state.rules.some((rule: LocalBlockRule) => rule.id === ruleId)
    if (!existing) {
      return
    }
    state.rules = state.rules
      .filter((rule: LocalBlockRule) => rule.id !== ruleId)
      .map((rule: LocalBlockRule) => LocalBlockSettings.cloneRule(rule))
    LocalBlockSettings.bumpVersion(state)
    LocalBlockSettings.mutationRevision = LocalBlockSettings.mutationRevision + 1
    await LocalBlockSettings.persistRuleRemoval(context, ruleId)
  }

  static async setRuleEnabled(context: common.UIAbilityContext, ruleId: string, enabled: boolean): Promise<void> {
    const state: LocalBlockState = connectLocalBlock()
    let changedIndex: number = -1
    for (let index: number = 0; index < state.rules.length; index++) {
      if (state.rules[index].id === ruleId) {
        changedIndex = index
        break
      }
    }
    if (changedIndex < 0) {
      return
    }
    const changed: LocalBlockRule = LocalBlockSettings.cloneRule(state.rules[changedIndex])
    changed.enabled = enabled
    state.rules = state.rules.map((rule: LocalBlockRule) => {
      const next: LocalBlockRule = LocalBlockSettings.cloneRule(rule)
      if (next.id === ruleId) {
        return changed
      }
      return next
    })
    LocalBlockSettings.bumpVersion(state)
    LocalBlockSettings.mutationRevision = LocalBlockSettings.mutationRevision + 1
    await LocalBlockSettings.persistRule(context, changed)
  }

  private static async persistSettings(context: common.UIAbilityContext): Promise<void> {
    try {
      const snapshot: LocalBlockSettingsSnapshot = LocalBlockSettings.current()
      await LocalBlockSettings.enqueueRdbWrite(async (): Promise<void> => {
        await LocalBlockRepository.upsertSettings(context, snapshot)
      })
      SyncScheduler.requestAfterLocalWrite(context, 'local_block')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'local_block_settings_save_failed', (error as Error).message)
    }
  }

  private static async persistRule(context: common.UIAbilityContext, rule: LocalBlockRule): Promise<void> {
    try {
      const snapshot: LocalBlockRuleSnapshot = LocalBlockSettings.snapshotRule(rule)
      await LocalBlockSettings.enqueueRdbWrite(async (): Promise<void> => {
        await LocalBlockRepository.upsertRule(context, snapshot)
      })
      SyncScheduler.requestAfterLocalWrite(context, 'local_block')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'local_block_rule_save_failed', (error as Error).message)
    }
  }

  private static async persistRuleRemoval(context: common.UIAbilityContext, ruleId: string): Promise<void> {
    try {
      await LocalBlockSettings.enqueueRdbWrite(async (): Promise<void> => {
        await LocalBlockRepository.tombstoneRule(context, ruleId)
      })
      SyncScheduler.requestAfterLocalWrite(context, 'local_block')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'local_block_rule_remove_failed', (error as Error).message)
    }
  }

  /** A failed write must not poison the queue behind it. */
  private static enqueueRdbWrite(work: () => Promise<void>): Promise<void> {
    const next: Promise<void> = LocalBlockSettings.rdbWriteTail.then(
      (): Promise<void> => work(),
      (): Promise<void> => work(),
    )
    LocalBlockSettings.rdbWriteTail = next
    return next
  }

  /** Do not replace a newer page mutation with an RDB snapshot that started before it. */
  private static async refreshFromStorage(context: common.UIAbilityContext): Promise<void> {
    for (let attempt: number = 0; attempt < 2; attempt++) {
      await LocalBlockSettings.rdbWriteTail
      const revision: number = LocalBlockSettings.mutationRevision
      const snapshot: LocalBlockSettingsSnapshot = await LocalBlockRepository.load(context)
      if (revision === LocalBlockSettings.mutationRevision) {
        LocalBlockSettings.apply(snapshot)
        return
      }
    }
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
      const snapshot: LocalBlockRuleSnapshot = LocalBlockSettings.snapshotRule(rule)
      if (snapshot.ruleText.length > 0) {
        out.push(snapshot)
      }
    })
    return out
  }

  private static snapshotRule(rule: LocalBlockRule): LocalBlockRuleSnapshot {
    const clean: LocalBlockRule = LocalBlockSettings.cloneRule(rule)
    const snapshot: LocalBlockRuleSnapshot = new LocalBlockRuleSnapshot()
    snapshot.id = clean.id
    snapshot.blockType = clean.blockType
    snapshot.ruleText = clean.ruleText
    snapshot.enabled = clean.enabled
    snapshot.enableRegex = clean.enableRegex
    return snapshot
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

import { common } from '@kit.AbilityKit'
import { ReadProgressEntry } from '../state/GalleryReadProgressState'
import { GalleryReadProgressSettings } from '../settings/GalleryReadProgressSettings'
import { EhGallery } from '../model/EhGallery'
import { LocalFavSettings } from '../settings/LocalFavSettings'
import { SearchHistorySettings } from '../settings/SearchHistorySettings'
import { LocalBlockSettings } from '../settings/LocalBlockSettings'
import {
  LocalBlockRuleSnapshot,
  LocalBlockSettingsSnapshot,
} from '../storage/LocalBlockRepository'
import { CustomProfile } from '../model/CustomProfile'
import { ImageBlockRule } from '../model/ImageBlockRule'
import { CustomProfilesSettings } from '../settings/CustomProfilesSettings'
import { ViewedGallery } from '../model/ViewedGallery'
import { ViewedHistorySettings } from '../settings/ViewedHistorySettings'
import { publishImageBlockRulesChanged } from '../state/ImageBlockRuntimeState'
import { ImageBlockRepository } from '../storage/ImageBlockRepository'
import {
  BackupCustomProfileEntry,
  BackupCustomProfilesSection,
  BackupImageBlockRuleEntry,
  BackupImageBlockSection,
  BackupLocalBlockRuleEntry,
  BackupLocalBlockSection,
  BackupLocalFavoriteEntry,
  BackupLocalDataSection,
  BackupReadProgressEntry,
  BackupViewedHistoryEntry,
} from './BackupTypes'

export class BackupLocalDataAdapter {
  static async exportSection(context: common.UIAbilityContext): Promise<BackupLocalDataSection> {
    return {
      readProgress: await BackupLocalDataAdapter.exportReadProgress(context),
      viewedHistory: await BackupLocalDataAdapter.exportViewedHistory(context),
      localFavorites: await BackupLocalDataAdapter.exportLocalFavorites(context),
      searchHistory: await BackupLocalDataAdapter.exportSearchHistory(context),
      localBlock: await BackupLocalDataAdapter.exportLocalBlock(context),
      imageBlock: await BackupLocalDataAdapter.exportImageBlock(context),
      customProfiles: await BackupLocalDataAdapter.exportCustomProfiles(context),
    }
  }

  private static async exportReadProgress(
    context: common.UIAbilityContext,
  ): Promise<BackupReadProgressEntry[]> {
    const source: ReadProgressEntry[] = await GalleryReadProgressSettings.exportForBackup(context)
    const out: BackupReadProgressEntry[] = []
    for (let i: number = 0; i < source.length; i++) {
      const entry: ReadProgressEntry = source[i]
      if (entry.g.length > 0 && entry.i >= 0) {
        out.push({ g: entry.g, i: entry.i, t: entry.t, c: entry.c })
      }
    }
    return out
  }

  private static async exportViewedHistory(
    context: common.UIAbilityContext,
  ): Promise<BackupViewedHistoryEntry[]> {
    const source: ViewedGallery[] = await ViewedHistorySettings.exportForBackup(context)
    const out: BackupViewedHistoryEntry[] = []
    for (let i: number = 0; i < source.length; i++) {
      const item: ViewedGallery = source[i]
      if (item.gid.length === 0) {
        continue
      }
      out.push({
        gid: item.gid,
        token: item.token,
        title: item.title,
        titleJp: item.titleJp,
        thumbUrl: item.thumbUrl,
        category: item.category,
        uploader: item.uploader,
        rating: item.rating,
        fileCount: item.fileCount,
        time: item.time,
        postTime: item.postTime,
        ratingFallBack: item.ratingFallBack,
        colorRating: item.colorRating,
        translated: item.translated,
        expunged: item.expunged,
      })
    }
    return out
  }

  private static async exportLocalFavorites(
    context: common.UIAbilityContext,
  ): Promise<BackupLocalFavoriteEntry[]> {
    const source: EhGallery[] = await LocalFavSettings.exportForBackup(context)
    const out: BackupLocalFavoriteEntry[] = []
    for (let i: number = 0; i < source.length; i++) {
      const item: EhGallery = source[i]
      if (item.gid.length === 0) {
        continue
      }
      out.push({
        gid: item.gid,
        token: item.token,
        url: item.url,
        thumbUrl: item.thumbUrl,
        thumbUrlL: item.thumbUrlL,
        imgWidth: item.imgWidth,
        imgHeight: item.imgHeight,
        englishTitle: item.englishTitle,
        japaneseTitle: item.japaneseTitle,
        category: item.category,
        uploader: item.uploader,
        postTime: item.postTime,
        fileCount: item.fileCount,
        rating: item.rating,
        ratingFallBack: item.ratingFallBack,
        colorRating: item.colorRating,
        favNote: item.favNote,
        favTitle: item.favTitle,
        expunged: item.expunged,
        lastViewTime: item.lastViewTime,
      })
    }
    return out
  }

  private static async exportSearchHistory(context: common.UIAbilityContext): Promise<string[]> {
    const source: string[] = await SearchHistorySettings.exportForBackup(context)
    const out: string[] = []
    for (let i: number = 0; i < source.length; i++) {
      const query: string = source[i].trim()
      if (query.length > 0 && out.indexOf(query) < 0) {
        out.push(query)
      }
    }
    return out
  }

  private static async exportLocalBlock(
    context: common.UIAbilityContext,
  ): Promise<BackupLocalBlockSection> {
    const source: LocalBlockSettingsSnapshot = await LocalBlockSettings.exportForBackup(context)
    const rules: BackupLocalBlockRuleEntry[] = []
    for (let i: number = 0; i < source.rules.length; i++) {
      const rule: LocalBlockRuleSnapshot = source.rules[i]
      if (rule.ruleText.length === 0) {
        continue
      }
      rules.push({
        id: rule.id,
        blockType: rule.blockType,
        ruleText: rule.ruleText,
        enabled: rule.enabled,
        enableRegex: rule.enableRegex,
      })
    }
    return {
      filterCommentsByScore: source.filterCommentsByScore,
      scoreFilteringThreshold: source.scoreFilteringThreshold,
      commentDisplayMode: source.commentDisplayMode,
      rules: rules,
    }
  }

  private static async exportImageBlock(
    context: common.UIAbilityContext,
  ): Promise<BackupImageBlockSection> {
    const source: ImageBlockRule[] = await ImageBlockRepository.loadUserRulesForBackup(context)
    const rules: BackupImageBlockRuleEntry[] = []
    for (let i: number = 0; i < source.length; i++) {
      const rule: ImageBlockRule = source[i]
      if (rule.id.length === 0 || rule.hash.length === 0) {
        continue
      }
      rules.push({
        id: rule.id,
        hash: rule.hash,
        threshold: rule.threshold,
        label: rule.label,
        scope: rule.scope,
        feedId: rule.feedId,
        sourceType: rule.sourceType,
        sourceUrl: rule.sourceUrl,
        sourcePage: rule.sourcePage,
        enabled: rule.enabled,
        updatedAt: rule.updatedAt,
      })
    }
    return { rules: rules }
  }

  private static async exportCustomProfiles(
    context: common.UIAbilityContext,
  ): Promise<BackupCustomProfilesSection> {
    const snapshot = await CustomProfilesSettings.exportForBackupSnapshot(context)
    const source: CustomProfile[] = snapshot.profiles
    const out: BackupCustomProfileEntry[] = []
    for (let i: number = 0; i < source.length; i++) {
      const p: CustomProfile = source[i]
      if (p.uuid.length === 0) {
        continue
      }
      out.push({
        uuid: p.uuid,
        name: p.name,
        listType: p.listType,
        searchText: p.searchText,
        selectedCats: p.selectedCats,
        advancedEnabled: p.advancedEnabled,
        minRating: p.minRating,
        pagesFrom: p.pagesFrom,
        pagesTo: p.pagesTo,
        requireTorrent: p.requireTorrent,
        showExpunged: p.showExpunged,
        disableLanguageFilter: p.disableLanguageFilter,
        disableUploaderFilter: p.disableUploaderFilter,
        disableTagFilter: p.disableTagFilter,
        favcat: p.favcat,
        toplistTl: p.toplistTl,
        displayMode: p.displayMode,
        hidden: p.hidden,
        builtin: p.builtin,
        lastEditTime: p.lastEditTime,
      })
    }
    return {
      selectedUuid: snapshot.selectedUuid,
      profiles: out,
    }
  }

  /**
   * A local-data backup is an authoritative replacement for several durable tables. Validate its
   * complete runtime shape before any restore can turn a missing or damaged field into an empty
   * replacement. `imageBlock` remains optional because it was added after the original schema-v1
   * local-data envelope; its absence preserves the target's image-block rules for that old format.
   */
  static hasCompleteRestoreShape(section: BackupLocalDataSection | undefined): boolean {
    if (!BackupLocalDataAdapter.isRecord(section)) {
      return false
    }
    const candidate: BackupLocalDataSection = section as BackupLocalDataSection
    if (
      !Array.isArray(candidate.readProgress) ||
      !Array.isArray(candidate.viewedHistory) ||
      !Array.isArray(candidate.localFavorites) ||
      !Array.isArray(candidate.searchHistory) ||
      !BackupLocalDataAdapter.hasLocalBlockShape(candidate.localBlock) ||
      !BackupLocalDataAdapter.hasCustomProfilesShape(candidate.customProfiles)
    ) {
      return false
    }
    if (
      candidate.imageBlock !== undefined &&
      !BackupLocalDataAdapter.hasImageBlockShape(candidate.imageBlock)
    ) {
      return false
    }
    return (
      BackupLocalDataAdapter.hasReadProgressEntries(candidate.readProgress) &&
      BackupLocalDataAdapter.hasViewedHistoryEntries(candidate.viewedHistory) &&
      BackupLocalDataAdapter.hasLocalFavoriteEntries(candidate.localFavorites) &&
      BackupLocalDataAdapter.hasSearchHistoryEntries(candidate.searchHistory)
    )
  }

  private static hasReadProgressEntries(entries: BackupReadProgressEntry[]): boolean {
    for (let i: number = 0; i < entries.length; i++) {
      const entry: BackupReadProgressEntry = entries[i]
      if (
        !BackupLocalDataAdapter.isRecord(entry) ||
        typeof entry.g !== 'string' ||
        entry.g.length === 0 ||
        typeof entry.i !== 'number' ||
        entry.i < 0 ||
        typeof entry.t !== 'number' ||
        (entry.c !== undefined && typeof entry.c !== 'string')
      ) {
        return false
      }
    }
    return true
  }

  private static hasViewedHistoryEntries(entries: BackupViewedHistoryEntry[]): boolean {
    for (let i: number = 0; i < entries.length; i++) {
      const entry: BackupViewedHistoryEntry = entries[i]
      if (
        !BackupLocalDataAdapter.isRecord(entry) ||
        typeof entry.gid !== 'string' ||
        entry.gid.length === 0 ||
        typeof entry.token !== 'string' ||
        typeof entry.title !== 'string' ||
        typeof entry.titleJp !== 'string' ||
        typeof entry.thumbUrl !== 'string' ||
        typeof entry.category !== 'string' ||
        typeof entry.uploader !== 'string' ||
        typeof entry.rating !== 'number' ||
        typeof entry.fileCount !== 'string' ||
        typeof entry.time !== 'number' ||
        (entry.postTime !== undefined && typeof entry.postTime !== 'string') ||
        (entry.ratingFallBack !== undefined && typeof entry.ratingFallBack !== 'number') ||
        (entry.colorRating !== undefined && typeof entry.colorRating !== 'string') ||
        (entry.translated !== undefined && typeof entry.translated !== 'string') ||
        (entry.expunged !== undefined && typeof entry.expunged !== 'boolean')
      ) {
        return false
      }
    }
    return true
  }

  private static hasLocalFavoriteEntries(entries: BackupLocalFavoriteEntry[]): boolean {
    for (let i: number = 0; i < entries.length; i++) {
      const entry: BackupLocalFavoriteEntry = entries[i]
      if (
        !BackupLocalDataAdapter.isRecord(entry) ||
        typeof entry.gid !== 'string' ||
        entry.gid.length === 0 ||
        typeof entry.token !== 'string' ||
        typeof entry.url !== 'string' ||
        typeof entry.thumbUrl !== 'string' ||
        typeof entry.thumbUrlL !== 'string' ||
        typeof entry.imgWidth !== 'number' ||
        typeof entry.imgHeight !== 'number' ||
        typeof entry.englishTitle !== 'string' ||
        typeof entry.japaneseTitle !== 'string' ||
        typeof entry.category !== 'string' ||
        typeof entry.uploader !== 'string' ||
        typeof entry.postTime !== 'string' ||
        typeof entry.fileCount !== 'string' ||
        typeof entry.rating !== 'number' ||
        typeof entry.ratingFallBack !== 'number' ||
        typeof entry.colorRating !== 'string' ||
        typeof entry.favNote !== 'string' ||
        typeof entry.favTitle !== 'string' ||
        typeof entry.expunged !== 'boolean' ||
        typeof entry.lastViewTime !== 'number'
      ) {
        return false
      }
    }
    return true
  }

  private static hasSearchHistoryEntries(entries: string[]): boolean {
    for (let i: number = 0; i < entries.length; i++) {
      if (typeof entries[i] !== 'string' || entries[i].trim().length === 0) {
        return false
      }
    }
    return true
  }

  private static hasLocalBlockShape(section: BackupLocalBlockSection): boolean {
    if (
      !BackupLocalDataAdapter.isRecord(section) ||
      typeof section.filterCommentsByScore !== 'boolean' ||
      typeof section.scoreFilteringThreshold !== 'number' ||
      typeof section.commentDisplayMode !== 'string' ||
      !Array.isArray(section.rules)
    ) {
      return false
    }
    for (let i: number = 0; i < section.rules.length; i++) {
      const rule: BackupLocalBlockRuleEntry = section.rules[i]
      if (
        !BackupLocalDataAdapter.isRecord(rule) ||
        typeof rule.id !== 'string' ||
        typeof rule.blockType !== 'string' ||
        typeof rule.ruleText !== 'string' ||
        rule.ruleText.length === 0 ||
        typeof rule.enabled !== 'boolean' ||
        typeof rule.enableRegex !== 'boolean'
      ) {
        return false
      }
    }
    return true
  }

  private static hasImageBlockShape(section: BackupImageBlockSection): boolean {
    if (!BackupLocalDataAdapter.isRecord(section) || !Array.isArray(section.rules)) {
      return false
    }
    for (let i: number = 0; i < section.rules.length; i++) {
      const rule: BackupImageBlockRuleEntry = section.rules[i]
      if (
        !BackupLocalDataAdapter.isRecord(rule) ||
        typeof rule.id !== 'string' ||
        rule.id.length === 0 ||
        typeof rule.hash !== 'string' ||
        rule.hash.length === 0 ||
        typeof rule.threshold !== 'number' ||
        typeof rule.label !== 'string' ||
        typeof rule.scope !== 'string' ||
        typeof rule.feedId !== 'string' ||
        typeof rule.sourceType !== 'string' ||
        rule.sourceType.length === 0 ||
        typeof rule.sourceUrl !== 'string' ||
        typeof rule.sourcePage !== 'number' ||
        typeof rule.enabled !== 'boolean' ||
        typeof rule.updatedAt !== 'number'
      ) {
        return false
      }
    }
    return true
  }

  private static hasCustomProfilesShape(section: BackupCustomProfilesSection): boolean {
    if (
      !BackupLocalDataAdapter.isRecord(section) ||
      typeof section.selectedUuid !== 'string' ||
      !Array.isArray(section.profiles)
    ) {
      return false
    }
    for (let i: number = 0; i < section.profiles.length; i++) {
      const profile: BackupCustomProfileEntry = section.profiles[i]
      if (
        !BackupLocalDataAdapter.isRecord(profile) ||
        typeof profile.uuid !== 'string' ||
        profile.uuid.length === 0 ||
        typeof profile.name !== 'string' ||
        typeof profile.listType !== 'string' ||
        typeof profile.searchText !== 'string' ||
        typeof profile.selectedCats !== 'number' ||
        typeof profile.advancedEnabled !== 'boolean' ||
        typeof profile.minRating !== 'number' ||
        typeof profile.pagesFrom !== 'number' ||
        typeof profile.pagesTo !== 'number' ||
        typeof profile.requireTorrent !== 'boolean' ||
        typeof profile.showExpunged !== 'boolean' ||
        typeof profile.disableLanguageFilter !== 'boolean' ||
        typeof profile.disableUploaderFilter !== 'boolean' ||
        typeof profile.disableTagFilter !== 'boolean' ||
        typeof profile.favcat !== 'string' ||
        typeof profile.toplistTl !== 'number' ||
        typeof profile.displayMode !== 'string' ||
        typeof profile.hidden !== 'boolean' ||
        typeof profile.builtin !== 'boolean' ||
        typeof profile.lastEditTime !== 'number'
      ) {
        return false
      }
    }
    return true
  }

  private static isRecord(value: Object | undefined): boolean {
    return value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)
  }

  static async restoreSection(
    context: common.UIAbilityContext,
    section: BackupLocalDataSection,
  ): Promise<void> {
    if (!BackupLocalDataAdapter.hasCompleteRestoreShape(section)) {
      throw new Error('backup local data is malformed')
    }
    const entries: ReadProgressEntry[] = []
    let source: BackupReadProgressEntry[] = []
    if (section.readProgress !== undefined) {
      source = section.readProgress
    }
    for (let i: number = 0; i < source.length; i++) {
      const entry: BackupReadProgressEntry = source[i]
      if (entry.g.length > 0 && entry.i >= 0) {
        entries.push(new ReadProgressEntry(
          entry.g,
          entry.i,
          entry.t > 0 ? entry.t : 0,
          entry.c === undefined ? '' : entry.c,
        ))
      }
    }
    await GalleryReadProgressSettings.restoreBackup(context, entries)

    const history: ViewedGallery[] = []
    let historySource: BackupViewedHistoryEntry[] = []
    if (section.viewedHistory !== undefined) {
      historySource = section.viewedHistory
    }
    for (let i: number = 0; i < historySource.length; i++) {
      const item: BackupViewedHistoryEntry = historySource[i]
      if (item.gid.length === 0) {
        continue
      }
      const gallery: ViewedGallery = new ViewedGallery()
      gallery.gid = item.gid
      gallery.token = item.token
      gallery.title = item.title
      gallery.titleJp = item.titleJp
      gallery.thumbUrl = item.thumbUrl
      gallery.category = item.category
      gallery.uploader = item.uploader
      gallery.rating = item.rating
      gallery.fileCount = item.fileCount
      gallery.time = item.time
      gallery.postTime = item.postTime === undefined ? '' : item.postTime
      gallery.ratingFallBack = item.ratingFallBack === undefined ? item.rating : item.ratingFallBack
      gallery.colorRating = item.colorRating === undefined ? '' : item.colorRating
      gallery.translated = item.translated === undefined ? '' : item.translated
      gallery.expunged = item.expunged === undefined ? false : item.expunged
      history.push(gallery)
    }
    await ViewedHistorySettings.restoreBackup(context, history)

    const favorites: EhGallery[] = []
    let favoriteSource: BackupLocalFavoriteEntry[] = []
    if (section.localFavorites !== undefined) {
      favoriteSource = section.localFavorites
    }
    for (let i: number = 0; i < favoriteSource.length; i++) {
      const item: BackupLocalFavoriteEntry = favoriteSource[i]
      if (item.gid.length === 0) {
        continue
      }
      const gallery: EhGallery = new EhGallery(item.gid, item.token)
      gallery.url = item.url
      gallery.thumbUrl = item.thumbUrl
      gallery.thumbUrlL = item.thumbUrlL
      gallery.imgWidth = item.imgWidth
      gallery.imgHeight = item.imgHeight
      gallery.englishTitle = item.englishTitle
      gallery.japaneseTitle = item.japaneseTitle
      gallery.category = item.category
      gallery.uploader = item.uploader
      gallery.postTime = item.postTime
      gallery.fileCount = item.fileCount
      gallery.rating = item.rating
      gallery.ratingFallBack = item.ratingFallBack
      gallery.colorRating = item.colorRating
      gallery.favNote = item.favNote
      gallery.favcat = 'l'
      gallery.favTitle = item.favTitle.length > 0 ? item.favTitle : 'Local'
      gallery.expunged = item.expunged
      gallery.lastViewTime = item.lastViewTime
      favorites.push(gallery)
    }
    await LocalFavSettings.restoreBackup(context, favorites)

    let searchHistory: string[] = []
    if (section.searchHistory !== undefined) {
      searchHistory = section.searchHistory
    }
    await SearchHistorySettings.restoreBackup(context, searchHistory)

    if (section.localBlock !== undefined) {
      const localBlock: LocalBlockSettingsSnapshot = new LocalBlockSettingsSnapshot()
      localBlock.filterCommentsByScore = section.localBlock.filterCommentsByScore
      localBlock.scoreFilteringThreshold = section.localBlock.scoreFilteringThreshold
      localBlock.commentDisplayMode = section.localBlock.commentDisplayMode
      for (let i: number = 0; i < section.localBlock.rules.length; i++) {
        const item: BackupLocalBlockRuleEntry = section.localBlock.rules[i]
        const rule: LocalBlockRuleSnapshot = new LocalBlockRuleSnapshot()
        rule.id = item.id
        rule.blockType = item.blockType
        rule.ruleText = item.ruleText
        rule.enabled = item.enabled
        rule.enableRegex = item.enableRegex
        if (rule.ruleText.length > 0) {
          localBlock.rules.push(rule)
        }
      }
      await LocalBlockSettings.restoreBackup(context, localBlock)
    }

    if (section.imageBlock !== undefined) {
      const imageBlockRules: ImageBlockRule[] = []
      for (let i: number = 0; i < section.imageBlock.rules.length; i++) {
        const item: BackupImageBlockRuleEntry = section.imageBlock.rules[i]
        if (item.id.length === 0 || item.hash.length === 0 || item.sourceType.length === 0) {
          continue
        }
        const rule: ImageBlockRule = new ImageBlockRule()
        rule.id = item.id
        rule.hash = item.hash
        rule.threshold = item.threshold
        rule.label = item.label
        rule.scope = item.scope
        rule.feedId = item.feedId
        rule.sourceType = item.sourceType
        rule.sourceUrl = item.sourceUrl
        rule.sourcePage = item.sourcePage
        rule.previewPath = ''
        rule.enabled = item.enabled
        rule.updatedAt = item.updatedAt
        imageBlockRules.push(rule)
      }
      await ImageBlockRepository.restoreUserRulesFromBackup(context, imageBlockRules)
      // Both a restore and its rollback must invalidate in-process decisions immediately.
      publishImageBlockRulesChanged('backup-restore')
    }

    if (section.customProfiles !== undefined) {
      const profiles: CustomProfile[] = []
      for (let i: number = 0; i < section.customProfiles.profiles.length; i++) {
        const item: BackupCustomProfileEntry = section.customProfiles.profiles[i]
        if (item.uuid.length === 0) {
          continue
        }
        const profile: CustomProfile = new CustomProfile()
        profile.uuid = item.uuid
        profile.name = item.name
        profile.listType = item.listType
        profile.searchText = item.searchText
        profile.selectedCats = item.selectedCats
        profile.advancedEnabled = item.advancedEnabled
        profile.minRating = item.minRating
        profile.pagesFrom = item.pagesFrom
        profile.pagesTo = item.pagesTo
        profile.requireTorrent = item.requireTorrent
        profile.showExpunged = item.showExpunged
        profile.disableLanguageFilter = item.disableLanguageFilter
        profile.disableUploaderFilter = item.disableUploaderFilter
        profile.disableTagFilter = item.disableTagFilter
        profile.favcat = item.favcat
        profile.toplistTl = item.toplistTl
        profile.displayMode = item.displayMode
        profile.hidden = item.hidden
        profile.builtin = item.builtin
        profile.lastEditTime = item.lastEditTime
        profiles.push(profile)
      }
      await CustomProfilesSettings.restoreBackup(context, profiles, section.customProfiles.selectedUuid)
    }
  }

  static async restoreLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    await GalleryReadProgressSettings.migrateLegacyPreferences(context)
    await ViewedHistorySettings.migrateLegacyPreferences(context)
    await LocalFavSettings.migrateLegacyPreferences(context)
    await SearchHistorySettings.migrateLegacyPreferences(context)
    await LocalBlockSettings.migrateLegacyPreferences(context)
    await CustomProfilesSettings.migrateLegacyPreferences(context)
  }

}

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
import { CustomProfilesSettings } from '../settings/CustomProfilesSettings'
import { ViewedGallery } from '../model/ViewedGallery'
import { ViewedHistorySettings } from '../settings/ViewedHistorySettings'
import {
  BackupCustomProfileEntry,
  BackupCustomProfilesSection,
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

  private static async exportCustomProfiles(
    context: common.UIAbilityContext,
  ): Promise<BackupCustomProfilesSection> {
    const source: CustomProfile[] = await CustomProfilesSettings.exportForBackup(context)
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
      selectedUuid: await CustomProfilesSettings.exportSelectedForBackup(context),
      profiles: out,
    }
  }

  static async restoreSection(
    context: common.UIAbilityContext,
    section: BackupLocalDataSection,
  ): Promise<void> {
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

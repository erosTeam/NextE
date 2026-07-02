import { SyncDatasetSelection } from './SyncTypes'

export class CloudSyncFeatureTables {
  static readonly READ_PROGRESS: string[] = ['gallery_read_progress']
  static readonly VIEWED_HISTORY: string[] = ['viewed_history']
  static readonly LOCAL_FAVORITES: string[] = ['local_favorites']
  static readonly SEARCH_HISTORY: string[] = ['search_history']
  static readonly LOCAL_BLOCK: string[] = ['local_block_settings', 'local_block_rules']
  static readonly IMAGE_BLOCK: string[] = ['image_block_user_rules']
  static readonly CUSTOM_PROFILES: string[] = ['custom_profiles', 'custom_profile_selection']
}

export const HUAWEI_CLOUD_SYNC_TABLES: string[] = [
  'gallery_read_progress',
  'viewed_history',
  'local_favorites',
  'search_history',
  'local_block_settings',
  'local_block_rules',
  'image_block_user_rules',
  'custom_profiles',
  'custom_profile_selection',
]

export function cloudSyncTablesForSelection(selection: SyncDatasetSelection): string[] {
  const tables: string[] = []
  if (selection.readProgress) {
    CloudSyncFeatureTables.READ_PROGRESS.forEach((table: string) => tables.push(table))
  }
  if (selection.viewedHistory) {
    CloudSyncFeatureTables.VIEWED_HISTORY.forEach((table: string) => tables.push(table))
  }
  if (selection.localFavorites) {
    CloudSyncFeatureTables.LOCAL_FAVORITES.forEach((table: string) => tables.push(table))
  }
  if (selection.searchHistory) {
    CloudSyncFeatureTables.SEARCH_HISTORY.forEach((table: string) => tables.push(table))
  }
  if (selection.localBlock) {
    CloudSyncFeatureTables.LOCAL_BLOCK.forEach((table: string) => tables.push(table))
  }
  if (selection.imageBlock) {
    CloudSyncFeatureTables.IMAGE_BLOCK.forEach((table: string) => tables.push(table))
  }
  if (selection.customProfiles) {
    CloudSyncFeatureTables.CUSTOM_PROFILES.forEach((table: string) => tables.push(table))
  }
  return tables
}

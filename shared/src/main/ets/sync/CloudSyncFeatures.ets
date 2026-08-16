import { SyncDatasetSelection } from './SyncTypes'

export class CloudSyncFeatureTables {
  static readonly READ_PROGRESS: string[] = ['gallery_read_progress']
  static readonly VIEWED_HISTORY: string[] = ['viewed_history']
  static readonly LOCAL_FAVORITES: string[] = ['local_favorites']
  static readonly SEARCH_HISTORY: string[] = ['search_history']
  static readonly LOCAL_BLOCK: string[] = ['local_block_settings', 'local_block_rules']
  static readonly IMAGE_BLOCK: string[] = ['image_block_user_rules']
  // Only the custom profile rows sync. The selected (last-viewed) tab is device-local so one
  // device's reading position never overrides another device's active tab.
  static readonly CUSTOM_PROFILES: string[] = ['custom_profiles']
}

// Complete durable cloud-table set for the disable-first pass. `custom_profile_selection` stays
// here so stale `autoSync: true` from older builds is neutralized to `autoSync: false`; it is never
// included in the enabled/selected subset (`cloudSyncTablesForSelection`), so no run uploads or
// downloads it and system cloud delivery cannot change the local tab selection anymore.
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

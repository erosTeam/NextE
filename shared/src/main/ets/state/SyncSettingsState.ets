import { AppStorageV2 } from '@kit.ArkUI'

export const SYNC_STATUS_IDLE: string = ''
export const SYNC_STATUS_OK: string = 'ok'
export const SYNC_STATUS_FAILED: string = 'failed'

/** Provider-neutral sync settings holder. Credentials are local-only settings, not sync data. */
@ObservedV2
export class SyncSettingsState {
  @Trace webdavUrl: string = ''
  @Trace webdavUsername: string = ''
  @Trace webdavPassword: string = ''
  @Trace datasetReadProgress: boolean = true
  @Trace datasetViewedHistory: boolean = true
  @Trace datasetLocalFavorites: boolean = true
  @Trace datasetSearchHistory: boolean = true
  @Trace datasetLocalBlock: boolean = true
  @Trace datasetCustomProfiles: boolean = true
  @Trace lastRunAt: number = 0
  @Trace lastStatus: string = SYNC_STATUS_IDLE
}

const SYNC_SETTINGS_KEY: string = 'v2:syncSettings'

export function connectSyncSettings(): SyncSettingsState {
  return AppStorageV2.connect(
    SyncSettingsState,
    SYNC_SETTINGS_KEY,
    () => new SyncSettingsState(),
  )!
}

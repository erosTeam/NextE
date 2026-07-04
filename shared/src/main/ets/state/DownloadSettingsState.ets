import { AppStorageV2 } from '@kit.ArkUI'

export enum DownloadOriginalMode {
  OFF = 'off',
  ASK = 'ask',
  ALWAYS = 'always',
}

export enum ArchiveBotType {
  EH_AR_BOT = 'eh_ar_bot',
  ARCHIVE_AT_HOME = 'archive_at_home',
}

/**
 * Download preferences shared by the queue workbench and the gallery image executor.
 * Defaults match a conservative first-run behavior: limited concurrency and ask before original files.
 */
@ObservedV2
export class DownloadSettingsState {
  @Trace concurrency: number = 2
  @Trace requestIntervalSeconds: number = 0
  @Trace retryCount: number = 2
  @Trace autoRetryFailed: boolean = true
  @Trace speedLimitKbps: number = 0
  @Trace notifyOnComplete: boolean = false
  @Trace hideFromMediaLibrary: boolean = true
  @Trace originalMode: string = DownloadOriginalMode.ASK
  @Trace archiveBotType: string = ArchiveBotType.EH_AR_BOT
  @Trace archiveBotAddress: string = 'https://eh-arc-api.mhdy.icu'
  @Trace archiveBotApiKey: string = ''
  @Trace archiveBotBalanceGp: number = -1
  @Trace archiveBotBalanceUpdatedAt: number = 0
}

const DOWNLOAD_SETTINGS_KEY: string = 'v2:downloadSettings'

export function connectDownloadSettings(): DownloadSettingsState {
  return AppStorageV2.connect(
    DownloadSettingsState,
    DOWNLOAD_SETTINGS_KEY,
    () => new DownloadSettingsState(),
  )!
}

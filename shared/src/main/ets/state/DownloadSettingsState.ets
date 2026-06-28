import { AppStorageV2 } from '@kit.ArkUI'

export enum DownloadOriginalMode {
  OFF = 'off',
  ASK = 'ask',
  ALWAYS = 'always',
}

/**
 * Download preferences shared by the queue workbench and the gallery image executor.
 * Defaults match a conservative first-run behavior: limited concurrency and ask before original files.
 */
@ObservedV2
export class DownloadSettingsState {
  @Trace concurrency: number = 2
  @Trace originalMode: string = DownloadOriginalMode.ASK
}

const DOWNLOAD_SETTINGS_KEY: string = 'v2:downloadSettings'

export function connectDownloadSettings(): DownloadSettingsState {
  return AppStorageV2.connect(
    DownloadSettingsState,
    DOWNLOAD_SETTINGS_KEY,
    () => new DownloadSettingsState(),
  )!
}

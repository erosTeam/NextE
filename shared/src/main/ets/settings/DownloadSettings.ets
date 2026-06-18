import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import {
  connectDownloadSettings,
  DownloadOriginalMode,
  DownloadSettingsState,
} from '../state/DownloadSettingsState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const MIN_CONCURRENCY: number = 1
const MAX_CONCURRENCY: number = 8

function clampConcurrency(value: number): number {
  return Math.min(MAX_CONCURRENCY, Math.max(MIN_CONCURRENCY, Math.round(value)))
}

function normalizeOriginalMode(value: string): string {
  if (
    value === DownloadOriginalMode.OFF ||
    value === DownloadOriginalMode.ASK ||
    value === DownloadOriginalMode.ALWAYS
  ) {
    return value
  }
  return DownloadOriginalMode.ASK
}

/** Single writer for persisted download preferences. */
export class DownloadSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const concurrency: number = store.getSync(StorageKeys.DOWNLOAD_CONCURRENCY, 2) as number
      const originalMode: string = store.getSync(
        StorageKeys.DOWNLOAD_ORIGINAL,
        DownloadOriginalMode.ASK,
      ) as string
      const state: DownloadSettingsState = connectDownloadSettings()
      state.concurrency = clampConcurrency(concurrency)
      state.originalMode = normalizeOriginalMode(originalMode)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_restore_failed', (error as Error).message)
    }
  }

  static async setConcurrency(
    context: common.UIAbilityContext,
    concurrency: number,
  ): Promise<void> {
    const value: number = clampConcurrency(concurrency)
    connectDownloadSettings().concurrency = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.DOWNLOAD_CONCURRENCY, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_concurrency_save_failed', (error as Error).message)
    }
  }

  static async setOriginalMode(
    context: common.UIAbilityContext,
    originalMode: string,
  ): Promise<void> {
    const value: string = normalizeOriginalMode(originalMode)
    connectDownloadSettings().originalMode = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.DOWNLOAD_ORIGINAL, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_original_save_failed', (error as Error).message)
    }
  }

  static minConcurrency(): number {
    return MIN_CONCURRENCY
  }

  static maxConcurrency(): number {
    return MAX_CONCURRENCY
  }
}

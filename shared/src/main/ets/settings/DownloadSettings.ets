import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import {
  ArchiveBotType,
  connectDownloadSettings,
  DownloadOriginalMode,
  DownloadSettingsState,
} from '../state/DownloadSettingsState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const MIN_CONCURRENCY: number = 1
const MAX_CONCURRENCY: number = 8
const MIN_REQUEST_INTERVAL_SECONDS: number = 0
const MAX_REQUEST_INTERVAL_SECONDS: number = 10
const MIN_RETRY_COUNT: number = 0
const MAX_RETRY_COUNT: number = 5
const MIN_SPEED_LIMIT_KBPS: number = 0
const MAX_SPEED_LIMIT_KBPS: number = 8192
const SPEED_LIMIT_STEP_KBPS: number = 256
const DEFAULT_EH_AR_BOT_ADDRESS: string = 'https://eh-arc-api.mhdy.icu'
const DEFAULT_ARCHIVE_AT_HOME_ADDRESS: string = 'https://api.archive-at-home.org/jhentai'

function clampConcurrency(value: number): number {
  return Math.min(MAX_CONCURRENCY, Math.max(MIN_CONCURRENCY, Math.round(value)))
}

function clampRequestIntervalSeconds(value: number): number {
  return Math.min(MAX_REQUEST_INTERVAL_SECONDS, Math.max(MIN_REQUEST_INTERVAL_SECONDS, Math.round(value)))
}

function clampRetryCount(value: number): number {
  return Math.min(MAX_RETRY_COUNT, Math.max(MIN_RETRY_COUNT, Math.round(value)))
}

function clampSpeedLimitKbps(value: number): number {
  const rounded: number = Math.round(value / SPEED_LIMIT_STEP_KBPS) * SPEED_LIMIT_STEP_KBPS
  return Math.min(MAX_SPEED_LIMIT_KBPS, Math.max(MIN_SPEED_LIMIT_KBPS, rounded))
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

function normalizeArchiveBotType(value: string): string {
  if (value === ArchiveBotType.EH_AR_BOT || value === ArchiveBotType.ARCHIVE_AT_HOME) {
    return value
  }
  return ArchiveBotType.EH_AR_BOT
}

function defaultArchiveBotAddress(type: string): string {
  return type === ArchiveBotType.ARCHIVE_AT_HOME ? DEFAULT_ARCHIVE_AT_HOME_ADDRESS : DEFAULT_EH_AR_BOT_ADDRESS
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
      const requestIntervalSeconds: number =
        store.getSync(StorageKeys.DOWNLOAD_REQUEST_INTERVAL_SECONDS, 0) as number
      const retryCount: number = store.getSync(StorageKeys.DOWNLOAD_RETRY_COUNT, 2) as number
      const speedLimitKbps: number = store.getSync(StorageKeys.DOWNLOAD_SPEED_LIMIT_KBPS, 0) as number
      const originalMode: string = store.getSync(
        StorageKeys.DOWNLOAD_ORIGINAL,
        DownloadOriginalMode.ASK,
      ) as string
      const archiveBotType: string = normalizeArchiveBotType(
        store.getSync(StorageKeys.DOWNLOAD_ARCHIVE_BOT_TYPE, ArchiveBotType.EH_AR_BOT) as string,
      )
      const archiveBotAddress: string = (store.getSync(
        StorageKeys.DOWNLOAD_ARCHIVE_BOT_ADDRESS,
        defaultArchiveBotAddress(archiveBotType),
      ) as string).trim()
      const archiveBotApiKey: string = (store.getSync(
        StorageKeys.DOWNLOAD_ARCHIVE_BOT_API_KEY,
        '',
      ) as string).trim()
      const state: DownloadSettingsState = connectDownloadSettings()
      state.concurrency = clampConcurrency(concurrency)
      state.requestIntervalSeconds = clampRequestIntervalSeconds(requestIntervalSeconds)
      state.retryCount = clampRetryCount(retryCount)
      state.speedLimitKbps = clampSpeedLimitKbps(speedLimitKbps)
      state.originalMode = normalizeOriginalMode(originalMode)
      state.archiveBotType = archiveBotType
      state.archiveBotAddress = archiveBotAddress.length > 0 ? archiveBotAddress : defaultArchiveBotAddress(archiveBotType)
      state.archiveBotApiKey = archiveBotApiKey
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

  static async setArchiveBotType(
    context: common.UIAbilityContext,
    botType: string,
  ): Promise<void> {
    const value: string = normalizeArchiveBotType(botType)
    const state: DownloadSettingsState = connectDownloadSettings()
    state.archiveBotType = value
    if (state.archiveBotAddress.length === 0 ||
      state.archiveBotAddress === DEFAULT_EH_AR_BOT_ADDRESS ||
      state.archiveBotAddress === DEFAULT_ARCHIVE_AT_HOME_ADDRESS) {
      state.archiveBotAddress = defaultArchiveBotAddress(value)
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.DOWNLOAD_ARCHIVE_BOT_TYPE, value)
      store.putSync(StorageKeys.DOWNLOAD_ARCHIVE_BOT_ADDRESS, state.archiveBotAddress)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_archive_bot_type_save_failed', (error as Error).message)
    }
  }

  static async setArchiveBotAddress(
    context: common.UIAbilityContext,
    address: string,
  ): Promise<void> {
    const value: string = address.trim()
    connectDownloadSettings().archiveBotAddress = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.DOWNLOAD_ARCHIVE_BOT_ADDRESS, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_archive_bot_address_save_failed', (error as Error).message)
    }
  }

  static async setArchiveBotApiKey(
    context: common.UIAbilityContext,
    apiKey: string,
  ): Promise<void> {
    const value: string = apiKey.trim()
    connectDownloadSettings().archiveBotApiKey = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.DOWNLOAD_ARCHIVE_BOT_API_KEY, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_archive_bot_key_save_failed', (error as Error).message)
    }
  }

  static archiveBotReady(state: DownloadSettingsState = connectDownloadSettings()): boolean {
    return state.archiveBotAddress.trim().length > 0 && state.archiveBotApiKey.trim().length > 0
  }

  static archiveBotDefaultAddress(botType: string): string {
    return defaultArchiveBotAddress(normalizeArchiveBotType(botType))
  }

  static async setRequestIntervalSeconds(
    context: common.UIAbilityContext,
    seconds: number,
  ): Promise<void> {
    const value: number = clampRequestIntervalSeconds(seconds)
    connectDownloadSettings().requestIntervalSeconds = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.DOWNLOAD_REQUEST_INTERVAL_SECONDS, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_request_interval_save_failed', (error as Error).message)
    }
  }

  static async setRetryCount(
    context: common.UIAbilityContext,
    retryCount: number,
  ): Promise<void> {
    const value: number = clampRetryCount(retryCount)
    connectDownloadSettings().retryCount = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.DOWNLOAD_RETRY_COUNT, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_retry_save_failed', (error as Error).message)
    }
  }

  static async setSpeedLimitKbps(
    context: common.UIAbilityContext,
    kbps: number,
  ): Promise<void> {
    const value: number = clampSpeedLimitKbps(kbps)
    connectDownloadSettings().speedLimitKbps = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.DOWNLOAD_SPEED_LIMIT_KBPS, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_speed_limit_save_failed', (error as Error).message)
    }
  }

  static minConcurrency(): number {
    return MIN_CONCURRENCY
  }

  static maxConcurrency(): number {
    return MAX_CONCURRENCY
  }

  static minRequestIntervalSeconds(): number {
    return MIN_REQUEST_INTERVAL_SECONDS
  }

  static maxRequestIntervalSeconds(): number {
    return MAX_REQUEST_INTERVAL_SECONDS
  }

  static minRetryCount(): number {
    return MIN_RETRY_COUNT
  }

  static maxRetryCount(): number {
    return MAX_RETRY_COUNT
  }

  static minSpeedLimitKbps(): number {
    return MIN_SPEED_LIMIT_KBPS
  }

  static maxSpeedLimitKbps(): number {
    return MAX_SPEED_LIMIT_KBPS
  }

  static speedLimitStepKbps(): number {
    return SPEED_LIMIT_STEP_KBPS
  }
}

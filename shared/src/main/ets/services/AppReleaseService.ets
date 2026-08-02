import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhConstants } from '../constants/EhConstants'
import { AppRelease, AppReleaseCacheSnapshot } from '../model/AppRelease'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'

const APP_RELEASES_API_URL: string = 'https://api.github.com/repos/erosTeam/NextE/releases'
const APP_RELEASE_PAGE_SIZE: number = 100
const APP_RELEASE_MAX_PAGE_COUNT: number = 50
const APP_RELEASE_CONNECT_TIMEOUT_MS: number = 15000
const APP_RELEASE_READ_TIMEOUT_MS: number = 20000
const APP_RELEASE_MAX_RESPONSE_BYTES: number = 2 * 1024 * 1024
const APP_RELEASE_CACHE_SCHEMA_VERSION: number = 1

class AppReleaseWire {
  tag_name: string = ''
  body: string = ''
  html_url: string = ''
  published_at: string = ''
  prerelease: boolean = false
  draft: boolean = false
}

class AppReleaseCachePayload {
  schemaVersion: number = APP_RELEASE_CACHE_SCHEMA_VERSION
  etag: string = ''
  checkedAt: number = 0
  releases: AppReleaseWire[] = []
}

class AppReleasePage {
  releases: AppRelease[] = []
  etag: string = ''
  hasNextPage: boolean = false
  notModified: boolean = false
}

/**
 * Single owner for app-release discovery and its persisted cache. The first About-page
 * paint can consume cached notes, while a stale snapshot is conditionally refreshed in
 * the background instead of forcing every viewer to wait for GitHub.
 */
export class AppReleaseService {
  private static memoryCache: AppReleaseCacheSnapshot | null = null
  private static refreshInFlight: Promise<AppReleaseCacheSnapshot> | null = null

  static async loadCached(context: common.UIAbilityContext): Promise<AppReleaseCacheSnapshot> {
    if (AppReleaseService.memoryCache !== null) {
      return AppReleaseService.memoryCache.copy()
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const raw: string = store.getSync(StorageKeys.APP_RELEASE_CACHE, '') as string
      const snapshot: AppReleaseCacheSnapshot = AppReleaseService.decodeCache(raw)
      AppReleaseService.memoryCache = snapshot.copy()
      return snapshot
    } catch (error) {
      DiagnosticLogger.warn('app-release', 'cache_load_failed', (error as Error).message)
      return new AppReleaseCacheSnapshot()
    }
  }

  static async refresh(
    context: common.UIAbilityContext,
    cached: AppReleaseCacheSnapshot,
    force: boolean,
  ): Promise<AppReleaseCacheSnapshot> {
    if (AppReleaseService.refreshInFlight !== null) {
      return AppReleaseService.refreshInFlight
    }
    const base: AppReleaseCacheSnapshot = AppReleaseService.memoryCache === null
      ? cached.copy()
      : AppReleaseService.memoryCache.copy()
    const active: Promise<AppReleaseCacheSnapshot> = AppReleaseService.refreshInternal(context, base, force)
      .finally(() => {
        AppReleaseService.refreshInFlight = null
      })
    AppReleaseService.refreshInFlight = active
    return active
  }

  static latestStable(snapshot: AppReleaseCacheSnapshot): AppRelease | null {
    let latest: AppRelease | null = null
    for (let i: number = 0; i < snapshot.releases.length; i++) {
      const release: AppRelease = snapshot.releases[i]
      if (release.prerelease || release.version().length === 0) {
        continue
      }
      if (latest === null || AppReleaseService.compareVersions(release.version(), latest.version()) > 0) {
        latest = release.copy()
      }
    }
    if (latest !== null) {
      return latest
    }
    if (snapshot.releases.length === 0) {
      return null
    }
    return snapshot.releases[0].copy()
  }

  static indexForVersion(releases: AppRelease[], version: string): number {
    const normalized: string = AppRelease.normalizeVersion(version)
    if (normalized.length === 0) {
      return 0
    }
    for (let i: number = 0; i < releases.length; i++) {
      if (releases[i].version() === normalized) {
        return i
      }
    }
    return 0
  }

  static compareVersions(current: string, latest: string): number {
    const leftParts: string[] = AppRelease.normalizeVersion(current).split('.')
    const rightParts: string[] = AppRelease.normalizeVersion(latest).split('.')
    const count: number = Math.max(leftParts.length, rightParts.length)
    for (let i: number = 0; i < count; i++) {
      const left: number = i < leftParts.length ? Number.parseInt(leftParts[i], 10) : 0
      const right: number = i < rightParts.length ? Number.parseInt(rightParts[i], 10) : 0
      const safeLeft: number = Number.isFinite(left) ? left : 0
      const safeRight: number = Number.isFinite(right) ? right : 0
      if (safeLeft < safeRight) {
        return -1
      }
      if (safeLeft > safeRight) {
        return 1
      }
    }
    return 0
  }

  private static async refreshInternal(
    context: common.UIAbilityContext,
    cached: AppReleaseCacheSnapshot,
    force: boolean,
  ): Promise<AppReleaseCacheSnapshot> {
    const firstPage: AppReleasePage = await AppReleaseService.fetchPage(
      1,
      force ? '' : cached.etag,
    )
    if (firstPage.notModified) {
      if (cached.releases.length === 0) {
        throw new Error('release cache missing after HTTP 304')
      }
      cached.checkedAt = Date.now()
      await AppReleaseService.persist(context, cached)
      DiagnosticLogger.info('app-release', 'refresh_not_modified', `releases=${cached.releases.length}`)
      return cached.copy()
    }

    const releases: AppRelease[] = firstPage.releases
    let page: number = 2
    let hasNextPage: boolean = firstPage.hasNextPage
    while (hasNextPage) {
      if (page > APP_RELEASE_MAX_PAGE_COUNT) {
        throw new Error(`release history exceeds ${APP_RELEASE_MAX_PAGE_COUNT} pages`)
      }
      const nextPage: AppReleasePage = await AppReleaseService.fetchPage(page, '')
      for (let i: number = 0; i < nextPage.releases.length; i++) {
        releases.push(nextPage.releases[i])
      }
      hasNextPage = nextPage.hasNextPage
      page++
    }

    const next: AppReleaseCacheSnapshot = new AppReleaseCacheSnapshot()
    next.releases = releases
    next.etag = firstPage.etag
    next.checkedAt = Date.now()
    await AppReleaseService.persist(context, next)
    DiagnosticLogger.info('app-release', 'refresh_completed', `releases=${next.releases.length}`)
    return next.copy()
  }

  private static async fetchPage(page: number, etag: string): Promise<AppReleasePage> {
    const headers: Record<string, string> = {
      'User-Agent': EhConstants.USER_AGENT,
      'Accept': 'application/vnd.github+json,application/json,*/*',
      'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
    }
    if (etag.length > 0) {
      headers['If-None-Match'] = etag
    }
    const response: AxiosTextResponse = await AxiosHttpClient.requestText(
      `${APP_RELEASES_API_URL}?per_page=${APP_RELEASE_PAGE_SIZE}&page=${page}`,
      'GET',
      headers,
      '',
      APP_RELEASE_CONNECT_TIMEOUT_MS,
      APP_RELEASE_READ_TIMEOUT_MS,
      APP_RELEASE_MAX_RESPONSE_BYTES,
    )
    const result: AppReleasePage = new AppReleasePage()
    if (response.statusCode === 304) {
      result.notModified = true
      return result
    }
    if (response.statusCode !== 200) {
      throw new Error(`GitHub releases HTTP ${response.statusCode}`)
    }
    let raw: AppReleaseWire[]
    try {
      raw = JSON.parse(response.body) as AppReleaseWire[]
    } catch (_error) {
      throw new Error('GitHub releases JSON invalid')
    }
    if (!Array.isArray(raw)) {
      throw new Error('GitHub releases JSON is not an array')
    }
    for (let i: number = 0; i < raw.length; i++) {
      const release: AppRelease | null = AppReleaseService.toRelease(raw[i])
      if (release !== null) {
        result.releases.push(release)
      }
    }
    result.etag = response.etag
    result.hasNextPage = raw.length >= APP_RELEASE_PAGE_SIZE
    return result
  }

  private static async persist(context: common.UIAbilityContext, snapshot: AppReleaseCacheSnapshot): Promise<void> {
    AppReleaseService.memoryCache = snapshot.copy()
    try {
      const payload: AppReleaseCachePayload = new AppReleaseCachePayload()
      payload.etag = snapshot.etag
      payload.checkedAt = snapshot.checkedAt
      for (let i: number = 0; i < snapshot.releases.length; i++) {
        const release: AppRelease = snapshot.releases[i]
        const wire: AppReleaseWire = new AppReleaseWire()
        wire.tag_name = release.tagName
        wire.body = release.body
        wire.html_url = release.htmlUrl
        wire.published_at = release.publishedAt
        wire.prerelease = release.prerelease
        payload.releases.push(wire)
      }
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.APP_RELEASE_CACHE, JSON.stringify(payload))
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('app-release', 'cache_save_failed', (error as Error).message)
    }
  }

  private static decodeCache(raw: string): AppReleaseCacheSnapshot {
    if (raw.length === 0) {
      return new AppReleaseCacheSnapshot()
    }
    try {
      const payload: AppReleaseCachePayload = JSON.parse(raw) as AppReleaseCachePayload
      if (payload.schemaVersion !== APP_RELEASE_CACHE_SCHEMA_VERSION || !Array.isArray(payload.releases)) {
        return new AppReleaseCacheSnapshot()
      }
      const snapshot: AppReleaseCacheSnapshot = new AppReleaseCacheSnapshot()
      snapshot.etag = typeof payload.etag === 'string' ? payload.etag : ''
      snapshot.checkedAt = typeof payload.checkedAt === 'number' && Number.isFinite(payload.checkedAt)
        ? payload.checkedAt
        : 0
      for (let i: number = 0; i < payload.releases.length; i++) {
        const release: AppRelease | null = AppReleaseService.toRelease(payload.releases[i])
        if (release !== null) {
          snapshot.releases.push(release)
        }
      }
      return snapshot
    } catch (_error) {
      return new AppReleaseCacheSnapshot()
    }
  }

  private static toRelease(raw: AppReleaseWire): AppRelease | null {
    if (raw.draft === true) {
      return null
    }
    const tagName: string = typeof raw.tag_name === 'string' ? raw.tag_name.trim() : ''
    const htmlUrl: string = typeof raw.html_url === 'string' ? raw.html_url.trim() : ''
    if (tagName.length === 0 || !htmlUrl.startsWith('https://')) {
      return null
    }
    const release: AppRelease = new AppRelease()
    release.tagName = tagName
    release.body = typeof raw.body === 'string' ? raw.body.trim() : ''
    release.htmlUrl = htmlUrl
    release.publishedAt = typeof raw.published_at === 'string' ? raw.published_at.trim() : ''
    release.prerelease = raw.prerelease === true
    return release
  }
}

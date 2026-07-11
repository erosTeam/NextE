import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { util } from '@kit.ArkTS'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { EhConstants } from '../constants/EhConstants'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { HtmlSelectorUtils } from '../parser/HtmlSelectorUtils'
import { connectAuth } from '../state/AuthState'
import { EhCookieStore } from '../network/EhCookieStore'
import { EhHttpClient, EhTextResponse } from '../network/EhHttpClient'
import { UserProfileRequestContext, UserProfileRequestFence } from './UserProfileRequestFence'

export class UserProfileInfo {
  nickName: string = ''
  avatarUrl: string = ''
}

class UserProfileSnapshot {
  nickName: string = ''
  avatarUrl: string = ''
}

export class UserProfileService {
  private static lastBlockedByCloudflare: boolean = false
  private static readonly AVATAR_CACHE_DIR: string = 'user-profile-avatar'

  static activeRequestContext(): UserProfileRequestContext {
    const cookieStore: EhCookieStore = EhCookieStore.getInstance()
    return new UserProfileRequestContext(
      cookieStore.get(EhConstants.COOKIE_MEMBER_ID),
      cookieStore.get(EhConstants.COOKIE_PASS_HASH),
    )
  }

  static profileUrlFor(request: UserProfileRequestContext): string {
    if (request.memberId.length === 0) {
      return EhConstants.FORUMS_BASE_URL
    }
    return `${EhConstants.FORUMS_BASE_URL}/index.php?showuser=${encodeURIComponent(request.memberId)}`
  }

  static activeProfileUrl(): string {
    return UserProfileService.profileUrlFor(UserProfileService.activeRequestContext())
  }

  static wasLastBlockedByCloudflare(): boolean {
    return UserProfileService.lastBlockedByCloudflare
  }

  static applyProfileHtml(html: string, request: UserProfileRequestContext): boolean {
    if (!UserProfileService.matchesActiveRequest(request)) {
      return UserProfileService.logDomEmpty('stale')
    }
    const info: UserProfileInfo = UserProfileService.parse(html)
    return UserProfileService.applyProfileInfo(info.nickName, info.avatarUrl, request)
  }

  static applyProfileDomPayload(raw: string, request: UserProfileRequestContext): boolean {
    if (!UserProfileService.matchesActiveRequest(request)) {
      return UserProfileService.logDomEmpty('stale')
    }
    let body: string = raw.trim()
    if (body.length === 0) {
      return UserProfileService.logDomEmpty('empty')
    }
    if (body.startsWith('"')) {
      try {
        body = JSON.parse(body) as string
      } catch (_error) {
        // Some ArkWeb builds return a raw string here; keep the original payload in that case.
      }
    }
    try {
      const rec = JSON.parse(body) as Record<string, Object>
      const nickName: string = typeof rec.nickName === 'string' ? (rec.nickName as string).trim() : ''
      const avatarUrl: string = typeof rec.avatarUrl === 'string' ? (rec.avatarUrl as string).trim() : ''
      const profileUrl: string = typeof rec.profileUrl === 'string' ? (rec.profileUrl as string) : ''
      if (!UserProfileRequestFence.matchesProfileUrl(request, profileUrl)) {
        return UserProfileService.logDomEmpty('profile_url')
      }
      return UserProfileService.applyProfileInfo(nickName, avatarUrl, request)
    } catch (_error) {
      return UserProfileService.logDomEmpty(`json hash=${DiagnosticLogger.ownerHash(raw)}`)
    }
  }

  static applyProfileInfo(
    nickName: string,
    avatarUrl: string,
    request: UserProfileRequestContext,
  ): boolean {
    const name: string = nickName.trim()
    if (name.length === 0) {
      return UserProfileService.logDomEmpty('name')
    }
    const auth = connectAuth()
    if (!UserProfileService.matchesActiveRequest(request) || auth.memberId !== request.memberId) {
      return UserProfileService.logDomEmpty('stale')
    }
    auth.nickName = name
    auth.avatarUrl = UserProfileService.normalizeAvatarUrl(avatarUrl)
    DiagnosticLogger.info(
      'auth',
      'user_profile_dom_applied',
      `profile=true avatar=${auth.avatarUrl.length > 0}`,
    )
    return true
  }

  static profileDomCaptureScript(): string {
    return `
        (() => {
          const name = document.querySelector('#profilename');
          const avatarBox = name && name.nextElementSibling
            ? name.nextElementSibling.nextElementSibling
            : null;
          const image = avatarBox ? avatarBox.querySelector('img') : null;
          let avatarUrl = image ? (image.getAttribute('src') || '') : '';
          if (image && image.complete && image.naturalWidth > 0 && image.naturalHeight > 0) {
            try {
              const canvas = document.createElement('canvas');
              canvas.width = image.naturalWidth;
              canvas.height = image.naturalHeight;
              const ctx = canvas.getContext('2d');
              ctx.drawImage(image, 0, 0);
              avatarUrl = canvas.toDataURL('image/png');
            } catch (e) {}
          }
          return JSON.stringify({
            nickName: name && name.textContent ? name.textContent.trim() : '',
            avatarUrl,
            profileUrl: String((location && location.href) || '')
          });
        })()
      `
  }

  static materializeAvatar(context: common.UIAbilityContext, request: UserProfileRequestContext): string {
    const auth = connectAuth()
    if (!UserProfileService.matchesActiveRequest(request) || auth.memberId !== request.memberId) {
      return auth.avatarUrl
    }
    const dataUri: string = auth.avatarUrl.trim()
    if (!dataUri.startsWith('data:image/')) {
      return dataUri
    }
    const commaIndex: number = dataUri.indexOf(',')
    if (commaIndex < 0) {
      return dataUri
    }
    const header: string = dataUri.substring(0, commaIndex).toLowerCase()
    if (header.indexOf(';base64') < 0) {
      return dataUri
    }
    const base64: string = dataUri.substring(commaIndex + 1)
    if (base64.length === 0) {
      return dataUri
    }
    try {
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(base64)
      const dir: string = `${context.cacheDir}/${UserProfileService.AVATAR_CACHE_DIR}`
      UserProfileService.ensureDirectory(dir)
      const filePath: string = `${dir}/${UserProfileService.avatarFileName(request.memberId, header)}`
      UserProfileService.writeBytes(filePath, bytes)
      auth.avatarUrl = UserProfileService.displayUri(filePath)
      DiagnosticLogger.info(
        'auth',
        'user_profile_avatar_cached',
        `bytes=${bytes.byteLength} memberHash=${DiagnosticLogger.ownerHash(request.memberId)}`,
      )
      return auth.avatarUrl
    } catch (error) {
      DiagnosticLogger.warn('auth', 'user_profile_avatar_cache_failed', (error as Error).message)
      return dataUri
    }
  }

  static async restoreActive(
    context: common.UIAbilityContext,
    request: UserProfileRequestContext,
  ): Promise<boolean> {
    if (!UserProfileService.matchesActiveRequest(request)) {
      return false
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      if (!UserProfileService.matchesActiveRequest(request)) {
        return false
      }
      const raw: string = store.getSync(UserProfileService.profileKey(request.memberId), '') as string
      if (raw.length === 0) {
        return false
      }
      const rec = JSON.parse(raw) as Record<string, Object>
      const auth = connectAuth()
      if (!UserProfileService.matchesActiveRequest(request) || auth.memberId !== request.memberId) {
        return false
      }
      auth.nickName = typeof rec.nickName === 'string' ? (rec.nickName as string) : ''
      auth.avatarUrl = typeof rec.avatarUrl === 'string' ? (rec.avatarUrl as string) : ''
      return true
    } catch (error) {
      DiagnosticLogger.warn('auth', 'user_profile_restore_failed', (error as Error).message)
      return false
    }
  }

  static async loadStoredProfile(
    context: common.UIAbilityContext,
    memberId: string,
  ): Promise<UserProfileInfo> {
    const info = new UserProfileInfo()
    if (memberId.length === 0) {
      return info
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(UserProfileService.profileKey(memberId), '') as string
      if (raw.length === 0) {
        return info
      }
      const rec = JSON.parse(raw) as Record<string, Object>
      info.nickName = typeof rec.nickName === 'string' ? (rec.nickName as string) : ''
      info.avatarUrl = typeof rec.avatarUrl === 'string' ? (rec.avatarUrl as string) : ''
    } catch (error) {
      DiagnosticLogger.warn('auth', 'user_profile_snapshot_load_failed', (error as Error).message)
    }
    return info
  }

  static async saveActive(
    context: common.UIAbilityContext,
    request: UserProfileRequestContext,
  ): Promise<boolean> {
    const auth = connectAuth()
    if (
      !UserProfileService.matchesActiveRequest(request) ||
      auth.memberId !== request.memberId ||
      auth.nickName.length === 0
    ) {
      return false
    }
    try {
      const snapshot = new UserProfileSnapshot()
      snapshot.nickName = auth.nickName
      snapshot.avatarUrl = auth.avatarUrl
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      if (!UserProfileService.matchesActiveRequest(request) || auth.memberId !== request.memberId) {
        return false
      }
      store.putSync(UserProfileService.profileKey(request.memberId), JSON.stringify(snapshot))
      store.flushSync()
      return true
    } catch (error) {
      DiagnosticLogger.warn('auth', 'user_profile_save_failed', (error as Error).message)
      return false
    }
  }

  static async refreshAndSaveActive(context: common.UIAbilityContext): Promise<boolean> {
    const request: UserProfileRequestContext = UserProfileService.activeRequestContext()
    try {
      const ok: boolean = await UserProfileService.refreshActive(request)
      if (!ok) {
        return false
      }
      UserProfileService.materializeAvatar(context, request)
      return await UserProfileService.saveActive(context, request)
    } catch (error) {
      DiagnosticLogger.warn('auth', 'user_profile_refresh_save_failed', (error as Error).message)
      return false
    }
  }

  private static profileKey(memberId: string): string {
    return `${StorageKeys.USER_PROFILE_PREFIX}${memberId}`
  }

  private static matchesActiveRequest(request: UserProfileRequestContext): boolean {
    return UserProfileRequestFence.matches(request, UserProfileService.activeRequestContext())
  }

  private static logDomEmpty(reason: string): boolean {
    DiagnosticLogger.info('auth', 'user_profile_dom_empty', reason)
    return false
  }

  private static normalizeAvatarUrl(raw: string): string {
    const url: string = raw.trim()
    if (url.length === 0 || url.startsWith('http') || url.startsWith('data:')) {
      return url
    }
    if (url.startsWith('/')) {
      return `${EhConstants.FORUMS_BASE_URL}${url}`
    }
    return `${EhConstants.FORUMS_BASE_URL}/${url}`
  }

  private static avatarFileName(memberId: string, header: string): string {
    let stem: string = memberId.trim()
    if (stem.length === 0) {
      stem = 'active'
    }
    if (header.indexOf('image/jpeg') >= 0 || header.indexOf('image/jpg') >= 0) {
      return `${stem}.jpg`
    }
    if (header.indexOf('image/webp') >= 0) {
      return `${stem}.webp`
    }
    return `${stem}.png`
  }

  private static displayUri(path: string): string {
    return fileUri.getUriFromPath(path)
  }

  private static ensureDirectory(dir: string): void {
    try {
      fileIo.mkdirSync(dir, true)
    } catch (error) {
      if (!fileIo.accessSync(dir)) {
        throw error as Error
      }
    }
  }

  private static writeBytes(filePath: string, bytes: Uint8Array): void {
    let file: fileIo.File | null = null
    try {
      const buffer: ArrayBuffer = new ArrayBuffer(bytes.byteLength)
      const out = new Uint8Array(buffer)
      for (let i: number = 0; i < bytes.byteLength; i++) {
        out[i] = bytes[i]
      }
      file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, buffer)
    } finally {
      UserProfileService.closeFileBestEffort(file)
    }
  }

  private static closeFileBestEffort(file: fileIo.File | null): void {
    if (!file) {
      return
    }
    try {
      fileIo.closeSync(file)
    } catch (_error) {
    }
  }

  static async refreshActive(request: UserProfileRequestContext): Promise<boolean> {
    UserProfileService.lastBlockedByCloudflare = false
    if (!UserProfileService.matchesActiveRequest(request)) {
      return false
    }
    const resp: EhTextResponse = await EhHttpClient.getInstance().getTextWithReferer(
      UserProfileService.profileUrlFor(request),
      `${EhConstants.FORUMS_BASE_URL}/index.php`,
    )
    const info: UserProfileInfo = UserProfileService.parse(resp.body)
    const hitProfile: boolean = info.nickName.length > 0
    const hitCf: boolean =
      resp.body.indexOf('Cloudflare') >= 0 || resp.body.indexOf('cf-browser-verification') >= 0
    const title: string = HtmlSelectorUtils.group1(resp.body, /<title[^>]*>([\s\S]*?)<\/title>/)
      .replace(/<[^>]+>/g, '')
      .trim()
    UserProfileService.lastBlockedByCloudflare =
      resp.statusCode === 403 && (hitCf || title.indexOf('Just a moment') >= 0)
    DiagnosticLogger.info(
      'auth',
      'user_profile_probe',
      `status=${resp.statusCode} profile=${hitProfile} cf=${hitCf} len=${resp.body.length} title=${title} cookies=${EhCookieStore.getInstance().nameSummary()} bodyHash=${DiagnosticLogger.ownerHash(resp.body)}`,
    )
    if (!hitProfile) {
      return false
    }
    if (!UserProfileService.matchesActiveRequest(request)) {
      DiagnosticLogger.info(
        'auth',
        'user_profile_probe_stale',
        `memberHash=${DiagnosticLogger.ownerHash(request.memberId)}`,
      )
      return false
    }
    return UserProfileService.applyProfileHtml(resp.body, request)
  }

  static parse(html: string): UserProfileInfo {
    const info = new UserProfileInfo()
    const name: string = HtmlSelectorUtils.group1(
      html,
      /<[^>]*id=["']profilename["'][^>]*>([\s\S]*?)<\/[^>]+>/,
    ).replace(/<[^>]+>/g, '').trim()
    info.nickName = HtmlSelectorUtils.htmlUnescape(name)
    let nameAt: number = html.indexOf('id="profilename"')
    if (nameAt < 0) {
      nameAt = html.indexOf("id='profilename'")
    }
    if (nameAt < 0) {
      return info
    }
    const tail: string = html.substring(nameAt, Math.min(html.length, nameAt + 4000))
    const src: string = HtmlSelectorUtils.htmlUnescape(
      HtmlSelectorUtils.group1(tail, /<img[^>]+src=["']([^"']+)["']/),
    ).trim()
    if (src.length > 0) {
      info.avatarUrl = UserProfileService.normalizeAvatarUrl(src)
    }
    return info
  }
}

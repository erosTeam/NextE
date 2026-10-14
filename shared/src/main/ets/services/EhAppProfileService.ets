import { common } from '@kit.AbilityKit'
import { EhApiService } from '../network/EhApiService'
import { EhCookieStore } from '../network/EhCookieStore'
import { EhError, EhErrorKind } from '../network/EhError'
import { EhProfile, EhProfileSettings } from '../model/EhProfileSettings'
import { CookieJarSettings } from '../settings/CookieJarSettings'
import { EhAppProfileSettings } from '../settings/EhAppProfileSettings'
import { connectEhAppProfile } from '../state/EhAppProfileState'
import { UserTagContextService, UserTagRequestContext, UserTagRequestFence } from './UserTagContextService'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/** Select once per active account/site scope, without changing the website's default profile. */
export class EhAppProfileService {
  static readonly PROFILE_NAME: string = 'NextE'
  private static context: common.UIAbilityContext | null = null
  private static ready: UserTagRequestContext | null = null
  private static readyRevision: number = -1
  private static lastFailure: EhError | null = null
  private static failureRequest: UserTagRequestContext | null = null
  private static pending: Promise<boolean> | null = null
  private static pendingRequest: UserTagRequestContext | null = null
  private static pendingRevision: number = -1
  // A lost create response must never cause another automatic create in this process.
  private static uncertainCreates: Set<string> = new Set<string>()

  static initialize(context: common.UIAbilityContext): void {
    EhAppProfileService.context = context
    EhAppProfileService.ready = null
  }

  private static isCurrent(request: UserTagRequestContext, revision: number): boolean {
    return connectEhAppProfile().enabled &&
      revision === EhAppProfileSettings.revision &&
      UserTagContextService.isCurrentAuthenticated(request)
  }

  static async ensureSelected(): Promise<boolean> {
    if (EhAppProfileService.context === null || !connectEhAppProfile().enabled || !EhCookieStore.getInstance().isLogin()) {
      return true
    }
    const request: UserTagRequestContext = UserTagContextService.captureActiveRequest()
    const revision: number = EhAppProfileSettings.revision
    const ready: UserTagRequestContext | null = EhAppProfileService.ready
    if (ready !== null && EhAppProfileService.readyRevision === revision &&
      UserTagRequestFence.sameScope(ready, request) && UserTagContextService.isCurrentAuthenticated(ready)) {
      return true
    }
    const previous: Promise<boolean> | null = EhAppProfileService.pending
    if (previous !== null) {
      const previousRequest: UserTagRequestContext | null = EhAppProfileService.pendingRequest
      const sameRequest: boolean = previousRequest !== null &&
        previousRequest.generation === request.generation &&
        UserTagRequestFence.sameScope(previousRequest, request) && EhAppProfileService.pendingRevision === revision
      const applied: boolean = await previous
      if (!EhAppProfileService.isCurrent(request, revision)) {
        return false
      }
      return sameRequest ? applied : await EhAppProfileService.ensureSelected()
    }
    const pending: Promise<boolean> = EhAppProfileService.prepare(request, revision)
    EhAppProfileService.pending = pending
    EhAppProfileService.pendingRequest = request
    EhAppProfileService.pendingRevision = revision
    try {
      return await pending
    } finally {
      if (EhAppProfileService.pending === pending) {
        EhAppProfileService.pending = null
        EhAppProfileService.pendingRequest = null
      }
    }
  }

  static listFailure(): EhError {
    const request: UserTagRequestContext | null = EhAppProfileService.failureRequest
    const failure: EhError | null = EhAppProfileService.lastFailure
    return request !== null && failure !== null && UserTagContextService.isCurrentAuthenticated(request)
      ? failure
      : new EhError(EhErrorKind.Network, 'dedicated gallery list profile is not ready')
  }

  private static findAppProfile(settings: EhProfileSettings): EhProfile | null {
    let found: EhProfile | null = null
    for (const profile of settings.profiles) {
      if (profile.name.trim() === EhAppProfileService.PROFILE_NAME) {
        if (found !== null) {
          throw new EhError(EhErrorKind.ParseFailure, 'dedicated profile name is ambiguous')
        }
        found = profile
      }
    }
    return found
  }

  private static selectedAppProfile(settings: EhProfileSettings): string {
    const profile: EhProfile | null = EhAppProfileService.findAppProfile(settings)
    if (profile === null || !profile.selected || profile.value !== settings.selectedProfile) {
      return ''
    }
    return settings.selectedProfileCookieValue()
  }

  private static async prepare(request: UserTagRequestContext, revision: number): Promise<boolean> {
    try {
      const api: EhApiService = EhApiService.getInstance()
      let settings: EhProfileSettings = await api.getUserConfig(request.isEx)
      if (!EhAppProfileService.isCurrent(request, revision)) {
        return false
      }
      if (settings.profiles.length === 0) {
        throw new EhError(EhErrorKind.ParseFailure, 'dedicated profile list is unavailable')
      }
      const profile: EhProfile | null = EhAppProfileService.findAppProfile(settings)
      if (EhAppProfileService.selectedAppProfile(settings).length === 0) {
        if (profile === null && EhAppProfileService.uncertainCreates.has(request.memberId)) {
          throw new EhError(EhErrorKind.Network, 'dedicated profile creation remains unconfirmed')
        }
        if (!EhAppProfileService.isCurrent(request, revision)) {
          return false
        }
        if (profile === null) {
          EhAppProfileService.uncertainCreates.add(request.memberId)
        }
        try {
          settings = await api.postProfileAction(
            request.isEx,
            profile === null ? 'create' : '',
            profile === null ? '' : `${profile.value}`,
            profile === null ? EhAppProfileService.PROFILE_NAME : '',
          )
        } catch (error) {
          // Read back an ambiguous write; never replay the POST. A later explicit refresh may
          // select a confirmed existing profile, but cannot create another after a lost response.
          if (!EhAppProfileService.isCurrent(request, revision)) {
            return false
          }
          settings = await api.getUserConfig(request.isEx)
          if (EhAppProfileService.selectedAppProfile(settings).length === 0) {
            throw error as Error
          }
        }
      }
      const selected: string = EhAppProfileService.selectedAppProfile(settings)
      const context: common.UIAbilityContext | null = EhAppProfileService.context
      if (selected.length === 0) {
        throw new EhError(EhErrorKind.ParseFailure, 'dedicated profile selection was not confirmed')
      }
      if (context === null || !EhAppProfileService.isCurrent(request, revision)) {
        return false
      }
      const persisted: boolean = await CookieJarSettings.persistServerSelectedProfile(
        context, request.memberId, request.passHash, request.isEx, selected,
        () => EhAppProfileService.isCurrent(request, revision),
      )
      if (!EhAppProfileService.isCurrent(request, revision)) {
        return false
      }
      if (!persisted) {
        throw new EhError(EhErrorKind.Network, 'dedicated profile selection could not be persisted')
      }
      EhAppProfileService.lastFailure = null
      EhAppProfileService.failureRequest = null
      EhAppProfileService.uncertainCreates.delete(request.memberId)
      EhAppProfileService.ready = request
      EhAppProfileService.readyRevision = revision
      DiagnosticLogger.info('auth', 'eh_app_profile_ready', 'selected=true')
      return true
    } catch (error) {
      if (EhAppProfileService.isCurrent(request, revision)) {
        EhAppProfileService.lastFailure = new EhError(EhError.kindOf(error as Object), 'dedicated profile preparation failed')
        EhAppProfileService.failureRequest = request
      }
      DiagnosticLogger.warn('auth', 'eh_app_profile_failed', `kind=${EhError.kindOf(error as Object)}`)
      return false
    }
  }
}

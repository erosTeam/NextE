import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { EhConstants } from '../constants/EhConstants'
import { EhCookieStore } from '../network/EhCookieStore'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectAccountList, AccountListState } from '../state/AccountListState'

/**
 * Persistence for the saved-accounts list, layered ADDITIVELY on top of the single-jar login: each saved
 * account is one cookie bundle ("name=value; …", carrying its own ipb_member_id), stored one per line under
 * ACCOUNTS_KEY. The ACTIVE account is whichever bundle is currently in EhCookieStore (and persisted as
 * COOKIE_JAR by CookieJarSettings) — recording/removing here never changes how the active account logs in
 * or restores, so login persistence can't break. Switching loads a saved bundle into the jar (in
 * CookieJarSettings). Only logs counts/ids, never cookie values.
 */
class AccountRecord {
  memberId: string = ''
  bundle: string = ''

  constructor(memberId: string, bundle: string) {
    this.memberId = memberId
    this.bundle = bundle
  }
}

export class AccountListSettings {
  private static memberIdOf(bundle: string): string {
    const pairs: string[] = bundle.split(';')
    for (const pair of pairs) {
      const trimmed: string = pair.trim()
      const eq: number = trimmed.indexOf('=')
      if (eq > 0 && trimmed.substring(0, eq) === EhConstants.COOKIE_MEMBER_ID) {
        return trimmed.substring(eq + 1).trim()
      }
    }
    return ''
  }

  private static parse(raw: string): AccountRecord[] {
    const list: AccountRecord[] = []
    if (raw.length === 0) {
      return list
    }
    const lines: string[] = raw.split('\n')
    for (const line of lines) {
      const bundle: string = line.trim()
      if (bundle.length === 0) {
        continue
      }
      const mid: string = AccountListSettings.memberIdOf(bundle)
      if (mid.length > 0) {
        list.push(new AccountRecord(mid, bundle))
      }
    }
    return list
  }

  private static serialize(records: AccountRecord[]): string {
    const parts: string[] = []
    for (const r of records) {
      parts.push(r.bundle)
    }
    return parts.join('\n')
  }

  private static syncState(records: AccountRecord[]): void {
    const state: AccountListState = connectAccountList()
    const ids: string[] = []
    for (const r of records) {
      ids.push(r.memberId)
    }
    state.accounts = ids
    state.activeMemberId = EhCookieStore.getInstance().get(EhConstants.COOKIE_MEMBER_ID)
  }

  private static async read(context: common.UIAbilityContext): Promise<AccountRecord[]> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    return AccountListSettings.parse(store.getSync(StorageKeys.AUTH_ACCOUNTS, '') as string)
  }

  /** Mirror the persisted list into the reactive state (no mutation). */
  static async load(context: common.UIAbilityContext): Promise<void> {
    try {
      AccountListSettings.syncState(await AccountListSettings.read(context))
    } catch (error) {
      DiagnosticLogger.warn('auth', 'account_list_load_failed', (error as Error).message)
    }
  }

  /** Insert/refresh the currently-loaded account (EhCookieStore) into the saved list. */
  static async recordActive(context: common.UIAbilityContext): Promise<void> {
    const cookieStore: EhCookieStore = EhCookieStore.getInstance()
    if (!cookieStore.isLogin()) {
      return
    }
    const mid: string = cookieStore.get(EhConstants.COOKIE_MEMBER_ID)
    const bundle: string = cookieStore.serializeForPersist()
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const records: AccountRecord[] = AccountListSettings.parse(
        store.getSync(StorageKeys.AUTH_ACCOUNTS, '') as string,
      )
      const updated: AccountRecord[] = []
      let found: boolean = false
      for (const r of records) {
        if (r.memberId === mid) {
          updated.push(new AccountRecord(mid, bundle))
          found = true
        } else {
          updated.push(r)
        }
      }
      if (!found) {
        updated.push(new AccountRecord(mid, bundle))
      }
      store.putSync(StorageKeys.AUTH_ACCOUNTS, AccountListSettings.serialize(updated))
      store.flushSync()
      AccountListSettings.syncState(updated)
      DiagnosticLogger.info('auth', 'account_recorded', `count=${updated.length}`)
    } catch (error) {
      DiagnosticLogger.warn('auth', 'account_list_record_failed', (error as Error).message)
    }
  }

  /**
   * Check whether a saved account still exists in the Preferences transaction held by the caller.
   * Profile persistence uses this before changing the active jar, so a delayed response cannot restore
   * an account that was removed while the request was in flight.
   */
  static hasStoredMember(store: preferences.Preferences, memberId: string): boolean {
    if (memberId.length === 0) {
      return false
    }
    try {
      const records: AccountRecord[] = AccountListSettings.parse(
        store.getSync(StorageKeys.AUTH_ACCOUNTS, '') as string,
      )
      for (let i: number = 0; i < records.length; i++) {
        if (records[i].memberId === memberId) {
          return true
        }
      }
    } catch (error) {
      DiagnosticLogger.warn('auth', 'account_list_member_lookup_failed', (error as Error).message)
    }
    return false
  }

  /**
   * Replace an existing account bundle in the caller's Preferences transaction. This intentionally never
   * appends: a delayed profile response must not recreate an account the user just removed.
   */
  static replaceExistingBundleInStore(
    store: preferences.Preferences,
    memberId: string,
    bundle: string,
  ): boolean {
    if (memberId.length === 0 || bundle.length === 0) {
      return false
    }
    try {
      const records: AccountRecord[] = AccountListSettings.parse(
        store.getSync(StorageKeys.AUTH_ACCOUNTS, '') as string,
      )
      const updated: AccountRecord[] = []
      let found: boolean = false
      for (let i: number = 0; i < records.length; i++) {
        const record: AccountRecord = records[i]
        if (record.memberId === memberId) {
          updated.push(new AccountRecord(memberId, bundle))
          found = true
        } else {
          updated.push(record)
        }
      }
      if (!found) {
        return false
      }
      store.putSync(StorageKeys.AUTH_ACCOUNTS, AccountListSettings.serialize(updated))
      return true
    } catch (error) {
      DiagnosticLogger.warn('auth', 'account_bundle_replace_failed', (error as Error).message)
      return false
    }
  }

  /** The cookie bundle for a saved account (used to switch into it). '' if absent. */
  static async bundleOf(context: common.UIAbilityContext, memberId: string): Promise<string> {
    try {
      const records: AccountRecord[] = await AccountListSettings.read(context)
      for (const r of records) {
        if (r.memberId === memberId) {
          return r.bundle
        }
      }
    } catch (error) {
      DiagnosticLogger.warn('auth', 'account_list_bundle_failed', (error as Error).message)
    }
    return ''
  }

  /** Remove a saved account; returns the remaining member ids (saved order). */
  static async remove(context: common.UIAbilityContext, memberId: string): Promise<string[]> {
    const remaining: string[] = []
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const records: AccountRecord[] = AccountListSettings.parse(
        store.getSync(StorageKeys.AUTH_ACCOUNTS, '') as string,
      )
      const updated: AccountRecord[] = []
      for (const r of records) {
        if (r.memberId !== memberId) {
          updated.push(r)
          remaining.push(r.memberId)
        }
      }
      store.putSync(StorageKeys.AUTH_ACCOUNTS, AccountListSettings.serialize(updated))
      store.flushSync()
      AccountListSettings.syncState(updated)
    } catch (error) {
      DiagnosticLogger.warn('auth', 'account_list_remove_failed', (error as Error).message)
    }
    return remaining
  }
}

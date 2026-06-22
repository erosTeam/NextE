import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Reactive list of saved EH accounts for the account switcher. Holds only the displayable member ids
 * (saved order) + the active member id; the actual cookie bundles live in AccountListSettings
 * (preferences) and are never mirrored into this reactive holder. AccountListSettings is the single
 * writer.
 */
@ObservedV2
export class AccountListState {
  @Trace accounts: string[] = []
  @Trace activeMemberId: string = ''
}

const ACCOUNT_LIST_KEY: string = 'v2:accountList'

export function connectAccountList(): AccountListState {
  return AppStorageV2.connect(AccountListState, ACCOUNT_LIST_KEY, () => new AccountListState())!
}

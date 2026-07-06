import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  AuthState,
  ConciseListRow,
  CookieJarSettings,
  DiagnosticLogger,
  EhApiService,
  EhHome,
  EhProfile,
  EhProfileSettings,
  GroupedListSection,
  SecondaryListScaffold,
  SiteModeState,
  ThemeConstants,
  connectAuth,
  connectNavStack,
  connectSiteMode,
  immersiveTitleBarOpts,
  AccountListState,
  connectAccountList,
  UserProfileService,
  UserProfileInfo,
  GalleryWebParams,
} from 'shared'

/**
 * The account hub (signed-in only — Settings routes signed-out straight to the login page). The
 * multi-account switcher: each saved account is a card, the active one selected via Radio, tap a row to
 * switch, swipe left to delete (no confirm — low misoperation risk). The title bar's top-right
 * person_badge_plus opens the login page to add another account. The bottom 退出登录 (with a confirm) logs
 * out the current account — both delete paths reuse removeAccount (switch to another if any, else logged
 * out). Nick/avatar refresh is best-effort from the forums profile page; ID remains the fallback.
 */
@ComponentV2
struct AccountAvatar {
  @Param memberId: string = '';
  @Param avatarUrl: string = '';
  @Param avatarSize: number = 44;

  private displayAvatarUrl(): string {
    return this.avatarUrl.trim()
  }

  build() {
    Stack() {
      if (this.displayAvatarUrl().length > 0) {
        Image(this.displayAvatarUrl())
          .objectFit(ImageFit.Cover)
          .width(this.avatarSize)
          .height(this.avatarSize)
      } else {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(this.avatarSize / 2)
          .fontColor([Color.White])
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .borderRadius(this.avatarSize / 2)
    .clip(true)
    .backgroundColor(ThemeConstants.BRAND_PRIMARY)
  }
}

class AccountProfileSummary {
  memberId: string = ''
  nickName: string = ''
  avatarUrl: string = ''

  constructor(memberId: string, nickName: string, avatarUrl: string) {
    this.memberId = memberId
    this.nickName = nickName
    this.avatarUrl = avatarUrl
  }
}

class AccountDashboardCache {
  private static homeSnapshots: Map<string, EhHome> = new Map<string, EhHome>()
  private static profileSnapshots: Map<string, EhProfileSettings> = new Map<string, EhProfileSettings>()

  static seedHome(key: string): EhHome | null {
    const cached: EhHome | undefined = AccountDashboardCache.homeSnapshots.get(key)
    if (cached === undefined) {
      return null
    }
    return cached.copy()
  }

  static putHome(key: string, home: EhHome): void {
    AccountDashboardCache.homeSnapshots.set(key, home.copy())
  }

  static seedProfile(key: string): EhProfileSettings | null {
    const cached: EhProfileSettings | undefined = AccountDashboardCache.profileSnapshots.get(key)
    if (cached === undefined) {
      return null
    }
    return cached.copy()
  }

  static putProfile(key: string, settings: EhProfileSettings): void {
    AccountDashboardCache.profileSnapshots.set(key, settings.copy())
  }
}

@ComponentV2
export struct AccountPage {
  @Local auth: AuthState = connectAuth();
  @Local accountList: AccountListState = connectAccountList();
  @Local site: SiteModeState = connectSiteMode();
  @Local home: EhHome = new EhHome();
  @Local profileSettings: EhProfileSettings = new EhProfileSettings();
  @Local accountProfiles: AccountProfileSummary[] = [];
  @Local homeLoading: boolean = false;
  @Local homeResetting: boolean = false;
  @Local profileLoading: boolean = false;
  @Local homeLoaded: boolean = false;
  @Local profileLoaded: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private homeLoadingKey: string = '';
  private profileLoadingKey: string = '';

  aboutToAppear(): void {
    this.restoreProfile()
    this.loadAccountProfiles()
    this.restoreDashboardCache()
    this.loadAccountDashboard()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private async restoreProfile(): Promise<void> {
    if (!this.auth.isLogin) {
      return
    }
    await UserProfileService.restoreActive(this.ctx())
    UserProfileService.materializeAvatar(this.ctx())
    this.loadAccountProfiles()
  }

  private async loadAccountProfiles(): Promise<void> {
    const ids: string[] = this.accountList.accounts
    const rows: AccountProfileSummary[] = []
    for (let i: number = 0; i < ids.length; i++) {
      const memberId: string = ids[i]
      const info: UserProfileInfo = await UserProfileService.loadStoredProfile(this.ctx(), memberId)
      rows.push(new AccountProfileSummary(memberId, info.nickName, info.avatarUrl))
    }
    this.accountProfiles = rows
  }

  private loadAccountDashboard(): void {
    if (!this.auth.isLogin) {
      return
    }
    this.loadHomeLimits()
    this.loadProfileSettings()
  }

  private activeAccountKey(): string {
    if (this.auth.memberId.length > 0) {
      return this.auth.memberId
    }
    return this.accountList.activeMemberId
  }

  private profileCacheKey(): string {
    const siteKey: string = this.site.isEx ? 'ex' : 'eh'
    return `${this.activeAccountKey()}:${siteKey}`
  }

  private restoreDashboardCache(): void {
    const accountKey: string = this.activeAccountKey()
    if (!this.auth.isLogin || accountKey.length === 0) {
      return
    }
    const cachedHome: EhHome | null = AccountDashboardCache.seedHome(accountKey)
    if (cachedHome !== null) {
      this.home = cachedHome
      this.homeLoaded = true
    }
    const cachedProfile: EhProfileSettings | null = AccountDashboardCache.seedProfile(this.profileCacheKey())
    if (cachedProfile !== null) {
      this.profileSettings = cachedProfile
      this.profileLoaded = true
    }
  }

  private resetDashboardStateForAccount(): void {
    this.homeLoading = false
    this.profileLoading = false
    this.homeLoadingKey = ''
    this.profileLoadingKey = ''
    this.home = new EhHome()
    this.profileSettings = new EhProfileSettings()
    this.homeLoaded = false
    this.profileLoaded = false
    this.restoreDashboardCache()
  }

  @Monitor('accountList.activeMemberId')
  private onActiveAccountChanged(): void {
    this.loadAccountProfiles()
    this.resetDashboardStateForAccount()
    this.loadAccountDashboard()
  }

  @Monitor('accountList.accounts')
  private onAccountListChanged(): void {
    this.loadAccountProfiles()
  }

  @Monitor('site.isEx')
  private onSiteModeChanged(): void {
    this.profileLoading = false
    this.profileLoadingKey = ''
    this.profileSettings = new EhProfileSettings()
    this.profileLoaded = false
    const cachedProfile: EhProfileSettings | null = AccountDashboardCache.seedProfile(this.profileCacheKey())
    if (cachedProfile !== null) {
      this.profileSettings = cachedProfile
      this.profileLoaded = true
    }
    this.loadProfileSettings()
  }

  private loadHomeLimits(): void {
    const key: string = this.activeAccountKey()
    if (key.length === 0) {
      return
    }
    if (this.homeLoading && this.homeLoadingKey === key) {
      return
    }
    this.homeLoading = true
    this.homeLoadingKey = key
    EhApiService.getInstance()
      .getEhHome()
      .then((home: EhHome) => {
        AccountDashboardCache.putHome(key, home)
        if (key !== this.activeAccountKey()) {
          return
        }
        this.home = home
        this.homeLoaded = true
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('auth', 'account_home_limits_failed', error.message)
      })
      .finally(() => {
        if (this.homeLoadingKey === key) {
          this.homeLoading = false
          this.homeLoadingKey = ''
        }
      })
  }

  private confirmResetImageLimits(): void {
    if (this.homeResetting || this.homeLoading) {
      return
    }
    if (!this.home.hasResetAction()) {
      this.toast($r('app.string.account_image_reset_unavailable'))
      return
    }
    this.getUIContext().showAlertDialog({
      message: AppStrings.get('account_image_reset_confirm').replace('%d', `${this.home.resetCost}`),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.account_image_reset_title'),
        fontColor: ThemeConstants.BRAND_PRIMARY,
        action: () => {
          this.resetImageLimits()
        },
      },
    })
  }

  private resetImageLimits(): void {
    if (this.homeResetting || !this.home.hasResetAction()) {
      return
    }
    this.homeResetting = true
    EhApiService.getInstance()
      .resetImageLimits(this.home)
      .then((home: EhHome) => {
        AccountDashboardCache.putHome(this.activeAccountKey(), home)
        this.home = home
        this.homeLoaded = true
        this.toast($r('app.string.account_image_reset_success'))
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('auth', 'account_image_limit_reset_failed', error.message)
        this.toast($r('app.string.account_image_reset_failed'))
      })
      .finally(() => {
        this.homeResetting = false
      })
  }

  private loadProfileSettings(): void {
    const key: string = this.profileCacheKey()
    if (this.activeAccountKey().length === 0) {
      return
    }
    if (this.profileLoading && this.profileLoadingKey === key) {
      return
    }
    this.profileLoading = true
    this.profileLoadingKey = key
    EhApiService.getInstance()
      .getUserConfig(this.site.isEx)
      .then((settings: EhProfileSettings) => {
        AccountDashboardCache.putProfile(key, settings)
        if (key !== this.profileCacheKey()) {
          return
        }
        this.profileSettings = settings
        this.profileLoaded = true
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('auth', 'account_uconfig_failed', error.message)
      })
      .finally(() => {
        if (this.profileLoadingKey === key) {
          this.profileLoading = false
          this.profileLoadingKey = ''
        }
      })
  }

  private openProfileWeb(): void {
    this.stack.pushPathByName(
      'GalleryWeb',
      new GalleryWebParams(UserProfileService.activeProfileUrl(), AppStrings.get('settings_account'), true),
    )
  }

  private switchAccount(memberId: string): void {
    if (memberId === this.accountList.activeMemberId) {
      return
    }
    CookieJarSettings.switchTo(this.ctx(), memberId)
  }

  // Remove a saved account; if that logged the user out entirely (it was the last), leave the page.
  private async removeAndMaybeExit(memberId: string): Promise<void> {
    await CookieJarSettings.removeAccount(this.ctx(), memberId)
    if (!this.auth.isLogin) {
      this.stack.pop()
    }
  }

  // Bottom logout: confirm, then log out the CURRENT account (switches to another if any, else logs out).
  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.logout_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.settings_logout'),
        fontColor: Color.Red,
        action: () => {
          this.removeAndMaybeExit(this.accountList.activeMemberId)
        },
      },
    })
  }

  // Title bar with a top-right person_badge_plus button → login page (add another account).
  private addAccountTitleBar(): Record<string, Object> {
    const item: Record<string, Object> = {
      'label': AppStrings.get('settings_add_account'),
      'icon': $r('sys.symbol.person_badge_plus'),
      'isEnabled': true,
      'action': (): void => {
        this.stack.pushPathByName('AccountLogin', null)
      },
    }
    const itemWrap: Record<string, Object> = { 'content': item }
    const menu: Record<string, Object> = { 'value': [itemWrap], 'maxCount': 1 }
    const title: Record<string, Object> = { 'mainTitle': AppStrings.get('settings_account') }
    const content: Record<string, Object> = { 'title': title, 'menu': menu }
    return immersiveTitleBarOpts(content)
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  private accountTitle(memberId: string): string {
    if (memberId === this.auth.memberId && this.auth.nickName.length > 0) {
      return this.auth.nickName
    }
    const profile: AccountProfileSummary | null = this.accountProfile(memberId)
    if (profile !== null && profile.nickName.length > 0) {
      return profile.nickName
    }
    return `ID ${memberId}`
  }

  private accountSubtitle(memberId: string): string {
    if (memberId === this.auth.memberId && this.auth.nickName.length > 0) {
      return `ID ${memberId}`
    }
    const profile: AccountProfileSummary | null = this.accountProfile(memberId)
    if (profile !== null && profile.nickName.length > 0) {
      return `ID ${memberId}`
    }
    return ''
  }

  private accountAvatarUrl(memberId: string): string {
    if (memberId === this.auth.memberId && this.auth.avatarUrl.length > 0) {
      return this.auth.avatarUrl
    }
    const profile: AccountProfileSummary | null = this.accountProfile(memberId)
    return profile !== null ? profile.avatarUrl : ''
  }

  private accountProfile(memberId: string): AccountProfileSummary | null {
    for (let i: number = 0; i < this.accountProfiles.length; i++) {
      if (this.accountProfiles[i].memberId === memberId) {
        return this.accountProfiles[i]
      }
    }
    return null
  }

  private cookieSummaryText(): string {
    return AppStrings.get('account_cookie_count_format').replace('%d', `${this.auth.cookieCount}`)
  }

  private exAccessText(): ResourceStr {
    if (this.auth.hasIgneous) {
      return $r('app.string.account_cookie_ex_available')
    }
    return $r('app.string.account_cookie_ex_locked')
  }

  private profileNameText(): ResourceStr {
    if (this.profileLoading && !this.profileLoaded) {
      return $r('app.string.common_loading')
    }
    for (let i: number = 0; i < this.profileSettings.profiles.length; i++) {
      const profile: EhProfile = this.profileSettings.profiles[i]
      if (profile.value === this.profileSettings.selectedProfile) {
        return profile.name
      }
    }
    return this.profileLoaded ? $r('app.string.account_profile_unknown') : $r('app.string.account_dashboard_not_available')
  }

  private imageQuotaText(): ResourceStr {
    if (this.homeLoading && !this.homeLoaded) {
      return $r('app.string.common_loading')
    }
    if (this.home.hasImageLimits()) {
      return `${this.home.currentLimit} / ${this.home.totLimit}`
    }
    return this.homeLoaded ? '' : $r('app.string.account_dashboard_not_loaded')
  }

  private imageQuotaSubtitle(): ResourceStr {
    if (this.homeLoading && !this.homeLoaded) {
      return $r('app.string.account_dashboard_loading_hint')
    }
    if (this.home.hasUnlockCost()) {
      return AppStrings.get('account_image_unlock_cost_format').replace('%d', `${this.home.unlockCost}`)
    }
    if (this.home.highResolutionLimited) {
      return $r('app.string.account_image_high_resolution_limited')
    }
    return ''
  }

  private imageResetSubtitle(): ResourceStr {
    return AppStrings.get('account_image_reset_cost_format').replace('%d', `${this.home.resetCost}`)
  }

  // One saved account as a card row; the active one is selected via Radio. Tap the row to switch.
  @Builder
  private AccountRow(memberId: string) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      AccountAvatar({
        memberId: memberId,
        avatarUrl: this.accountAvatarUrl(memberId),
        avatarSize: ThemeConstants.ACCOUNT_AVATAR_SIZE,
      })
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(this.accountTitle(memberId))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.accountSubtitle(memberId).length > 0) {
          Text(this.accountSubtitle(memberId))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      Radio({ value: memberId, group: 'nexte_accounts' })
        .checked(memberId === this.accountList.activeMemberId)
        .radioStyle({ checkedBackgroundColor: ThemeConstants.BRAND_PRIMARY })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .padding(ThemeConstants.SPACE_MD)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Center)
  }

  // Swipe-left delete (V2Next pattern): a red trash-icon button, no confirm (low misoperation risk).
  @Builder
  private DeleteAction(memberId: string) {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([Color.White])
      }
      .width(48)
      .height(40)
      .backgroundColor(Color.Red)
      .onClick(() => {
        this.removeAndMaybeExit(memberId)
      })
    }
    .height('100%')
    .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
    .justifyContent(FlexAlign.Center)
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ForEach(
          this.accountList.accounts,
          (memberId: string) => {
            ListItem() {
              this.AccountRow(memberId)
            }
            .swipeAction({
              end: () => {
                this.DeleteAction(memberId)
              },
            })
            .onClick(() => {
              this.switchAccount(memberId)
            })
          },
          (memberId: string) => memberId,
        )
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.account_status_ex'),
              leadingIcon: $r('sys.symbol.lock_open'),
              trailingText: this.exAccessText(),
              showChevron: false,
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.account_status_profile'),
              leadingIcon: $r('sys.symbol.gearshape'),
              trailingText: this.profileNameText(),
              showChevron: false,
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.account_dashboard_quota_section'),
              subtitle: this.imageQuotaSubtitle(),
              leadingIcon: $r('sys.symbol.picture_badge_arrow_down'),
              trailingText: this.imageQuotaText(),
              showChevron: false,
              action: () => {
                this.loadHomeLimits()
              },
            })
            if (this.home.resetCost > 0) {
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.account_image_reset_title'),
                subtitle: this.imageResetSubtitle(),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                trailingText: this.homeResetting ? $r('app.string.common_loading') : '',
                showChevron: false,
                action: () => {
                  this.confirmResetImageLimits()
                },
              })
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.account_cookie_title'),
              subtitle: this.exAccessText(),
              leadingIcon: $r('sys.symbol.key'),
              trailingText: this.cookieSummaryText(),
              action: () => {
                this.stack.pushPathByName('AccountCookie', null)
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.ehp_entry_title'),
              subtitle: $r('app.string.ehp_entry_hint'),
              leadingIcon: $r('sys.symbol.gearshape'),
              action: () => {
                this.stack.pushPathByName('EhProfileSettings', null)
              },
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.settings_mytags'),
              leadingIcon: $r('sys.symbol.bookmark'),
              action: () => {
                this.stack.pushPathByName('MyTags', null)
              },
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.settings_refresh_profile'),
              subtitle: $r('app.string.settings_refresh_profile_hint'),
              leadingIcon: $r('sys.symbol.person'),
              action: () => {
                this.openProfileWeb()
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.settings_logout'),
              leadingIcon: $r('sys.symbol.arrow_right_to_line'),
              destructive: true,
              showChevron: false,
              action: () => {
                this.confirmLogout()
              },
            })
          }
        }
      }
    }
    .titleBar(this.addAccountTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}

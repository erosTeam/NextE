import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  AuthState,
  ConciseListRow,
  CookieJarSettings,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  connectAuth,
  connectNavStack,
  immersiveTitleBarOpts,
  AccountListState,
  connectAccountList,
  UserProfileService,
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
  @Param avatarSize: number = 44;
  @Local auth: AuthState = connectAuth();

  private activeAvatarUrl(): string {
    if (this.memberId === this.auth.memberId) {
      return this.auth.avatarUrl
    }
    return ''
  }

  build() {
    Stack() {
      if (this.activeAvatarUrl().length > 0) {
        Image(this.activeAvatarUrl())
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
    .backgroundColor(ThemeConstants.BRAND_PRIMARY)
  }
}

@ComponentV2
export struct AccountPage {
  @Local auth: AuthState = connectAuth();
  @Local accountList: AccountListState = connectAccountList();
  @Local refreshing: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.restoreProfile()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  // Force-refresh igneous (eros_fe "Refresh Igneous") for the active account — useful if EX access lapsed.
  private refreshIgneous(): void {
    if (this.refreshing) {
      return
    }
    this.refreshing = true
    this.toast($r('app.string.site_ex_checking'))
    CookieJarSettings.refreshIgneous(this.ctx())
      .then((ok: boolean) => {
        this.toast(ok ? $r('app.string.site_ex_unlocked') : $r('app.string.site_ex_no_access'))
      })
      .finally(() => {
        this.refreshing = false
      })
  }

  private async restoreProfile(): Promise<void> {
    if (!this.auth.isLogin) {
      return
    }
    await UserProfileService.restoreActive(this.ctx())
    UserProfileService.materializeAvatar(this.ctx())
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
    return `ID ${memberId}`
  }

  private accountSubtitle(memberId: string): string {
    if (memberId === this.auth.memberId && this.auth.nickName.length > 0) {
      return `ID ${memberId}`
    }
    return ''
  }

  // One saved account as a card row; the active one is selected via Radio. Tap the row to switch.
  @Builder
  private AccountRow(memberId: string) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      AccountAvatar({ memberId: memberId, avatarSize: ThemeConstants.ACCOUNT_AVATAR_SIZE })
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
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.settings_refresh_igneous'),
              leadingIcon: $r('sys.symbol.arrow_clockwise'),
              showChevron: false,
              action: () => {
                this.refreshIgneous()
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

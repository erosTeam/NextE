import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
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
  immersiveTitleBar,
  AccountListState,
  connectAccountList,
} from 'shared'

/**
 * The account hub, reached from the settings account block. Owns everything account-related so the main
 * settings list stays clean. Signed in, it is the multi-account switcher: each saved account is a card,
 * the active one carries a checkmark_circle, tapping another switches to it, swiping left deletes it (which
 * logs out only if it was the last). A single "添加账号" entry opens a menu of the three login methods —
 * adding always starts a fresh session (EhLoginWebPage clears the WebView), so a different account can sign
 * in. Real avatars/nicknames are unavailable (forum-only, CF-blocked), so the avatar is a placeholder and
 * accounts are shown by member id.
 */
@ComponentV2
export struct AccountPage {
  @Local auth: AuthState = connectAuth();
  @Local accountList: AccountListState = connectAccountList();
  @Local refreshing: boolean = false;
  @Local addMenuShown: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

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

  private switchAccount(memberId: string): void {
    if (memberId === this.accountList.activeMemberId) {
      return
    }
    CookieJarSettings.switchTo(this.ctx(), memberId)
  }

  private confirmRemove(memberId: string): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.account_remove_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.account_remove'),
        fontColor: Color.Red,
        action: () => {
          CookieJarSettings.removeAccount(this.ctx(), memberId)
        },
      },
    })
  }

  private openLogin(route: string): void {
    this.addMenuShown = false
    this.stack.pushPathByName(route, null)
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private Avatar(size: number) {
    Stack() {
      SymbolGlyph($r('sys.symbol.person_fill'))
        .fontSize(size / 2)
        .fontColor([Color.White])
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor(ThemeConstants.BRAND_PRIMARY)
  }

  // One saved account as a card row; the active account carries a checkmark_circle (single-select).
  @Builder
  private AccountRow(memberId: string) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      this.Avatar(44)
      Text(`ID ${memberId}`)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      if (memberId === this.accountList.activeMemberId) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(ThemeConstants.FONT_SIZE_HEADING)
          .fontColor([ThemeConstants.BRAND_PRIMARY])
      }
    }
    .width('100%')
    .padding(ThemeConstants.SPACE_MD)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Center)
  }

  // Swipe-left delete (V2Next pattern): a red trash-icon button, not a full-width text block.
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
        this.confirmRemove(memberId)
      })
    }
    .height('100%')
    .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
    .justifyContent(FlexAlign.Center)
  }

  // The three login methods, behind the single 添加账号 / 登录账号 entry.
  @Builder
  private AddAccountMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.settings_login_web'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.person_badge_plus')),
      })
        .onClick(() => {
          this.openLogin('EhLogin')
        })
      MenuItem({
        content: $r('app.string.settings_login_password'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.lock')),
      })
        .onClick(() => {
          this.openLogin('EhPasswordLogin')
        })
      MenuItem({
        content: $r('app.string.settings_login_cookie'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line_circle_fill')),
      })
        .onClick(() => {
          this.openLogin('EhCookieImport')
        })
    }
  }

  @Builder
  private AddAccountEntry(title: ResourceStr, icon: Resource) {
    Column() {
      GroupedListSection() {
        ConciseListRow({
          title: title,
          leadingIcon: icon,
          showChevron: false,
          action: () => {
            this.addMenuShown = true
          },
        })
      }
    }
    .bindMenu(this.addMenuShown, this.AddAccountMenu, {
      placement: Placement.BottomRight,
      onDisappear: () => {
        this.addMenuShown = false
      },
    })
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        if (this.auth.isLogin) {
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
            this.AddAccountEntry($r('app.string.settings_add_account'), $r('sys.symbol.plus'))
          }
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.settings_mytags'),
                leadingIcon: $r('sys.symbol.bookmark'),
                action: () => {
                  this.stack.pushPathByName('MyTags', null)
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
        } else {
          ListItem() {
            this.AddAccountEntry($r('app.string.settings_login'), $r('sys.symbol.person'))
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_account')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}

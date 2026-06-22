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
  immersiveTitleBar,
} from 'shared'

/**
 * The account hub, reached from the settings account block. Owns everything account-related so the main
 * settings list stays clean: the signed-in identity, EH account actions (我的标签, refresh Igneous), and
 * logout — which lives INSIDE here rather than being exposed on the settings list. Logged out, it offers
 * the two login routes. Single active account for now; multi-account lands on top of this.
 */
@ComponentV2
export struct AccountPage {
  @Local auth: AuthState = connectAuth();
  @Local refreshing: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  // Force-refresh igneous (eros_fe's "Refresh Igneous") — useful if ExHentai access lapsed.
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
          CookieJarSettings.clear(this.ctx())
          this.stack.pop()
        },
      },
    })
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  // Signed-in header: a placeholder avatar (real avatars are a forum-only feature, and the forum is
  // unreachable from the app's network) + the member id.
  @Builder
  private Header() {
    Row({ space: ThemeConstants.SPACE_MD }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(28)
          .fontColor([Color.White])
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(ThemeConstants.BRAND_PRIMARY)
      Text(`ID ${this.auth.memberId}`)
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding(ThemeConstants.SPACE_LG)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        if (this.auth.isLogin) {
          ListItem() {
            GroupedListSection() {
              this.Header()
            }
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
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.settings_logout'),
                leadingIcon: $r('sys.symbol.arrow_right'),
                destructive: true,
                showChevron: false,
                action: () => {
                  this.confirmLogout()
                },
              })
            }
          }
        } else {
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.settings_login'),
                leadingIcon: $r('sys.symbol.person'),
                action: () => {
                  this.stack.pushPathByName('EhLogin', null)
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.settings_login_cookie'),
                leadingIcon: $r('sys.symbol.arrow_down_to_line_circle_fill'),
                action: () => {
                  this.stack.pushPathByName('EhCookieImport', null)
                },
              })
            }
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_account')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}

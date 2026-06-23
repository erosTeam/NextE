import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  connectNavStack,
  immersiveTitleBar,
  AccountListState,
  connectAccountList,
} from 'shared'

/**
 * The login page — a dedicated sub-page that just lists the login methods (web / password / cookie).
 * Reached when signed out (Settings → account) or when adding another account (account page top-right
 * person_badge_plus). It auto-dismisses once a login lands (activeMemberId changes) so the user returns
 * to where they came from (Settings or the account page) instead of staying on the chooser.
 */
@ComponentV2
export struct AccountLoginPage {
  @Local accountList: AccountListState = connectAccountList();
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  // Any method that logs in lands a new active account — leave the chooser so we return to the source page.
  @Monitor('accountList.activeMemberId')
  private onLoggedIn() {
    this.stack.pop()
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.settings_login_web'),
              leadingIcon: $r('sys.symbol.person_badge_plus'),
              action: () => {
                this.stack.pushPathByName('EhLogin', null)
              },
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.settings_login_password'),
              leadingIcon: $r('sys.symbol.lock'),
              action: () => {
                this.stack.pushPathByName('EhPasswordLogin', null)
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
    .titleBar(immersiveTitleBar(AppStrings.get('nav_login')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}

import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  WebLoginStyleSettings,
  WebLoginStyleState,
  connectNavStack,
  NavStackHolder,
  connectWebLoginStyle,
  closeLoginFlowToAccount,
  immersiveTitleBar,
  isTopRoute,
  AccountListState,
  connectAccountList,
} from 'shared'

/**
 * The login page — a dedicated sub-page that just lists the login methods (web / password / cookie).
 * Reached when signed out (Settings → account) or when adding another account (account page top-right
 * person_badge_plus). It auto-dismisses once a login lands on this page itself. Method pages close the
 * whole login flow explicitly, so this monitor must not pop while a child method page is still on top.
 */
@ComponentV2
export struct AccountLoginPage {
  @Local accountList: AccountListState = connectAccountList();
  @Local webLoginStyle: WebLoginStyleState = connectWebLoginStyle();
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local isFirstSecondaryDestination: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // Any method that logs in lands a new active account — leave the chooser so we return to the source page.
  @Monitor('accountList.activeMemberId')
  private onLoggedIn() {
    if (isTopRoute(this.stack, 'AccountLogin')) {
      closeLoginFlowToAccount(this.stack)
    }
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  private setWebLoginBeautify(value: boolean): void {
    WebLoginStyleSettings.save(this.ctx(), value)
  }

  private refreshFirstSecondaryDestination(pathStack: NavPathStack): void {
    const pathNames: string[] = pathStack.getAllPathName()
    this.isFirstSecondaryDestination = pathNames.length === 1 && pathNames[0] === 'AccountLogin'
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
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.web_login_beautify_setting'),
              subtitle: $r('app.string.web_login_beautify_setting_hint'),
              leadingIcon: $r('sys.symbol.paintbrush'),
              hasSwitch: true,
              checked: this.webLoginStyle.beautifyEnabled,
              switchAction: (value: boolean) => {
                this.setWebLoginBeautify(value)
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('nav_login')))
    .hideBackButton(this.navStackHolder.isSplitMode && this.isFirstSecondaryDestination)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      this.refreshFirstSecondaryDestination(context.pathStack)
    })
    .onWillShow(() => {
      this.refreshFirstSecondaryDestination(this.stack)
    })
  }
}

import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  AuthState,
  ConciseListRow,
  CookieJarSettings,
  GroupedListSection,
  SecondaryListScaffold,
  SiteModeSettings,
  SiteModeState,
  ThemeConstants,
  connectAuth,
  connectNavStack,
  connectSiteMode,
  immersiveTitleBar,
} from 'shared'

/**
 * EH settings page grounded in eros_fe EhSettingPage. This lane only groups the EH account/site
 * actions NextE already owns; website settings, cloud sync, link handlers, and favorite write
 * behavior remain separate feature lanes.
 */
@ComponentV2
export struct EhSettingsPage {
  @Local siteMode: SiteModeState = connectSiteMode();
  @Local auth: AuthState = connectAuth();
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private siteLabel(): string {
    return this.siteMode.isEx ? 'ExHentai' : 'E-Hentai'
  }

  private toggleSite(): void {
    const ctx: common.UIAbilityContext = this.ctx()
    if (this.siteMode.isEx) {
      SiteModeSettings.setEx(ctx, false)
    } else if (this.auth.isLogin && this.auth.hasIgneous) {
      SiteModeSettings.setEx(ctx, true)
    } else {
      this.getUIContext()
        .getPromptAction()
        .showToast({ message: $r('app.string.site_ex_locked') })
    }
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
          this.logout()
        },
      },
    })
  }

  private logout(): void {
    CookieJarSettings.clear(this.ctx())
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
      }) {
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.settings_site'),
              subtitle: $r('app.string.eh_settings_site_hint'),
              leadingIcon: $r('sys.symbol.house_fill'),
              trailingText: this.siteLabel(),
              action: () => {
                this.toggleSite()
              },
            })
          }
        }
        ListItem() {
          this.AccountRows()
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_eh')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  private AccountRows() {
    GroupedListSection() {
      if (this.auth.isLogin) {
        ConciseListRow({
          title: $r('app.string.settings_account'),
          leadingIcon: $r('sys.symbol.person'),
          trailingText: `ID ${this.auth.memberId}`,
          showChevron: false,
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.settings_mytags'),
          subtitle: $r('app.string.eh_settings_mytags_hint'),
          leadingIcon: $r('sys.symbol.bookmark'),
          action: () => {
            this.stack.pushPathByName('MyTags', null)
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.settings_logout'),
          leadingIcon: $r('sys.symbol.arrow_right'),
          destructive: true,
          showChevron: false,
          action: () => {
            this.confirmLogout()
          },
        })
      } else {
        ConciseListRow({
          title: $r('app.string.settings_login'),
          subtitle: $r('app.string.eh_settings_login_hint'),
          leadingIcon: $r('sys.symbol.person'),
          action: () => {
            this.stack.pushPathByName('EhLogin', null)
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.settings_login_cookie'),
          subtitle: $r('app.string.eh_settings_cookie_hint'),
          leadingIcon: $r('sys.symbol.arrow_down_to_line_circle_fill'),
          action: () => {
            this.stack.pushPathByName('EhCookieImport', null)
          },
        })
      }
    }
  }
}

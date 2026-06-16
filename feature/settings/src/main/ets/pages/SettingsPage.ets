import { common } from '@kit.AbilityKit'
import {
  ThemeConstants,
  connectSiteMode,
  SiteModeState,
  connectAuth,
  AuthState,
  connectNavStack,
  CookieJarSettings,
  SiteModeSettings,
  connectListMode,
  ListModeState,
  ListMode,
  ListModeSettings,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
} from 'shared'

/**
 * Settings tab on the shared V2Next grouped-list framework. M3 adds the account section:
 * logged out → a "Log in" row that opens the in-app EH web login; logged in → the member id
 * + a "Log out" row (clears the persisted cookie jar). Site (表站/里站) + version follow. The
 * full settings tree (reading / layout / download / network) grafts on as more sections later.
 */
@ComponentV2
export struct SettingsPage {
  @Local siteMode: SiteModeState = connectSiteMode();
  @Local auth: AuthState = connectAuth();
  @Local listMode: ListModeState = connectListMode();
  private stack: NavPathStack = connectNavStack().stack;
  // Index-owned scroller for this tab (title-bar scroll-up auto-hide via bindToScrollable).
  @Param scroller: Scroller = new Scroller();

  build() {
    Column() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
      }) {
        ListItem() {
          this.AccountSection()
        }
        ListItem() {
          this.MainSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  AccountSection() {
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
          leadingIcon: $r('sys.symbol.person'),
          action: () => {
            this.stack.pushPathByName('EhLogin', null)
          },
        })
      }
    }
  }

  @Builder
  MainSection() {
    GroupedListSection() {
      ConciseListRow({
        title: $r('app.string.settings_site'),
        leadingIcon: $r('sys.symbol.house_fill'),
        trailingText: this.siteMode.isEx ? '里站 (ExHentai)' : '表站 (E-Hentai)',
        action: () => {
          this.toggleSite()
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_view'),
        leadingIcon: $r('sys.symbol.square_grid_2x2'),
        trailingText: this.viewModeLabel(),
        action: () => {
          this.toggleView()
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_about'),
        leadingIcon: $r('sys.symbol.info_circle'),
        trailingText: 'NextE v1.0.0',
        showChevron: false,
      })
    }
  }

  @Builder
  rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  // 里站 (ExHentai) needs login + igneous; 表站 is always available. Toggle + persist.
  private toggleSite(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
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

  private viewModeLabel(): Resource {
    if (this.listMode.mode === ListMode.GRID) {
      return $r('app.string.view_grid')
    }
    if (this.listMode.mode === ListMode.SIMPLE_LIST) {
      return $r('app.string.view_simple')
    }
    return $r('app.string.view_list')
  }

  // Cycle the gallery view density: List (cards) → Compact (dense rows) → Grid → List.
  private toggleView(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    let next: string = ListMode.LIST
    if (this.listMode.mode === ListMode.LIST) {
      next = ListMode.SIMPLE_LIST
    } else if (this.listMode.mode === ListMode.SIMPLE_LIST) {
      next = ListMode.GRID
    } else {
      next = ListMode.LIST
    }
    ListModeSettings.setMode(ctx, next)
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.logout_confirm'),
      primaryButton: {
        value: $r('app.string.settings_logout'),
        fontColor: Color.Red,
        action: () => {
          const ctx: common.UIAbilityContext =
            this.getUIContext().getHostContext() as common.UIAbilityContext
          CookieJarSettings.clear(ctx)
        },
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
    })
  }
}

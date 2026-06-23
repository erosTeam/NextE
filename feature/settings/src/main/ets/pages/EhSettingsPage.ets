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
  SiteModeSettings,
  SiteModeState,
  ThemeConstants,
  ToplistFilterSettings,
  ToplistFilterState,
  connectAuth,
  connectSiteMode,
  connectToplistFilter,
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
  @Local toplistFilter: ToplistFilterState = connectToplistFilter();
  @Local switchingSite: boolean = false;
  @Local siteMenuShown: boolean = false;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private siteLabel(): string {
    return this.siteMode.isEx ? 'ExHentai' : 'E-Hentai'
  }

  // Selecting a site from the dropdown (not a tap-to-cycle toggle). E-Hentai is always allowed;
  // ExHentai requires login + a real igneous, fetched on demand the first time (eros_fe getExIgneous).
  private selectSite(toEx: boolean): void {
    this.siteMenuShown = false
    const ctx: common.UIAbilityContext = this.ctx()
    if (!toEx) {
      SiteModeSettings.setEx(ctx, false)
      return
    }
    if (this.siteMode.isEx) {
      return
    }
    if (!this.auth.isLogin) {
      this.toast($r('app.string.site_ex_locked'))
      return
    }
    if (this.auth.hasIgneous) {
      SiteModeSettings.setEx(ctx, true)
      return
    }
    if (this.switchingSite) {
      return
    }
    this.switchingSite = true
    this.toast($r('app.string.site_ex_checking'))
    CookieJarSettings.refreshIgneous(ctx)
      .then((ok: boolean) => {
        if (ok) {
          SiteModeSettings.setEx(ctx, true)
          this.toast($r('app.string.site_ex_unlocked'))
        } else {
          this.toast($r('app.string.site_ex_no_access'))
        }
      })
      .finally(() => {
        this.switchingSite = false
      })
  }

  @Builder
  SiteMenu() {
    Menu() {
      MenuItem({
        content: 'E-Hentai',
        symbolEndIcon: !this.siteMode.isEx
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      })
        .onClick(() => {
          this.selectSite(false)
        })
      MenuItem({
        content: 'ExHentai',
        symbolEndIcon: this.siteMode.isEx
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      })
        .onClick(() => {
          this.selectSite(true)
        })
    }
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private setToplistHiddenFilter(value: boolean): void {
    ToplistFilterSettings.save(this.ctx(), value)
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
            Column() {
              ConciseListRow({
                title: $r('app.string.settings_site'),
                leadingIcon: $r('sys.symbol.house_fill'),
                trailingText: this.siteLabel(),
                trailingDropdown: true,
                action: () => {
                  this.siteMenuShown = true
                },
              })
            }
            .bindMenu(this.siteMenuShown, this.SiteMenu, {
              placement: Placement.BottomRight,
              onDisappear: () => {
                this.siteMenuShown = false
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.eh_settings_toplist_hidden_filter'),
              subtitle: $r('app.string.eh_settings_toplist_hidden_filter_hint'),
              leadingIcon: $r('sys.symbol.eye_slash'),
              hasSwitch: true,
              checked: this.toplistFilter.applyHiddenUserTags,
              switchAction: (value: boolean) => {
                this.setToplistHiddenFilter(value)
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_eh')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}

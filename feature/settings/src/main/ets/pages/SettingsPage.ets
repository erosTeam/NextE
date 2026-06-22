import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  ThemeConstants,
  connectAuth,
  AuthState,
  connectNavStack,
  CookieJarSettings,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  ThemeSettings,
  LanguageSettings,
  ThemeDisplayState,
  connectThemeDisplay,
  LanguageState,
  connectLanguageState,
} from 'shared'

/**
 * Settings tab on the shared V2Next grouped-list framework. M3 adds the account section:
 * logged out → a "Log in" row that opens the in-app EH web login; logged in → the member id
 * + a "Log out" row (clears the persisted cookie jar). Site (E-Hentai/ExHentai) + version follow. The
 * full settings tree (reading / layout / download / network) grafts on as more sections later.
 */
@ComponentV2
export struct SettingsPage {
  @Local auth: AuthState = connectAuth();
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  @Local language: LanguageState = connectLanguageState();
  @Local themeMenuShown: boolean = false;
  @Local languageMenuShown: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  // Index-owned scroller for this tab (title-bar scroll-up auto-hide via bindToScrollable).
  @Param scroller: Scroller = new Scroller();
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;

  build() {
    Column() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
        onDidScroll: (offset: number, state: ScrollState) => {
          if (this.onDidScroll) {
            this.onDidScroll(offset, state)
          }
        },
      }) {
        ListItem() {
          this.AccountSection()
        }
        ListItem() {
          this.AppearanceSection()
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
        this.rowDivider()
        // Safe fallback to the WebView login: paste an existing EH cookie header (donor/other device).
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

  @Builder
  AppearanceSection() {
    GroupedListSection() {
      Column() {
        ConciseListRow({
          title: $r('app.string.settings_theme'),
          leadingIcon: $r('sys.symbol.moon'),
          trailingText: this.themeModeLabel(),
          trailingDropdown: true,
          action: () => {
            this.themeMenuShown = true
          },
        })
      }
      .bindMenu(this.themeMenuShown, this.ThemeMenu, {
        placement: Placement.BottomRight,
        onDisappear: () => {
          this.themeMenuShown = false
        },
      })
      this.rowDivider()
      Column() {
        ConciseListRow({
          title: $r('app.string.settings_language'),
          leadingIcon: $r('sys.symbol.translate'),
          trailingText: this.languageModeLabel(),
          trailingDropdown: true,
          action: () => {
            this.languageMenuShown = true
          },
        })
      }
      .bindMenu(this.languageMenuShown, this.LanguageMenu, {
        placement: Placement.BottomRight,
        onDisappear: () => {
          this.languageMenuShown = false
        },
      })
    }
  }

  @Builder
  ThemeMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.appearance_follow_system'),
        symbolEndIcon:
          this.themeDisplay.mode === ThemeSettings.MODE_SYSTEM
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setTheme(ThemeSettings.MODE_SYSTEM)
        })
      MenuItem({
        content: $r('app.string.theme_light'),
        symbolEndIcon:
          this.themeDisplay.mode === ThemeSettings.MODE_LIGHT
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setTheme(ThemeSettings.MODE_LIGHT)
        })
      MenuItem({
        content: $r('app.string.theme_dark'),
        symbolEndIcon:
          this.themeDisplay.mode === ThemeSettings.MODE_DARK
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setTheme(ThemeSettings.MODE_DARK)
        })
    }
  }

  @Builder
  LanguageMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.appearance_follow_system'),
        symbolEndIcon:
          this.language.mode === LanguageSettings.MODE_SYSTEM
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setLanguage(LanguageSettings.MODE_SYSTEM)
        })
      MenuItem({
        content: $r('app.string.language_zh'),
        symbolEndIcon:
          this.language.mode === LanguageSettings.MODE_ZH_CN
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setLanguage(LanguageSettings.MODE_ZH_CN)
        })
      MenuItem({
        content: $r('app.string.language_en'),
        symbolEndIcon:
          this.language.mode === LanguageSettings.MODE_EN
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setLanguage(LanguageSettings.MODE_EN)
        })
      MenuItem({
        content: $r('app.string.language_ja'),
        symbolEndIcon:
          this.language.mode === LanguageSettings.MODE_JA
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setLanguage(LanguageSettings.MODE_JA)
        })
    }
  }

  private themeModeLabel(): ResourceStr {
    if (this.themeDisplay.mode === ThemeSettings.MODE_LIGHT) {
      return $r('app.string.theme_light')
    }
    if (this.themeDisplay.mode === ThemeSettings.MODE_DARK) {
      return $r('app.string.theme_dark')
    }
    return $r('app.string.appearance_follow_system')
  }

  private languageModeLabel(): ResourceStr {
    if (this.language.mode === LanguageSettings.MODE_ZH_CN) {
      return $r('app.string.language_zh')
    }
    if (this.language.mode === LanguageSettings.MODE_EN) {
      return $r('app.string.language_en')
    }
    if (this.language.mode === LanguageSettings.MODE_JA) {
      return $r('app.string.language_ja')
    }
    return $r('app.string.appearance_follow_system')
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private setTheme(mode: string): void {
    this.themeMenuShown = false
    ThemeSettings.setMode(this.ctx(), mode)
  }

  private setLanguage(mode: string): void {
    this.languageMenuShown = false
    LanguageSettings.setMode(this.ctx(), mode)
  }

  @Builder
  MainSection() {
    GroupedListSection() {
      ConciseListRow({
        title: $r('app.string.settings_eh'),
        leadingIcon: $r('sys.symbol.house_fill'),
        action: () => {
          this.stack.pushPathByName('EhSettings', null)
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_layout'),
        leadingIcon: $r('sys.symbol.square_grid_2x2'),
        action: () => {
          this.stack.pushPathByName('LayoutSettings', null)
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_reader'),
        leadingIcon: $r('sys.symbol.doc_plaintext'),
        action: () => {
          this.stack.pushPathByName('ReaderSettings', null)
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_search'),
        leadingIcon: $r('sys.symbol.magnifyingglass'),
        action: () => {
          this.stack.pushPathByName('SearchSettings', null)
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.tab_history'),
        leadingIcon: $r('sys.symbol.clock'),
        action: () => {
          this.stack.pushPathByName('History', null)
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.advanced_diagnostics'),
        leadingIcon: $r('sys.symbol.gearshape'),
        action: () => {
          this.stack.pushPathByName('AdvancedSettings', null)
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_about'),
        leadingIcon: $r('sys.symbol.info_circle'),
        action: () => {
          this.stack.pushPathByName('About', null)
        },
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
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    CookieJarSettings.clear(ctx)
  }
}

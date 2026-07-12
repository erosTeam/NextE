import {
  ThemeConstants,
  connectAuth,
  AuthState,
  connectNavStack,
  NavStackHolder,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  EhImageKnifeImage,
  SafeModeState,
  connectSafeMode,
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
  @Local safeMode: SafeModeState = connectSafeMode();
  @Local navStackHolder: NavStackHolder = connectNavStack();
  private stack: NavPathStack = connectNavStack().stack;
  // Index-owned scroller for this tab (title-bar scroll-up auto-hide via bindToScrollable).
  @Param scroller: Scroller = new Scroller();
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;

  private accountTitle(): string {
    if (this.auth.nickName.length > 0) {
      return this.auth.nickName
    }
    return `ID ${this.auth.memberId}`
  }

  private accountSubtitle(): string {
    if (this.auth.nickName.length > 0) {
      return `ID ${this.auth.memberId}`
    }
    // Reserve the same secondary-text row before the best-effort profile fetch returns a nickname.
    return ' '
  }

  private openRootDetail(name: string): void {
    const pathNames: string[] = this.stack.getAllPathName()
    const topIndex: number = pathNames.length - 1
    if (topIndex >= 0 && pathNames[topIndex] === name) {
      return
    }
    if (topIndex >= 0) {
      this.stack.replacePathByName(name, null, true)
      return
    }
    this.stack.pushPathByName(name, null)
  }

  private isSettingsRootSelected(name: string): boolean {
    return this.navStackHolder.isSettingsRootSelected(name)
  }

  @Builder
  private AccountAvatar() {
    Stack() {
      if (this.auth.avatarUrl.length > 0) {
        EhImageKnifeImage({
          src: this.auth.avatarUrl,
          objectFit: ImageFit.Cover,
          widthValue: ThemeConstants.ACCOUNT_AVATAR_SIZE,
          heightValue: ThemeConstants.ACCOUNT_AVATAR_SIZE,
          radius: ThemeConstants.ACCOUNT_AVATAR_SIZE / 2,
        })
      } else {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(ThemeConstants.ACCOUNT_AVATAR_SIZE / 2)
          .fontColor([Color.White])
      }
    }
    .width(ThemeConstants.ACCOUNT_AVATAR_SIZE)
    .height(ThemeConstants.ACCOUNT_AVATAR_SIZE)
    .borderRadius(ThemeConstants.ACCOUNT_AVATAR_SIZE / 2)
    .clip(true)
    .backgroundColor(ThemeConstants.BRAND_PRIMARY)
  }

  build() {
    Column() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
        alwaysEnableEdgeSpring: true,
        onDidScroll: (offset: number, state: ScrollState) => {
          if (this.onDidScroll) {
            this.onDidScroll(offset, state)
          }
        },
      }) {
        if (!this.safeMode.restricted()) {
          ListItem() {
            this.AccountSection()
          }
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

  // The account block is just an ENTRY to the account hub (AccountPage); all account actions, including
  // logout, live inside there rather than being exposed on this list.
  @Builder
  AccountSection() {
    GroupedListSection() {
      if (this.auth.isLogin) {
        ConciseListRow({
          title: this.accountTitle(),
          subtitle: this.accountSubtitle(),
          selected: this.isSettingsRootSelected('Account'),
          prefixBuilderParam: () => {
            this.AccountAvatar()
          },
          action: () => {
            this.openRootDetail('Account')
          },
        })
      } else {
        ConciseListRow({
          title: $r('app.string.settings_login'),
          selected: this.isSettingsRootSelected('AccountLogin'),
          leadingIcon: $r('sys.symbol.person'),
          action: () => {
            this.openRootDetail('AccountLogin')
          },
        })
      }
    }
  }

  @Builder
  MainSection() {
    GroupedListSection() {
      if (!this.safeMode.restricted()) {
        ConciseListRow({
          title: $r('app.string.settings_eh'),
          selected: this.isSettingsRootSelected('EhSettings'),
          leadingIcon: $r('sys.symbol.worldclock'),
          action: () => {
            this.openRootDetail('EhSettings')
          },
        })
        this.rowDivider()
      }
      ConciseListRow({
        title: $r('app.string.settings_layout'),
        selected: this.isSettingsRootSelected('LayoutSettings'),
        leadingIcon: $r('sys.symbol.paintpalette'),
        action: () => {
          this.openRootDetail('LayoutSettings')
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_reader'),
        selected: this.isSettingsRootSelected('ReaderSettings'),
        leadingIcon: $r('sys.symbol.doc_plaintext'),
        action: () => {
          this.openRootDetail('ReaderSettings')
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_download'),
        selected: this.isSettingsRootSelected('DownloadSettings'),
        leadingIcon: $r('sys.symbol.arrow_down_to_line'),
        action: () => {
          this.openRootDetail('DownloadSettings')
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_search'),
        selected: this.isSettingsRootSelected('SearchSettings'),
        leadingIcon: $r('sys.symbol.magnifyingglass'),
        action: () => {
          this.openRootDetail('SearchSettings')
        },
      })
      this.rowDivider()
      if (!this.safeMode.restricted()) {
        ConciseListRow({
          title: $r('app.string.tab_history'),
          selected: this.isSettingsRootSelected('History'),
          leadingIcon: $r('sys.symbol.clock'),
          action: () => {
            this.openRootDetail('History')
          },
        })
        this.rowDivider()
      }
      ConciseListRow({
        title: $r('app.string.settings_cache'),
        selected: this.isSettingsRootSelected('CacheSettings'),
        leadingIcon: $r('sys.symbol.externaldrive'),
        action: () => {
          this.openRootDetail('CacheSettings')
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_advanced'),
        selected: this.isSettingsRootSelected('AdvancedSettings'),
        leadingIcon: $r('sys.symbol.gearshape'),
        action: () => {
          this.openRootDetail('AdvancedSettings')
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_about'),
        selected: this.isSettingsRootSelected('About'),
        leadingIcon: $r('sys.symbol.info_circle'),
        action: () => {
          this.openRootDetail('About')
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
}

import {
  ThemeConstants,
  connectAuth,
  AuthState,
  connectNavStack,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
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

  @Builder
  private AccountAvatar() {
    Stack() {
      if (this.auth.avatarUrl.length > 0) {
        Image(this.auth.avatarUrl)
          .objectFit(ImageFit.Cover)
          .width(ThemeConstants.ACCOUNT_AVATAR_SIZE)
          .height(ThemeConstants.ACCOUNT_AVATAR_SIZE)
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
          prefixBuilderParam: () => {
            this.AccountAvatar()
          },
          action: () => {
            this.stack.pushPathByName('Account', null)
          },
        })
      } else {
        ConciseListRow({
          title: $r('app.string.settings_login'),
          leadingIcon: $r('sys.symbol.person'),
          action: () => {
            this.stack.pushPathByName('AccountLogin', null)
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
          leadingIcon: $r('sys.symbol.worldclock'),
          action: () => {
            this.stack.pushPathByName('EhSettings', null)
          },
        })
        this.rowDivider()
      }
      ConciseListRow({
        title: $r('app.string.settings_layout'),
        leadingIcon: $r('sys.symbol.paintpalette'),
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
        title: $r('app.string.settings_download'),
        leadingIcon: $r('sys.symbol.arrow_down_to_line'),
        action: () => {
          this.stack.pushPathByName('DownloadSettings', null)
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
      if (!this.safeMode.restricted()) {
        ConciseListRow({
          title: $r('app.string.tab_history'),
          leadingIcon: $r('sys.symbol.clock'),
          action: () => {
            this.stack.pushPathByName('History', null)
          },
        })
        this.rowDivider()
      }
      ConciseListRow({
        title: $r('app.string.settings_cache'),
        leadingIcon: $r('sys.symbol.externaldrive'),
        action: () => {
          this.stack.pushPathByName('CacheSettings', null)
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_advanced'),
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
}

import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  ThemeConstants,
  connectReadMode,
  ReadModeState,
  ReadMode,
  ReadSpreadLayout,
  ReadModeSettings,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  AppStrings,
  connectNavStack,
  NavStackHolder,
  immersiveTitleBar,
  AppModalScaffold,
} from 'shared'

/**
 * Reader settings (eros_fe 阅读 settings category). Page-turn mode is a native dropdown picker:
 * the row shows the current mode with a chevron, and tapping it opens a native
 * HDS `Menu` with the options and a `checkmark` on the active one — the same native idiom as the
 * favorites order picker (V2Next TopicDetailComponents bindMenu). eros_fe presents direction as an
 * action sheet, NOT inline checkmark rows; this is the native equivalent, not a hand-rolled tick.
 */
@ComponentV2
export struct ReaderSettingsPage {
  @Param sheetPresentation: boolean = false;
  @Event closeSheet?: () => void;
  @Local readMode: ReadModeState = connectReadMode();
  @Local dirMenuShown: boolean = false;
  @Local spreadLayoutMenuShown: boolean = false;
  @Local autoPageMenuShown: boolean = false;
  @Local preloadPageMenuShown: boolean = false;
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local isFirstSecondaryDestination: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private setMode(mode: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setMode(ctx, mode)
  }

  private setDoublePageEnabled(enabled: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setDoublePageEnabled(ctx, enabled)
  }

  private setSpreadLayoutMode(mode: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setSpreadLayoutMode(ctx, mode)
  }

  private setAutoPageSeconds(seconds: number): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setAutoPageSeconds(ctx, seconds)
  }

  private setPreloadPages(pages: number): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setPreloadPages(ctx, pages)
  }

  private setVolumeKeyTurn(enabled: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setVolumeKeyTurn(ctx, enabled)
  }

  private modeLabel(): Resource {
    if (this.readMode.mode === ReadMode.RTL) {
      return $r('app.string.read_mode_rtl')
    }
    if (this.readMode.mode === ReadMode.TOP_TO_BOTTOM) {
      return $r('app.string.read_mode_ttb')
    }
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return $r('app.string.read_mode_vertical')
    }
    return $r('app.string.read_mode_ltr')
  }

  private modeIconFor(mode: string): Resource {
    if (mode === ReadMode.RTL) {
      return $r('sys.symbol.arrow_left_and_square')
    }
    if (mode === ReadMode.TOP_TO_BOTTOM) {
      return $r('sys.symbol.single_page_flipping')
    }
    if (mode === ReadMode.VERTICAL) {
      return $r('sys.symbol.scroll_vertical')
    }
    return $r('sys.symbol.arrow_right_and_square')
  }

  private doublePageAvailable(): boolean {
    return this.readMode.mode === ReadMode.LTR || this.readMode.mode === ReadMode.RTL
  }

  private spreadLayoutLabel(): Resource {
    if (this.readMode.spreadLayoutMode === ReadSpreadLayout.SPLIT) {
      return $r('app.string.settings_reader_spread_layout_split')
    }
    return $r('app.string.settings_reader_spread_layout_joined')
  }

  private autoPageLabel(): string {
    return `${this.readMode.autoPageSeconds}s`
  }

  private preloadPageLabel(): string {
    return `${this.readMode.preloadPages}`
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  // Native direction picker: a framework Menu/MenuItem with a checkmark symbolEndIcon on the active
  // mode (V2Next TopicDetailComponents.ets:192-227). Selecting one persists via ReadModeSettings + closes.
  @Builder
  DirMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.read_mode_ltr'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.LTR)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.LTR
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setMode(ReadMode.LTR)
        this.dirMenuShown = false
      })
      MenuItem({
        content: $r('app.string.read_mode_rtl'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.RTL)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.RTL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setMode(ReadMode.RTL)
        this.dirMenuShown = false
      })
      MenuItem({
        content: $r('app.string.read_mode_ttb'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.TOP_TO_BOTTOM)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.TOP_TO_BOTTOM
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setMode(ReadMode.TOP_TO_BOTTOM)
        this.dirMenuShown = false
      })
      MenuItem({
        content: $r('app.string.read_mode_vertical'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.VERTICAL)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.VERTICAL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setMode(ReadMode.VERTICAL)
        this.dirMenuShown = false
      })
    }
  }

  @Builder
  AutoPageMenu() {
    Menu() {
      MenuItem({
        content: '2s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 2
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(2)
        this.autoPageMenuShown = false
      })
      MenuItem({
        content: '3s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 3
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(3)
        this.autoPageMenuShown = false
      })
      MenuItem({
        content: '5s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 5
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(5)
        this.autoPageMenuShown = false
      })
      MenuItem({
        content: '8s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 8
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(8)
        this.autoPageMenuShown = false
      })
      MenuItem({
        content: '10s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 10
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(10)
        this.autoPageMenuShown = false
      })
    }
  }

  @Builder
  SpreadLayoutMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.settings_reader_spread_layout_joined'),
        symbolEndIcon:
          this.readMode.spreadLayoutMode === ReadSpreadLayout.JOINED
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setSpreadLayoutMode(ReadSpreadLayout.JOINED)
        this.spreadLayoutMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_spread_layout_split'),
        symbolEndIcon:
          this.readMode.spreadLayoutMode === ReadSpreadLayout.SPLIT
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setSpreadLayoutMode(ReadSpreadLayout.SPLIT)
        this.spreadLayoutMenuShown = false
      })
    }
  }

  @Builder
  PreloadPageMenu() {
    Menu() {
      MenuItem({
        content: '0',
        symbolEndIcon:
          this.readMode.preloadPages === 0
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(0)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '1',
        symbolEndIcon:
          this.readMode.preloadPages === 1
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(1)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '2',
        symbolEndIcon:
          this.readMode.preloadPages === 2
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(2)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '3',
        symbolEndIcon:
          this.readMode.preloadPages === 3
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(3)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '4',
        symbolEndIcon:
          this.readMode.preloadPages === 4
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(4)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '5',
        symbolEndIcon:
          this.readMode.preloadPages === 5
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(5)
        this.preloadPageMenuShown = false
      })
    }
  }

  private refreshFirstSecondaryDestination(pathStack: NavPathStack): void {
    const pathNames: string[] = pathStack.getAllPathName()
    this.isFirstSecondaryDestination = pathNames.length === 1 && pathNames[0] === 'ReaderSettings'
  }

  @Builder
  private SettingsListItem() {
    ListItem() {
          Column() {
            GroupedListSection() {
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_reader_direction'),
                  trailingText: this.modeLabel(),
                  trailingDropdown: true,
                  action: () => {
                    this.dirMenuShown = true
                  },
                })
              }
              .bindMenu(this.dirMenuShown, this.DirMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.dirMenuShown = false
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.settings_reader_double_page'),
                hasSwitch: true,
                checked: this.doublePageAvailable() && this.readMode.doublePageEnabled,
                isEnabled: this.doublePageAvailable(),
                showChevron: false,
                action: () => {
                  if (this.doublePageAvailable()) {
                    this.setDoublePageEnabled(!this.readMode.doublePageEnabled)
                  }
                },
                switchAction: (value: boolean) => {
                  if (this.doublePageAvailable()) {
                    this.setDoublePageEnabled(value)
                  }
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_reader_spread_layout'),
                  trailingText: this.spreadLayoutLabel(),
                  trailingDropdown: true,
                  isEnabled: this.doublePageAvailable(),
                  action: () => {
                    if (this.doublePageAvailable()) {
                      this.spreadLayoutMenuShown = true
                    }
                  },
                })
              }
              .bindMenu(this.spreadLayoutMenuShown, this.SpreadLayoutMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.spreadLayoutMenuShown = false
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_reader_auto_page_interval'),
                  trailingText: this.autoPageLabel(),
                  trailingDropdown: true,
                  action: () => {
                    this.autoPageMenuShown = true
                  },
                })
              }
              .bindMenu(this.autoPageMenuShown, this.AutoPageMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.autoPageMenuShown = false
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_reader_preload_pages'),
                  trailingText: this.preloadPageLabel(),
                  trailingDropdown: true,
                  action: () => {
                    this.preloadPageMenuShown = true
                  },
                })
              }
              .bindMenu(this.preloadPageMenuShown, this.PreloadPageMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.preloadPageMenuShown = false
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.settings_reader_volume_key'),
                subtitle: $r('app.string.settings_reader_volume_key_hint'),
                subtitleMaxLines: 3,
                hasSwitch: true,
                checked: this.readMode.volumeKeyTurn,
                showChevron: false,
                action: () => {
                  this.setVolumeKeyTurn(!this.readMode.volumeKeyTurn)
                },
                switchAction: (value: boolean) => {
                  this.setVolumeKeyTurn(value)
                },
              })
            }
          }
    }
  }

  build() {
    if (this.sheetPresentation) {
      AppModalScaffold({
        title: $r('app.string.settings_reader'),
        showConfirmAction: false,
        closeAction: () => {
          if (this.closeSheet) {
            this.closeSheet()
          }
        },
      }) {
        this.SettingsListItem()
      }
    } else {
      HdsNavDestination() {
        SecondaryListScaffold({
          scroller: this.scroller,
          bottomPadding: ThemeConstants.SPACE_XL,
          alwaysEnableEdgeSpring: true,
        }) {
          this.SettingsListItem()
        }
      }
      .titleBar(immersiveTitleBar(AppStrings.get('settings_reader')))
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
}
